// yupa-rubric.js — DRO-314 (Phase 2 of the DRO-311 plan-quality eval harness)
//
// Advisory coaching-quality audit for a generated training plan. Makes ONE OpenAI
// call per plan, scored against a rubric derived from Yupa's (the `triathlon-coach`
// subagent, .claude/agents/triathlon-coach.md) 80/20 polarized-training baseline.
//
// This module is intentionally NOT the deterministic gate. `check-step3-violations.js`
// (HARD/SOFT structural checks: duration caps, sport eligibility, rest days, etc.) decides
// PASS/FAIL for a scenario. `reviewPlan` here is advisory only — its verdict is attached to
// the eval report for human review and never blocks a run. The `triathlon-coach` subagent
// itself can't be invoked from a plain `node` script (it needs the Claude Code agent runtime),
// so this re-derives its non-negotiable coaching principles as a system prompt and asks
// gpt-4.1 to apply them to one plan + its availability constraints.
//
// Pure function, no side effects: does not read/write files, does not touch the DB. The only
// I/O is the OpenAI call itself. Never throws on a "bad" plan (a plan riddled with coaching
// problems is a valid, well-formed result — it should come back as verdict: "DO NOT SHIP").
// It only throws when the OpenAI call itself fails (auth/network/rate-limit) — callers
// (the eval runner) decide how to handle that (e.g. skip the advisory audit for that run,
// don't fail the whole scenario).

const OpenAI = require("openai");

const MODEL = "gpt-4.1";
const TEMPERATURE = 0.2;

const VALID_VERDICTS = ["SHIP", "SHIP WITH CHANGES", "DO NOT SHIP"];
const VALID_SEVERITIES = ["blocker", "warning", "nit"];

// Yupa's non-negotiable coaching baseline, condensed from
// .claude/agents/triathlon-coach.md into a system prompt a plain chat-completion call can apply.
const SYSTEM_PROMPT = `You are Yupa, a world-class triathlon coach who audits AI-generated training
plans for the Dromos app. You review through the lens of 80/20 polarized training
(Seiler, Fitzgerald). Apply this baseline, non-negotiably unless the athlete's
context clearly demands a deviation (state the deviation and justify it if so):

- ~80% of weekly volume in Zone 1-2 (Easy/Recovery — below first ventilatory
  threshold, conversational pace). ~20% in Zone 4-5 (Intervals — hard, above
  second ventilatory threshold). Minimize Zone 3 / "gray zone" tempo work — it is
  too hard to recover from and too easy to get real adaptation from. Some tempo is
  fine (race-specific, sweet-spot for time-crunched athletes) but it should not
  dominate the plan.
- Periodization: Base -> Build -> Peak -> Taper, in that order, with progressive
  overload. Weekly volume ramp should not exceed ~10%/week (yellow flag) or
  ~15%/week (red flag). Recovery weeks should appear on a roughly 3:1 or 2:1
  load-to-deload cadence.
- SHORT PLANS ARE DIFFERENT (do NOT flag missing Base as broken periodization):
  when total_weeks <= 8 the race is only weeks away and there is no time to build
  an aerobic base — the athlete races on the base they arrive with. A short plan is
  correctly a SHARPENING / race-prep block, not a miniature full periodization.
  For total_weeks <= 5 it is CORRECT to skip Base and Recovery entirely and go
  race-specific (Build/Peak) from week 1 at roughly flat volume with rising
  intensity dose; week 1 may be a lighter on-ramp. Do NOT require a Base phase, a
  deload week, or a multi-week taper in a <=5-week plan. For 6-8 weeks, expect one
  light intro week + a single deload. Judge short plans on: presence of real
  Z4-5 intensity, flat/safe volume progression, and a sharp race-week taper — NOT
  on whether they contain all four classic phases.
- Discipline balance should reflect the race distance and the athlete's available
  time per sport — not equal thirds.
- Brick workouts (bike->run) earn their place close to race-specific prep
  (Build/Peak), not scattered randomly through Base.
- Taper: reduce volume while preserving intensity, typically 7-21 days depending
  on race distance (shorter for Olympic, longer for Ironman 70.3).
- Recovery is training: flag plans that skip true rest days, or stack hard
  (Tempo/Intervals) sessions on the same or adjacent days without recovery
  between same-system stress.
- CRITICAL FOR THIS AUDIT: the plan must respect the athlete's stated
  availability (which days/sports are eligible, and each day's duration cap).
  A coaching-quality plan that silently ignores availability constraints is not
  shippable regardless of its periodization — but note that hard availability
  violations are ALSO caught by a separate deterministic checker; your job here
  is to judge whether the plan's PACING/PROGRESSION/SESSION-DESIGN choices are
  sound GIVEN those constraints, not to re-derive the deterministic checks.

Be blunt and quantify whenever you can (percentages, ramp rates). This is one
automated review among many scenarios run in a batch — be decisive, not hedgy.

Return your review as a single JSON object matching the required schema. Set
"verdict" to exactly one of: "SHIP", "SHIP WITH CHANGES", "DO NOT SHIP".
- SHIP: no blockers, at most minor warnings/nits.
- SHIP WITH CHANGES: no blockers, but warnings that should be fixed before this
  plan design ships to real athletes.
- DO NOT SHIP: at least one blocker (a real coaching risk: dangerous load spike,
  no recovery, ignored injury/limiter, structurally broken periodization).
Each issue must have a "severity" of "blocker", "warning", or "nit", and a
concrete "note" citing the principle violated and what to change. "summary"
is 2-3 sentences giving the overall coaching read.`;

