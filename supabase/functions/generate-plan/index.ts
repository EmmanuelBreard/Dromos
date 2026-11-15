import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import OpenAI from "npm:openai@4";

// The edge runtime provides this global. The imported .d.ts only declares a namespace.
declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };

// Shared materializer — pure function, no Supabase/Deno.env deps.
// Converts a WorkoutTemplate from workout-library.json into the SessionStructure
// JSON shape stored in plan_sessions.structure.
import { materialize, type WorkoutTemplate } from "../_shared/materialize-structure.ts";
import {
  isRetryableError,
  PlanInputError,
  publicErrorMessage,
  retryable,
  withRetry,
} from "./lib/errors.ts";
import {
  assertGeneratable,
  computePlanHorizon,
  shouldRestartPlan,
  toAthletePlanInput,
  weeklyTrainingMinutes,
  type AthletePlanInput,
} from "./lib/input.ts";
import { fillTemplate } from "./lib/prompt.ts";
import {
  extractWeekArray,
  macroPlanFromMarkdown,
  parseModelJson,
  splitMarkdownWeeks,
  type MacroPlan,
} from "./lib/macro-plan.ts";
import { alignBlockWeeks, preparePlanWeeks } from "./lib/sanitize.ts";

// Static assets (bundled as TS modules for CLI deploy)
import STEP1_MACRO_PLAN_PROMPT from "./prompts/step1-macro-plan-prompt.ts";
import STEP2_MD_TO_JSON_PROMPT from "./prompts/step2-md-to-json-prompt.ts";
import STEP3_WORKOUT_BLOCK_PROMPT from "./prompts/step3-workout-block-prompt.ts";
import TRAINING_PHILOSOPHY from "./context/training-philosophy-content.ts";

// Large static asset fetched at runtime from Supabase Storage (too big to bundle on free plan)
// Construct URL dynamically from SUPABASE_URL environment variable
function getWorkoutLibraryUrl(): string {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  if (!supabaseUrl) {
    throw new Error("SUPABASE_URL environment variable not set");
  }
  return `${supabaseUrl}/storage/v1/object/public/static-assets/workout-library.json`;
}

// Constants
const BLOCK_SIZE = 4;
const MODEL_STEP1 = "gpt-4.1";
const MODEL_STEP2 = "gpt-4o-mini";
const MODEL_STEP3 = "gpt-4.1";
const TEMPERATURE = 0.2;
const MAX_TOKENS_STEP1 = 16384;
const MAX_TOKENS_STEP2 = 16384;
// A 4-week block of workouts is often larger than 4k tokens once pretty-printed.
// Truncation used to throw at JSON.parse and fail the whole plan.
const MAX_TOKENS_STEP3 = 16384;

// Plans still running when the isolate is killed (wall-clock). One listener for
// the warm worker; each request registers its plan id.
const inflightPlans = new Map<string, { db: any; settled: boolean }>();

if (typeof addEventListener === "function") {
  addEventListener("beforeunload", (ev: Event) => {
    const reason = (ev as Event & { detail?: { reason?: string } }).detail?.reason ?? "shutdown";
    for (const [id, job] of inflightPlans) {
      if (job.settled) continue;
      const pending = job.db
        .from("training_plans")
        .update({
          status: "failed",
          error_message: `Plan generation was interrupted (${reason}). Please try again.`.slice(0, 300),
          failed_at: new Date().toISOString(),
        })
        .eq("id", id)
        .eq("status", "generating");
      try {
        EdgeRuntime.waitUntil(Promise.resolve(pending));
      } catch {
        // The isolate is already going away.
      }
    }
  });
}

// Day normalization (for post-processing)
const DAY_NORM: Record<string, string> = {
  "mon": "Monday",
  "monday": "Monday",
  "tue": "Tuesday",
  "tues": "Tuesday",
  "tuesday": "Tuesday",
  "wed": "Wednesday",
  "wednesday": "Wednesday",
  "thu": "Thursday",
  "thur": "Thursday",
  "thurs": "Thursday",
  "thursday": "Thursday",
  "fri": "Friday",
  "friday": "Friday",
  "sat": "Saturday",
  "saturday": "Saturday",
  "sun": "Sunday",
  "sunday": "Sunday",
};

const ALL_DAYS = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
];

function normDay(d: string): string {
  return DAY_NORM[(d || "").toLowerCase()] || d;
}

// Helper: Format date as YYYY-MM-DD
function formatDate(date: Date): string {
  return date.toISOString().split("T")[0];
}

// Helper: Add days to a date
function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}

// Helper: Map experience_years to experience_level
function mapExperienceLevel(experienceYears: number | null): string {
  if (experienceYears === null || experienceYears === undefined) {
    return "beginner";
  }
  if (experienceYears <= 1) return "beginner";
  if (experienceYears <= 4) return "intermediate";
  return "experienced";
}

// Helper: Expand race_objective to full description
function expandRaceObjective(raceObjective: string | null): string {
  if (!raceObjective) return "not specified";
  const mapping: Record<string, string> = {
    Olympic: "Olympic (1.5km swim / 40km bike / 10km run)",
    "Ironman 70.3": "Half-Ironman (1.9km swim / 90km bike / 21.1km run)",
  };
  return mapping[raceObjective] || raceObjective;
}

// Helper: Format CSS pace from total seconds per 100m
function formatCSS(cssSecondsPer100m: number | null): string {
  if (cssSecondsPer100m === null || cssSecondsPer100m === undefined) return "not provided";
  const minutes = Math.floor(cssSecondsPer100m / 60);
  const seconds = cssSecondsPer100m % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

// Helper: Compute per-session duration caps for weekdays and weekends
// Weekday cap = smallest non-null Mon-Fri duration (conservative: fits any weekday)
// Weekend cap = largest non-null Sat-Sun duration (generous: allows long sessions)
function calculateSessionDurationCaps(user: any): { maxWeekday: number; maxWeekend: number } {
  const weekdayDurations = [
    user.mon_duration,
    user.tue_duration,
    user.wed_duration,
    user.thu_duration,
    user.fri_duration,
  ].filter((d: number | null) => d !== null && d !== undefined) as number[];

  const weekendDurations = [
    user.sat_duration,
    user.sun_duration,
  ].filter((d: number | null) => d !== null && d !== undefined) as number[];

  const maxWeekday = weekdayDurations.length > 0 ? Math.min(...weekdayDurations) : 60;
  const maxWeekend = weekendDurations.length > 0 ? Math.max(...weekendDurations) : 240;

  return { maxWeekday, maxWeekend };
}

// OpenAI client initialization
function getOpenAIClient(): OpenAI {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    throw new Error("OPENAI_API_KEY not set");
  }
  return new OpenAI({ apiKey });
}

function modelOutputCap(model: string): number {
  // gpt-4o-mini rejects completions above 16,384. gpt-4.1 allows 32,768.
  if (model.includes("gpt-4o")) return 16384;
  return 32768;
}

function isUnsupportedMaxTokens(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error ?? "");
  return /max_tokens/i.test(message) && /unsupported|not supported|max_completion_tokens/i.test(message);
}

// Call OpenAI. Retries transient failures and a too-small token budget.
// Returns finishReason so callers can tell a truncated JSON blob from a finished one.
async function callOpenAI(
  client: OpenAI,
  model: string,
  prompt: string,
  temperature: number,
  maxTokens: number,
  responseFormat?: { type: "json_object" }
): Promise<{ content: string; finishReason: string | null }> {
  const cap = modelOutputCap(model);
  let tokens = Math.min(maxTokens, cap);
  let useCompletionTokens = false;
  let lastError: unknown;

  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const tokenLimit = useCompletionTokens
        ? { max_completion_tokens: tokens }
        : { max_tokens: tokens };
      const response = await client.chat.completions.create({
        model,
        messages: [{ role: "user", content: prompt }],
        temperature,
        ...tokenLimit,
        ...(responseFormat && { response_format: responseFormat }),
      });

      const choice = response.choices[0];
      const content = choice?.message?.content?.trim() ?? "";
      const finishReason = choice?.finish_reason ?? null;
      if (!content) throw retryable("The model returned an empty response.");
      if (finishReason === "length" && tokens < cap && attempt < 2) {
        tokens = Math.min(cap, tokens * 2);
        throw retryable("The model response was cut off.");
      }
      return { content, finishReason };
    } catch (error) {
      lastError = error;
      if (!useCompletionTokens && isUnsupportedMaxTokens(error)) {
        useCompletionTokens = true;
        attempt -= 1;
        continue;
      }
      if (!isRetryableError(error) || attempt === 2) break;
      await new Promise((resolve) => setTimeout(resolve, 400 * 2 ** attempt));
    }
  }

  throw lastError instanceof Error ? lastError : new Error("The plan generator hit a temporary error.");
}

// Build prompt for Step 1 (macro plan).
// Every placeholder is replaced, including the ones the rules repeat
// (`{{total_weeks}}`, `{{weekly_hours}}`). A single String.replace left those
// literal, so the short-plan and volume rules never saw the athlete's numbers.
function buildStep1Prompt(
  user: AthletePlanInput,
  vars: { raceDate: string; planStartDate: string; totalWeeks: number; weeklyHours: number },
): string {
  const caps = calculateSessionDurationCaps(user);
  const weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"];
  const weekendDays = ["Saturday", "Sunday"];
  const swimDays = new Set(user.swim_days || []);
  const bikeDays = new Set(user.bike_days || []);
  const runDays = new Set(user.run_days || []);
  const count = (days: Set<string>, pool: string[]) =>
    pool.filter((day) => days.has(day)).length.toString();

  return fillTemplate(STEP1_MACRO_PLAN_PROMPT, {
    training_philosophy: TRAINING_PHILOSOPHY,
    experience_level: mapExperienceLevel(user.experience_years),
    race_distance: expandRaceObjective(user.race_objective),
    race_date: vars.raceDate,
    plan_start_date: vars.planStartDate,
    total_weeks: vars.totalWeeks.toString(),
    weekly_hours: vars.weeklyHours.toString(),
    current_weekly_hours: user.current_weekly_hours != null
      ? user.current_weekly_hours.toString()
      : "not provided",
    ftp_watts: user.ftp ? user.ftp.toString() : "not provided",
    mas_kmh: user.vma ? user.vma.toString() : "not provided",
    swim_css: formatCSS(user.css_seconds_per100m),
    limiters: (user.limiters || "none").toString().replace(/[\n\r]/g, " ").slice(0, 200),
    max_weekday_minutes: caps.maxWeekday.toString(),
    max_weekend_minutes: caps.maxWeekend.toString(),
    swim_weekday_count: count(swimDays, weekdays),
    swim_weekend_count: count(swimDays, weekendDays),
    bike_weekday_count: count(bikeDays, weekdays),
    bike_weekend_count: count(bikeDays, weekendDays),
    run_weekday_count: count(runDays, weekdays),
    run_weekend_count: count(runDays, weekendDays),
  });
}

// Build prompt for Step 2 (MD → JSON). Function replacement so a `$` in the
// markdown cannot be eaten as a replacement pattern.
function buildStep2Prompt(step1Output: string): string {
  return fillTemplate(STEP2_MD_TO_JSON_PROMPT, { step1_output: step1Output });
}

// Build constraint string from user profile
// Formats per-day availability, sport eligibility, and duration caps for Step 3
function buildConstraintString(user: any): string {
  const dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
  const durationFields = ["mon_duration", "tue_duration", "wed_duration", "thu_duration", "fri_duration", "sat_duration", "sun_duration"];

  // Parse sport availability arrays (JSONB)
  const swimDays = new Set(user.swim_days || []);
  const bikeDays = new Set(user.bike_days || []);
  const runDays = new Set(user.run_days || []);

  const lines: string[] = [];

  for (let i = 0; i < dayNames.length; i++) {
    const day = dayNames[i];
    const duration = user[durationFields[i]];

    if (duration === null || duration === undefined) {
      // No availability on this day = REST day
      lines.push(`${day}: REST`);
    } else {
      // Build list of eligible sports for this day
      const eligibleSports: string[] = [];
      if (swimDays.has(day)) eligibleSports.push("swim");
      if (bikeDays.has(day)) eligibleSports.push("bike");
      if (runDays.has(day)) eligibleSports.push("run");

      if (eligibleSports.length === 0) {
        // User has duration but no sport eligibility = constraint error, but handle gracefully
        lines.push(`${day}: ${duration}min available (no sports eligible)`);
      } else if (eligibleSports.length === 3) {
        // All sports eligible = simpler format
        lines.push(`${day}: ${duration}min available (all sports)`);
      } else {
        // Some sports eligible
        lines.push(`${day}: ${duration}min available (${eligibleSports.join(", ")} only)`);
      }
    }
  }

  return lines.join("\n");
}

// Build a simplified workout library string for Step 3
// Reads pre-computed duration_minutes from each template (added to workout-library.json)
// Reduces prompt from ~20K tokens to ~1K tokens
function buildSimplifiedLibrary(workoutLibrary: any): string {
  const lines: string[] = [];
  for (const sport of ["swim", "bike", "run"]) {
    for (const tmpl of workoutLibrary[sport] || []) {
      const tid: string = tmpl.template_id;
      const type = tid.split("_")[1];
      lines.push(`${tid} | ${sport} | ${type} | ${tmpl.duration_minutes}min`);
    }
  }
  return "template_id | sport | type | duration\n" + lines.join("\n");
}

