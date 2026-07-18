// report.js — DRO-317 (Phase 5 of the DRO-311 eval harness)
//
// Renders the structured results object produced by `run-generation-eval.js` into a
// reviewable markdown report. Pure string-building: `buildReport` does NO I/O (no
// network, no DB, no filesystem), so it is trivially unit-testable against a fixture.
// `writeReport` is the only side-effecting export — it writes the string to
// `ai/eval/results/eval-report-<runLabel>.md` and returns the path.
//
// The report deliberately mirrors, but is richer than, the console summary the runner
// prints: overall PASS/FAIL tally + per-scenario HARD/SOFT-per-run breakdown, per-metric
// stability labels, generation-reliability failures (with the captured error_message),
// and the advisory Yupa coaching verdict/issues attached to each scored run.
//
// Expected results shape (see run-generation-eval.js `main()`):
//   { runLabel, startedAt, finishedAt,
//     config:  { scenariosRun, scenariosAvailable, runsPerScenario },
//     summary: { scenarios, passed, failed, reliabilityFailures, usersNotCleanedUp:[{userId,reason}] },
//     scenarios: [ {
//       scenario_name, race_objective, verdict:'PASS'|'FAIL',
//       runsRequested, runsScored, reliabilityFailureCount, hardFailRunCount, failReasons,
//       runs: [ { run, planId, outcome:'scored'|'reliability_failure',
//                 metrics?, hard?, soft?, coaching?, reason?, error_message?, error? } ],
//       stability: { <metric>: { class:'hard'|'soft', runsWithViolation, scoredRuns, total, label } }
//     } ] }

const fs = require("fs");
const path = require("path");

const VERDICT_EMOJI = { PASS: "✅", FAIL: "❌" };
const COACHING_EMOJI = {
  SHIP: "🟢",
  "SHIP WITH CHANGES": "🟡",
  "DO NOT SHIP": "🔴",
  UNKNOWN: "⚪️",
};

/** Join a list, or a friendly dash when empty — keeps table cells non-blank. */
function orNone(list) {
  return list && list.length ? list.join(", ") : "—";
}

/** Render one scored run's advisory coaching verdict as a compact one-liner. */
function coachingCell(coaching) {
  if (!coaching) return "—";
  const emoji = COACHING_EMOJI[coaching.verdict] || "⚪️";
  if (coaching.verdict === "UNKNOWN") {
    return `${emoji} UNKNOWN${coaching.error ? ` (${coaching.error})` : ""}`;
  }
  return `${emoji} ${coaching.verdict}`;
}

/** Full per-run coaching detail block (verdict, summary, itemized issues). */
function coachingDetail(run) {
  const c = run.coaching;
  if (!c) return null;
  const lines = [`- **Run ${run.run}:** ${coachingCell(c)}`];
  if (c.verdict === "UNKNOWN") return lines.join("\n"); // errored — nothing more to show
  if (c.summary) lines.push(`  - ${c.summary}`);
  for (const issue of c.issues || []) {
    lines.push(`  - _${issue.severity}_: ${issue.note}`);
  }
  return lines.join("\n");
}

