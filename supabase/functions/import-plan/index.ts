import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Shared materializer — pure function, no Supabase/Deno.env deps.
// Converts a WorkoutTemplate from workout-library.json into the SessionStructure
// JSON shape stored in plan_sessions.structure.
import { materialize, type WorkoutTemplate } from "../_shared/materialize-structure.ts";

// ── Allowlist — V0 is gated to a single user ────────────────────────────────
// Server-side enforcement. Same convention as chat-adjust.
const ALLOWED_EMAIL = "ebreard4@gmail.com";

// ── Valid values ─────────────────────────────────────────────────────────────
const VALID_DAYS = new Set([
  "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
]);
const VALID_PHASES = new Set(["Base", "Build", "Peak", "Taper", "Recovery"]);
const VALID_SPORTS = new Set(["swim", "bike", "run", "strength", "race"]);
const VALID_TYPES  = new Set(["Easy", "Tempo", "Intervals", "Race"]);
const VALID_RACE_OBJECTIVES = new Set([
  "Sprint", "Olympic", "Ironman 70.3", "Ironman",
]);

// ── CORS headers ──────────────────────────────────────────────────────────────
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Helper: build a JSON response with CORS headers
function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

// ── Types ─────────────────────────────────────────────────────────────────────

type Day = "Monday" | "Tuesday" | "Wednesday" | "Thursday" | "Friday" | "Saturday" | "Sunday";

interface ImportPlanBody {
  plan: {
    race_objective: "Sprint" | "Olympic" | "Ironman 70.3" | "Ironman";
    race_date: string;    // "YYYY-MM-DD"
    start_date: string;   // "YYYY-MM-DD"
    total_weeks: number;
  };
  profile_updates?: Partial<{
    max_hr: number;
    ftp: number;
    vma: number;
    css_seconds_per100m: number;
    race_objective: string;
    race_date: string;    // "YYYY-MM-DD" — converted to TIMESTAMPTZ at write time
  }>;
  weeks: Array<{
    week_number: number;
    phase: "Base" | "Build" | "Peak" | "Taper" | "Recovery";
    is_recovery: boolean;
    rest_days: string[];
    notes?: string;
    start_date: string;   // "YYYY-MM-DD"
    sessions: Array<{
      day: Day;
      sport: "swim" | "bike" | "run" | "strength" | "race";
      type: "Easy" | "Tempo" | "Intervals" | "Race";
      template_id: string;
      duration_minutes: number;
      is_brick: boolean;
      notes?: string;
      order_in_day: number;
    }>;
  }>;
  replace?: boolean;      // must be true to overwrite an existing plan
}

// ── Workout library loader ────────────────────────────────────────────────────

/**
 * Loads workout-library.json from Supabase Storage.
 * Returns a Map<template_id, WorkoutTemplate> for O(1) lookups.
 * Throws on network error or non-200 response.
 */