// Parse user profile into structured constraint objects for post-processing fixers.
// Returns { dayCaps: { Monday: 60, ... }, sportEligibility: { Monday: ['swim','run'], ... } }
function parseConstraints(user: any): {
  dayCaps: Record<string, number>;
  sportEligibility: Record<string, string[]>;
} {
  const dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
  const durationFields = ["mon_duration", "tue_duration", "wed_duration", "thu_duration", "fri_duration", "sat_duration", "sun_duration"];

  const swimDays = new Set(user.swim_days || []);
  const bikeDays = new Set(user.bike_days || []);
  const runDays = new Set(user.run_days || []);

  const dayCaps: Record<string, number> = {};
  const sportEligibility: Record<string, string[]> = {};

  for (let i = 0; i < dayNames.length; i++) {
    const day = dayNames[i];
    const duration = user[durationFields[i]];
    dayCaps[day] = duration !== null && duration !== undefined ? duration : 0;

    const eligible: string[] = [];
    if (swimDays.has(day)) eligible.push("swim");
    if (bikeDays.has(day)) eligible.push("bike");
    if (runDays.has(day)) eligible.push("run");
    sportEligibility[day] = eligible;
  }

  return { dayCaps, sportEligibility };
}

// Compute session priority for eviction ordering.
// Intervals(3) > Tempo(2) > Easy(1), +0.5 if is_brick.
function sessionPriority(session: any): number {
  const typeScores: Record<string, number> = { Intervals: 3, Tempo: 2, Easy: 1 };
  return (typeScores[session.type] || 1) + (session.is_brick ? 0.5 : 0);
}

// Build template_id → duration_minutes lookup from workout library.
// e.g. { SWIM_Easy_01: 40, BIKE_Tempo_01: 45, ... }
function buildTemplateDurationMap(lib: any): Record<string, number> {
  const map: Record<string, number> = {};
  for (const sport of ["swim", "bike", "run"]) {
    for (const tmpl of lib[sport] || []) {
      map[tmpl.template_id] = tmpl.duration_minutes;
    }
  }
  return map;
}

// Build template_id → full WorkoutTemplate lookup from workout library.
// Used at insert time to materialise the structure column without re-scanning the library.
function buildTemplateMap(lib: any): Record<string, WorkoutTemplate> {
  const map: Record<string, WorkoutTemplate> = {};
  for (const sport of ["swim", "bike", "run"]) {
    for (const tmpl of lib[sport] || []) {
      map[tmpl.template_id] = tmpl as WorkoutTemplate;
    }
  }
  return map;
}

// Extract last-used templates from a block result
function extractLastUsed(blockResult: any): any[] {
  const lastUsed: Record<string, any> = {};
  for (const week of blockResult.weeks || []) {
    for (const session of week.sessions || []) {
      const key = `${session.sport}_${session.type}`;
      lastUsed[key] = {
        sport: session.sport,
        type: session.type,
        template_id: session.template_id,
        week: week.week_number,
      };
    }
  }
  return Object.values(lastUsed);
}

// Non-standard session types the LLM occasionally emits (as a `type` value or baked
// into an invented template_id like RUN_OPENER_01), mapped onto the 3 valid types.
// Mirrors the DRO-318 phase normalization (Race -> Taper). Keys are lower-cased.
const TYPE_ALIASES: Record<string, string> = {
  brick: "Easy", // brick transition run — the is_brick flag carries the brick-ness
  opener: "Easy", // race-week primer: short easy + a few surges
  openers: "Easy",
  primer: "Easy",
  shakeout: "Easy",
  recovery: "Easy",
  endurance: "Easy",
  long: "Easy",
  aerobic: "Easy",
  race: "Tempo", // "Race" / "Race-pace" effort maps to Tempo
  racepace: "Tempo",
  "race-pace": "Tempo",
  threshold: "Tempo",
  sweetspot: "Tempo",
  "sweet-spot": "Tempo",
  vo2: "Intervals",
  vo2max: "Intervals",
  interval: "Intervals",
  speed: "Intervals",
  hard: "Intervals",
};

// Post-processing: normalize any non-standard session type onto {Easy,Tempo,Intervals}
// BEFORE fixTypes/validation, and repair the template_id so it points at a real library
// template of the resolved (sport, type). This is the deterministic guard that stops a
// stray LLM type (e.g. "OPENER", "BRICK") from crashing generation at the validation gate
// (DRO-320 + follow-ups). Runs first in the fixer chain so everything downstream sees
// valid types/templates.
function normalizeSessionTypes(
  planWeeks: any[],
  workoutLibrary: any,
  durationMap: Record<string, number>
): number {
  const VALID = new Set(["Easy", "Tempo", "Intervals"]);
  // catalog: `${sport}_${type}` -> [{ id, dur }] for template repair
  const catalog: Record<string, { id: string; dur: number }[]> = {};
  for (const sport of ["swim", "bike", "run"]) {
    for (const t of workoutLibrary[sport] || []) {
      if (typeof t.template_id !== "string" || !t.template_id) continue;
      const seg = t.template_id.split("_")[1];
      const key = `${sport}_${seg}`;
      (catalog[key] = catalog[key] || []).push({
        id: t.template_id,
        dur: durationMap[t.template_id] || t.duration_minutes || 0,
      });
    }
  }

  let fixes = 0;
  for (const week of planWeeks) {
    for (const s of week.sessions || []) {
      const tidSeg = s.template_id ? s.template_id.split("_")[1] : undefined;
      // Resolve the intended valid type: trust a valid template segment first, else
      // alias the declared type, else fall back to Easy (the safe, lowest-stress default).
      let type: string;
      if (tidSeg && VALID.has(tidSeg)) {
        type = tidSeg;
      } else if (VALID.has(s.type)) {
        type = s.type;
      } else {
        type = TYPE_ALIASES[String(s.type || "").toLowerCase().trim()] || "Easy";
      }

      // Repair the template_id if it doesn't resolve or its type segment disagrees.
      const tidResolves =
        s.template_id && durationMap[s.template_id] !== undefined && tidSeg === type;
      if (!tidResolves) {
        const opts = catalog[`${s.sport}_${type}`] || [];
        if (opts.length > 0) {
          const want = s.duration_minutes || opts[0].dur;
          opts.sort((a, b) => Math.abs(a.dur - want) - Math.abs(b.dur - want));
          s.template_id = opts[0].id;
          s.duration_minutes = opts[0].dur;
        }
      }

      if (s.type !== type) {
        s.type = type;
        fixes++;
      }
    }
  }
  return fixes;
}

// Post-processing: fix type from template_id (source of truth)
function fixTypes(planWeeks: any[]): number {
  let fixes = 0;
  for (const week of planWeeks) {
    for (const session of week.sessions || []) {
      const tid = session.template_id;
      if (!tid) continue;
      // Extract type from template_id: e.g. "SWIM_Easy_01" → "Easy"
      const tidType = tid.split("_")[1];
      if (tidType && session.type !== tidType) {
        session.type = tidType;
        fixes++;
      }
    }
  }
  return fixes;
}

// Post-processing: fix brick pairs (both sessions on same day must have is_brick)
function fixBrickPairs(planWeeks: any[]): number {
  let fixes = 0;
  for (const week of planWeeks) {
    // Group sessions by day
    const byDay: Record<string, any[]> = {};
    for (const session of week.sessions || []) {
      const d = normDay(session.day);
      byDay[d] = byDay[d] || [];
      byDay[d].push(session);
    }
    // If any session on a day has is_brick, ensure the bike+run pair both have it
    for (const [day, sessions] of Object.entries(byDay)) {
      const hasBrick = sessions.some((s) => s.is_brick);
      if (!hasBrick) continue;
      const bike = sessions.find((s) => s.sport === "bike");
      const run = sessions.find((s) => s.sport === "run");
      if (bike && run) {
        if (!bike.is_brick) {
          bike.is_brick = true;
          fixes++;
        }
        if (!run.is_brick) {
          run.is_brick = true;
          fixes++;
        }
      }
    }
  }
  return fixes;
}

// Post-processing: fix consecutive-week template repeats (duration-aware)
function fixConsecutiveRepeats(
  planWeeks: any[],
  workoutLibrary: any,
  durationMap: Record<string, number>
): number {
  // Build catalog of available templates per category from the library
  const catalog: Record<string, string[]> = {};
  for (const sport of ["swim", "bike", "run"]) {
    if (workoutLibrary[sport]) {
      for (const w of workoutLibrary[sport]) {
        if (typeof w.template_id !== "string" || !w.template_id) continue;
        const type = w.template_id.split("_")[1];
        const cat = `${sport}_${type}`;
        if (!catalog[cat]) catalog[cat] = [];
        catalog[cat].push(w.template_id);
      }
    }
  }

  let fixes = 0;
  const sorted = [...planWeeks].sort(
    (a, b) => a.week_number - b.week_number
  );

  for (let i = 1; i < sorted.length; i++) {
    const prevWeek = sorted[i - 1];
    const currWeek = sorted[i];

    // Build map of previous week's templates per sport/type
    const prevMap: Record<string, Set<string>> = {};
    for (const s of prevWeek.sessions || []) {
      const key = `${s.sport}_${s.type}`;
      if (!prevMap[key]) prevMap[key] = new Set();
      prevMap[key].add(s.template_id);
    }

    // Check current week for repeats and swap with closest-duration alternative
    for (const session of currWeek.sessions || []) {
      const key = `${session.sport}_${session.type}`;
      if (prevMap[key] && prevMap[key].has(session.template_id)) {
        const options = (catalog[key] || []).filter(
          (t) => t !== session.template_id
        );
        if (options.length > 0) {
          const originalDuration = durationMap[session.template_id] || 0;
          // Sort by closest duration to avoid introducing cap violations downstream
          options.sort(
            (a, b) =>
              Math.abs((durationMap[a] || 0) - originalDuration) -
              Math.abs((durationMap[b] || 0) - originalDuration)
          );
          const alt = options[0];
          session.template_id = alt;
          session.duration_minutes = durationMap[alt] || session.duration_minutes;
          fixes++;
        }
      }
    }
  }
  return fixes;
}

// Post-processing: fix duration cap violations
// When total session minutes on a day exceed dayCaps[day], apply cascading fixes:
//   1. Swap longest session to shorter template (same sport/type, within 20% margin)
//   2. Move session to eligible day with remaining capacity
//   3. Evict lowest-priority session in the week (if target outranks)
//   4. Last resort: drop lowest-priority session on the day
function fixDurationCaps(
  planWeeks: any[],
  workoutLibrary: any,
  durationMap: Record<string, number>,
  dayCaps: Record<string, number>,
  sportEligibility: Record<string, string[]>
): number {
  // Build template catalog per sport/type for swapping
  const catalog: Record<string, string[]> = {};
  for (const sport of ["swim", "bike", "run"]) {
    for (const w of workoutLibrary[sport] || []) {
      if (typeof w.template_id !== "string" || !w.template_id) continue;
      const type = w.template_id.split("_")[1];
      const cat = `${sport}_${type}`;
      if (!catalog[cat]) catalog[cat] = [];
      catalog[cat].push(w.template_id);
    }
  }

  const MARGIN = 1.2; // Accept templates within 20% of remaining cap
  const TRIGGER_MARGIN = 1.1; // Only fix days exceeding 10% over cap
  let fixes = 0;

  for (const week of planWeeks) {
    // Compute used minutes per day
    const usedMinutes: Record<string, number> = {};
    for (const s of week.sessions || []) {
      const d = normDay(s.day);
      usedMinutes[d] = (usedMinutes[d] || 0) + (s.duration_minutes || 0);
    }

    for (const day of ALL_DAYS) {
      const cap = dayCaps[day] || 0;
      if (cap === 0) continue; // REST day — handled by fixRestDays

      let iterations = 0;
      const MAX_ITER = 10;

      while ((usedMinutes[day] || 0) > cap * TRIGGER_MARGIN && iterations < MAX_ITER) {
        iterations++;
        const daySessions = (week.sessions || []).filter(
          (s: any) => normDay(s.day) === day
        );
        if (daySessions.length === 0) break;

        // Target the longest session on the overflowing day
        daySessions.sort(
          (a: any, b: any) =>
            (b.duration_minutes || 0) - (a.duration_minutes || 0)
        );
        const target = daySessions[0];
        const targetDur = target.duration_minutes || 0;

        // Remaining cap for this slot = cap minus all OTHER sessions
        const othersTotal = (usedMinutes[day] || 0) - targetDur;
        const slotCap = cap - othersTotal;

        // Strategy 1: Swap to shorter template (same sport/type, fits within margin)
        const key = `${target.sport}_${target.type}`;
        const swapCandidates = (catalog[key] || []).filter((tid) => {
          const dur = durationMap[tid] || 0;
          return dur < targetDur && dur <= slotCap * MARGIN;
        });

        if (swapCandidates.length > 0) {
          swapCandidates.sort(
            (a, b) => (durationMap[b] || 0) - (durationMap[a] || 0)
          );
          const alt = swapCandidates[0];
          const altDur = durationMap[alt] || 0;
          usedMinutes[day] = usedMinutes[day] - targetDur + altDur;
          target.template_id = alt;
          target.duration_minutes = altDur;
          fixes++;
          continue;
        }

        // Strategy 2: Move session to eligible day with remaining capacity
        const moveCandidates = ALL_DAYS.filter((d) => {
          if (d === day) return false;
          const eligible = sportEligibility[d] || [];
          if (!eligible.includes(target.sport)) return false;
          const remaining = (dayCaps[d] || 0) - (usedMinutes[d] || 0);
          return remaining >= targetDur;
        });

        if (moveCandidates.length > 0) {
          moveCandidates.sort(
            (a, b) =>
              ((dayCaps[b] || 0) - (usedMinutes[b] || 0)) -
              ((dayCaps[a] || 0) - (usedMinutes[a] || 0))
          );
          const newDay = moveCandidates[0];
          usedMinutes[day] -= targetDur;
          target.day = newDay;
          usedMinutes[newDay] = (usedMinutes[newDay] || 0) + targetDur;
          fixes++;
          continue;
        }

        // Strategy 3: Evict lowest-priority session in the week if target outranks
        const targetPriority = sessionPriority(target);
        let lowestSession: any = null;
        let lowestPriority = Infinity;

        for (const other of week.sessions || []) {
          if (other === target) continue;
          const p = sessionPriority(other);
          if (p < lowestPriority) {
            lowestPriority = p;
            lowestSession = other;
          }
        }

        if (lowestSession && targetPriority > lowestPriority) {
          const evictDay = normDay(lowestSession.day);
          const evictDur = lowestSession.duration_minutes || 0;
          usedMinutes[evictDay] = (usedMinutes[evictDay] || 0) - evictDur;
          const idx = week.sessions.indexOf(lowestSession);
          if (idx >= 0) week.sessions.splice(idx, 1);
          fixes++;
          continue;
        }

        // Strategy 4: Last resort — drop lowest-priority session on this day
        const dayByPriority = [...daySessions].sort(
          (a: any, b: any) => sessionPriority(a) - sessionPriority(b)
        );
        const toDrop = dayByPriority[0];
        const dropDur = toDrop.duration_minutes || 0;
        usedMinutes[day] -= dropDur;
        const dropIdx = week.sessions.indexOf(toDrop);
        if (dropIdx >= 0) week.sessions.splice(dropIdx, 1);
        fixes++;
      }
    }
  }

  return fixes;
}

