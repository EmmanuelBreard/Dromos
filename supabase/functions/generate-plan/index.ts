import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import OpenAI from "npm:openai@4";

// Shared materializer — pure function, no Supabase/Deno.env deps.
// Converts a WorkoutTemplate from workout-library.json into the SessionStructure
// JSON shape stored in plan_sessions.structure.
import { materialize, type WorkoutTemplate } from "../_shared/materialize-structure.ts";

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
const MAX_TOKENS_STEP3 = 4096;

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

// Helper: Calculate days between two dates
function daysBetween(date1: Date, date2: Date): number {
  const diff = date2.getTime() - date1.getTime();
  return Math.ceil(diff / (1000 * 60 * 60 * 24));
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
    Sprint: "Sprint (750m swim / 20km bike / 5km run)",
    Olympic: "Olympic (1.5km swim / 40km bike / 10km run)",
    "Ironman 70.3": "Half-Ironman (1.9km swim / 90km bike / 21.1km run)",
    Ironman: "Ironman (3.8km swim / 180km bike / 42.2km run)",
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

// Helper: Calculate weekly hours from daily durations
function calculateWeeklyHours(user: any): number {
  const durations = [
    user.mon_duration,
    user.tue_duration,
    user.wed_duration,
    user.thu_duration,
    user.fri_duration,
    user.sat_duration,
    user.sun_duration,
  ];
  const totalMinutes = durations.reduce(
    (sum: number, d: number | null) => sum + (d || 0),
    0
  );
  return Math.round((totalMinutes / 60) * 10) / 10; // Round to 1 decimal
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

// Call OpenAI API
async function callOpenAI(
  client: OpenAI,
  model: string,
  prompt: string,
  temperature: number,
  maxTokens: number,
  responseFormat?: { type: "json_object" }
): Promise<string> {
  const response = await client.chat.completions.create({
    model,
    messages: [{ role: "user", content: prompt }],
    temperature,
    max_tokens: maxTokens,
    ...(responseFormat && { response_format: responseFormat }),
  });

  const content = response.choices[0]?.message?.content;
  if (!content) {
    throw new Error("Empty response from OpenAI");
  }
  return content;
}

// Build prompt for Step 1 (macro plan)
function buildStep1Prompt(user: any, vars: any): string {
  let prompt = STEP1_MACRO_PLAN_PROMPT;
  prompt = prompt.replace("{{training_philosophy}}", TRAINING_PHILOSOPHY);
  prompt = prompt.replace(
    "{{experience_level}}",
    mapExperienceLevel(user.experience_years)
  );
  prompt = prompt.replace(
    "{{race_distance}}",
    expandRaceObjective(user.race_objective)
  );
  prompt = prompt.replace("{{race_date}}", vars.raceDate);
  prompt = prompt.replace("{{plan_start_date}}", vars.planStartDate);
  prompt = prompt.replace("{{total_weeks}}", vars.totalWeeks.toString());
  prompt = prompt.replace("{{weekly_hours}}", vars.weeklyHours.toString());
  prompt = prompt.replace(
    "{{ftp_watts}}",
    user.ftp ? user.ftp.toString() : "not provided"
  );
  prompt = prompt.replace(
    "{{mas_kmh}}",
    user.vma ? user.vma.toString() : "not provided"
  );
  prompt = prompt.replace(
    "{{swim_css}}",
    formatCSS(user.css_seconds_per100m)
  );
  // Limiters column not yet in users table — defaults to "none" until onboarding captures it
  const limitersValue = (user.limiters || "none").toString().replace(/[\n\r]/g, " ").slice(0, 200);
  prompt = prompt.replace("{{limiters}}", limitersValue);

  // Current training volume (athlete's baseline for progressive overload)
  prompt = prompt.replace(
    "{{current_weekly_hours}}",
    user.current_weekly_hours != null
      ? user.current_weekly_hours.toString()
      : "not provided"
  );

  // Session duration caps (derived from per-day availability)
  const caps = calculateSessionDurationCaps(user);
  prompt = prompt.replace("{{max_weekday_minutes}}", caps.maxWeekday.toString());
  prompt = prompt.replace("{{max_weekend_minutes}}", caps.maxWeekend.toString());

  // Sport day availability counts (how many weekdays/weekend days each sport can use)
  const weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"];
  const weekendDays = ["Saturday", "Sunday"];
  const swimDays = new Set(user.swim_days || []);
  const bikeDays = new Set(user.bike_days || []);
  const runDays = new Set(user.run_days || []);

  prompt = prompt.replace("{{swim_weekday_count}}", weekdays.filter(d => swimDays.has(d)).length.toString());
  prompt = prompt.replace("{{swim_weekend_count}}", weekendDays.filter(d => swimDays.has(d)).length.toString());
  prompt = prompt.replace("{{bike_weekday_count}}", weekdays.filter(d => bikeDays.has(d)).length.toString());
  prompt = prompt.replace("{{bike_weekend_count}}", weekendDays.filter(d => bikeDays.has(d)).length.toString());
  prompt = prompt.replace("{{run_weekday_count}}", weekdays.filter(d => runDays.has(d)).length.toString());
  prompt = prompt.replace("{{run_weekend_count}}", weekendDays.filter(d => runDays.has(d)).length.toString());

  return prompt;
}

// Build prompt for Step 2 (MD → JSON)
function buildStep2Prompt(step1Output: string): string {
  return STEP2_MD_TO_JSON_PROMPT.replace("{{step1_output}}", step1Output);
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

// Post-processing: fix same-day hard session conflicts
// Rule 1: Max 1 bike and max 1 run per day (brick sessions count)
// Rule 2: No two hard (bike/run) sessions on same day (brick hard sessions count)
// Swim is exempt from both rules.
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
          }
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
        }
      }
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
            const tType = t.template_id.split('_')[1];
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

    // Calculate plan variables
    const planStartDate = new Date(Date.now() + 86400000); // Tomorrow
    const raceDate = new Date(userProfile.race_date);
    const totalWeeks = Math.ceil(daysBetween(planStartDate, raceDate) / 7);
    const weeklyHours = calculateWeeklyHours(userProfile);

    const vars = {
      raceDate: formatDate(raceDate),
      planStartDate: formatDate(planStartDate),
      totalWeeks,
      weeklyHours,
    };

    // Delete existing plan (CASCADE deletes weeks + sessions)
    const { error: deleteError } = await dbClient
      .from("training_plans")
      .delete()
      .eq("user_id", userId);

    if (deleteError) {
      throw new Error(`Failed to delete existing plan: ${deleteError.message}`);
    }

    // Create new training_plans row with status 'generating'
    const { data: plan, error: planError } = await dbClient
      .from("training_plans")
      .insert({
        user_id: userId,
        status: "generating",
        race_date: formatDate(raceDate),
        race_objective: userProfile.race_objective,
        total_weeks: totalWeeks,
        start_date: formatDate(planStartDate),
      })
      .select()
      .single();

    if (planError || !plan) {
      throw new Error(`Failed to create training plan: ${planError?.message}`);
    }

    planId = plan.id;

    // Respond immediately — plan generation continues as a background task.
    // The iOS app polls training_plans.status for 'active' or 'failed'.
    EdgeRuntime.waitUntil((async () => {
      try {
        // Initialize OpenAI client
        const openai = getOpenAIClient();

    // Step 1: Generate macro plan (markdown)
    const step1Prompt = buildStep1Prompt(userProfile, vars);
    const step1Output = await callOpenAI(
      openai,
      MODEL_STEP1,
      step1Prompt,
      TEMPERATURE,
      MAX_TOKENS_STEP1
    );

    // Step 2: Convert markdown to JSON
    const step2Prompt = buildStep2Prompt(step1Output);
    const step2Output = await callOpenAI(
      openai,
      MODEL_STEP2,
      step2Prompt,
      0, // Temperature 0 for deterministic JSON conversion
      MAX_TOKENS_STEP2,
      { type: "json_object" }
    );

    // Parse Step 2 output
    const step2Json = step2Output.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
    const macroPlan = JSON.parse(step2Json);

    if (!macroPlan.weeks || !Array.isArray(macroPlan.weeks) || macroPlan.weeks.length === 0) {
      throw new Error("Invalid macro plan structure from Step 2");
    }

    // Step 3: Process blocks
    // Fetch workout library from Supabase Storage at runtime
    const wlResponse = await fetch(getWorkoutLibraryUrl());
    if (!wlResponse.ok) {
      throw new Error(`Failed to fetch workout library: ${wlResponse.status}`);
    }
    const workoutLibrary = await wlResponse.json();

    const weeks = macroPlan.weeks;
    const blocks = [];
    for (let j = 0; j < weeks.length; j += BLOCK_SIZE) {
      blocks.push(weeks.slice(j, j + BLOCK_SIZE));
    }

    // Build constraint string once (same for all blocks)
    const constraintString = buildConstraintString(userProfile);

    // Build simplified library for Step 3 (strips segment details, keeps only template matching info)
    const simplifiedLibrary = buildSimplifiedLibrary(workoutLibrary);

    // Run all blocks in parallel — cuts step 3 from O(blocks) sequential calls to O(1).
    // previouslyUsed cross-block deduplication is dropped; fixConsecutiveRepeats post-processing
    // handles adjacent repeats, and intra-block variety is preserved.
    const limitersStep3 = (userProfile.limiters || "none").toString().replace(/[\n\r]/g, " ").slice(0, 200);

    const blockResults = await Promise.all(
      blocks.map(async (block) => {
        let finalPrompt = STEP3_WORKOUT_BLOCK_PROMPT;
        finalPrompt = finalPrompt.replace("{{workout_library}}", simplifiedLibrary);
        finalPrompt = finalPrompt.replace("{{block_weeks_json}}", JSON.stringify(block, null, 2));
        finalPrompt = finalPrompt.replace("{{limiters}}", limitersStep3);
        finalPrompt = finalPrompt.replace("{{constraints}}", constraintString);
        finalPrompt = finalPrompt.replace("{{previously_used}}", "None — blocks are processed in parallel.");

        const blockResponse = await callOpenAI(
          openai,
          MODEL_STEP3,
          finalPrompt,
          TEMPERATURE,
          MAX_TOKENS_STEP3,
          { type: "json_object" }
        );

        const blockJson = blockResponse.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
        return JSON.parse(blockJson);
      })
    );

    const allBlockWeeks = blockResults.flatMap((r) => r.weeks || []);

    // Post-processing
    const templateDurationMap = buildTemplateDurationMap(workoutLibrary);
    // Template map for insert-time materialisation (template_id → full WorkoutTemplate).
    // Built once here; fixers mutate session.template_id BEFORE the insert site so the
    // correct (post-fix) template is always resolved at insertion — no re-materialisation needed.
    const templateMap = buildTemplateMap(workoutLibrary);
    const { dayCaps, sportEligibility } = parseConstraints(userProfile);

    fixTypes(allBlockWeeks);
    fixBrickPairs(allBlockWeeks);
    fixConsecutiveRepeats(allBlockWeeks, workoutLibrary, templateDurationMap);
    fixDurationCaps(allBlockWeeks, workoutLibrary, templateDurationMap, dayCaps, sportEligibility);
    fixRestDays(allBlockWeeks, weeks, dayCaps, sportEligibility);
    fixMissingBricks(allBlockWeeks, workoutLibrary, dayCaps, sportEligibility);
    fixBrickRunDuration(allBlockWeeks, workoutLibrary);
    fixBrickOrder(allBlockWeeks);
    fixSameDayHardConflicts(allBlockWeeks, dayCaps, sportEligibility, workoutLibrary);
    fixIntensitySpread(allBlockWeeks, dayCaps, sportEligibility);
    fixSportClustering(allBlockWeeks, dayCaps, sportEligibility, weeklyHours);
    fixVolumeGaps(allBlockWeeks, weeks, dayCaps, sportEligibility, workoutLibrary);
    // Re-run duration caps after all changes to catch any new violations
    fixDurationCaps(allBlockWeeks, workoutLibrary, templateDurationMap, dayCaps, sportEligibility);
    // Re-run same-day conflicts — volume gaps or cap fixes may have introduced new ones
    fixSameDayHardConflicts(allBlockWeeks, dayCaps, sportEligibility, workoutLibrary);
    // Final brick order pass — catch any bricks reordered by later fixers
    fixBrickOrder(allBlockWeeks);

    // Validate LLM output before DB writes
    const VALID_PHASES = ["Base", "Build", "Peak", "Taper", "Recovery"];
    const VALID_SPORTS = ["swim", "bike", "run"];
    const VALID_TYPES = ["Easy", "Tempo", "Intervals"];
    for (const week of allBlockWeeks) {
      if (!VALID_PHASES.includes(week.phase)) {
        throw new Error(`Invalid phase "${week.phase}" in week ${week.week_number}. Expected: ${VALID_PHASES.join(", ")}`);
      }
      for (const session of week.sessions || []) {
        if (!VALID_SPORTS.includes(session.sport)) {
          throw new Error(`Invalid sport "${session.sport}" in week ${week.week_number}. Expected: ${VALID_SPORTS.join(", ")}`);
        }
        if (!VALID_TYPES.includes(session.type)) {
          throw new Error(`Invalid type "${session.type}" in week ${week.week_number}. Expected: ${VALID_TYPES.join(", ")}`);
        }
        if (!session.duration_minutes || session.duration_minutes <= 0) {
          throw new Error(`Invalid duration ${session.duration_minutes} in week ${week.week_number}`);
        }
      }
    }

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
        if (!sessionsByDay[day]) sessionsByDay[day] = [];
        sessionsByDay[day].push(session);
      }

      // Insert sessions
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
          let orderInDay = i;
          if (session.is_brick) {
            orderInDay = session.sport === "bike" ? 0 : 1;
          }

          // Materialise the structure column from the resolved template.
          //
          // Design note: all post-processing fixers (fixConsecutiveRepeats, fixDurationCaps,
          // fixMissingBricks, etc.) mutate session.template_id BEFORE this insert site runs.
          // Materialisation therefore happens exactly once — here — always against the
          // final post-fix template. Fixers do NOT call materialize() themselves.
          if (!session.template_id) {
            console.warn(
              `[generate-plan] Session at index ${i} has no template_id — skipping structure materialization`
            );
          }
          const template = session.template_id ? templateMap[session.template_id] : undefined;
          const structure = template ? materialize(template) : null;
          if (!structure && session.template_id) {
            unknownTemplateIds.add(session.template_id);
          }

          await dbClient.from("plan_sessions").insert({
            week_id: weekRow.id,
            day: normDay(session.day),
            sport: session.sport,
            type: session.type,
            template_id: session.template_id,
            duration_minutes: session.duration_minutes,
            is_brick: session.is_brick || false,
            notes: null,
            order_in_day: orderInDay,
            structure,
          });
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

        // Update plan status to 'active'
        await dbClient
          .from("training_plans")
          .update({ status: "active" })
          .eq("id", planId);

        console.log(`Plan ${planId} generation complete — status set to active`);
      } catch (bgError) {
        console.error("Background plan generation failed:", bgError);
        // Mark plan as failed so the iOS app can detect it via polling
        try {
          await dbClient
            .from("training_plans")
            .update({ status: "failed" })
            .eq("id", planId);
        } catch (updateError) {
          console.error("Failed to mark plan as failed:", updateError);
        }
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

    const message =
      error instanceof Error
        ? `Plan generation failed: ${error.message}`
        : "Plan generation failed. Please try again.";

    return new Response(
      JSON.stringify({ error: message }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );
  }
});

