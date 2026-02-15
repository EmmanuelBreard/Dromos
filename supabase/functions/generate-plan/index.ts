import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import OpenAI from "npm:openai@4";

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
const MODEL_STEP1 = "gpt-4o";
const MODEL_STEP2 = "gpt-4o-mini";
const MODEL_STEP3 = "gpt-4o";
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
  prompt = prompt.replace("{{limiters}}", user.limiters || "none");

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

// Post-processing: fix sport clustering on single-session days
// When consecutive single-session days (≤75min) have the same sport, spread them apart
function fixSportClustering(
  planWeeks: any[],
  dayCaps: Record<string, number>,
  sportEligibility: Record<string, string[]>
): number {
  const SINGLE_SESSION_CAP = 75;
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
      const sessions = byDay[day] || [];
      if (cap > 0 && cap <= SINGLE_SESSION_CAP && sessions.length === 1) {
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

      const session1 = byDay[day1][0];
      const session2 = byDay[day2][0];

      // If same sport, try to move session2
      if (session1.sport === session2.sport) {
        // Find a candidate: same sport, same type, not brick, not adjacent to day1
        const session2Dur = session2.duration_minutes || 0;
        let swapCandidate: any = null;
        let swapCandidateDay: string | null = null;

        for (const candidateDay of ALL_DAYS) {
          // Skip day1 and days adjacent to day1
          const candidateIdx = ALL_DAYS.indexOf(candidateDay);
          if (candidateIdx === idx1 || candidateIdx === idx1 - 1 || candidateIdx === idx1 + 1) {
            continue;
          }

          const candidateSessions = byDay[candidateDay] || [];
          for (const candidate of candidateSessions) {
            if (
              candidate.sport === session2.sport &&
              candidate.type === session2.type &&
              !candidate.is_brick
            ) {
              const candidateDur = candidate.duration_minutes || 0;

              // Check if swap is feasible
              // Can session2 fit on candidateDay?
              const candidateDayEligible = (sportEligibility[candidateDay] || []).includes(session2.sport);
              const candidateDayCap = dayCaps[candidateDay] || 0;
              const candidateDayUsed = candidateSessions.reduce((sum: number, s: any) => sum + (s.duration_minutes || 0), 0);
              const candidateDayRemaining = candidateDayCap - candidateDayUsed + candidateDur;

              // Can candidate fit on day2?
              const day2Eligible = (sportEligibility[day2] || []).includes(candidate.sport);
              const day2Cap = dayCaps[day2] || 0;
              const day2Remaining = day2Cap - session2Dur + candidateDur;

              if (
                candidateDayEligible &&
                candidateDayRemaining >= session2Dur &&
                day2Eligible &&
                day2Remaining >= candidateDur
              ) {
                swapCandidate = candidate;
                swapCandidateDay = candidateDay;
                break;
              }
            }
          }
          if (swapCandidate) break;
        }

        // Perform the swap
        if (swapCandidate && swapCandidateDay) {
          session2.day = swapCandidateDay;
          swapCandidate.day = day2;
          fixes++;
        }
      }
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

    // Extract user_id from JWT payload.
    // Deployed with --no-verify-jwt (gateway JWT check disabled due to
    // platform issue). The JWT is still issued by Supabase Auth on sign-in.
    const jwt = authHeader.replace("Bearer ", "");
    const payloadBase64 = jwt.split(".")[1];
    if (!payloadBase64) {
      return new Response(JSON.stringify({ error: "Malformed token" }), {
        status: 401,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }
    const payload = JSON.parse(
      atob(payloadBase64.replace(/-/g, "+").replace(/_/g, "/"))
    );
    const userId = payload.sub;
    if (!userId) {
      return new Response(JSON.stringify({ error: "Invalid token: missing sub" }), {
        status: 401,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    // Create service_role client for DB operations
    const dbClient = createClient(supabaseUrl, supabaseServiceRoleKey);

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

    const planId = plan.id;

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

    let previouslyUsed: any[] = [];
    const allBlockWeeks: any[] = [];

    // Build constraint string once (same for all blocks)
    const constraintString = buildConstraintString(userProfile);

    // Build simplified library for Step 3 (strips segment details, keeps only template matching info)
    const simplifiedLibrary = buildSimplifiedLibrary(workoutLibrary);

    for (let b = 0; b < blocks.length; b++) {
      const block = blocks[b];
      // Build prompt for this block
      let finalPrompt = STEP3_WORKOUT_BLOCK_PROMPT;
      finalPrompt = finalPrompt.replace("{{workout_library}}", simplifiedLibrary);
      finalPrompt = finalPrompt.replace(
        "{{block_weeks_json}}",
        JSON.stringify(block, null, 2)
      );
      finalPrompt = finalPrompt.replace("{{limiters}}", userProfile.limiters || "none");
      finalPrompt = finalPrompt.replace("{{constraints}}", constraintString);
      const prevStr =
        previouslyUsed.length > 0
          ? previouslyUsed
              .map(
                (p) =>
                  `- ${p.sport} ${p.type}: last used ${p.template_id} in W${p.week}`
              )
              .join("\n")
          : "None — this is the first block.";
      finalPrompt = finalPrompt.replace("{{previously_used}}", prevStr);

      const blockResponse = await callOpenAI(
        openai,
        MODEL_STEP3,
        finalPrompt,
        TEMPERATURE,
        MAX_TOKENS_STEP3,
        { type: "json_object" }
      );

      const blockJson = blockResponse.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
      const blockResult = JSON.parse(blockJson);
      allBlockWeeks.push(...(blockResult.weeks || []));
      previouslyUsed = extractLastUsed(blockResult);
    }

    // Post-processing
    const templateDurationMap = buildTemplateDurationMap(workoutLibrary);
    const { dayCaps, sportEligibility } = parseConstraints(userProfile);

    fixTypes(allBlockWeeks);
    fixBrickPairs(allBlockWeeks);
    fixConsecutiveRepeats(allBlockWeeks, workoutLibrary, templateDurationMap);
    fixDurationCaps(allBlockWeeks, workoutLibrary, templateDurationMap, dayCaps, sportEligibility);
    fixRestDays(allBlockWeeks, weeks, dayCaps, sportEligibility);
    fixSportClustering(allBlockWeeks, dayCaps, sportEligibility);

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
          });
        }
      }
    }

    // Update plan status to 'active'
    await dbClient
      .from("training_plans")
      .update({ status: "active" })
      .eq("id", planId);

    // Fetch full plan for response
    const { data: finalPlan } = await dbClient
      .from("training_plans")
      .select("*")
      .eq("id", planId)
      .single();

    const { data: planWeeks } = await dbClient
      .from("plan_weeks")
      .select("*")
      .eq("plan_id", planId)
      .order("week_number");

    const { data: planSessions } = await dbClient
      .from("plan_sessions")
      .select("*")
      .in(
        "week_id",
        planWeeks?.map((w) => w.id) || []
      )
      .order("week_id, day, order_in_day");

    // Build response JSON
    const responseWeeks = (planWeeks || []).map((week) => ({
      week_number: week.week_number,
      phase: week.phase,
      is_recovery: week.is_recovery,
      rest_days: week.rest_days,
      notes: week.notes,
      start_date: week.start_date,
      sessions: (planSessions || [])
        .filter((s) => s.week_id === week.id)
        .map((s) => ({
          sport: s.sport,
          type: s.type,
          template_id: s.template_id,
          duration_minutes: s.duration_minutes,
          day: s.day,
          is_brick: s.is_brick,
          notes: s.notes,
          order_in_day: s.order_in_day,
        })),
    }));

    return new Response(
      JSON.stringify({
        plan: {
          id: finalPlan?.id,
          status: finalPlan?.status,
          total_weeks: finalPlan?.total_weeks,
          start_date: finalPlan?.start_date,
          race_date: finalPlan?.race_date,
          race_objective: finalPlan?.race_objective,
        },
        weeks: responseWeeks,
      }),
      {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );
  } catch (error) {
    console.error("Plan generation failed:", error);
    return new Response(
      JSON.stringify({
        error: "Plan generation failed. Please try again.",
      }),
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

