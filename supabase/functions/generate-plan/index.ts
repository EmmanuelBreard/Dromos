import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import OpenAI from "npm:openai@4";

// Static assets (bundled as TS modules for CLI deploy)
import STEP1_MACRO_PLAN_PROMPT from "./prompts/step1-macro-plan-prompt.ts";
import STEP1B_MD_TO_JSON_PROMPT from "./prompts/step1b-md-to-json-prompt.ts";
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
  prompt = prompt.replace("{{limiters}}", "none");

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
  return STEP1B_MD_TO_JSON_PROMPT.replace("{{step1_output}}", step1Output);
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

// Note: Step 3 prompt building is done inline in the main handler
// to avoid loading the template file multiple times

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

// Post-processing: fix consecutive-week template repeats
function fixConsecutiveRepeats(planWeeks: any[], workoutLibrary: any): number {
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

    // Check current week for repeats and swap
    for (const session of currWeek.sessions || []) {
      const key = `${session.sport}_${session.type}`;
      if (prevMap[key] && prevMap[key].has(session.template_id)) {
        const options = (catalog[key] || []).filter(
          (t) => t !== session.template_id
        );
        if (options.length > 0) {
          // Pick a random alternative to avoid always defaulting to the same swap
          const alt = options[Math.floor(Math.random() * options.length)];
          session.template_id = alt;
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

    // Create client for auth verification
    const authClient = createClient(supabaseUrl, supabaseAnonKey);
    const {
      data: { user },
      error: authError,
    } = await authClient.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    const userId = user.id;

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
    const WORKOUT_LIBRARY_STR = await wlResponse.text();
    const workoutLibrary = JSON.parse(WORKOUT_LIBRARY_STR);

    const weeks = macroPlan.weeks;
    const blocks = [];
    for (let j = 0; j < weeks.length; j += BLOCK_SIZE) {
      blocks.push(weeks.slice(j, j + BLOCK_SIZE));
    }

    let previouslyUsed: any[] = [];
    const allBlockWeeks: any[] = [];

    // Build constraint string once (same for all blocks)
    const constraintString = buildConstraintString(userProfile);

    for (let b = 0; b < blocks.length; b++) {
      const block = blocks[b];
      // Build prompt for this block
      let finalPrompt = STEP3_WORKOUT_BLOCK_PROMPT;
      finalPrompt = finalPrompt.replace("{{workout_library}}", WORKOUT_LIBRARY_STR);
      finalPrompt = finalPrompt.replace(
        "{{block_weeks_json}}",
        JSON.stringify(block, null, 2)
      );
      finalPrompt = finalPrompt.replace("{{limiters}}", "none");
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
    fixTypes(allBlockWeeks);
    fixBrickPairs(allBlockWeeks);
    fixConsecutiveRepeats(allBlockWeeks, workoutLibrary);

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