const RESPONSE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    verdict: { type: "string", enum: VALID_VERDICTS },
    issues: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          severity: { type: "string", enum: VALID_SEVERITIES },
          note: { type: "string" },
        },
        required: ["severity", "note"],
      },
    },
    summary: { type: "string" },
  },
  required: ["verdict", "issues", "summary"],
};

const DAY_ORDER = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

// Heuristic session-type -> zone-bucket mapping, used only to hand the model a
// pre-computed anchor number so it quantifies rather than eyeballs. The model is
// told this is a proxy and may reason past it (e.g. a long Easy day contributing
// meaningful aerobic TSS is still Zone 1-2, but a mislabeled "Easy" brick might not be).
const ZONE_BUCKET = {
  Easy: "z1_2",
  Recovery: "z1_2",
  Long: "z1_2",
  Tempo: "z3",
  Intervals: "z4_5",
  Race: "z4_5",
};

/**
 * Computes lightweight, deterministic summary stats from the plan to anchor the
 * model's quantitative reasoning (intensity distribution, weekly volume ramp,
 * rest-day usage). This is NOT a substitute for the HARD/SOFT checker — just
 * context to reduce hallucinated percentages in the LLM's response.
 */
function summarizePlan(evalPlan, scenarioVars) {
  const weeks = evalPlan?.weeks || [];
  const zoneMinutes = { z1_2: 0, z3: 0, z4_5: 0, other: 0 };
  const weeklyTotals = [];

  const activeDayCount = DAY_ORDER.filter((d) => {
    const key = d.slice(0, 3).toLowerCase() + "_duration";
    return scenarioVars && scenarioVars[key] > 0;
  }).length;

  for (const week of weeks) {
    let weekTotal = 0;
    for (const session of week.sessions || []) {
      const bucket = ZONE_BUCKET[session.type] || "other";
      zoneMinutes[bucket] += session.duration_minutes || 0;
      weekTotal += session.duration_minutes || 0;
    }
    weeklyTotals.push({ week_number: week.week_number, phase: week.phase, total_minutes: weekTotal });
  }

  const totalMinutes = zoneMinutes.z1_2 + zoneMinutes.z3 + zoneMinutes.z4_5 + zoneMinutes.other;
  const pct = (n) => (totalMinutes > 0 ? Math.round((n / totalMinutes) * 1000) / 10 : 0);

  // Ramp rate: week-over-week % change in total minutes (within the same phase run is most meaningful,
  // but a simple global week-over-week series is enough to flag obvious spikes for the model to inspect).
  const rampRates = [];
  for (let i = 1; i < weeklyTotals.length; i++) {
    const prev = weeklyTotals[i - 1].total_minutes;
    const cur = weeklyTotals[i].total_minutes;
    if (prev > 0) {
      rampRates.push({ week_number: weeklyTotals[i].week_number, pct_change: Math.round(((cur - prev) / prev) * 1000) / 10 });
    }
  }

  return {
    total_weeks: weeks.length,
    active_availability_days_per_week: activeDayCount,
    intensity_distribution_pct: {
      z1_2_easy_recovery: pct(zoneMinutes.z1_2),
      z3_tempo: pct(zoneMinutes.z3),
      z4_5_intervals: pct(zoneMinutes.z4_5),
      unclassified: pct(zoneMinutes.other),
    },
    weekly_totals_minutes: weeklyTotals,
    week_over_week_pct_change: rampRates,
  };
}

