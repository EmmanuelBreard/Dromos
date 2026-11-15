/**
 * Reliability tests for plan generation.
 *
 * Run from the repo root:
 *   deno test supabase/functions/generate-plan/__tests__/plan-generation.test.ts
 */

import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { isRetryableError, PlanInputError, publicErrorMessage, retryable } from "../lib/errors.ts";
import {
  assertGeneratable,
  computePlanHorizon,
  shouldRestartPlan,
  toAthletePlanInput,
  weeklyTrainingMinutes,
} from "../lib/input.ts";
import { fillTemplate } from "../lib/prompt.ts";
import {
  extractWeekArray,
  macroPlanFromMarkdown,
  parseMacroMarkdown,
  parseModelJson,
  splitMarkdownWeeks,
} from "../lib/macro-plan.ts";
import { alignBlockWeeks, preparePlanWeeks } from "../lib/sanitize.ts";
import STEP1 from "../prompts/step1-macro-plan-prompt.ts";

const NOW = new Date("2026-11-15T12:00:00.000Z");

const LIBRARY = {
  swim: [
    { template_id: "SWIM_Easy_01", duration_minutes: 30 },
    { template_id: "SWIM_Tempo_01", duration_minutes: 40 },
  ],
  bike: [
    { template_id: "BIKE_Easy_01", duration_minutes: 60 },
    { template_id: "BIKE_Intervals_01", duration_minutes: 45 },
  ],
  run: [
    { template_id: "RUN_Easy_01", duration_minutes: 30 },
    { template_id: "RUN_Easy_02", duration_minutes: 75 },
    { template_id: "RUN_Tempo_01", duration_minutes: 40 },
  ],
};

const CONSTRAINTS = {
  dayCaps: {
    Monday: 60,
    Tuesday: 60,
    Wednesday: 60,
    Thursday: 60,
    Friday: 0,
    Saturday: 180,
    Sunday: 90,
  },
  sportEligibility: {
    Monday: ["bike"],
    Tuesday: ["swim", "run"],
    Wednesday: ["bike"],
    Thursday: ["run"],
    Friday: [],
    Saturday: ["swim", "bike", "run"],
    Sunday: ["run"],
  },
};

const MARKDOWN = `
Some preamble the model added anyway.

# Plan Summary
Total weeks: 2 | Race: Olympic | Date: 2026-12-06

## W1 — Base — 2026-11-16
Total: 5h | Swim 1h | Bike 2.5h | Run 1.5h
- Swim: Easy 40min, Tempo 20min
- Bike: Easy 90min, Intervals 45min
- Run: Long 75min
Notes: Aerobic base

## W2 — Race — 2026-11-23
Total: 3h | Swim 0.5h | Bike 1.5h | Run 1h
- Swimming: 30 min Easy
- Bike: Easy 60min
- Running: Easy 30min
Notes: Race week
`;

Deno.test("fillTemplate replaces every placeholder and does not interpret $", () => {
  const template = "Weeks {{total_weeks}}. Ceiling {{weekly_hours}}. Again {{total_weeks}}.";
  const filled = fillTemplate(template, {
    total_weeks: "8",
    weekly_hours: "5",
  });
  assertEquals(filled, "Weeks 8. Ceiling 5. Again 8.");

  const tricky = fillTemplate("Value: {{note}}", { note: "cost is $100 and $' still here" });
  assertEquals(tricky, "Value: cost is $100 and $' still here");
});

Deno.test("step 1 prompt has no leftover placeholders", () => {
  const filled = fillTemplate(STEP1, {
    training_philosophy: "philosophy",
    experience_level: "intermediate",
    race_distance: "Olympic (1.5km swim / 40km bike / 10km run)",
    race_date: "2026-12-06",
    plan_start_date: "2026-11-16",
    weekly_hours: "8",
    current_weekly_hours: "5",
    ftp_watts: "220",
    mas_kmh: "15",
    swim_css: "1:45",
    limiters: "none",
    swim_weekday_count: "2",
    swim_weekend_count: "0",
    bike_weekday_count: "2",
    bike_weekend_count: "1",
    run_weekday_count: "2",
    run_weekend_count: "1",
    total_weeks: "8",
    max_weekday_minutes: "60",
    max_weekend_minutes: "180",
  });
  assertEquals(filled.includes("{{"), false);
  assertEquals(filled.includes("Generate a 8-week"), true);
  assertEquals(filled.split("8").length > 3, true);
});

