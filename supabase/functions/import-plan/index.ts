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
const VALID_PHASES         = new Set(["Base", "Build", "Peak", "Taper", "Recovery"]);
const VALID_SPORTS         = new Set(["swim", "bike", "run", "strength", "race"]);
const VALID_TYPES          = new Set(["Easy", "Tempo", "Intervals", "Race"]);
const VALID_RACE_OBJECTIVES = new Set([
  "Sprint", "Olympic", "Ironman 70.3", "Ironman",
]);

// ── Request limits ────────────────────────────────────────────────────────────
// 512 KB is generous for any realistic plan payload (even 60-week / 14-session).
const MAX_BODY_BYTES  = 512 * 1024;
const MAX_WEEKS       = 60;
const MAX_SESSIONS_PER_WEEK = 14;

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

// ── Date validation ───────────────────────────────────────────────────────────

/**
 * Returns true if the string is a valid calendar date in YYYY-MM-DD format.
 * Two-pass check: regex shape + actual Date parse (catches 2026-02-30, etc.).
 */
function isValidDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  return !Number.isNaN(new Date(value).getTime());
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

// Typed shape returned by import_plan_atomic RPC — cast once, use everywhere.
interface AtomicResult {
  plan_id:           string;
  snapshot_id:       string | null;
  weeks_inserted:    number;
  sessions_inserted: number;
}

// ── Module-scope workout library cache ───────────────────────────────────────
// Supabase Edge Functions share module state across warm invocations within the
// same isolate, making this a simple and effective cold-start optimisation.
// Set to null so the first request triggers a fetch; subsequent requests reuse.
let cachedLibrary: Map<string, WorkoutTemplate> | null = null;

/**
 * Loads workout-library.json from Supabase Storage and caches the result.
 * Returns a Map<template_id, WorkoutTemplate> for O(1) lookups.
 * Throws on network error or non-200 response.
 */