// Post-processing: fix rest day violations (cap-aware + sport-eligibility-aware)
// Moves sessions off rest days to eligible days that have remaining capacity.
// Falls back to priority-based eviction when no day has room.
function fixRestDays(
  planWeeks: any[],
  macroWeeks: any[],
  dayCaps: Record<string, number>,
  sportEligibility: Record<string, string[]>
): number {
  let fixes = 0;
  for (const week of planWeeks) {
    const macroWeek = macroWeeks.find(
      (w: any) => w.week_number === week.week_number
    );
    if (!macroWeek || !macroWeek.rest_days) continue;

    const restDays = new Set(macroWeek.rest_days.map(normDay));
    if (restDays.size === 0) continue;

    // Track used minutes per day for cap checking
    const usedMinutes: Record<string, number> = {};
    for (const s of week.sessions || []) {
      const d = normDay(s.day);
      usedMinutes[d] = (usedMinutes[d] || 0) + (s.duration_minutes || 0);
    }

    // Snapshot sessions on rest days to avoid splice-during-iteration bugs
    const restSessions = (week.sessions || []).filter(
      (s: any) => restDays.has(normDay(s.day))
    );

    for (const session of restSessions) {
      const d = normDay(session.day);
      const dur = session.duration_minutes || 0;

      // Find eligible days: not a rest day, sport is allowed, and has remaining capacity
      const candidates = ALL_DAYS.filter((day) => {
        if (restDays.has(day)) return false;
        const eligible = sportEligibility[day] || [];
        if (!eligible.includes(session.sport)) return false;
        const remaining = (dayCaps[day] || 0) - (usedMinutes[day] || 0);
        return remaining >= dur;
      });

      if (candidates.length > 0) {
        // Pick the day with the most remaining capacity
        candidates.sort(
          (a, b) =>
            ((dayCaps[b] || 0) - (usedMinutes[b] || 0)) -
            ((dayCaps[a] || 0) - (usedMinutes[a] || 0))
        );
        const newDay = candidates[0];
        usedMinutes[d] = (usedMinutes[d] || 0) - dur;
        session.day = newDay;
        usedMinutes[newDay] = (usedMinutes[newDay] || 0) + dur;
        fixes++;
      } else {
        // No day has capacity — evict lowest-priority session in the week if current outranks
        const currentPriority = sessionPriority(session);
        let lowestSession: any = null;
        let lowestPriority = Infinity;

        for (const other of week.sessions || []) {
          if (other === session) continue;
          const otherDay = normDay(other.day);
          if (restDays.has(otherDay)) continue; // skip sessions also on rest days
          const p = sessionPriority(other);
          if (p < lowestPriority) {
            lowestPriority = p;
            lowestSession = other;
          }
        }

        if (lowestSession && currentPriority > lowestPriority) {
          // Evict the lower-priority session and take its day
          const evictDay = normDay(lowestSession.day);
          const evictDur = lowestSession.duration_minutes || 0;
          usedMinutes[evictDay] = (usedMinutes[evictDay] || 0) - evictDur;
          usedMinutes[d] = (usedMinutes[d] || 0) - dur;
          // Remove evicted session
          const idx = week.sessions.indexOf(lowestSession);
          if (idx >= 0) week.sessions.splice(idx, 1);
          // Move current session to evicted day
          session.day = evictDay;
          usedMinutes[evictDay] = (usedMinutes[evictDay] || 0) + dur;
          fixes++;
        }
        // If current session is lower priority, leave it (will be caught by fixDurationCaps later)
      }
    }
  }
  return fixes;
}

// Post-processing: spread hard sessions (Tempo/Intervals) to prevent consecutive hard days
// Tries both days of a consecutive pair, uses post-swap adjacency simulation, and
// checks same-sport conflicts on swap targets
function fixIntensitySpread(
  planWeeks: any[],
  dayCaps: Record<string, number>,
  sportEligibility: Record<string, string[]>
): number {
  const HARD_TYPES = ['Tempo', 'Intervals'];
  let fixes = 0;

  for (const week of planWeeks) {
    // Group sessions by day
    const byDay: Record<string, any[]> = {};
    for (const session of week.sessions || []) {
      const d = normDay(session.day);
      byDay[d] = byDay[d] || [];
      byDay[d].push(session);
    }

    // Build list of hard days (days with at least one bike/run Tempo/Intervals session)
    // Swim intensity is excluded — swim hard day adjacent to bike/run hard day is acceptable
    const hardDays: string[] = [];
    for (const day of ALL_DAYS) {
      const sessions = byDay[normDay(day)] || [];
      if (sessions.some((s: any) => HARD_TYPES.includes(s.type) && s.sport !== 'swim')) {
        hardDays.push(day);
      }
    }

    // Find consecutive hard day pairs
    for (let i = 0; i < hardDays.length - 1; i++) {
      const day1 = hardDays[i];
      const day2 = hardDays[i + 1];
      const day1Idx = ALL_DAYS.indexOf(day1);
      const day2Idx = ALL_DAYS.indexOf(day2);

      // Check if they are consecutive in ALL_DAYS
      if (day2Idx !== day1Idx + 1) continue;

      // Try both day2 and day1 — sometimes day1's hard session is easier to relocate
      let resolved = false;
      for (const dayToFix of [day2, day1]) {
        if (resolved) break;
        const daySessions = byDay[normDay(dayToFix)] || [];
        const hardSession = daySessions.find((s: any) => HARD_TYPES.includes(s.type) && s.sport !== 'swim');
        if (!hardSession || hardSession.is_brick) continue;

        const hardSessionDur = hardSession.duration_minutes || 0;

        // Strategy A: Swap with Easy session on another day (post-swap adjacency check)
        for (const candidateDay of ALL_DAYS) {
          if (candidateDay === dayToFix) continue;

          // Post-swap adjacency: after swap, dayToFix is no longer hard, candidateDay becomes hard
          const postSwapHardDays = hardDays.filter((hd: string) => hd !== dayToFix);
          if (!postSwapHardDays.includes(candidateDay)) postSwapHardDays.push(candidateDay);
          postSwapHardDays.sort((a: string, b: string) => ALL_DAYS.indexOf(a) - ALL_DAYS.indexOf(b));
          const hasConsecutiveAfterSwap = postSwapHardDays.some((hd: string, idx: number) => {
            if (idx === 0) return false;
            return ALL_DAYS.indexOf(hd) === ALL_DAYS.indexOf(postSwapHardDays[idx - 1]) + 1;
          });
          if (hasConsecutiveAfterSwap) continue;

          const candidateSessions = byDay[normDay(candidateDay)] || [];
          if (candidateSessions.some((s: any) => s.is_brick)) continue;

          for (const candidate of candidateSessions) {
            if (candidate.type !== 'Easy' || candidate.is_brick) continue;

            const candidateDur = candidate.duration_minutes || 0;
            if (!(sportEligibility[candidateDay] || []).includes(hardSession.sport)) continue;
            if (!(sportEligibility[dayToFix] || []).includes(candidate.sport)) continue;

            // No same-sport on target day after swap
            if (['bike', 'run'].includes(hardSession.sport) &&
                candidateSessions.some((s: any) => s !== candidate && s.sport === hardSession.sport)) continue;
            // No same-sport on source day after swap
            if (['bike', 'run'].includes(candidate.sport) &&
                daySessions.some((s: any) => s !== hardSession && s.sport === candidate.sport)) continue;

            const dayUsed = daySessions.reduce((sum: number, s: any) => sum + (s.duration_minutes || 0), 0);
            const dayRemaining = (dayCaps[dayToFix] || 0) - dayUsed + hardSessionDur;
            const candUsed = candidateSessions.reduce((sum: number, s: any) => sum + (s.duration_minutes || 0), 0);
            const candRemaining = (dayCaps[candidateDay] || 0) - candUsed + candidateDur;

            if (dayRemaining < candidateDur || candRemaining < hardSessionDur) continue;

            // Perform swap
            byDay[normDay(dayToFix)] = (byDay[normDay(dayToFix)] || []).filter((s: any) => s !== hardSession);
            byDay[normDay(candidateDay)] = (byDay[normDay(candidateDay)] || []).filter((s: any) => s !== candidate);
            byDay[normDay(candidateDay)] = byDay[normDay(candidateDay)] || [];
            byDay[normDay(candidateDay)].push(hardSession);
            byDay[normDay(dayToFix)] = byDay[normDay(dayToFix)] || [];
            byDay[normDay(dayToFix)].push(candidate);

            hardSession.day = candidateDay;
            candidate.day = dayToFix;

            fixes++;
            resolved = true;
            break;
          }
          if (resolved) break;
        }

        // Strategy B: Direct move to day with capacity (with post-move adjacency check)
        if (!resolved) {
          for (const gapDay of ALL_DAYS) {
            if (gapDay === dayToFix) continue;
            if ((byDay[normDay(gapDay)] || []).some((s: any) => s.is_brick)) continue;

            // Post-move adjacency check
            const postMoveHardDays = hardDays.filter((hd: string) => hd !== dayToFix);
            if (!postMoveHardDays.includes(gapDay)) postMoveHardDays.push(gapDay);
            postMoveHardDays.sort((a: string, b: string) => ALL_DAYS.indexOf(a) - ALL_DAYS.indexOf(b));
            const hasConsecutiveAfterMove = postMoveHardDays.some((hd: string, idx: number) => {
              if (idx === 0) return false;
              return ALL_DAYS.indexOf(hd) === ALL_DAYS.indexOf(postMoveHardDays[idx - 1]) + 1;
            });
            if (hasConsecutiveAfterMove) continue;

            if (!(sportEligibility[gapDay] || []).includes(hardSession.sport)) continue;

            const gapSessions = byDay[normDay(gapDay)] || [];
            // No same-sport on target day
            if (['bike', 'run'].includes(hardSession.sport) &&
                gapSessions.some((s: any) => s.sport === hardSession.sport)) continue;
            // No dual hard on target day
            if (gapSessions.some((s: any) => HARD_TYPES.includes(s.type) && ['bike', 'run'].includes(s.sport))) continue;

            const gapUsed = gapSessions.reduce((sum: number, s: any) => sum + (s.duration_minutes || 0), 0);
            const gapRemaining = (dayCaps[gapDay] || 0) - gapUsed;

            if (gapRemaining >= hardSessionDur) {
              byDay[normDay(dayToFix)] = (byDay[normDay(dayToFix)] || []).filter((s: any) => s !== hardSession);
              hardSession.day = gapDay;
              byDay[normDay(gapDay)] = byDay[normDay(gapDay)] || [];
              byDay[normDay(gapDay)].push(hardSession);

              fixes++;
              resolved = true;
              break;
            }
          }
        }
      }

      if (resolved) {
        // Rebuild hardDays after swap/move (swim excluded)
        hardDays.length = 0;
        for (const d of ALL_DAYS) {
          const sess = byDay[normDay(d)] || [];
          if (sess.some((s: any) => HARD_TYPES.includes(s.type) && s.sport !== 'swim')) {
            hardDays.push(d);
          }
        }
        i = -1; // Restart from beginning (will increment to 0)
        continue;
      }
    }
  }

  return fixes;
}