Deno.test("horizon rejects a race that is today or tomorrow", () => {
  assertThrows(
    () => computePlanHorizon("2026-11-15T00:00:00.000Z", NOW),
    PlanInputError,
  );
  assertThrows(
    () => computePlanHorizon("2026-11-16", NOW),
    PlanInputError,
  );
});

Deno.test("horizon counts whole weeks from tomorrow", () => {
  const horizon = computePlanHorizon("2026-12-06T00:00:00.000Z", NOW);
  assertEquals(horizon.planStartISO, "2026-11-16");
  assertEquals(horizon.raceISO, "2026-12-06");
  assertEquals(horizon.totalWeeks, 3);
});

Deno.test("zero-minute days are rest days, not available slots", () => {
  const athlete = toAthletePlanInput({
    race_objective: "Olympic",
    race_date: "2026-12-06",
    mon_duration: 0,
    tue_duration: "60",
    wed_duration: null,
    swim_days: "[\"Tuesday\"]",
    bike_days: [],
    run_days: null,
  });
  assertEquals(athlete.mon_duration, null);
  assertEquals(athlete.tue_duration, 60);
  assertEquals(athlete.swim_days, ["Tuesday"]);
  assertEquals(athlete.bike_days, []);
  assertEquals(weeklyTrainingMinutes(athlete), 60);
});

Deno.test("a profile with no training time is rejected before any model call", () => {
  const athlete = toAthletePlanInput({
    race_objective: "Olympic",
    race_date: "2026-12-06",
  });
  assertThrows(() => assertGeneratable(athlete), PlanInputError, "at least one day");
});

Deno.test("an in-flight plan is reused; a stale or failed one is replaced", () => {
  const created = "2026-11-15T12:00:00.000Z";
  const now = Date.parse(created) + 30_000;
  assertEquals(shouldRestartPlan(null, now), "create");
  assertEquals(
    shouldRestartPlan({ status: "generating", created_at: created }, now),
    "attach",
  );
  assertEquals(
    shouldRestartPlan(
      { status: "generating", created_at: created },
      Date.parse(created) + 9 * 60 * 1000,
    ),
    "replace",
  );
  assertEquals(shouldRestartPlan({ status: "failed", created_at: created }, now), "replace");
  assertEquals(shouldRestartPlan({ status: "active", created_at: created }, now), "replace");
});

Deno.test("markdown macro plan parses the compact format, including messy variants", () => {
  const plan = parseMacroMarkdown(MARKDOWN);
  assertEquals(plan.weeks.length, 2);
  assertEquals(plan.weeks[0].phase, "Base");
  assertEquals(plan.weeks[0].week_number, 1);
  assertEquals(plan.weeks[0].swim.sessions.map((s) => s.type), ["Easy", "Tempo"]);
  assertEquals(plan.weeks[0].bike.sessions[1], { type: "Intervals", duration_minutes: 45 });
  assertEquals(plan.weeks[0].run.sessions[0].type, "Easy");
  assertEquals(plan.weeks[0].notes, "Aerobic base");
  assertEquals(plan.weeks[1].phase, "Taper");
  assertEquals(plan.weeks[1].swim.sessions[0].duration_minutes, 30);

  const accepted = macroPlanFromMarkdown(MARKDOWN, 2);
  assertEquals(accepted?.weeks.length, 2);
  assertEquals(macroPlanFromMarkdown("no weeks here", 8), null);
  assertEquals(macroPlanFromMarkdown(MARKDOWN, 8), null);
});

Deno.test("markdown splitter keeps week headers inside each chunk", () => {
  const chunks = splitMarkdownWeeks(MARKDOWN, 1);
  assertEquals(chunks.length, 2);
  assertEquals(chunks[0].includes("## W1"), true);
  assertEquals(chunks[1].includes("## W2"), true);
  assertEquals(chunks[0].includes("## W2"), false);
});

Deno.test("model JSON parses fenced output and a trailing explanation", () => {
  const fenced = "```json\n{\"weeks\":[{\"week_number\":1}]}\n```";
  assertEquals(extractWeekArray(parseModelJson(fenced)).length, 1);

  const trailing = "Sure.\n{\"weeks\":[{\"week_number\":2}]}\nDone.";
  assertEquals((extractWeekArray(parseModelJson(trailing))[0].week_number), 2);
});

Deno.test("a renumbered step 3 block is mapped back onto the macro weeks", () => {
  const macro = [
    { week_number: 5, phase: "Build" },
    { week_number: 6, phase: "Build" },
  ];
  const aligned = alignBlockWeeks(
    { weeks: [{ week_number: 1, phase: "Build" }, { week_number: 2 }] },
    macro,
  );
  assertEquals(aligned.map((week) => week.week_number), [5, 6]);
  assertEquals(aligned[1].phase, "Build");
});

