import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import OpenAI from "npm:openai@4";

// Auto-generated prompt template — run scripts/sync-prompts.sh to regenerate
import promptTemplate from "./prompts/session-feedback-v0-prompt.ts";

// ── CORS headers ──────────────────────────────────────────────────────────────
// Allow all origins; the mobile app uses JWT auth, not cookies.
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

interface PlanSessionRow {
  id: string;
  day: string;
  sport: string;
  type: string;
  duration_minutes: number;
  feedback: string | null;
  order_in_day: number;
  week_id: string;
  plan_weeks: {
    id: string;
    phase: string;
    is_recovery: boolean;
    week_number: number;
    start_date: string;
    plan_id: string;
    training_plans: {
      user_id: string;
    };
  };
}

interface StravaActivityRow {
  id: string;
  user_id: string;
  normalized_sport: string | null;
  moving_time: number;
  distance: number | null;
  average_speed: number | null;
  average_heartrate: number | null;
  average_watts: number | null;
}

interface UserProfileRow {
  race_objective: string | null;
  race_date: string | null;
  experience_years: number | null;
  vma: number | null;
  css_seconds_per100m: number | null;
  ftp: number | null;
}

interface LapRow {
  lap_index: number;
  elapsed_time: number;
  moving_time: number;
  distance: number | null;
  average_speed: number | null;
  average_cadence: number | null;
  average_watts: number | null;
  average_heartrate: number | null;
  max_heartrate: number | null;
}

interface WeekSessionRow {
  id: string;
  day: string;
  sport: string;
  type: string;
  duration_minutes: number;
  feedback: string | null;
  order_in_day: number;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Map day name to offset from Monday (0-indexed). */
const dayOffsets: Record<string, number> = {
  Mon: 0,
  Tue: 1,
  Wed: 2,
  Thu: 3,
  Fri: 4,
  Sat: 5,
  Sun: 6,
};

/**
 * Format sport-specific pace from average_speed (m/s).
 * - Run: min:sec/km
 * - Bike: km/h
 * - Swim: min:sec/100m
 */
function formatPace(sport: string, avgSpeedMs: number | null): string {
  if (avgSpeedMs == null || avgSpeedMs <= 0) return "N/A";

  switch (sport) {
    case "run": {
      // m/s → sec/km → min:sec/km
      const secPerKm = 1000 / avgSpeedMs;
      const min = Math.floor(secPerKm / 60);
      const sec = Math.round(secPerKm % 60);
      return `${min}:${String(sec).padStart(2, "0")}/km`;
    }
    case "bike": {
      // m/s → km/h
      const kmh = avgSpeedMs * 3.6;
      return `${kmh.toFixed(1)} km/h`;
    }
    case "swim": {
      // m/s → sec/100m → min:sec/100m
      const secPer100m = 100 / avgSpeedMs;
      const min = Math.floor(secPer100m / 60);
      const sec = Math.round(secPer100m % 60);
      return `${min}:${String(sec).padStart(2, "0")}/100m`;
    }
    default:
      return "N/A";
  }
}

/**
 * Format lap data for the prompt.
 * Each lap line includes duration, HR (if available), sport-specific metric, and distance.
 * Rest is inferred from elapsed_time vs moving_time difference per lap.
 */
function formatLaps(laps: LapRow[], sport: string): string {
  if (!laps || laps.length === 0) return "No lap data available.";

  return laps.map((lap) => {
    const parts: string[] = [];

    // Duration: format moving_time as M:SS
    const durMin = Math.floor(lap.moving_time / 60);
    const durSec = Math.round(lap.moving_time % 60);
    parts.push(`${durMin}:${String(durSec).padStart(2, "0")}`);

    // HR: avg bpm if available
    if (lap.average_heartrate != null) {
      parts.push(`avg ${Math.round(lap.average_heartrate)} bpm`);
    }

    // Sport-specific metric
    switch (sport) {
      case "run":
        parts.push(formatPace("run", lap.average_speed));
        break;
      case "bike":
        if (lap.average_watts != null) {
          parts.push(`${Math.round(lap.average_watts)} W`);
        }
        break;
      case "swim":
        parts.push(formatPace("swim", lap.average_speed));
        break;
    }

    // Distance: km for run/bike, meters for swim
    if (lap.distance != null) {
      if (sport === "swim") {
        parts.push(`${Math.round(lap.distance)} m`);
      } else {
        parts.push(`${(lap.distance / 1000).toFixed(2)} km`);
      }
    }

    let line = `Lap ${lap.lap_index + 1}: ${parts.join(", ")}`;

    // Append rest indicator if elapsed_time significantly exceeds moving_time
    const rest = lap.elapsed_time - lap.moving_time;
    if (rest > 10) {
      line += ` (includes ${Math.round(rest)}s rest)`;
    }

    return line;
  }).join("\n");
}

/**
 * Format weekly sessions context for the prompt.
 * Each session: "Mon: Easy Swim 45 min [completed]" / "[missed]" / "[upcoming]"
 */
function formatWeekSessions(
  sessions: WeekSessionRow[],
  weekStartDate: string,
  today: Date
): string {
  if (!sessions || sessions.length === 0) return "No sessions this week.";

  // Parse week start date
  const weekStart = new Date(weekStartDate + "T00:00:00Z");

  const lines = sessions
    .sort((a, b) => {
      const dayDiff = (dayOffsets[a.day] ?? 0) - (dayOffsets[b.day] ?? 0);
      return dayDiff !== 0 ? dayDiff : a.order_in_day - b.order_in_day;
    })
    .map((s) => {
      const offset = dayOffsets[s.day] ?? 0;
      const sessionDate = new Date(weekStart);
      sessionDate.setUTCDate(sessionDate.getUTCDate() + offset);

      // V0 limitation: comparison uses UTC — may mis-label sessions near
      // midnight in the athlete's local timezone. Acceptable for prompt context.
      let status: string;
      if (s.feedback != null) {
        status = "[completed]";
      } else if (sessionDate < today) {
        // "pending" rather than "missed" — the session may just not be synced yet
        status = "[pending]";
      } else {
        status = "[upcoming]";
      }

      const sportLabel = s.sport.charAt(0).toUpperCase() + s.sport.slice(1);
      return `${s.day}: ${s.type} ${sportLabel} ${s.duration_minutes} min ${status}`;
    });

  return lines.join("\n");
}

// ── Main handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  // 1. CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // 2. Method guard — only POST accepted
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  // 3. Validate required environment variables
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const openaiApiKey = Deno.env.get("OPENAI_API_KEY");