/** Per-scenario section. */
function renderScenario(s) {
  const emoji = VERDICT_EMOJI[s.verdict] || "";
  const lines = [];
  lines.push(`### ${emoji} ${s.verdict} — ${s.scenario_name}` + (s.race_objective ? ` (${s.race_objective})` : ""));
  lines.push("");
  lines.push(
    `Runs: ${s.runsScored}/${s.runsRequested} scored · ` +
      `${s.hardFailRunCount} with HARD violation · ` +
      `${s.reliabilityFailureCount} generation-reliability failure(s)`
  );
  lines.push("");

  // ── Per-run breakdown ──
  lines.push("| Run | Outcome | HARD | SOFT | Coaching |");
  lines.push("| --- | --- | --- | --- | --- |");
  for (const run of s.runs) {
    if (run.outcome === "scored") {
      lines.push(
        `| ${run.run} | scored | ${orNone(run.hard)} | ${orNone(run.soft)} | ${coachingCell(run.coaching)} |`
      );
    } else {
      // reliability failure — surface the reason + captured message inline
      const detail = run.error_message || run.error || run.reason || "unknown";
      lines.push(`| ${run.run} | reliability_failure | — | — | ${run.reason || "error"}: ${detail} |`);
    }
  }
  lines.push("");

  // ── Generation-reliability failures (called out separately with full message) ──
  const relFailures = s.runs.filter((r) => r.outcome === "reliability_failure");
  if (relFailures.length) {
    lines.push("**Generation-reliability failures:**");
    for (const run of relFailures) {
      const msg = run.error_message || run.error || "(no message)";
      lines.push(`- Run ${run.run} — ${run.reason || "error"}: ${msg}`);
    }
    lines.push("");
  }

  // ── Per-metric stability ──
  const metrics = Object.keys(s.stability || {});
  if (metrics.length) {
    lines.push("**Per-metric stability (across scored runs):**");
    lines.push("");
    lines.push("| Metric | Class | Runs w/ violation | Total | Label |");
    lines.push("| --- | --- | --- | --- | --- |");
    for (const m of metrics) {
      const st = s.stability[m];
      lines.push(
        `| ${m} | ${st.class} | ${st.runsWithViolation}/${st.scoredRuns} | ${st.total} | ${st.label} |`
      );
    }
    lines.push("");
  }

  // ── Advisory coaching detail (Yupa) ──
  const scored = s.runs.filter((r) => r.outcome === "scored" && r.coaching);
  if (scored.length) {
    lines.push("**Advisory coaching audit (Yupa — non-gating):**");
    for (const run of scored) {
      const detail = coachingDetail(run);
      if (detail) lines.push(detail);
    }
    lines.push("");
  }

  return lines.join("\n");
}

/**
 * buildReport — pure: results object → markdown string. No I/O.
 * @param {object} results - the structured results object from run-generation-eval.js
 * @returns {string} markdown report
 */
function buildReport(results) {
  const cfg = results.config || {};
  const sum = results.summary || {};
  const lines = [];

  // ── Header ──
  lines.push(`# Generation Eval Report — ${results.runLabel}`);
  lines.push("");
  lines.push(`- **Run label:** ${results.runLabel}`);
  lines.push(`- **Started:** ${results.startedAt}`);
  lines.push(`- **Finished:** ${results.finishedAt}`);
  lines.push(
    `- **Scenarios:** ${cfg.scenariosRun ?? "?"} run / ${cfg.scenariosAvailable ?? "?"} available`
  );
  lines.push(`- **Runs per scenario:** ${cfg.runsPerScenario ?? "?"}`);
  lines.push("");

  // ── Overall summary ──
  lines.push("## Summary");
  lines.push("");
  lines.push(
    `**${sum.passed ?? 0}/${sum.scenarios ?? 0} scenarios PASS**, ` +
      `${sum.failed ?? 0} FAIL, ` +
      `${sum.reliabilityFailures ?? 0} generation-reliability failure(s) across all runs.`
  );
  lines.push("");

  const notCleaned = sum.usersNotCleanedUp || [];
  if (notCleaned.length) {
    lines.push(`⚠️ **${notCleaned.length} test user(s) NOT cleaned up — remove manually:**`);
    for (const u of notCleaned) lines.push(`- \`${u.userId}\` (${u.reason})`);
    lines.push("");
  } else {
    lines.push("✅ All test users cleaned up.");
    lines.push("");
  }

  // ── Per-scenario ──
  lines.push("## Scenarios");
  lines.push("");
  for (const s of results.scenarios || []) {
    lines.push(renderScenario(s));
  }

  return lines.join("\n");
}

/**
 * writeReport — build the report and write it to disk.
 * @param {object} results - the structured results object
 * @param {string} outDir  - directory to write into (typically ai/eval/results)
 * @returns {string} absolute path of the written markdown file
 */
function writeReport(results, outDir) {
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
  const outPath = path.join(outDir, `eval-report-${results.runLabel}.md`);
  fs.writeFileSync(outPath, buildReport(results));
  return outPath;
}

module.exports = { buildReport, writeReport };