Deno.test("prepare repairs invalid sessions and synthesizes a missed week", () => {
  const macro = parseMacroMarkdown(MARKDOWN).weeks as unknown as Array<Record<string, unknown>>;
  const dirty = [
    {
      week_number: 1,
      phase: "race",
      sessions: [
        { sport: "Running", type: "OPENER", duration_minutes: "45min", day: "Thu" },
        { sport: "strength", type: "Easy", duration_minutes: 30, day: "Monday" },
        { sport: "bike", type: "Intervals", template_id: "BIKE_Intervals_01", duration_minutes: 45, day: "Monday" },
      ],
    },
  ];

  const weeks = preparePlanWeeks(dirty, macro, LIBRARY, CONSTRAINTS);
  assertEquals(weeks.map((week) => week.week_number), [1, 2]);

  const week1 = weeks[0];
  assertEquals(week1.phase, "Taper");
  const sessions = week1.sessions as Array<Record<string, unknown>>;
  assertEquals(sessions.some((session) => session.sport === "strength"), false);
  const run = sessions.find((session) => session.sport === "run");
  assertEquals(run?.type, "Easy");
  assertEquals(run?.template_id, "RUN_Easy_01");
  assertEquals(typeof run?.day, "string");
  assertEquals(["Tuesday", "Thursday", "Saturday", "Sunday"].includes(String(run?.day)), true);

  const bike = sessions.find((session) => session.sport === "bike");
  assertEquals(bike?.template_id, "BIKE_Intervals_01");
  assertEquals(bike?.day, "Monday");

  const week2 = weeks[1];
  const synthesized = week2.sessions as Array<Record<string, unknown>>;
  assertEquals(synthesized.length > 0, true);
  for (const session of synthesized) {
    assertEquals(["swim", "bike", "run"].includes(String(session.sport)), true);
    assertEquals(["Easy", "Tempo", "Intervals"].includes(String(session.type)), true);
    assertEquals(typeof session.template_id, "string");
    assertEquals(Number(session.duration_minutes) > 0, true);
  }
});

Deno.test("the post-fixer pass keeps placed days and does not refill a cleared week", () => {
  const macro = [
    {
      week_number: 1,
      phase: "Base",
      sessions: [
        { sport: "run", type: "Easy", duration_minutes: 75, day: "Saturday" },
      ],
    },
    {
      week_number: 2,
      phase: "Build",
      swim: { sessions: [{ type: "Easy", duration_minutes: 30 }] },
    },
  ];
  const afterFixers = [
    {
      week_number: 1,
      phase: "not-a-phase",
      sessions: [
        {
          sport: "run",
          type: "Long",
          template_id: "RUN_Easy_02",
          duration_minutes: 75,
          day: "Saturday",
          is_brick: false,
        },
      ],
    },
    { week_number: 2, phase: "Build", sessions: [] },
  ];

  const weeks = preparePlanWeeks(afterFixers, macro, LIBRARY, CONSTRAINTS, {
    preserveDays: true,
    fillGaps: false,
  });
  assertEquals(weeks.map((week) => week.week_number), [1, 2]);
  assertEquals(weeks[0].phase, "Base");
  const kept = (weeks[0].sessions as Array<Record<string, unknown>>)[0];
  assertEquals(kept.day, "Saturday");
  assertEquals(kept.type, "Easy");
  assertEquals(kept.duration_minutes, 75);
  assertEquals((weeks[1].sessions as unknown[]).length, 0);
});

Deno.test("retry classification and public errors", () => {
  assertEquals(isRetryableError(retryable("Workout block response was cut off")), true);
  assertEquals(isRetryableError(Object.assign(new Error("nope"), { status: 429 })), true);
  assertEquals(isRetryableError(new SyntaxError("Unexpected end of JSON input")), true);
  assertEquals(isRetryableError(new PlanInputError("Choose a race date before generating a plan.")), false);
  assertEquals(isRetryableError(Object.assign(new Error("bad schema"), { status: 400 })), false);

  const leaked = publicErrorMessage(new Error("OpenAI error sk-abcSECRET Bearer tok123"));
  assertEquals(leaked.includes("sk-abc"), false);
  assertEquals(leaked.includes("tok123"), false);
  assertEquals(leaked.startsWith("Plan generation failed:"), true);
});