  if (!supabaseUrl || !supabaseServiceRoleKey) {
    return jsonResponse({ error: "Missing Supabase environment variables" }, 500);
  }
  if (!openaiApiKey) {
    return jsonResponse({ error: "Missing OpenAI environment variable" }, 500);
  }

  // 4. Validate JWT — exact same pattern as chat-adjust
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing Authorization header" }, 401);
  }
  const jwt = authHeader.replace("Bearer ", "");

  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? supabaseServiceRoleKey;
  const authClient = createClient(supabaseUrl, supabaseAnonKey);
  const { data: { user }, error: authError } = await authClient.auth.getUser(jwt);
  if (authError || !user) {
    return jsonResponse({ error: "Invalid token" }, 401);
  }
  const userId = user.id;

  // Service-role client for all DB operations (bypasses RLS)
  const db = createClient(supabaseUrl, supabaseServiceRoleKey);

  try {
    // 5. Parse and validate request body
    let body: { plan_session_id?: string; strava_activity_id?: string };
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const { plan_session_id: planSessionId, strava_activity_id: stravaActivityId } = body;
    if (!planSessionId || typeof planSessionId !== "string") {
      return jsonResponse({ error: "Missing required field: plan_session_id" }, 400);
    }
    if (!stravaActivityId || typeof stravaActivityId !== "string") {
      return jsonResponse({ error: "Missing required field: strava_activity_id" }, 400);
    }

    // 6. Fetch plan session with joins (also serves as idempotency check)
    const { data: sessionData, error: sessionFetchError } = await db
      .from("plan_sessions")
      .select(
        "id, day, sport, type, duration_minutes, feedback, order_in_day, week_id, " +
        "plan_weeks!inner(id, phase, is_recovery, week_number, start_date, plan_id, " +
        "training_plans!inner(user_id))"
      )
      .eq("id", planSessionId)
      .single();

    if (sessionFetchError || !sessionData) {
      console.error("Session fetch error:", sessionFetchError?.message);
      return jsonResponse({ error: "Session not found" }, 404);
    }

    const session = sessionData as unknown as PlanSessionRow;

    // Idempotency: if feedback already exists, skip
    if (session.feedback != null) {
      return jsonResponse({ skipped: true });
    }

    // 7. Fetch remaining context in parallel (activity, profile, week sessions)
    const weekId = session.plan_weeks.id;

    const [activityResult, profileResult, weekSessionsResult, lapsResult] = await Promise.all([
      // a) Strava activity
      db
        .from("strava_activities")
        .select("id, user_id, normalized_sport, moving_time, distance, average_speed, average_heartrate, average_watts")
        .eq("id", stravaActivityId)
        .single(),

      // b) User profile
      db
        .from("users")
        .select("race_objective, race_date, experience_years, vma, css_seconds_per100m, ftp")
        .eq("id", userId)
        .single(),

      // c) All sessions in this week
      db
        .from("plan_sessions")
        .select("id, day, sport, type, duration_minutes, feedback, order_in_day")
        .eq("week_id", weekId),

      // d) Activity laps
      db
        .from("strava_activity_laps")
        .select("lap_index, elapsed_time, moving_time, distance, average_speed, average_cadence, average_watts, average_heartrate, max_heartrate")
        .eq("activity_id", stravaActivityId)
        .order("lap_index", { ascending: true }),
    ]);

    // Validate activity fetch
    if (activityResult.error || !activityResult.data) {
      console.error("Activity fetch error:", activityResult.error?.message);
      return jsonResponse({ error: "Activity not found" }, 404);
    }

    const activity = activityResult.data as StravaActivityRow;

    // 8. Validate ownership
    const planOwnerUserId = session.plan_weeks?.training_plans?.user_id;
    if (planOwnerUserId !== userId) {
      return jsonResponse({ error: "Session does not belong to this user" }, 403);
    }
    if (activity.user_id !== userId) {
      return jsonResponse({ error: "Activity does not belong to this user" }, 403);
    }

    // Non-critical: log profile errors but continue
    if (profileResult.error) {
      console.error("User profile fetch warning:", profileResult.error.message);
    }
    const profile = profileResult.data as UserProfileRow | null;

    // Non-critical: log week sessions errors but continue
    if (weekSessionsResult.error) {
      console.error("Week sessions fetch warning:", weekSessionsResult.error.message);
    }
    const weekSessions = (weekSessionsResult.data as WeekSessionRow[] | null) ?? [];

    // Non-critical: log laps errors but continue
    if (lapsResult.error) {
      console.error("Laps fetch warning:", lapsResult.error.message);
    }
    const laps = (lapsResult.data as LapRow[] | null) ?? [];

    // 9. Build the rendered prompt
    const weekStartDate = session.plan_weeks.start_date;
    const today = new Date();

    // Format CSS for the prompt
    let cssFormatted = "N/A";
    if (profile?.css_seconds_per100m != null) {
      const cssMin = Math.floor(profile.css_seconds_per100m / 60);
      const cssSec = Math.round(profile.css_seconds_per100m % 60);
      cssFormatted = `${cssMin}:${String(cssSec).padStart(2, "0")}`;
    }

    const movingTimeMin = Math.round(activity.moving_time / 60);
    const distanceKm = activity.distance != null ? (activity.distance / 1000).toFixed(2) : "N/A";
    const avgHr = activity.average_heartrate != null ? Math.round(activity.average_heartrate).toString() : "N/A";
    const formattedPace = formatPace(session.sport, activity.average_speed);
    const avgWatts = activity.average_watts != null ? Math.round(activity.average_watts).toString() : "N/A";

    const renderedPrompt = promptTemplate
      .replace("{{race_objective}}", profile?.race_objective ?? "N/A")
      .replace("{{race_date}}", profile?.race_date ?? "N/A")
      .replace("{{experience_years}}", profile?.experience_years?.toString() ?? "N/A")
      .replace("{{vma}}", profile?.vma?.toString() ?? "N/A")
      .replace("{{ftp}}", profile?.ftp?.toString() ?? "N/A")
      .replace("{{css}}", cssFormatted)
      .replace("{{phase}}", session.plan_weeks.phase)
      .replace("{{week_number}}", session.plan_weeks.week_number.toString())
      .replace("{{is_recovery}}", session.plan_weeks.is_recovery ? "Yes" : "No")
      .replace("{{week_sessions}}", formatWeekSessions(weekSessions, weekStartDate, today))
      .replace("{{sport}}", session.sport)
      .replace("{{type}}", session.type)
      .replace("{{planned_duration}}", session.duration_minutes.toString())
      .replace("{{moving_time_min}}", movingTimeMin.toString())
      .replace("{{distance_km}}", distanceKm)
      .replace("{{avg_hr}}", avgHr)
      .replace("{{formatted_pace}}", formattedPace)
      .replace("{{avg_watts}}", avgWatts)
      .replace("{{laps}}", formatLaps(laps, session.sport));

    // 10. Call OpenAI
    const openai = new OpenAI({ apiKey: openaiApiKey });
    let completion;
    try {
      completion = await openai.chat.completions.create({
        model: "gpt-4.1",
        temperature: 0.7,
        max_tokens: 150,
        messages: [
          { role: "system", content: renderedPrompt },
          { role: "user", content: "Please provide feedback for this session." },
        ],
      });
    } catch (err) {
      console.error("OpenAI error:", err instanceof Error ? err.message : String(err));
      return jsonResponse({ error: "AI service unavailable" }, 502);
    }

    const feedbackText = completion.choices[0]?.message?.content?.trim() ?? "";

    if (!feedbackText) {
      console.error("OpenAI returned empty response for session:", planSessionId);
      return jsonResponse({ error: "AI returned an empty response. Please try again." }, 502);
    }

    // 11. Write feedback to DB
    const { error: updateError } = await db
      .from("plan_sessions")
      .update({
        feedback: feedbackText,
        matched_activity_id: stravaActivityId,
      })
      .eq("id", planSessionId);

    if (updateError) {
      console.error("DB update error:", updateError.message);
      return jsonResponse({ error: "Failed to save feedback" }, 500);
    }

    // 12. Return feedback
    return jsonResponse({ feedback: feedbackText });
  } catch (err) {
    console.error(
      "Unhandled error in session-feedback:",
      err instanceof Error ? err.message : String(err)
    );
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