// Helper: Get sports from neighboring single-session days
function getNeighborSingleSessionSports(
  byDay: Record<string, any[]>,
  targetDay: string,
  allDays: string[]
): string[] {
  const targetIdx = allDays.indexOf(targetDay);
  const neighborSports: string[] = [];

  // Check previous day
  if (targetIdx > 0) {
    const prevDay = allDays[targetIdx - 1];
    const prevSessions = byDay[normDay(prevDay)] || [];
    if (prevSessions.length === 1) {
      neighborSports.push(prevSessions[0].sport);
    }
  }

  // Check next day
  if (targetIdx < allDays.length - 1) {
    const nextDay = allDays[targetIdx + 1];
    const nextSessions = byDay[normDay(nextDay)] || [];
    if (nextSessions.length === 1) {
      neighborSports.push(nextSessions[0].sport);
    }
  }

  return neighborSports;
}

// Post-processing: fix sport clustering on single-session days
// When consecutive single-session days have the same sport, spread them apart
function fixSportClustering(
  planWeeks: any[],
  dayCaps: Record<string, number>,
  sportEligibility: Record<string, string[]>,
  weeklyHours?: number
): number {
  // Skip for high-volume athletes — consecutive same-sport days are expected with 3 sports over 7 days
  if ((weeklyHours || 0) >= 8) return 0;
  let fixes = 0;

  for (const week of planWeeks) {
    // Group sessions by day
    const byDay: Record<string, any[]> = {};
    for (const session of week.sessions || []) {
      const d = normDay(session.day);
      byDay[d] = byDay[d] || [];
      byDay[d].push(session);
    }

    // Identify single-session days
    const singleSessionDays: string[] = [];
    for (const day of ALL_DAYS) {
      const cap = dayCaps[day] || 0;
      const sessions = byDay[normDay(day)] || [];
      if (cap > 0 && sessions.length === 1) {
        singleSessionDays.push(day);
      }
    }

    // Check for consecutive single-session days with the same sport
    for (let i = 0; i < singleSessionDays.length - 1; i++) {
      const day1 = singleSessionDays[i];
      const day2 = singleSessionDays[i + 1];

      // Check if they are consecutive in ALL_DAYS
      const idx1 = ALL_DAYS.indexOf(day1);
      const idx2 = ALL_DAYS.indexOf(day2);
      if (idx2 !== idx1 + 1) continue;

      const session1 = byDay[normDay(day1)][0];
      const session2 = byDay[normDay(day2)][0];

      // Never swap brick sessions — would break brick pairing
      if (session2.is_brick) continue;

      // If same sport, try to move session2
      if (session1.sport === session2.sport) {
        const session2Dur = session2.duration_minutes || 0;
        let swapCandidate: any = null;
        let swapCandidateDay: string | null = null;

        // PHASE 1: Try same-sport+type swap first (current behavior)
        for (const candidateDay of ALL_DAYS) {
          // Skip day1 and days adjacent to day1
          const candidateIdx = ALL_DAYS.indexOf(candidateDay);
          if (candidateIdx === idx1 || candidateIdx === idx1 - 1 || candidateIdx === idx1 + 1) {
            continue;
          }

          const candidateSessions = byDay[normDay(candidateDay)] || [];
          for (const candidate of candidateSessions) {
            if (
              candidate.sport === session2.sport &&
              candidate.type === session2.type &&
              !candidate.is_brick
            ) {
              const candidateDur = candidate.duration_minutes || 0;

              // Check if swap is feasible
              const candidateDayEligible = (sportEligibility[candidateDay] || []).includes(session2.sport);
              const candidateDayCap = dayCaps[candidateDay] || 0;
              const candidateDayUsed = candidateSessions.reduce((sum: number, s: any) => sum + (s.duration_minutes || 0), 0);
              const candidateDayRemaining = candidateDayCap - candidateDayUsed + candidateDur;

              const day2Eligible = (sportEligibility[day2] || []).includes(candidate.sport);
              const day2Cap = dayCaps[day2] || 0;

              if (
                candidateDayEligible &&
                candidateDayRemaining >= session2Dur &&
                day2Eligible &&
                day2Cap >= candidateDur
              ) {
                swapCandidate = candidate;
                swapCandidateDay = candidateDay;
                break;
              }
            }
          }
          if (swapCandidate) break;
        }

        // PHASE 2: Fall back to cross-sport swap if no same-sport+type found
        if (!swapCandidate) {
          for (const candidateDay of ALL_DAYS) {
            const candidateIdx = ALL_DAYS.indexOf(candidateDay);
            if (candidateIdx === idx1 || candidateIdx === idx1 - 1 || candidateIdx === idx1 + 1) {
              continue;
            }

            const candidateSessions = byDay[normDay(candidateDay)] || [];
            for (const candidate of candidateSessions) {
              if (candidate.is_brick) continue;

              const candidateDur = candidate.duration_minutes || 0;

              // Check sport eligibility both ways
              const session2EligibleOnCandidateDay = (sportEligibility[candidateDay] || []).includes(session2.sport);
              const candidateEligibleOnDay2 = (sportEligibility[day2] || []).includes(candidate.sport);

              if (!session2EligibleOnCandidateDay || !candidateEligibleOnDay2) continue;

              // Check duration caps both ways
              const candidateDayCap = dayCaps[candidateDay] || 0;
              const candidateDayUsed = candidateSessions.reduce((sum: number, s: any) => sum + (s.duration_minutes || 0), 0);
              const candidateDayRemaining = candidateDayCap - candidateDayUsed + candidateDur;

              if (candidateDayRemaining < session2Dur) continue;

              const day2Cap = dayCaps[day2] || 0;
              if (day2Cap < candidateDur) continue;

              // Check swap doesn't CREATE new clustering on day2
              const day2Neighbors = getNeighborSingleSessionSports(byDay, day2, ALL_DAYS);
              if (day2Neighbors.includes(candidate.sport)) continue;

              // Also check that session2 doesn't cluster on candidateDay
              const candNeighbors = getNeighborSingleSessionSports(byDay, candidateDay, ALL_DAYS);
              if (candNeighbors.includes(session2.sport)) continue;

              swapCandidate = candidate;
              swapCandidateDay = candidateDay;
              break;
            }
            if (swapCandidate) break;
          }
        }

        // Perform the swap
        if (swapCandidate && swapCandidateDay) {
          // Update byDay to reflect the swap
          byDay[normDay(day2)] = (byDay[normDay(day2)] || []).filter((s: any) => s !== session2);
          byDay[normDay(swapCandidateDay)] = (byDay[normDay(swapCandidateDay)] || []).filter((s: any) => s !== swapCandidate);
          byDay[normDay(swapCandidateDay)] = byDay[normDay(swapCandidateDay)] || [];
          byDay[normDay(swapCandidateDay)].push(session2);
          byDay[normDay(day2)] = byDay[normDay(day2)] || [];
          byDay[normDay(day2)].push(swapCandidate);
          // Update day properties on session objects
          session2.day = swapCandidateDay;
          swapCandidate.day = day2;
          fixes++;
        }
      }
    }
  }

  return fixes;
}