async function loadWorkoutLibrary(
  supabaseUrl: string
): Promise<Map<string, WorkoutTemplate>> {
  const url = `${supabaseUrl}/storage/v1/object/public/static-assets/workout-library.json`;
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Failed to fetch workout-library.json: ${res.status} ${res.statusText}`);
  }
  const lib = await res.json() as Record<string, WorkoutTemplate[]>;

  const map = new Map<string, WorkoutTemplate>();
  // Sports present in the library: swim, bike, run, race, strength
  for (const templates of Object.values(lib)) {
    for (const t of templates) {
      map.set(t.template_id, t);
    }
  }
  return map;
}

// ── Main handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  // 1. CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // 2. Method guard
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  // 3. Validate required environment variables
  const supabaseUrl            = Deno.env.get("SUPABASE_URL");
  const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !supabaseServiceRoleKey) {
    return jsonResponse({ error: "Missing Supabase environment variables" }, 500);
  }

  // 4. Validate JWT
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing Authorization header" }, 401);
  }
  const jwt = authHeader.replace("Bearer ", "");

  // Auth client (anon key fallback to service role) — used only for token validation
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? supabaseServiceRoleKey;
  const authClient = createClient(supabaseUrl, supabaseAnonKey);
  const { data: { user }, error: authError } = await authClient.auth.getUser(jwt);
  if (authError || !user) {
    return jsonResponse({ error: "Invalid token" }, 401);
  }

  // 5. Allowlist gate — V0 single-user
  if (user.email !== ALLOWED_EMAIL) {
    return jsonResponse({ error: "Not authorized" }, 403);
  }

  const userId = user.id;

  // Service-role client for all DB writes (bypasses RLS)
  const db = createClient(supabaseUrl, supabaseServiceRoleKey);

  try {
    // 6. Parse request body
    let body: ImportPlanBody;
    try {
      body = await req.json() as ImportPlanBody;
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    // ── 7. Validate body structure ───────────────────────────────────────────

    // 7a. Top-level plan object
    if (!body.plan || typeof body.plan !== "object") {
      return jsonResponse({ error: "Missing required field: plan" }, 400);
    }
    const { plan, weeks, profile_updates, replace } = body;

    if (!VALID_RACE_OBJECTIVES.has(plan.race_objective)) {
      return jsonResponse({
        error: `Invalid plan.race_objective: "${plan.race_objective}". Must be one of: ${[...VALID_RACE_OBJECTIVES].join(", ")}`,
      }, 400);
    }
    if (!plan.race_date || !/^\d{4}-\d{2}-\d{2}$/.test(plan.race_date)) {
      return jsonResponse({ error: "Invalid plan.race_date — expected YYYY-MM-DD" }, 400);
    }
    if (!plan.start_date || !/^\d{4}-\d{2}-\d{2}$/.test(plan.start_date)) {
      return jsonResponse({ error: "Invalid plan.start_date — expected YYYY-MM-DD" }, 400);
    }
    if (typeof plan.total_weeks !== "number" || plan.total_weeks < 1) {
      return jsonResponse({ error: "Invalid plan.total_weeks — must be a positive integer" }, 400);
    }

    // 7b. Weeks array
    if (!Array.isArray(weeks) || weeks.length === 0) {
      return jsonResponse({ error: "Missing or empty required field: weeks" }, 400);
    }

    // Weeks count must match plan.total_weeks
    if (weeks.length !== plan.total_weeks) {
      return jsonResponse({
        error: `weeks.length (${weeks.length}) does not match plan.total_weeks (${plan.total_weeks})`,
      }, 400);
    }

    // Week numbers must be sequential 1..N
    const sortedWeeks = [...weeks].sort((a, b) => a.week_number - b.week_number);
    for (let i = 0; i < sortedWeeks.length; i++) {
      if (sortedWeeks[i].week_number !== i + 1) {
        return jsonResponse({
          error: `week_numbers must be sequential 1..${plan.total_weeks}. Found ${sortedWeeks[i].week_number} at position ${i + 1}`,
        }, 400);
      }
    }

    // 7c. Validate each week and session
    const invalidDays: string[] = [];
    const invalidPhases: string[] = [];

    for (const week of weeks) {
      if (!VALID_PHASES.has(week.phase)) {
        invalidPhases.push(`week ${week.week_number}: "${week.phase}"`);
      }
      for (const session of (week.sessions ?? [])) {
        if (!VALID_DAYS.has(session.day)) {
          invalidDays.push(`week ${week.week_number} session: "${session.day}"`);
        }
      }
    }
    if (invalidPhases.length > 0) {
      return jsonResponse({ error: `Invalid phase values: ${invalidPhases.join(", ")}` }, 400);
    }
    if (invalidDays.length > 0) {
      return jsonResponse({ error: `Invalid day values: ${invalidDays.join(", ")}` }, 400);
    }

    // ── 8. Load workout library + validate template_ids ──────────────────────
    let libraryMap: Map<string, WorkoutTemplate>;
    try {
      libraryMap = await loadWorkoutLibrary(supabaseUrl);
    } catch (err) {
      console.error("import-plan: failed to load workout-library.json:", err instanceof Error ? err.message : String(err));
      return jsonResponse({ error: "Failed to load workout library" }, 500);
    }

    const missingTemplateIds: string[] = [];
    for (const week of weeks) {
      for (const session of (week.sessions ?? [])) {
        if (!libraryMap.has(session.template_id)) {
          missingTemplateIds.push(session.template_id);
        }
      }
    }
    if (missingTemplateIds.length > 0) {
      return jsonResponse({
        error: "Unknown template_id(s) — not found in workout-library.json",
        missing_template_ids: [...new Set(missingTemplateIds)],
      }, 400);
    }

    // ── 9. Conflict check — existing plan requires replace: true ─────────────
    const { data: existingPlan } = await db
      .from("training_plans")
      .select("id")
      .eq("user_id", userId)
      .maybeSingle();

    if (existingPlan && replace !== true) {
      return jsonResponse({
        error: "User already has an active plan. Set replace: true to overwrite.",
      }, 409);
    }

    // ── 10. Materialise session structures in TypeScript ─────────────────────
    // Each session gets its structure JSONB pre-built here, then passed into
    // the Postgres function. This keeps all TS logic out of plpgsql.
    const weeksWithStructure = weeks.map((week) => ({
      ...week,
      sessions: week.sessions.map((session) => {
        const template = libraryMap.get(session.template_id)!;
        let structure: ReturnType<typeof materialize> | undefined;
        try {
          structure = materialize(template);
        } catch (err) {
          // Log but don't fail — structure is nullable; iOS falls back to template lookup
          console.error(
            `import-plan: materialize failed for ${session.template_id}:`,
            err instanceof Error ? err.message : String(err)
          );
        }
        return { ...session, structure: structure ?? null };
      }),
    }));

    // ── 11. Call import_plan_atomic Postgres function ─────────────────────────
    // This handles snapshot → delete → insert in a single transaction.
    const { data: atomicResult, error: atomicError } = await db.rpc(
      "import_plan_atomic",
      {
        p_user_id:         userId,
        p_plan:            plan,
        p_weeks:           weeksWithStructure,
        p_profile_updates: profile_updates ?? null,
      }
    );

    if (atomicError) {
      console.error("import-plan: import_plan_atomic RPC error:", atomicError.message);
      return jsonResponse({ error: "Database error during plan import" }, 500);
    }

    // ── 12. Success logging + response ────────────────────────────────────────
    console.log(JSON.stringify({
      event:             "import-plan-success",
      user_id:           userId,
      plan_id:           (atomicResult as Record<string, unknown>)?.plan_id,
      snapshot_id:       (atomicResult as Record<string, unknown>)?.snapshot_id,
      weeks_inserted:    (atomicResult as Record<string, unknown>)?.weeks_inserted,
      sessions_inserted: (atomicResult as Record<string, unknown>)?.sessions_inserted,
    }));

    return jsonResponse({
      success:           true,
      plan_id:           (atomicResult as Record<string, unknown>)?.plan_id,
      snapshot_id:       (atomicResult as Record<string, unknown>)?.snapshot_id,
      weeks_inserted:    (atomicResult as Record<string, unknown>)?.weeks_inserted,
      sessions_inserted: (atomicResult as Record<string, unknown>)?.sessions_inserted,
    }, 200);

  } catch (err) {
    console.error(
      "import-plan: unhandled error:",
      err instanceof Error ? err.message : String(err)
    );
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