function buildUserPrompt(evalPlan, scenarioVars) {
  const stats = summarizePlan(evalPlan, scenarioVars);
  return [
    "Audit the following AI-generated training plan for coaching quality.",
    "",
    "## Athlete availability & profile (the constraints the plan was generated under)",
    "```json",
    JSON.stringify(scenarioVars, null, 2),
    "```",
    "",
    "## Pre-computed summary stats (heuristic Easy/Recovery/Long=Z1-2, Tempo=Z3, Intervals=Z4-5 — a proxy, not ground truth; verify against the full plan below)",
    "```json",
    JSON.stringify(stats, null, 2),
    "```",
    "",
    "## Full plan (weeks -> sessions)",
    "```json",
    JSON.stringify(evalPlan, null, 2),
    "```",
    "",
    "Return the JSON verdict now.",
  ].join("\n");
}

/**
 * reviewPlan — advisory coaching audit of one generated plan.
 *
 * @param {{weeks: Array}} evalPlan - eval-shaped plan (see db-plan-to-eval-shape.js):
 *   { weeks: [ { week_number, phase, sessions: [ { day, sport, type, duration_minutes, is_brick } ] } ] }
 * @param {object} scenarioVars - the full scenario profile the plan was generated under
 *   (an entry from vars/availability-scenarios.yaml: race_objective, race_date,
 *   experience_years, current_weekly_hours, ftp, vma, css_seconds_per100m,
 *   swim_days/bike_days/run_days, {day}_duration, scenario_name)
 * @returns {Promise<{verdict: 'SHIP'|'SHIP WITH CHANGES'|'DO NOT SHIP', issues: Array<{severity: string, note: string}>, summary: string}>}
 * @throws only on OpenAI API failure (auth/network/rate-limit) — never on a low-quality plan.
 */
async function reviewPlan(evalPlan, scenarioVars) {
  if (!process.env.OPENAI_API_KEY) {
    throw new Error("yupa-rubric: OPENAI_API_KEY is not set — required for the coaching-audit OpenAI call.");
  }

  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

  const completion = await client.chat.completions.create({
    model: MODEL,
    temperature: TEMPERATURE,
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      { role: "user", content: buildUserPrompt(evalPlan, scenarioVars) },
    ],
    response_format: {
      type: "json_schema",
      json_schema: { name: "yupa_coaching_verdict", strict: true, schema: RESPONSE_SCHEMA },
    },
  });

  const raw = completion.choices?.[0]?.message?.content;
  if (!raw) {
    // No content at all is an API-shape failure, not a plan-quality judgment — throw.
    throw new Error("yupa-rubric: OpenAI returned no content in the completion response");
  }

  try {
    const parsed = JSON.parse(raw);
    return normalize(parsed);
  } catch (e) {
    // A malformed response is a quality problem with the audit itself, not the plan —
    // surface it as an advisory note instead of throwing, per the "never throws on a
    // bad plan" contract (this is functionally indistinguishable from a bad plan to callers).
    return {
      verdict: "DO NOT SHIP",
      issues: [{ severity: "blocker", note: `yupa-rubric: model returned unparseable JSON (${e.message}). Treat this run's advisory audit as inconclusive.` }],
      summary: "Coaching audit failed to parse a structured verdict from the model response; advisory result is inconclusive, not a reflection of plan quality.",
    };
  }
}

/** Defensive normalization in case the model (despite strict schema mode) returns something odd. */
function normalize(parsed) {
  const verdict = VALID_VERDICTS.includes(parsed.verdict) ? parsed.verdict : "DO NOT SHIP";
  const issues = Array.isArray(parsed.issues)
    ? parsed.issues
        .filter((i) => i && typeof i.note === "string")
        .map((i) => ({
          severity: VALID_SEVERITIES.includes(i.severity) ? i.severity : "warning",
          note: i.note,
        }))
    : [];
  const summary = typeof parsed.summary === "string" ? parsed.summary : "";
  return { verdict, issues, summary };
}

module.exports = { reviewPlan, summarizePlan };