// Post-processing: ensure brick sessions in Build/Peak weeks
// Creates bike+run brick pairs when missing (weekly in Build/Peak, biweekly in Base)
function fixMissingBricks(
  planWeeks: any[],
  workoutLibrary: any,
  dayCaps: Record<string, number>,
  sportEligibility: Record<string, string[]>
): number {
  // Preferred brick days - weekends first
  const BRICK_PREFERRED_DAYS = ['Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
  let fixes = 0;

  for (const week of planWeeks) {
    const phase = week.phase;
    // Skip Taper and Recovery weeks
    if (phase === 'Taper' || phase === 'Recovery') continue;
    // Base: biweekly bricks (even-numbered weeks only)
    if (phase === 'Base' && week.week_number % 2 === 1) continue;
    // Check if week already has brick sessions
    if ((week.sessions || []).some((s: any) => s.is_brick)) continue;

    // Group sessions by day
    const byDay: Record<string, any[]> = {};
    for (const session of week.sessions || []) {
      const d = normDay(session.day);
      byDay[d] = byDay[d] || [];
      byDay[d].push(session);
    }

    // Find brick-eligible day
    let brickDay: string | null = null;
    for (const day of BRICK_PREFERRED_DAYS) {
      const eligible = sportEligibility[day] || [];
      if (!eligible.includes('bike') || !eligible.includes('run')) continue;
      if ((dayCaps[day] || 0) < 90) continue; // need enough capacity for bike+run

      // Prefer day that already has a bike session
      if ((byDay[normDay(day)] || []).some((s: any) => s.sport === 'bike')) {
        brickDay = day;
        break;
      }

      // Otherwise take first eligible day
      if (brickDay === null) {
        brickDay = day;
      }
    }

    if (brickDay === null) continue;

    // STEP 1: Clear non-bike sessions off brickDay BEFORE placing brick pair
    const brickDaySessions = [...(byDay[normDay(brickDay)] || [])];
    for (const session of brickDaySessions) {
      if (session.sport === 'bike') continue; // keep bikes

      // Find best alternative day for this session
      const sessionDur = session.duration_minutes || 0;

      // Build list of alternative days: eligible for sport and NOT brickDay
      const candidates = ALL_DAYS.filter((day) => {
        if (day === brickDay) return false;
        const eligible = sportEligibility[day] || [];
        if (!eligible.includes(session.sport)) return false;
        return true;
      });

      // Sort candidates: prefer empty days, then days with fewest sessions that have room
      candidates.sort((a, b) => {
        const aSessions = byDay[normDay(a)] || [];
        const bSessions = byDay[normDay(b)] || [];
        const aUsed = aSessions.reduce((sum: number, s: any) => sum + (s.duration_minutes || 0), 0);
        const bUsed = bSessions.reduce((sum: number, s: any) => sum + (s.duration_minutes || 0), 0);
        const aRemaining = (dayCaps[a] || 0) - aUsed;
        const bRemaining = (dayCaps[b] || 0) - bUsed;

        // Prioritize: empty days first (0 sessions)
        if (aSessions.length === 0 && bSessions.length > 0) return -1;
        if (bSessions.length === 0 && aSessions.length > 0) return 1;

        // Then by fewest sessions
        if (aSessions.length !== bSessions.length) {
          return aSessions.length - bSessions.length;
        }

        // Then by most remaining capacity
        return bRemaining - aRemaining;
      });

      // Find first candidate with enough room
      for (const newDay of candidates) {
        const newDaySessions = byDay[normDay(newDay)] || [];
        const newDayUsed = newDaySessions.reduce((sum: number, s: any) => sum + (s.duration_minutes || 0), 0);
        const newDayRemaining = (dayCaps[newDay] || 0) - newDayUsed;

        if (newDayRemaining >= sessionDur) {
          // Move session
          const oldDay = normDay(session.day);
          byDay[oldDay] = (byDay[oldDay] || []).filter((s: any) => s !== session);
          session.day = newDay;
          byDay[normDay(newDay)] = byDay[normDay(newDay)] || [];
          byDay[normDay(newDay)].push(session);
          break;
        }
      }
      // If no alternative found, leave it (don't break the plan)
    }

    // STEP 2: Ensure a bike session is on brickDay
    let bikeSession = (byDay[normDay(brickDay)] || []).find((s: any) => s.sport === 'bike');
    if (!bikeSession) {
      // Find a bike from another day and move it
      const allBikes = (week.sessions || []).filter(
        (s: any) => s.sport === 'bike' && !s.is_brick
      );
      for (const bike of allBikes) {
        const brickDayUsed = (byDay[normDay(brickDay)] || []).reduce(
          (sum: number, s: any) => sum + (s.duration_minutes || 0), 0
        );
        const brickDayRemaining = (dayCaps[brickDay] || 0) - brickDayUsed;
        if ((bike.duration_minutes || 0) <= brickDayRemaining) {
          // Move bike to brickDay
          const bikeOrigDay = normDay(bike.day);
          byDay[bikeOrigDay] = (byDay[bikeOrigDay] || []).filter((s: any) => s !== bike);
          bike.day = brickDay;
          byDay[normDay(brickDay)] = byDay[normDay(brickDay)] || [];
          byDay[normDay(brickDay)].push(bike);
          bikeSession = bike;
          break;
        }
      }
    }

    if (!bikeSession) continue;

    // STEP 3: Always use RUN_Easy_01 (30min) for brick run
    // Find RUN_Easy_01 template
    const brickRunTemplate = (workoutLibrary.run || []).find(
      (t: any) => t.template_id === 'RUN_Easy_01'
    );
    if (!brickRunTemplate) continue; // Safety check

    // Check if brick run fits on brickDay
    const brickDayUsed = (byDay[normDay(brickDay)] || []).reduce(
      (sum: number, s: any) => sum + (s.duration_minutes || 0), 0
    );
    const brickDayRemaining = (dayCaps[brickDay] || 0) - brickDayUsed;

    if (brickRunTemplate.duration_minutes > brickDayRemaining) continue; // Can't fit 30min run

    // Find any run in the week (non-brick) and move it to brickDay with RUN_Easy_01 template
    const allRuns = (week.sessions || []).filter((s: any) => s.sport === 'run' && !s.is_brick);
    // Prefer shortest Easy run to minimize disruption to quality workouts
    allRuns.sort((a: any, b: any) => {
      if (a.type === 'Easy' && b.type !== 'Easy') return -1;
      if (a.type !== 'Easy' && b.type === 'Easy') return 1;
      return (a.duration_minutes || 0) - (b.duration_minutes || 0);
    });

    if (allRuns.length > 0) {
      const run = allRuns[0];
      const runOrigDay = normDay(run.day);
      byDay[runOrigDay] = (byDay[runOrigDay] || []).filter((s: any) => s !== run);

      // Swap to RUN_Easy_01 (30min)
      run.template_id = brickRunTemplate.template_id;
      run.duration_minutes = brickRunTemplate.duration_minutes;
      run.type = 'Easy';
      run.day = brickDay;
      run.is_brick = true;

      byDay[normDay(brickDay)] = byDay[normDay(brickDay)] || [];
      byDay[normDay(brickDay)].push(run);

      bikeSession.is_brick = true;
      fixes++;
    } else {
      // No existing run to repurpose — create a new brick run
      const newRun: any = {
        sport: 'run',
        type: 'Easy',
        template_id: brickRunTemplate.template_id,
        duration_minutes: brickRunTemplate.duration_minutes,
        day: brickDay,
        is_brick: true,
      };
      week.sessions = week.sessions || [];
      week.sessions.push(newRun);
      byDay[normDay(brickDay)] = byDay[normDay(brickDay)] || [];
      byDay[normDay(brickDay)].push(newRun);
      bikeSession.is_brick = true;
      fixes++;
    }
  }

  return fixes;
}

// Post-processing: enforce RUN_Easy_01 (30min) on all brick-tagged runs
function fixBrickRunDuration(
  planWeeks: any[],
  workoutLibrary: any
): number {
  const brickRunTemplate = (workoutLibrary.run || []).find((t: any) => t.template_id === 'RUN_Easy_01');
  if (!brickRunTemplate) return 0;

  let fixes = 0;
  for (const week of planWeeks) {
    for (const session of week.sessions || []) {
      if (session.is_brick && session.sport === 'run' && (session.duration_minutes || 0) > 30) {
        session.template_id = brickRunTemplate.template_id;
        session.duration_minutes = brickRunTemplate.duration_minutes;
        session.type = 'Easy';
        fixes++;
      }
    }
  }
  // Second pass: catch informal bricks (bike+run same day without is_brick tag)
  for (const week of planWeeks) {
    const byDay: Record<string, any[]> = {};
    for (const session of week.sessions || []) {
      const d = normDay(session.day);
      byDay[d] = byDay[d] || [];
      byDay[d].push(session);
    }
    for (const [day, sessions] of Object.entries(byDay)) {
      const bikes = sessions.filter((s: any) => s.sport === 'bike');
      const runs = sessions.filter((s: any) => s.sport === 'run' && s.type === 'Easy' && !s.is_brick && (s.duration_minutes || 0) > 30);
      if (bikes.length > 0 && runs.length > 0) {
        for (const run of runs) {
          run.template_id = brickRunTemplate.template_id;
          run.duration_minutes = brickRunTemplate.duration_minutes;
          run.type = 'Easy';
          run.is_brick = true;
          fixes++;
        }
        for (const bike of bikes) {
          if (!bike.is_brick) bike.is_brick = true;
        }
        // Enforce bike→run order in sessions array for informal bricks
        const bikeIdx = (week.sessions || []).indexOf(bikes[0]);
        const runIdx2 = (week.sessions || []).indexOf(runs[0]);
        if (bikeIdx >= 0 && runIdx2 >= 0 && runIdx2 < bikeIdx) {
          week.sessions[runIdx2] = bikes[0];
          week.sessions[bikeIdx] = runs[0];
        }
      }
    }
  }

  return fixes;
}

// Post-processing: fix brick ordering (bike before run in sessions array)
function fixBrickOrder(planWeeks: any[]): number {
  let fixes = 0;
  for (const week of planWeeks) {
    const byDay: Record<string, any[]> = {};
    for (const session of week.sessions || []) {
      const d = normDay(session.day);
      byDay[d] = byDay[d] || [];
      byDay[d].push(session);
    }
    for (const [_day, sessions] of Object.entries(byDay)) {
      const brickBike = sessions.find((s: any) => s.is_brick && s.sport === 'bike');
      const brickRun = sessions.find((s: any) => s.is_brick && s.sport === 'run');
      if (!brickBike || !brickRun) continue;
      const bikeIdx = (week.sessions || []).indexOf(brickBike);
      const runIdx = (week.sessions || []).indexOf(brickRun);
      if (bikeIdx >= 0 && runIdx >= 0 && runIdx < bikeIdx) {
        week.sessions[runIdx] = brickBike;
        week.sessions[bikeIdx] = brickRun;
        fixes++;
      }
    }
  }
  return fixes;
}

// Remove a session from both the week and the byDay index.
function removeSessionFromWeek(
  week: any,
  byDay: Record<string, any[]>,
  day: string,
  session: any
): void {
  const idx = (week.sessions || []).indexOf(session);
  if (idx >= 0) week.sessions.splice(idx, 1);
  byDay[normDay(day)] = (byDay[normDay(day)] || []).filter((s: any) => s !== session);
}

// Downgrade a hard (Tempo/Intervals) session to Easy in place — swaps to the closest-
// duration Easy template of the same sport. Used as the LAST RESORT for an unrelocatable
// same-day dual-hard conflict: keeps the session (and its volume) but removes the hard
// clash. Losing one intensity slot on a tight-availability week is the correct trade
// against shipping an illegal plan.
function downgradeSessionToEasy(session: any, workoutLibrary: any): void {
  const dur = session.duration_minutes || 0;
  const alt = (workoutLibrary[session.sport] || [])
    .filter((t: any) => t.template_id.includes("_Easy_"))
    .map((t: any) => ({ id: t.template_id, d: t.duration_minutes || 0 }))
    .sort((a: any, b: any) => Math.abs(a.d - dur) - Math.abs(b.d - dur))[0];
  session.type = "Easy";
  if (alt) {
    session.template_id = alt.id;
    session.duration_minutes = alt.d;
  }
}

// Post-processing: relocate sessions scheduled on a day where their sport is not
// eligible (a HARD sport-eligibility violation — e.g. a run placed on a swim-only day).
// The LLM occasionally ignores the per-sport day lists; no earlier fixer specifically
// repairs this. Reuses tryRelocateSession, which only ever moves a session to an eligible
// day with capacity and never introduces same-sport/dual-hard conflicts. Last resort: if
// no eligible day has room, drop the session (it cannot be placed legally for this
// athlete). Brick sessions are left to the brick fixers to avoid splitting a pair.
function fixSportEligibility(
  planWeeks: any[],
  dayCaps: Record<string, number>,
  sportEligibility: Record<string, string[]>,
  workoutLibrary: any
): number {
  let fixes = 0;
  for (const week of planWeeks) {
    const byDay: Record<string, any[]> = {};
    for (const session of week.sessions || []) {
      const d = normDay(session.day);
      byDay[d] = byDay[d] || [];
      byDay[d].push(session);
    }

    // --- Pass A: brick pairs on a day not eligible for BOTH sports ---
    // A brick (bike+run same day) needs a day eligible for every sport in the pair.
    // Relocate the whole pair to such a day with room; if none exists, dissolve the
    // brick (clear is_brick) so Pass B can place each half individually.
    const brickDays = new Set<string>();
    for (const s of week.sessions || []) if (s.is_brick) brickDays.add(normDay(s.day));
    for (const bday of brickDays) {
      const bricks = (byDay[bday] || []).filter((s: any) => s.is_brick);
      if (bricks.length === 0) continue;
      const sports = [...new Set(bricks.map((s: any) => s.sport))];
      const elig = sportEligibility[bday] || [];
      if (sports.every((sp) => elig.includes(sp))) continue; // brick day is legal

      const totalDur = bricks.reduce((a: number, s: any) => a + (s.duration_minutes || 0), 0);
      let target: string | null = null;
      for (const td of ALL_DAYS) {
        if (normDay(td) === bday) continue;
        const te = sportEligibility[td] || [];
        if (!sports.every((sp) => te.includes(sp))) continue;
        const tsessions = byDay[normDay(td)] || [];
        // Keep the brick on its own day pair — skip targets already holding a bike/run.
        if (tsessions.some((s: any) => ["bike", "run"].includes(s.sport))) continue;
        const used = tsessions.reduce((a: number, s: any) => a + (s.duration_minutes || 0), 0);
        if (used + totalDur > (dayCaps[td] || 0)) continue;
        target = normDay(td);
        break;
      }

      if (target) {
        for (const s of bricks) {
          byDay[bday] = (byDay[bday] || []).filter((x: any) => x !== s);
          s.day = target;
          byDay[target] = byDay[target] || [];
          byDay[target].push(s);
        }
        fixes++;
      } else {
        // No day supports the brick — dissolve it; Pass B relocates/drops each half.
        for (const s of bricks) s.is_brick = false;
      }
    }

    // --- Pass B: individual (non-brick) sessions on a sport-ineligible day ---
    // Snapshot: we may relocate or drop sessions while iterating.
    for (const session of [...(week.sessions || [])]) {
      if (session.is_brick) continue; // preserved bricks were handled in Pass A
      const day = normDay(session.day);
      if ((sportEligibility[day] || []).includes(session.sport)) continue; // already legal
      if (tryRelocateSession(session, day, week, byDay, dayCaps, sportEligibility, workoutLibrary)) {
        fixes++;
        continue;
      }
      // No eligible day has capacity — the session cannot be legally placed; drop it.
      removeSessionFromWeek(week, byDay, day, session);
      fixes++;
    }
  }
  return fixes;
}

// Post-processing: fix same-day hard session conflicts
// Rule 1: Max 1 bike and max 1 run per day (brick sessions count)
// Rule 2: No two hard (bike/run) sessions on same day (brick hard sessions count)
// Swim is exempt from both rules.
// When a conflicting session cannot be relocated (tight availability), a deterministic
// LAST RESORT is applied so the violation never ships: Rule 1 merges two Easy duplicates
// (or drops the lower-priority one); Rule 2 downgrades one hard session to Easy.
function fixSameDayHardConflicts(
  planWeeks: any[],
  dayCaps: Record<string, number>,
  sportEligibility: Record<string, string[]>,
  workoutLibrary: any
): number {
  const HARD_TYPES = ['Tempo', 'Intervals'];
  let fixes = 0;

  for (const week of planWeeks) {
    const byDay: Record<string, any[]> = {};
    for (const session of week.sessions || []) {
      const d = normDay(session.day);
      byDay[d] = byDay[d] || [];
      byDay[d].push(session);
    }

    // Repeat the day-scan until stable: a relocation or last-resort can drop a session
    // onto an already-scanned day; loop so that newly-introduced conflict is re-resolved
    // in a later pass (bounded — the last-resort guarantees convergence).
    let sdPass = 0;
    let sdPrevFixes = -1;
    while (fixes !== sdPrevFixes && sdPass < 6) {
      sdPrevFixes = fixes;
      for (const day of ALL_DAYS) {
      // Rule 1: Max 1 bike and max 1 run per day (brick sessions count)
      for (const sport of ['bike', 'run']) {
        const sportSessions = (byDay[normDay(day)] || []).filter((s: any) => s.sport === sport);
        if (sportSessions.length < 2) continue;

        // Keep: brick session first, then hard session, then longest
        const keeper = sportSessions.find((s: any) => s.is_brick)
          || sportSessions.find((s: any) => HARD_TYPES.includes(s.type))
          || [...sportSessions].sort((a: any, b: any) => (b.duration_minutes || 0) - (a.duration_minutes || 0))[0];

        const toMove = sportSessions.filter((s: any) => s !== keeper);
        for (const session of toMove) {
          if (tryRelocateSession(session, day, week, byDay, dayCaps, sportEligibility, workoutLibrary)) {
            fixes++;
            continue;
          }
          // Last resort: cannot relocate this same-sport duplicate. If both it and the
          // keeper are Easy, fold its minutes into the keeper (up to the day cap) before
          // dropping it, so volume is preserved; otherwise just drop the duplicate. Never
          // drop a brick session.
          if (session.is_brick) continue;
          removeSessionFromWeek(week, byDay, day, session);
          if (session.type === "Easy" && keeper.type === "Easy" && !keeper.is_brick) {
            const cap = dayCaps[day] || 0;
            const dayUsedAfter = (byDay[normDay(day)] || []).reduce(
              (sum: number, s: any) => sum + (s.duration_minutes || 0),
              0
            );
            const target = Math.min(
              (keeper.duration_minutes || 0) + (session.duration_minutes || 0),
              (keeper.duration_minutes || 0) + (cap - dayUsedAfter)
            );
            const grown = (workoutLibrary[sport] || [])
              .filter((t: any) => t.template_id.includes("_Easy_") && (t.duration_minutes || 0) <= target && (t.duration_minutes || 0) > (keeper.duration_minutes || 0))
              .sort((a: any, b: any) => (b.duration_minutes || 0) - (a.duration_minutes || 0))[0];
            if (grown) {
              keeper.template_id = grown.template_id;
              keeper.duration_minutes = grown.duration_minutes;
            }
          }
          fixes++;
        }
      }

      // Rule 2: No two hard (bike/run) sessions on same day (brick hard sessions count)
      const currentSessions = byDay[normDay(day)] || [];
      const hardBikeRun = currentSessions.filter((s: any) =>
        HARD_TYPES.includes(s.type) && ['bike', 'run'].includes(s.sport)
      );

      if (hardBikeRun.length >= 2) {
        // Prefer moving non-brick session
        const nonBrick = hardBikeRun.filter((s: any) => !s.is_brick);
        const toMove = nonBrick.length > 0
          ? nonBrick.sort((a: any, b: any) => (a.duration_minutes || 0) - (b.duration_minutes || 0))[0]
          : hardBikeRun.sort((a: any, b: any) => (a.duration_minutes || 0) - (b.duration_minutes || 0))[0];
        if (tryRelocateSession(toMove, day, week, byDay, dayCaps, sportEligibility, workoutLibrary)) {
          fixes++;
        } else {
          // Last resort: cannot relocate the second hard session (tight availability).
          // Downgrade it to Easy so the day no longer has two hard bike/run sessions.
          // Keeps the session and its volume; sacrifices one intensity slot to stay legal.
          downgradeSessionToEasy(toMove, workoutLibrary);
          fixes++;
        }
      }
      }
      sdPass++;
    }
  }

  return fixes;
}

// Helper: try to move a session from sourceDay to another day
// Strategy 1: direct move, Strategy 2: swap with Easy of different sport, Strategy 3: downsize + move
function tryRelocateSession(
  session: any,
  sourceDay: string,
  week: any,
  byDay: Record<string, any[]>,
  dayCaps: Record<string, number>,
  sportEligibility: Record<string, string[]>,
  workoutLibrary: any
): boolean {
  const HARD_TYPES = ['Tempo', 'Intervals'];
  const dur = session.duration_minutes || 0;
  const sport = session.sport;
  const isHard = HARD_TYPES.includes(session.type);

  // Strategy 1: Direct move to day with capacity (no new conflicts)
  for (const targetDay of ALL_DAYS) {
    if (targetDay === sourceDay) continue;
    if (!(sportEligibility[targetDay] || []).includes(sport)) continue;
    const targetSessions = byDay[normDay(targetDay)] || [];

    // No same-sport on target day (bike/run only — max 1 per sport per day)
    if (['bike', 'run'].includes(sport) && targetSessions.some((s: any) => s.sport === sport)) continue;
    // No dual hard on target day
    if (isHard && targetSessions.some((s: any) => HARD_TYPES.includes(s.type) && ['bike', 'run'].includes(s.sport))) continue;

    const targetUsed = targetSessions.reduce((sum: number, s: any) => sum + (s.duration_minutes || 0), 0);
    if (targetUsed + dur > (dayCaps[targetDay] || 0)) continue;

    byDay[normDay(sourceDay)] = (byDay[normDay(sourceDay)] || []).filter((s: any) => s !== session);
    session.day = targetDay;
    byDay[normDay(targetDay)] = byDay[normDay(targetDay)] || [];
    byDay[normDay(targetDay)].push(session);
    return true;
  }

  // Strategy 2: Swap with an Easy session of a DIFFERENT sport on another day
  for (const targetDay of ALL_DAYS) {
    if (targetDay === sourceDay) continue;
    const targetSessions = byDay[normDay(targetDay)] || [];

    for (const candidate of targetSessions) {
      if (candidate.is_brick || candidate.type !== 'Easy') continue;
      if (candidate.sport === sport) continue; // different sport only
      if (!(sportEligibility[targetDay] || []).includes(sport)) continue;
      if (!(sportEligibility[sourceDay] || []).includes(candidate.sport)) continue;

      // Check target day after swap: no same-sport conflict
      if (['bike', 'run'].includes(sport) && targetSessions.some((s: any) => s !== candidate && s.sport === sport)) continue;
      // Check target day after swap: no dual hard
      if (isHard && targetSessions.some((s: any) => s !== candidate && HARD_TYPES.includes(s.type) && ['bike', 'run'].includes(s.sport))) continue;
      // Check source day after swap: no same-sport conflict for candidate
      const sourceSessions = byDay[normDay(sourceDay)] || [];
      if (['bike', 'run'].includes(candidate.sport) && sourceSessions.some((s: any) => s !== session && s.sport === candidate.sport)) continue;

      const candidateDur = candidate.duration_minutes || 0;
      const sourceUsed = sourceSessions.reduce((sum: number, s: any) => sum + (s.duration_minutes || 0), 0);
      const sourceRemaining = (dayCaps[sourceDay] || 0) - sourceUsed + dur;
      const targetUsed = targetSessions.reduce((sum: number, s: any) => sum + (s.duration_minutes || 0), 0);
      const targetRemaining = (dayCaps[targetDay] || 0) - targetUsed + candidateDur;

      if (sourceRemaining < candidateDur || targetRemaining < dur) continue;

      byDay[normDay(sourceDay)] = (byDay[normDay(sourceDay)] || []).filter((s: any) => s !== session);
      byDay[normDay(targetDay)] = (byDay[normDay(targetDay)] || []).filter((s: any) => s !== candidate);
      session.day = targetDay;
      candidate.day = sourceDay;
      byDay[normDay(targetDay)] = byDay[normDay(targetDay)] || [];
      byDay[normDay(targetDay)].push(session);
      byDay[normDay(sourceDay)] = byDay[normDay(sourceDay)] || [];
      byDay[normDay(sourceDay)].push(candidate);
      return true;
    }
  }

  // Strategy 3: Downsize + move (for sessions too big for weekday caps)
  if (dur > 60) {
    for (const targetDay of ALL_DAYS) {
      if (targetDay === sourceDay) continue;
      if (!(sportEligibility[targetDay] || []).includes(sport)) continue;
      const targetSessions = byDay[normDay(targetDay)] || [];

      // No same-sport on target day (bike/run only)
      if (['bike', 'run'].includes(sport) && targetSessions.some((s: any) => s.sport === sport)) continue;
      // No dual hard on target day
      if (isHard && targetSessions.some((s: any) => HARD_TYPES.includes(s.type) && ['bike', 'run'].includes(s.sport))) continue;

      const targetUsed = targetSessions.reduce((sum: number, s: any) => sum + (s.duration_minutes || 0), 0);
      const targetRemaining = (dayCaps[targetDay] || 0) - targetUsed;

      if (targetRemaining >= 30) {
        const shorterTemplates = (workoutLibrary[sport] || [])
          .filter((t: any) => {
            const tType = typeof t.template_id === "string" ? t.template_id.split("_")[1] : "";
            return tType === session.type &&
              (t.duration_minutes || 0) <= targetRemaining &&
              (t.duration_minutes || 0) >= 30;
          })
          .sort((a: any, b: any) => (b.duration_minutes || 0) - (a.duration_minutes || 0));

        if (shorterTemplates.length > 0) {
          const shorter = shorterTemplates[0];
          byDay[normDay(sourceDay)] = (byDay[normDay(sourceDay)] || []).filter((s: any) => s !== session);
          session.template_id = shorter.template_id;
          session.duration_minutes = shorter.duration_minutes;
          session.day = targetDay;
          byDay[normDay(targetDay)] = byDay[normDay(targetDay)] || [];
          byDay[normDay(targetDay)].push(session);
          return true;
        }
      }
    }
  }

  return false;
}

// Post-processing: fill empty available days with Easy sessions
// Uses macro plan targets to decide which sport needs the most volume
function fixVolumeGaps(
  planWeeks: any[],
  macroWeeks: any[],
  dayCaps: Record<string, number>,
  sportEligibility: Record<string, string[]>,
  workoutLibrary: any
): number {
  let fixes = 0;

  for (const week of planWeeks) {
    const macroWeek = macroWeeks.find((mw: any) => mw.week_number === week.week_number);
    if (!macroWeek) continue;

    // Skip Recovery/Taper — rest days are expected and healthy in these phases
    if (week.phase === 'Recovery' || week.phase === 'Taper') continue;

    // Build byDay
    const byDay: Record<string, any[]> = {};
    for (const session of week.sessions || []) {
      const d = normDay(session.day);
      byDay[d] = byDay[d] || [];
      byDay[d].push(session);
    }

    // Compute target sport minutes from macro plan
    const targetMinutes: Record<string, number> = {};
    for (const sport of ['swim', 'bike', 'run']) {
      const sportData = macroWeek[sport];
      targetMinutes[sport] = sportData ? Math.round((sportData.hours || 0) * 60) : 0;
    }

    // Compute current sport minutes
    const currentMinutes: Record<string, number> = { swim: 0, bike: 0, run: 0 };
    for (const s of week.sessions || []) {
      if (currentMinutes[s.sport] !== undefined) {
        currentMinutes[s.sport] += (s.duration_minutes || 0);
      }
    }

    // Check if total is under target (skip if already at/over target)
    const currentTotal = currentMinutes.swim + currentMinutes.bike + currentMinutes.run;
    const targetTotal = targetMinutes.swim + targetMinutes.bike + targetMinutes.run;
    if (currentTotal >= targetTotal) continue;

    // Find empty available days (days with capacity but no sessions)
    const emptyDays = ALL_DAYS.filter((day: string) => {
      const cap = dayCaps[day] || 0;
      if (cap === 0) return false;
      return (byDay[normDay(day)] || []).length === 0;
    });

    if (emptyDays.length === 0) continue;

    for (const day of emptyDays) {
      const cap = dayCaps[day] || 0;
      const eligible = sportEligibility[day] || [];
      if (eligible.length === 0) continue;

      // Rank eligible sports by gap (target - current), largest first
      const sportGaps = eligible.map((sport: string) => ({
        sport,
        gap: targetMinutes[sport] - currentMinutes[sport]
      })).sort((a: any, b: any) => b.gap - a.gap);

      // Check sport alternation — prefer sports that don't cluster with neighbors
      const neighborSports = getNeighborSingleSessionSports(byDay, day, ALL_DAYS);

      let chosenSport: string | null = null;
      let chosenTemplate: any = null;

      // First pass: pick sport with largest gap that doesn't cluster
      for (const { sport } of sportGaps) {
        if (neighborSports.includes(sport) && sportGaps.filter((sg: any) => !neighborSports.includes(sg.sport)).length > 0) {
          continue; // skip if would cluster and alternatives exist
        }
        const templates = (workoutLibrary[sport] || [])
          .filter((t: any) => t.template_id.includes('_Easy_') && (t.duration_minutes || 0) <= cap)
          .sort((a: any, b: any) => (b.duration_minutes || 0) - (a.duration_minutes || 0));
        if (templates.length > 0) {
          chosenSport = sport;
          chosenTemplate = templates[0];
          break;
        }
      }

      // Fallback: allow clustering if no non-clustering option
      if (!chosenSport) {
        for (const { sport } of sportGaps) {
          const templates = (workoutLibrary[sport] || [])
            .filter((t: any) => t.template_id.includes('_Easy_') && (t.duration_minutes || 0) <= cap)
            .sort((a: any, b: any) => (b.duration_minutes || 0) - (a.duration_minutes || 0));
          if (templates.length > 0) {
            chosenSport = sport;
            chosenTemplate = templates[0];
            break;
          }
        }
      }

      if (!chosenSport || !chosenTemplate) continue;

      const newSession: any = {
        sport: chosenSport,
        type: 'Easy',
        template_id: chosenTemplate.template_id,
        duration_minutes: chosenTemplate.duration_minutes,
        day: day,
        is_brick: false,
      };

      week.sessions = week.sessions || [];
      week.sessions.push(newSession);
      byDay[normDay(day)] = byDay[normDay(day)] || [];
      byDay[normDay(day)].push(newSession);
      currentMinutes[chosenSport] += chosenTemplate.duration_minutes;

      fixes++;
    }
  }

  return fixes;
}

// Post-processing: smooth week-to-week volume ramp (injury safety).
// Text instructions can't hold a flat/progressive volume curve reliably, so this
// deterministic pass clamps each LOADING week (Base/Build/Peak) into a ±10% band
// around a progressive baseline. Recovery/Taper weeks are EXEMPT (their volume drop
// is intentional) and do NOT reset the baseline — so the week resuming load after a
// deload references the pre-deload plateau, not the deload week (avoids a false
// "+24% after recovery" spike). Only Easy volume is moved: quality sessions
// (Tempo/Intervals) and the weekly long run (longest Easy run, ≥75min) are never cut.
function fixVolumeRamp(
  planWeeks: any[],
  durationMap: Record<string, number>,
  dayCaps: Record<string, number>,
  sportEligibility: Record<string, string[]>,
  workoutLibrary: any,
  startVolumeMinutes: number
): number {
  const MAX_RAMP = 0.1; // a loading week may exceed the baseline by at most +10%
  const MAX_DROP = 0.1; // ...or fall below it by at most -10%
  const MIN_SESSION = 30; // DB floor for {day}_duration
  const LONG_RUN_MIN = 75; // never trim the weekly long run below this
  const TAPER_MAX = 0.6; // a Taper week must sit at or below 60% of the plateau
  const RECOVERY_MAX = 0.7; // a Recovery week must sit at or below 70% of the plateau

  // Easy template catalog per sport, ascending by duration (for down/up swaps).
  const easyBySport: Record<string, { id: string; dur: number }[]> = {};
  for (const sport of ["swim", "bike", "run"]) {
    easyBySport[sport] = (workoutLibrary[sport] || [])
      .filter((t: any) => t.template_id.includes("_Easy_"))
      .map((t: any) => ({ id: t.template_id, dur: durationMap[t.template_id] || t.duration_minutes || 0 }))
      .filter((t: any) => t.dur > 0)
      .sort((a: any, b: any) => a.dur - b.dur);
  }

  const weekTotal = (wk: any): number =>
    (wk.sessions || []).reduce((sum: number, s: any) => sum + (s.duration_minutes || 0), 0);
  const isLoading = (phase: string) => phase === "Base" || phase === "Build" || phase === "Peak";

  const sorted = [...planWeeks].sort((a, b) => (a.week_number || 0) - (b.week_number || 0));
  if (sorted.length === 0) return 0;

  let fixes = 0;
  // Anchor the baseline to the athlete's CURRENT weekly volume so an inflated
  // week-1 from Step 1 can't set the bar for the whole plan.
  let baseline = startVolumeMinutes > 0 ? startVolumeMinutes : weekTotal(sorted[0]);
  if (baseline <= 0) return 0;

  for (const week of sorted) {
    const total = weekTotal(week);

    if (isLoading(week.phase)) {
      // Loading week: clamp into the ±band around the progressive plateau.
      const upper = Math.round(baseline * (1 + MAX_RAMP));
      const lower = Math.round(baseline * (1 - MAX_DROP));
      if (total > upper) {
        fixes += trimWeekVolume(week, total - upper, easyBySport, LONG_RUN_MIN, MIN_SESSION);
      } else if (total < lower) {
        fixes += padWeekVolume(week, lower - total, easyBySport, dayCaps, sportEligibility);
      }
      baseline = weekTotal(week); // ratchet to the (clamped) actual → smooth progression
    } else {
      // Recovery/Taper: the volume drop is intentional — enforce a ceiling BELOW the
      // plateau so a too-heavy deload/taper week is pulled down. "Keep intensity, cut
      // volume": trim Easy only; the long-run floor does NOT apply here (long runs are
      // deliberately shortened in a deload). The plateau (baseline) is NOT updated, so
      // load resuming afterward references the pre-deload plateau, not this low week.
      const ceiling = Math.round(baseline * (week.phase === "Taper" ? TAPER_MAX : RECOVERY_MAX));
      if (total > ceiling) {
        fixes += trimWeekVolume(week, total - ceiling, easyBySport, MIN_SESSION, MIN_SESSION);
      }
    }
  }

  return fixes;
}

// Reduce a week's total minutes by ~excess, cutting only Easy volume via shorter
// Easy-template swaps. Protects the weekly long run (never below LONG_RUN_MIN) and
// never touches Tempo/Intervals. Returns the number of session mutations made.
function trimWeekVolume(
  week: any,
  excess: number,
  easyBySport: Record<string, { id: string; dur: number }[]>,
  longRunMin: number,
  minSession: number
): number {
  let fixes = 0;
  // Identify the week's long run (longest Easy run) to protect below longRunMin.
  let longRun: any = null;
  for (const s of week.sessions || []) {
    if (s.sport === "run" && s.type === "Easy") {
      if (!longRun || (s.duration_minutes || 0) > (longRun.duration_minutes || 0)) longRun = s;
    }
  }

  let guard = 0;
  while (excess > 0 && guard < 50) {
    guard++;
    const floorFor = (s: any) => (s === longRun ? longRunMin : minSession);

    // Easy sessions that still have a strictly-shorter Easy template at/above their floor.
    const candidates = (week.sessions || []).filter((s: any) => {
      if (s.type !== "Easy") return false;
      const floor = floorFor(s);
      const cur = s.duration_minutes || 0;
      if (cur <= floor) return false;
      return (easyBySport[s.sport] || []).some((o) => o.dur < cur && o.dur >= floor);
    });
    if (candidates.length === 0) break;

    // Trim the largest session first (most slack).
    candidates.sort((a: any, b: any) => (b.duration_minutes || 0) - (a.duration_minutes || 0));
    const s = candidates[0];
    const floor = floorFor(s);
    const cur = s.duration_minutes || 0;
    const desired = Math.max(cur - excess, floor);

    const opts = (easyBySport[s.sport] || []).filter((o) => o.dur < cur && o.dur >= floor);
    // Prefer the smallest template >= desired (reduce without overshooting the excess);
    // if none qualifies, take the largest available (reduces the least → minimal overshoot).
    const atOrAbove = opts.filter((o) => o.dur >= desired);
    const chosen = atOrAbove.length > 0 ? atOrAbove[0] : opts[opts.length - 1];

    excess -= cur - chosen.dur;
    s.duration_minutes = chosen.dur;
    s.template_id = chosen.id;
    fixes++;
  }

  return fixes;
}

// Raise a week's total minutes by ~deficit, adding only Easy volume by swapping
// existing Easy sessions UP to longer Easy templates — always within the session's
// day cap. Availability-bound: if caps are full it pads as far as possible and
// accepts the shortfall (never invents time). Returns session mutations made.
function padWeekVolume(
  week: any,
  deficit: number,
  easyBySport: Record<string, { id: string; dur: number }[]>,
  dayCaps: Record<string, number>,
  sportEligibility: Record<string, string[]>
): number {
  let fixes = 0;
  const usedByDay: Record<string, number> = {};
  for (const s of week.sessions || []) {
    const d = normDay(s.day);
    usedByDay[d] = (usedByDay[d] || 0) + (s.duration_minutes || 0);
  }

  let guard = 0;
  while (deficit > 0 && guard < 50) {
    guard++;
    let grew = false;

    // Grow the Easy session whose day has the most remaining headroom.
    const easySessions = (week.sessions || []).filter((s: any) => s.type === "Easy");
    easySessions.sort((a: any, b: any) => {
      const ha = (dayCaps[normDay(a.day)] || 0) - (usedByDay[normDay(a.day)] || 0);
      const hb = (dayCaps[normDay(b.day)] || 0) - (usedByDay[normDay(b.day)] || 0);
      return hb - ha;
    });

    for (const s of easySessions) {
      const d = normDay(s.day);
      const headroom = (dayCaps[d] || 0) - (usedByDay[d] || 0);
      if (headroom <= 0) continue;
      const cur = s.duration_minutes || 0;
      const ceiling = cur + headroom;
      // Longest Easy template that is longer than current and still fits the day cap.
      const opts = (easyBySport[s.sport] || []).filter((o) => o.dur > cur && o.dur <= ceiling);
      if (opts.length === 0) continue;
      const chosen = opts[opts.length - 1];
      const added = chosen.dur - cur;
      s.duration_minutes = chosen.dur;
      s.template_id = chosen.id;
      usedByDay[d] += added;
      deficit -= added;
      fixes++;
      grew = true;
      break;
    }

    if (!grew) break; // no session can grow within caps — availability-bound, accept shortfall
  }

  return fixes;
}

const JSON_HEADERS = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

async function loadWorkoutLibrary(): Promise<any> {
  return await withRetry(async () => {
    const response = await fetch(getWorkoutLibraryUrl());
    if (!response.ok) {
      const error = new Error(`Failed to fetch workout library (${response.status}).`);
      (error as Error & { retryable: boolean }).retryable = response.status >= 500 || response.status === 429;
      throw error;
    }
    return await response.json();
  }, { attempts: 3 });
}

async function convertMarkdownChunk(
  openai: OpenAI,
  chunk: string,
  depth = 0,
): Promise<Record<string, unknown>[]> {
  try {
    return await withRetry(async () => {
      const raw = await callOpenAI(
        openai,
        MODEL_STEP2,
        buildStep2Prompt(chunk),
        0,
        MAX_TOKENS_STEP2,
        { type: "json_object" },
      );
      if (raw.finishReason === "length") {
        const error = new Error("The plan conversion was cut off.");
        (error as Error & { truncated: boolean; retryable: boolean }).truncated = true;
        (error as Error & { retryable: boolean }).retryable = false;
        throw error;
      }
      let parsed: unknown;
      try {
        parsed = parseModelJson(raw.content);
      } catch (error) {
        throw retryable(error instanceof Error ? error.message : "Model returned invalid JSON");
      }
      const weeks = extractWeekArray(parsed);
      if (weeks.length === 0) throw retryable("The plan conversion returned no weeks.");
      return weeks;
    }, { attempts: 2 });
  } catch (error) {
    const truncated = (error as { truncated?: boolean }).truncated === true;
    if (truncated && depth < 2) {
      const smaller = splitMarkdownWeeks(chunk, 3);
      if (smaller.length > 1) {
        const nested = await Promise.all(
          smaller.map((part) => convertMarkdownChunk(openai, part, depth + 1)),
        );
        return nested.flat();
      }
    }
    throw error;
  }
}

async function macroPlanViaModel(openai: OpenAI, markdown: string): Promise<MacroPlan> {
  const chunks = splitMarkdownWeeks(markdown, 8);
  const groups = await Promise.all(chunks.map((chunk) => convertMarkdownChunk(openai, chunk)));
  const byNumber = new Map<number, Record<string, unknown>>();
  for (const week of groups.flat()) {
    const n = Number(week.week_number);
    if (Number.isFinite(n) && n > 0) byNumber.set(n, week);
  }
  const weeks = [...byNumber.values()].sort(
    (a, b) => Number(a.week_number) - Number(b.week_number),
  );
  if (weeks.length === 0) {
    throw new Error("Could not turn the training plan into a schedule. Please try again.");
  }
  return {
    plan_summary: { total_weeks: weeks.length },
    weeks: weeks as unknown as MacroPlan["weeks"],
  };
}

function step3Prompt(
  block: unknown,
  simplifiedLibrary: string,
  limiters: string,
  constraints: string,
): string {
  return fillTemplate(STEP3_WORKOUT_BLOCK_PROMPT, {
    workout_library: simplifiedLibrary,
    block_weeks_json: JSON.stringify(block, null, 2),
    limiters,
    constraints,
    previously_used: "None — blocks are processed in parallel.",
  });
}

async function runStep3Block(
  openai: OpenAI,
  block: any[],
  prompt: string,
): Promise<any[]> {
  try {
    return await withRetry(async () => {
      const raw = await callOpenAI(
        openai,
        MODEL_STEP3,
        prompt,
        TEMPERATURE,
        MAX_TOKENS_STEP3,
        { type: "json_object" },
      );
      // callOpenAI already raised the token budget once. Another attempt would
      // repeat a multi-thousand-token call and blow the wall-clock limit.
      if (raw.finishReason === "length") {
        const error = new Error("Workout block response was cut off.");
        (error as Error & { retryable: boolean }).retryable = false;
        throw error;
      }
      let parsed: unknown;
      try {
        parsed = parseModelJson(raw.content);
      } catch (error) {
        throw retryable(error instanceof Error ? error.message : "Model returned invalid JSON");
      }
      const aligned = alignBlockWeeks(parsed, block);
      if (aligned.length === 0) throw retryable("Workout block returned no weeks.");
      return aligned;
    }, { attempts: 3 });
  } catch (error) {
    console.warn("[generate-plan] step 3 block failed; scheduling from the macro plan:", error);
    return block;
  }
}

/**
 * Run the 3-step pipeline and the fixer chain.
 * `AthletePlanInput` is the stable input: onboarding fills it today, and a
 * conversational onboarding can pass the same object.
 */
async function buildScheduledPlan(
  openai: OpenAI,
  athlete: AthletePlanInput,
  vars: { raceDate: string; planStartDate: string; totalWeeks: number; weeklyHours: number },
): Promise<{ allBlockWeeks: any[]; macroWeeks: any[]; templateMap: Record<string, WorkoutTemplate> }> {
  const started = Date.now();
  const step1 = await callOpenAI(
    openai,
    MODEL_STEP1,
    buildStep1Prompt(athlete, vars),
    TEMPERATURE,
    MAX_TOKENS_STEP1,
  );
  console.log(JSON.stringify({
    event: "generate-plan",
    step: "step1",
    ms: Date.now() - started,
    finish: step1.finishReason,
    chars: step1.content.length,
  }));

  let macroPlan = macroPlanFromMarkdown(step1.content, vars.totalWeeks);
  if (macroPlan) {
    console.log(JSON.stringify({
      event: "generate-plan",
      step: "step2",
      source: "parser",
      weeks: macroPlan.weeks.length,
    }));
  } else {
    const step2Started = Date.now();
    macroPlan = await macroPlanViaModel(openai, step1.content);
    console.log(JSON.stringify({
      event: "generate-plan",
      step: "step2",
      source: "model",
      ms: Date.now() - step2Started,
      weeks: macroPlan.weeks.length,
    }));
  }

  const macroWeeks = macroPlan.weeks;
  if (!Array.isArray(macroWeeks) || macroWeeks.length === 0) {
    throw new Error("The training plan came back empty. Please try again.");
  }

  const workoutLibrary = await loadWorkoutLibrary();
  const blocks: any[][] = [];
  for (let j = 0; j < macroWeeks.length; j += BLOCK_SIZE) {
    blocks.push(macroWeeks.slice(j, j + BLOCK_SIZE));
  }

  const constraintString = buildConstraintString(athlete);
  const simplifiedLibrary = buildSimplifiedLibrary(workoutLibrary);
  const limitersStep3 = (athlete.limiters || "none").toString().replace(/[\n\r]/g, " ").slice(0, 200);
  const step3Started = Date.now();

  const blockResults = await Promise.all(
    blocks.map((block) =>
      runStep3Block(openai, block, step3Prompt(block, simplifiedLibrary, limitersStep3, constraintString))
    ),
  );
  console.log(JSON.stringify({
    event: "generate-plan",
    step: "step3",
    ms: Date.now() - step3Started,
    blocks: blocks.length,
  }));

  const templateDurationMap = buildTemplateDurationMap(workoutLibrary);
  const templateMap = buildTemplateMap(workoutLibrary);
  const { dayCaps, sportEligibility } = parseConstraints(athlete);

  let allBlockWeeks = preparePlanWeeks(
    blockResults.flat(),
    macroWeeks as unknown as Array<Record<string, unknown>>,
    workoutLibrary,
    { dayCaps, sportEligibility },
  );

  normalizeSessionTypes(allBlockWeeks, workoutLibrary, templateDurationMap);
  fixTypes(allBlockWeeks);
  fixBrickPairs(allBlockWeeks);
  fixConsecutiveRepeats(allBlockWeeks, workoutLibrary, templateDurationMap);
  fixDurationCaps(allBlockWeeks, workoutLibrary, templateDurationMap, dayCaps, sportEligibility);
  fixRestDays(allBlockWeeks, macroWeeks, dayCaps, sportEligibility);
  fixSportEligibility(allBlockWeeks, dayCaps, sportEligibility, workoutLibrary);
  fixMissingBricks(allBlockWeeks, workoutLibrary, dayCaps, sportEligibility);
  fixBrickRunDuration(allBlockWeeks, workoutLibrary);
  fixBrickOrder(allBlockWeeks);
  fixSameDayHardConflicts(allBlockWeeks, dayCaps, sportEligibility, workoutLibrary);
  fixIntensitySpread(allBlockWeeks, dayCaps, sportEligibility);
  fixSportClustering(allBlockWeeks, dayCaps, sportEligibility, vars.weeklyHours);
  fixVolumeGaps(allBlockWeeks, macroWeeks, dayCaps, sportEligibility, workoutLibrary);
  fixVolumeRamp(
    allBlockWeeks,
    templateDurationMap,
    dayCaps,
    sportEligibility,
    workoutLibrary,
    (athlete.current_weekly_hours || 0) * 60,
  );
  fixDurationCaps(allBlockWeeks, workoutLibrary, templateDurationMap, dayCaps, sportEligibility);
  fixSportEligibility(allBlockWeeks, dayCaps, sportEligibility, workoutLibrary);
  fixSameDayHardConflicts(allBlockWeeks, dayCaps, sportEligibility, workoutLibrary);
  fixBrickOrder(allBlockWeeks);

  // One last repair pass. Fixers can leave a stray phase or type; do not throw
  // the whole plan away for a label the database would reject.
  allBlockWeeks = preparePlanWeeks(
    allBlockWeeks,
    macroWeeks as unknown as Array<Record<string, unknown>>,
    workoutLibrary,
    { dayCaps, sportEligibility },
    { preserveDays: true, fillGaps: false },
  );

  const sessionCount = allBlockWeeks.reduce(
    (sum, week) => sum + ((week.sessions as unknown[] | undefined)?.length ?? 0),
    0,
  );
  if (sessionCount === 0) {
    throw new Error("The plan generator could not schedule any workouts. Please try again.");
  }

  return { allBlockWeeks, macroWeeks, templateMap };
}

// Main handler
Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  let planId: string | null = null;
  // deno-lint-ignore no-explicit-any
  let dbClient: any = null;

  try {
    // Verify JWT and get user_id
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        {
          status: 401,
          headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
      throw new Error("Missing Supabase environment variables");
    }

    // Cryptographically validate the JWT via auth.getUser() — same pattern as strava-sync.
    // This validates the token server-side, so verify_jwt on the gateway is not required.
    const jwt = authHeader.replace("Bearer ", "");
    const authClient = createClient(supabaseUrl, supabaseAnonKey);
    const { data: { user }, error: authError } = await authClient.auth.getUser(jwt);
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid or expired token" }), {
        status: 401,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }
    const userId = user.id;

    // Create service_role client for DB operations
    dbClient = createClient(supabaseUrl, supabaseServiceRoleKey);

    // Fetch user profile
    const { data: userProfile, error: profileError } = await dbClient
      .from("users")
      .select("*")
      .eq("id", userId)
      .single();

    if (profileError || !userProfile) {
      return new Response(
        JSON.stringify({ error: "User profile not found" }),
        {
          status: 404,
          headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        }
      );
    }

    // Validate required fields
    if (
      !userProfile.race_objective ||
      !userProfile.race_date ||
      !userProfile.onboarding_completed
    ) {
      return new Response(
        JSON.stringify({
          error: "Missing required fields: race_objective, race_date, or onboarding not completed",
        }),
        {
          status: 400,
          headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        }
      );
    }

    // AthletePlanInput is the generation contract. Onboarding writes these
    // fields today; a conversational onboarding can build the same object.
    const athlete = toAthletePlanInput(userProfile);
    assertGeneratable(athlete);
    const horizon = computePlanHorizon(athlete.race_date);
    const weeklyHours = Math.round((weeklyTrainingMinutes(athlete) / 60) * 10) / 10;
    const vars = {
      raceDate: horizon.raceISO,
      planStartDate: horizon.planStartISO,
      totalWeeks: horizon.totalWeeks,
      weeklyHours,
    };
    const planStartDate = horizon.planStartDate;

    const { data: existingPlan, error: existingError } = await dbClient
      .from("training_plans")
      .select("id, status, created_at")
      .eq("user_id", userId)
      .maybeSingle();
    if (existingError) {
      throw new Error(`Failed to read the current plan: ${existingError.message}`);
    }

    // A retry while the first run is still going must not delete that row.
    const decision = shouldRestartPlan(existingPlan, Date.now());
    if (decision === "attach" && existingPlan) {
      console.log(`[generate-plan] attaching to in-flight plan ${existingPlan.id}`);
      return jsonResponse({ planId: existingPlan.id }, 200);
    }
    if (decision === "replace") {
      const { error: deleteError } = await dbClient
        .from("training_plans")
        .delete()
        .eq("user_id", userId);
      if (deleteError) {
        throw new Error(`Failed to delete existing plan: ${deleteError.message}`);
      }
    }

    const { data: plan, error: planError } = await dbClient
      .from("training_plans")
      .insert({
        user_id: userId,
        status: "generating",
        race_date: horizon.raceISO,
        race_objective: athlete.race_objective,
        total_weeks: horizon.totalWeeks,
        start_date: horizon.planStartISO,
      })
      .select()
      .single();

    if (planError || !plan) {
      // Two requests raced to create the single plan row. Use the winner.
      if (planError?.code === "23505") {
        const { data: winner } = await dbClient
          .from("training_plans")
          .select("id")
          .eq("user_id", userId)
          .maybeSingle();
        if (winner?.id) return jsonResponse({ planId: winner.id }, 200);
      }
      throw new Error(`Failed to create training plan: ${planError?.message}`);
    }

    planId = String(plan.id);
    const activePlanId = planId;
    inflightPlans.set(activePlanId, { db: dbClient, settled: false });

    // Respond immediately — plan generation continues as a background task.
    // The iOS app polls training_plans.status for 'active' or 'failed'.
    EdgeRuntime.waitUntil((async () => {
      const planId = activePlanId;
      try {
        const openai = getOpenAIClient();
        const scheduled = await buildScheduledPlan(openai, athlete, vars);
        const allBlockWeeks = scheduled.allBlockWeeks;
        const weeks = scheduled.macroWeeks;
        const templateMap = scheduled.templateMap;

    // Write to database
    const weekIds: Record<number, string> = {};
    const unknownTemplateIds = new Set<string>();

    for (const week of allBlockWeeks) {
      const weekStartDate = addDays(planStartDate, (week.week_number - 1) * 7);
      const macroWeek = weeks.find((w: any) => w.week_number === week.week_number);

      // Compute rest_days from actual sessions (days with no sessions = rest days)
      const scheduledDays = new Set(
        (week.sessions || []).map((s: any) => normDay(s.day))
      );
      const restDays = ALL_DAYS.filter((day) => !scheduledDays.has(day));

      const { data: weekRow, error: weekError } = await dbClient
        .from("plan_weeks")
        .insert({
          plan_id: planId,
          week_number: week.week_number,
          phase: week.phase,
          is_recovery: week.phase === "Recovery",
          rest_days: restDays,
          notes: macroWeek?.notes || null,
          start_date: formatDate(weekStartDate),
        })
        .select()
        .single();

      if (weekError || !weekRow) {
        throw new Error(`Failed to create plan_week: ${weekError?.message}`);
      }

      weekIds[week.week_number] = weekRow.id;

      // Group sessions by day for order_in_day calculation
      const sessionsByDay: Record<string, any[]> = {};
      for (const session of week.sessions || []) {
        const day = normDay(session.day);
        if (!ALL_DAYS.includes(day)) continue;
        if (!sessionsByDay[day]) sessionsByDay[day] = [];
        sessionsByDay[day].push(session);
      }

      const sessionRows = [];
      for (const [day, daySessions] of Object.entries(sessionsByDay)) {
        // Sort sessions: brick bike first (order 0), then brick run (order 1), then others
        daySessions.sort((a, b) => {
          if (a.is_brick && b.is_brick) {
            if (a.sport === "bike") return -1;
            if (b.sport === "bike") return 1;
          }
          if (a.is_brick) return -1;
          if (b.is_brick) return 1;
          return 0;
        });

        for (let i = 0; i < daySessions.length; i++) {
          const session = daySessions[i];
          if (typeof session.template_id !== "string" || !session.template_id) {
            console.warn(
              `[generate-plan] Week ${week.week_number} ${day} session has no template_id — skipping`,
            );
            continue;
          }
          let orderInDay = i;
          if (session.is_brick) {
            orderInDay = session.sport === "bike" ? 0 : 1;
          }

          // Materialise once, against the post-fixer template. A bad template
          // must not abort the plan; the session still saves and the renderer
          // falls back when structure is null.
          const template = templateMap[session.template_id];
          let structure = null;
          if (template) {
            try {
              structure = materialize(template);
            } catch (materializeError) {
              console.warn(
                `[generate-plan] materialize failed for ${session.template_id}:`,
                materializeError,
              );
              unknownTemplateIds.add(session.template_id);
            }
          } else {
            unknownTemplateIds.add(session.template_id);
          }

          const duration = Math.round(Number(session.duration_minutes));
          if (!Number.isFinite(duration) || duration <= 0) continue;

          sessionRows.push({
            week_id: weekRow.id,
            day,
            sport: session.sport,
            type: session.type,
            template_id: session.template_id,
            duration_minutes: duration,
            is_brick: session.is_brick || false,
            notes: null,
            order_in_day: orderInDay,
            structure,
          });
        }
      }

      if (sessionRows.length > 0) {
        const { error: sessionError } = await dbClient.from("plan_sessions").insert(sessionRows);
        if (sessionError) {
          throw new Error(
            `Failed to save workouts for week ${week.week_number}: ${sessionError.message}`,
          );
        }
      }
    }

        // Emit one summary warn if any sessions had unrecognised template_ids
        if (unknownTemplateIds.size > 0) {
          console.warn(
            "[generate-plan] Unknown template_ids encountered (structure left NULL):",
            Array.from(unknownTemplateIds)
          );
        }

        const { error: activeError } = await dbClient
          .from("training_plans")
          .update({ status: "active", error_message: null })
          .eq("id", planId);
        if (activeError) {
          throw new Error(`Failed to activate the plan: ${activeError.message}`);
        }

        const job = inflightPlans.get(planId);
        if (job) job.settled = true;
        console.log(`Plan ${planId} generation complete — status set to active`);
      } catch (bgError) {
        console.error("Background plan generation failed:", bgError);
        const job = planId ? inflightPlans.get(planId) : undefined;
        if (job) job.settled = true;
        // Persist a short, secret-free reason so the app can show it (DRO-312).
        const errorMessage = publicErrorMessage(bgError);
        try {
          await dbClient
            .from("training_plans")
            .update({
              status: "failed",
              error_message: errorMessage,
              failed_at: new Date().toISOString(),
            })
            .eq("id", planId);
        } catch (updateError) {
          console.error("Failed to mark plan as failed:", updateError);
        }
      } finally {
        if (planId) inflightPlans.delete(planId);
      }
    })());

    // Return immediately — iOS polls training_plans.status for completion
    return new Response(
      JSON.stringify({ planId }),
      {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );
  } catch (error) {
    console.error("Plan generation setup failed:", error);
    const status = error instanceof PlanInputError ? 400 : 500;
    const message = error instanceof PlanInputError
      ? error.message
      : publicErrorMessage(error);
    return jsonResponse({ error: message }, status);
  }
});

