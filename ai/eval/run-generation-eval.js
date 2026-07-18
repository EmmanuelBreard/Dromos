#!/usr/bin/env node
/**
 * run-generation-eval.js — DRO-315 (Phase 3 of the DRO-311 eval harness)
 *
 * Orchestrates the plan-quality generation eval: for every availability scenario
 * in `vars/availability-scenarios.yaml`, runs N iterations through the REAL deployed
 * `generate-plan` edge function, scores each materialized plan with the 8-metric
 * checker, and classifies the scenario PASS/FAIL.
 *
 * Per run (see Phase 1 client `lib/eval-supabase-client.js`):
 *   createTestUser(profile) → invokeGeneratePlan(jwt) → pollStatus(planId, jwt)
 *     • 'active'                    → readPlan → dbPlanToEvalShape → scorePlan
 *     • {status:'failed', ...} | 'timeout' → generation-reliability failure (NOT a pass)
 *   deleteTestUser(userId) ALWAYS runs in a `finally` (CASCADE cleanup), and every
 *   created userId is tracked in a module-level set swept again at the very end so a
 *   crash mid-loop still cleans up what it made.
 *
 * Verdict: a scenario FAILS if ANY HARD violation occurs in ANY of its runs, OR if
 * ALL of its runs are generation-reliability failures. SOFT violations are recorded
 * but never gate. Per-metric stability across the scored runs is labeled with
 * aggregate-violations.js's shared CLEAN/VARIANCE/INVESTIGATE/SYSTEMATIC buckets.
 *
 * Output: a structured results object, written to
 *   ai/eval/results/generation-eval-<runlabel>.json
 * plus a concise per-scenario console summary. (The pretty markdown report is Phase 5.)
 *
 * ⚠️  COST: each run is a real prod `generate-plan` call (~1-2 min, costs OpenAI).
 *     Use the flags to run a cheap subset — do NOT default-run the full 12×N matrix
 *     casually.
 *
 * Usage:
 *   node ai/eval/run-generation-eval.js                    # all scenarios, N=3
 *   node ai/eval/run-generation-eval.js --scenarios 1 --runs 1   # cheap smoke test
 *   node ai/eval/run-generation-eval.js --label pre-fix    # custom output filename tag
 */

const path = require("path");
const fs = require("fs");
const yaml = require("js-yaml");

const {
  createTestUser,
  invokeGeneratePlan,
  pollStatus,
  readPlan,
  deleteTestUser,
} = require("./lib/eval-supabase-client");
const { dbPlanToEvalShape } = require("./db-plan-to-eval-shape");
const { scorePlan, HARD_VIOLATIONS, SOFT_VIOLATIONS } = require("./check-step3-violations");
const { labelStability } = require("./aggregate-violations");

const SCENARIOS_FILE = path.join(__dirname, "vars", "availability-scenarios.yaml");
const RESULTS_DIR = path.join(__dirname, "results");
const DEFAULT_RUNS = 3;

// All 8 checker metrics (HARD gates + SOFT warns), in the checker's summary-key order.
const ALL_METRICS = [...HARD_VIOLATIONS, ...SOFT_VIOLATIONS];
const DAY_DURATION_FIELDS = [
  "mon_duration", "tue_duration", "wed_duration", "thu_duration",
  "fri_duration", "sat_duration", "sun_duration",
];

// ── CLI flag parsing ──────────────────────────────────────────────────────────
function parseArgs(argv) {
  const args = { scenarios: null, runs: DEFAULT_RUNS, label: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--scenarios") args.scenarios = parseInt(argv[++i], 10);
    else if (a === "--runs") args.runs = parseInt(argv[++i], 10);
    else if (a === "--label") args.label = argv[++i];
  }
  if (args.scenarios !== null && (!Number.isFinite(args.scenarios) || args.scenarios < 1)) {
    throw new Error("--scenarios must be a positive integer");
  }
  if (!Number.isFinite(args.runs) || args.runs < 1) {
    throw new Error("--runs must be a positive integer");
  }
  return args;
}

/**
 * Bridge the two var shapes. The scenario file is DB-shaped (day-lists as arrays,
 * durations as numbers); scorePlan expects the `athletes.yaml` promptfoo-vars shape
 * (swim/bike/run_days as comma-separated day-name strings, day durations + weekly_hours
 * parseInt-readable). The SAME DB-shaped profile still goes straight to createTestUser —
 * this adapter output is used ONLY for scoring.
 *
 * weekly_hours is computed from the seeded day durations (sum of active-day minutes / 60);
 * scorePlan only uses it as the ≥8h/week threshold that relaxes the sport-clustering check.
 */