async function loadWorkoutLibrary(
  supabaseUrl: string
): Promise<Map<string, WorkoutTemplate>> {
  if (cachedLibrary) return cachedLibrary;

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
  cachedLibrary = map;
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

  // Hard-fail if the anon key is absent — we need it for JWT validation.
  // Falling back to service_role for auth.getUser() would accept service-role
  // JWTs as valid user sessions, bypassing the allowlist gate.
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseAnonKey) {
    console.error("import-plan: SUPABASE_ANON_KEY is not set");
    return jsonResponse({ error: "Server misconfigured: SUPABASE_ANON_KEY missing" }, 500);
  }

  // 3b. Request body size guard — reject before reading the body to avoid
  //     allocating large buffers for oversized payloads.
  const contentLength = parseInt(req.headers.get("Content-Length") ?? "0", 10);
  if (contentLength > MAX_BODY_BYTES) {
    return jsonResponse({
      error: `Payload too large. Maximum allowed: ${MAX_BODY_BYTES} bytes`,
    }, 413);
  }

  // 4. Validate JWT
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing Authorization header" }, 401);
  }
  const jwt = authHeader.replace("Bearer ", "");

  // Auth client — used only for token validation, never for DB writes.
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

    if (!plan.race_date || !isValidDate(plan.race_date)) {
      return jsonResponse({ error: "Invalid plan.race_date — expected YYYY-MM-DD and a valid calendar date" }, 400);
    }
    if (!plan.start_date || !isValidDate(plan.start_date)) {
      return jsonResponse({ error: "Invalid plan.start_date — expected YYYY-MM-DD and a valid calendar date" }, 400);
    }

    // Require a positive integer — 1.5 or NaN must be rejected.
    if (typeof plan.total_weeks !== "number" || !Number.isInteger(plan.total_weeks) || plan.total_weeks < 1) {
      return jsonResponse({ error: "Invalid plan.total_weeks — must be a positive integer" }, 400);
    }

    // 7b. Weeks array
    if (!Array.isArray(weeks) || weeks.length === 0) {
      return jsonResponse({ error: "Missing or empty required field: weeks" }, 400);
    }

    // Belt-and-braces size cap
    if (weeks.length > MAX_WEEKS) {
      return jsonResponse({ error: `Too many weeks: ${weeks.length}. Maximum is ${MAX_WEEKS}.` }, 400);
    }

    // Weeks count must match plan.total_weeks
    if (weeks.length !== plan.total_weeks) {
      return jsonResponse({
        error: `weeks.length (${weeks.length}) does not match plan.total_weeks (${plan.total_weeks})`,
      }, 400);
    }

    // Duplicate week_number check — must happen before sequential check so the
    // error message is accurate (duplicate vs. non-sequential are different bugs).
    const uniqueWeekNumbers = new Set(weeks.map((w) => w.week_number));
    if (uniqueWeekNumbers.size !== weeks.length) {
      return jsonResponse({ error: "Duplicate week_number values in payload" }, 400);
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

    // 7c. Validate each week and session fields
    const invalidDays:     string[] = [];
    const invalidPhases:   string[] = [];
    const invalidSports:   string[] = [];
    const invalidTypes:    string[] = [];
    const fieldErrors:     string[] = [];

    for (const week of weeks) {
      const wLabel = `week ${week.week_number}`;

      // Per-week field types
      if (typeof week.is_recovery !== "boolean") {
        fieldErrors.push(`${wLabel}: is_recovery must be boolean`);
      }
      if (!Array.isArray(week.rest_days) || !week.rest_days.every((d) => typeof d === "string")) {
        fieldErrors.push(`${wLabel}: rest_days must be an array of strings`);
      }
      if (week.notes !== undefined && typeof week.notes !== "string") {
        fieldErrors.push(`${wLabel}: notes must be a string when present`);
      }
      if (!week.start_date || !isValidDate(week.start_date)) {
        fieldErrors.push(`${wLabel}: start_date must be a valid YYYY-MM-DD date`);
      }

      if (!VALID_PHASES.has(week.phase)) {
        invalidPhases.push(`${wLabel}: "${week.phase}"`);
      }

      // Per-session size cap
      const sessions = week.sessions ?? [];
      if (sessions.length > MAX_SESSIONS_PER_WEEK) {
        return jsonResponse({
          error: `${wLabel} has ${sessions.length} sessions — maximum is ${MAX_SESSIONS_PER_WEEK} per week`,
        }, 400);
      }

      for (const session of sessions) {
        const sLabel = `${wLabel} session (${session.day ?? "?"})`;

        if (!VALID_DAYS.has(session.day)) {
          invalidDays.push(`${sLabel}: "${session.day}"`);
        }
        if (!VALID_SPORTS.has(session.sport)) {
          invalidSports.push(`${sLabel}: sport "${session.sport}"`);
        }
        if (!VALID_TYPES.has(session.type)) {
          invalidTypes.push(`${sLabel}: type "${session.type}"`);
        }
        if (!Number.isInteger(session.duration_minutes) || session.duration_minutes <= 0) {
          fieldErrors.push(`${sLabel}: duration_minutes must be a positive integer`);
        }
        if (typeof session.is_brick !== "boolean") {
          fieldErrors.push(`${sLabel}: is_brick must be boolean`);
        }
        if (!Number.isInteger(session.order_in_day) || session.order_in_day < 0) {
          fieldErrors.push(`${sLabel}: order_in_day must be a non-negative integer`);
        }
        if (session.notes !== undefined && typeof session.notes !== "string") {
          fieldErrors.push(`${sLabel}: notes must be a string when present`);
        }
      }
    }

    if (invalidPhases.length > 0) {
      return jsonResponse({ error: `Invalid phase values`, invalid_phases: invalidPhases }, 400);
    }
    if (invalidDays.length > 0) {
      return jsonResponse({ error: `Invalid day values`, invalid_days: invalidDays }, 400);
    }
    if (invalidSports.length > 0) {
      return jsonResponse({ error: `Invalid sport values`, invalid_sports: invalidSports }, 400);
    }
    if (invalidTypes.length > 0) {
      return jsonResponse({ error: `Invalid type values`, invalid_types: invalidTypes }, 400);
    }
    if (fieldErrors.length > 0) {
      return jsonResponse({ error: `Field type validation failed`, field_errors: fieldErrors }, 400);
    }

    // 7d. profile_updates validation
    // Only validate keys that are actually present in the payload.
    if (profile_updates) {
      const pu = profile_updates;

      if (pu.max_hr !== undefined) {
        if (!Number.isInteger(pu.max_hr) || pu.max_hr < 100 || pu.max_hr > 220) {
          return jsonResponse({ error: "profile_updates.max_hr must be an integer between 100 and 220" }, 400);
        }
      }
      if (pu.ftp !== undefined) {
        if (!Number.isInteger(pu.ftp) || pu.ftp < 50 || pu.ftp > 500) {
          return jsonResponse({ error: "profile_updates.ftp must be an integer between 50 and 500" }, 400);
        }
      }
      if (pu.vma !== undefined) {
        if (typeof pu.vma !== "number" || pu.vma < 10 || pu.vma > 25) {
          return jsonResponse({ error: "profile_updates.vma must be a number between 10 and 25" }, 400);
        }
      }
      if (pu.css_seconds_per100m !== undefined) {
        if (!Number.isInteger(pu.css_seconds_per100m) || pu.css_seconds_per100m < 25 || pu.css_seconds_per100m > 300) {
          return jsonResponse({ error: "profile_updates.css_seconds_per100m must be an integer between 25 and 300" }, 400);
        }
      }
      if (pu.race_objective !== undefined) {
        if (!VALID_RACE_OBJECTIVES.has(pu.race_objective)) {
          return jsonResponse({
            error: `profile_updates.race_objective must be one of: ${[...VALID_RACE_OBJECTIVES].join(", ")}`,
          }, 400);
        }
      }
      if (pu.race_date !== undefined) {
        if (!isValidDate(pu.race_date)) {
          return jsonResponse({ error: "profile_updates.race_date must be a valid YYYY-MM-DD date" }, 400);
        }
      }
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

    // ── 9. Conflict check — existing active plan requires replace: true ───────
    const { data: existingPlan } = await db
      .from("training_plans")
      .select("id")
      .eq("user_id", userId)
      .eq("status", "active")
      .maybeSingle();

    if (existingPlan && replace !== true) {
      return jsonResponse({
        error: "User already has an active plan. Set replace: true to overwrite.",
      }, 409);
    }

    // ── 10. Materialise session structures in TypeScript ─────────────────────
    // Each session gets its structure JSONB pre-built here, then passed into
    // the Postgres function. This keeps all TS logic out of plpgsql.
    // Any materialize() failure is treated as a hard 400 — the caller must fix
    // their template rather than silently inserting a null-structure session.
    const failedTemplateIds: string[] = [];
    const weeksWithStructure = weeks.map((week) => ({
      ...week,
      sessions: week.sessions.map((session) => {
        // Safe: we validated every template_id exists above.
        const template = libraryMap.get(session.template_id);
        if (!template) {
          // This should never happen post-validation, but explicit guard beats !
          throw new Error(`Template ${session.template_id} missing post-validation`);
        }

        let structure: ReturnType<typeof materialize> | null = null;
        try {
          structure = materialize(template);
        } catch (err) {
          console.error(
            `import-plan: materialize failed for ${session.template_id}:`,
            err instanceof Error ? err.message : String(err)
          );
          failedTemplateIds.push(session.template_id);
        }
        return { ...session, structure };
      }),
    }));

    // Fail fast: do NOT call the RPC if any template failed to materialise.
    // The caller must fix the template before retrying.
    if (failedTemplateIds.length > 0) {
      return jsonResponse({
        error: "One or more session templates failed to materialise. Fix the templates and retry.",
        failed_template_ids: [...new Set(failedTemplateIds)],
      }, 400);
    }

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
      // PostgrestError has .message, .code, .details, .hint as top-level fields.
      console.error("import-plan: import_plan_atomic RPC error:", {
        message: atomicError.message,
        code:    atomicError.code,
        details: atomicError.details,
        hint:    atomicError.hint,
      });
      return jsonResponse({ error: "Database error during plan import" }, 500);
    }

    // ── 12. Success logging + response ────────────────────────────────────────
    // Cast once to the typed interface — avoids repeated inline casts.
    const result = atomicResult as AtomicResult;

    console.log(JSON.stringify({
      event:             "import-plan-success",
      user_id:           userId,
      plan_id:           result.plan_id,
      snapshot_id:       result.snapshot_id,
      weeks_inserted:    result.weeks_inserted,
      sessions_inserted: result.sessions_inserted,
    }));

    return jsonResponse({
      success:           true,
      plan_id:           result.plan_id,
      snapshot_id:       result.snapshot_id,
      weeks_inserted:    result.weeks_inserted,
      sessions_inserted: result.sessions_inserted,
    }, 200);

  } catch (err) {
    console.error(
      "import-plan: unhandled error:",
      err instanceof Error ? err.message : String(err)
    );
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