function scenarioToScoringVars(profile) {
  const joinDays = (arr) => (Array.isArray(arr) ? arr.join(", ") : arr || "");
  const totalMinutes = DAY_DURATION_FIELDS.reduce(
    (sum, f) => sum + (Number(profile[f]) || 0),
    0
  );
  const vars = {
    scenario_name: profile.scenario_name,
    swim_days: joinDays(profile.swim_days),
    bike_days: joinDays(profile.bike_days),
    run_days: joinDays(profile.run_days),
    weekly_hours: totalMinutes / 60,
  };
  for (const f of DAY_DURATION_FIELDS) vars[f] = profile[f];
  return vars;
}

// ── Cleanup tracking: every created user is registered here and removed once
//    confirmed deleted. Swept again in main()'s finally as a crash safety net. ──
const createdUsers = new Set();

async function cleanupUser(userId, notDeleted) {
  try {
    const res = await deleteTestUser(userId);
    if (res.deleted) {
      createdUsers.delete(userId);
    } else {
      // deleteTestUser returns {deleted:false} only when no admin key is configured;
      // it already logged the manual-cleanup SQL. Surface it in the results too.
      notDeleted.push({ userId, reason: "no-admin-key" });
    }
  } catch (err) {
    notDeleted.push({ userId, reason: err.message });
  }
}

// ── One scenario: N runs → classified verdict ──────────────────────────────────
async function runScenario(profile, runs, notDeleted) {
  const scoringVars = scenarioToScoringVars(profile);
  // `scenario_name` is a harness-only label, not a public.users column — strip it so
  // createTestUser's profile-seed UPDATE only touches real DB columns.
  const { scenario_name, ...seedProfile } = profile;
  const runResults = [];

  for (let r = 1; r <= runs; r++) {
    let userId = null;
    const label = `${profile.scenario_name} run ${r}/${runs}`;
    try {
      const user = await createTestUser(seedProfile);
      userId = user.userId;
      createdUsers.add(userId);

      const planId = await invokeGeneratePlan(user.jwt);
      const status = await pollStatus(planId, user.jwt);

      if (status === "active") {
        const dbPlan = await readPlan(planId, user.jwt);
        const evalPlan = dbPlanToEvalShape(dbPlan);
        const metrics = scorePlan(evalPlan, scoringVars); // { log:false } default — stays quiet
        const hard = HARD_VIOLATIONS.filter((m) => (metrics[m] || 0) > 0);
        const soft = SOFT_VIOLATIONS.filter((m) => (metrics[m] || 0) > 0);
        runResults.push({ run: r, planId, outcome: "scored", metrics, hard, soft });
        console.log(
          `    ${label}: scored — ${hard.length ? "HARD[" + hard.join(",") + "]" : "no hard"}` +
            `${soft.length ? " SOFT[" + soft.join(",") + "]" : ""}`
        );
      } else if (status === "timeout") {
        runResults.push({ run: r, planId, outcome: "reliability_failure", reason: "timeout", error_message: null });
        console.log(`    ${label}: RELIABILITY FAILURE (timeout)`);
      } else {
        // { status:'failed', error_message }
        runResults.push({
          run: r, planId, outcome: "reliability_failure", reason: "failed",
          error_message: status.error_message || null,
        });
        console.log(`    ${label}: RELIABILITY FAILURE (failed: ${status.error_message || "no message"})`);
      }
    } catch (err) {
      // Any thrown error (seed/invoke/read/network) is a reliability failure for this run,
      // never a silent pass.
      runResults.push({ run: r, outcome: "reliability_failure", reason: "error", error_message: err.message });
      console.log(`    ${label}: RELIABILITY FAILURE (error: ${err.message})`);
    } finally {
      if (userId) await cleanupUser(userId, notDeleted);
    }
  }

  // ── Aggregate ──
  const scored = runResults.filter((r) => r.outcome === "scored");
  const reliabilityFailures = runResults.filter((r) => r.outcome === "reliability_failure");
  const hardFailRuns = scored.filter((r) => r.hard.length > 0);
  const anyHard = hardFailRuns.length > 0;
  const allReliabilityFail = reliabilityFailures.length === runs;
  const verdict = anyHard || allReliabilityFail ? "FAIL" : "PASS";

  // Per-metric stability across the scored runs (reuse aggregate-violations labels).
  const stability = {};
  for (const metric of ALL_METRICS) {
    const counts = scored.map((r) => r.metrics[metric] || 0);
    const runsWithViolation = counts.filter((c) => c > 0).length;
    const total = counts.reduce((a, b) => a + b, 0);
    stability[metric] = {
      class: HARD_VIOLATIONS.includes(metric) ? "hard" : "soft",
      runsWithViolation,
      scoredRuns: scored.length,
      total,
      label: labelStability(runsWithViolation, scored.length),
    };
  }

  return {
    scenario_name: profile.scenario_name,
    race_objective: profile.race_objective,
    verdict,
    runsRequested: runs,
    runsScored: scored.length,
    reliabilityFailureCount: reliabilityFailures.length,
    hardFailRunCount: hardFailRuns.length,
    failReasons: {
      hardViolationInSomeRun: anyHard,
      allRunsReliabilityFailed: allReliabilityFail,
    },
    runs: runResults,
    stability,
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (!fs.existsSync(RESULTS_DIR)) fs.mkdirSync(RESULTS_DIR, { recursive: true });

  const allScenarios = yaml.load(fs.readFileSync(SCENARIOS_FILE, "utf8"));
  if (!Array.isArray(allScenarios) || allScenarios.length === 0) {
    throw new Error(`No scenarios found in ${SCENARIOS_FILE}`);
  }
  const scenarios =
    args.scenarios !== null ? allScenarios.slice(0, args.scenarios) : allScenarios;

  const runLabel =
    args.label || new Date().toISOString().replace(/[:.]/g, "-").replace("T", "_").slice(0, 19);
  const startedAt = new Date().toISOString();

  console.log("=== DRO-315 generation eval ===");
  console.log(
    `scenarios: ${scenarios.length}/${allScenarios.length}  runs/scenario: ${args.runs}  ` +
      `total generations: ${scenarios.length * args.runs}  label: ${runLabel}\n`
  );

  const notDeleted = [];
  const scenarioResults = [];

  try {
    for (let i = 0; i < scenarios.length; i++) {
      const profile = scenarios[i];
      console.log(`[${i + 1}/${scenarios.length}] ${profile.scenario_name} (${profile.race_objective})`);
      const result = await runScenario(profile, args.runs, notDeleted);
      scenarioResults.push(result);
      console.log(`  → ${result.verdict}`);
    }
  } finally {
    // Crash safety net: sweep any users that were created but never confirmed-deleted.
    if (createdUsers.size > 0) {
      console.log(`\nSweeping ${createdUsers.size} un-cleaned test user(s)...`);
      for (const userId of [...createdUsers]) await cleanupUser(userId, notDeleted);
    }
  }

  const finishedAt = new Date().toISOString();
  const passed = scenarioResults.filter((s) => s.verdict === "PASS").length;
  const failed = scenarioResults.filter((s) => s.verdict === "FAIL").length;
  const totalReliabilityFailures = scenarioResults.reduce(
    (n, s) => n + s.reliabilityFailureCount,
    0
  );

  const results = {
    runLabel,
    startedAt,
    finishedAt,
    config: {
      scenariosRun: scenarios.length,
      scenariosAvailable: allScenarios.length,
      runsPerScenario: args.runs,
    },
    summary: {
      scenarios: scenarioResults.length,
      passed,
      failed,
      reliabilityFailures: totalReliabilityFailures,
      usersNotCleanedUp: notDeleted,
    },
    scenarios: scenarioResults,
  };

  const outFile = path.join(RESULTS_DIR, `generation-eval-${runLabel}.json`);
  fs.writeFileSync(outFile, JSON.stringify(results, null, 2));

  // ── Console summary ──
  console.log("\n=== SUMMARY ===");
  for (const s of scenarioResults) {
    const rel = s.reliabilityFailureCount
      ? ` (${s.reliabilityFailureCount}/${s.runsRequested} reliability fail)`
      : "";
    console.log(`  ${s.verdict.padEnd(4)}  ${s.scenario_name}${rel}`);
  }
  console.log(
    `\n${passed}/${scenarioResults.length} scenarios PASS, ${failed} FAIL, ` +
      `${totalReliabilityFailures} reliability failure(s) across all runs.`
  );
  if (notDeleted.length > 0) {
    console.log(`\n⚠️  ${notDeleted.length} test user(s) NOT cleaned up — clean up manually:`);
    for (const u of notDeleted) console.log(`     ${u.userId} (${u.reason})`);
  } else {
    console.log("All test users cleaned up.");
  }
  console.log(`\nResults written to ${path.relative(process.cwd(), outFile)}`);

  return results;
}

if (require.main === module) {
  main().catch((e) => {
    console.error("\n❌ generation eval crashed:", e.message);
    if (createdUsers.size > 0) {
      console.error(
        `⚠️  ${createdUsers.size} test user(s) may remain — clean up: ${[...createdUsers].join(", ")}`
      );
    }
    process.exit(1);
  });
}

module.exports = { scenarioToScoringVars, runScenario };
