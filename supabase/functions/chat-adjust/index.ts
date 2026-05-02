import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import OpenAI from "npm:openai@4";

// Auto-generated prompt template — run scripts/sync-prompts.sh to regenerate
import promptTemplate from "./prompts/coach-chat-v0-prompt.ts";

// ── Prompt split — fail loud at boot time if the delimiter is missing ─────────
// The prompt has two sections: everything before "--- DYNAMIC ---" is the stable
// STATIC system message (persona, rules, length caps). Everything after is the
// DYNAMIC user-message block with {{placeholder}} tokens for per-request context.
// This split is validated once here; bad prompt files will crash on cold start,
// not silently mid-request.
const promptParts = promptTemplate.split(/^--- DYNAMIC ---$/m);
if (promptParts.length !== 2) {
  throw new Error(
    `coach-chat-v0 prompt must contain exactly one '--- DYNAMIC ---' delimiter, got ${promptParts.length - 1}`
  );
}
const STATIC_SYSTEM = promptParts[0].trim();
const DYNAMIC_TEMPLATE = promptParts[1]; // preserve leading newline for template placeholders

// ── Allowlist — V0 is gated to a single user ────────────────────────────────
// Server-side enforcement. The iOS client also hides the tab, but this guard
// is the authoritative gate (defense in depth per Critical Decisions).
const ALLOWED_EMAIL = "ebreard4@gmail.com";

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

interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

interface UserProfile {
  race_objective?: string | null;
  race_date?: string | null;
  experience_years?: number | null;
  vma?: number | null;
  css_seconds_per100m?: number | null;
  ftp?: number | null;
  max_hr?: number | null;
  current_weekly_hours?: number | null;
  swim_days?: string[] | null;
  bike_days?: string[] | null;
  run_days?: string[] | null;
}

interface TrainingPlan {
  id: string;
  total_weeks: number;
  start_date: string;
  race_date?: string | null;
}

interface PlanWeek {
  id: string;
  week_number: number;
  phase: string;
  is_recovery: boolean;
  start_date: string;
}

interface PlanSession {
  id: string;
  day: string;
  sport: string;
  type: string;
  template_id: string;
  duration_minutes: number;
  notes?: string | null;
  feedback?: string | null;
  matched_activity_id?: string | null;
  order_in_day: number;
}

interface StravaActivityLap {
  lap_index: number;
  average_heartrate?: number | null;
  max_heartrate?: number | null;
  average_speed?: number | null; // m/s
  average_watts?: number | null;
}

// ── Context formatters ────────────────────────────────────────────────────────

/**
 * Athlete profile: race objective, race date, experience, VMA, FTP, CSS, max HR.
 * The fixture shape from scripts/test-coach-chat.mjs is:
 *   "Race objective: Ironman 70.3 on 2026-05-31 (29 days away)
 *    Experience: 2 years
 *    VMA: 18 km/h | FTP: 275W | CSS: 1:55/100m | Max HR: 192 bpm"
 */
function formatAthleteProfile(profile: UserProfile | null): string {
  if (!profile) return "No profile available.";

  const lines: string[] = [];

  // Race objective + date
  if (profile.race_objective) {
    if (profile.race_date) {
      const raceDate = new Date(profile.race_date);
      const today = new Date();
      const daysAway = Math.ceil(
        (raceDate.getTime() - today.getTime()) / (1000 * 60 * 60 * 24)
      );
      const dateStr = raceDate.toISOString().slice(0, 10);
      lines.push(`Race objective: ${profile.race_objective} on ${dateStr} (${daysAway} days away)`);
    } else {
      lines.push(`Race objective: ${profile.race_objective}`);
    }
  }

  if (profile.experience_years != null) lines.push(`Experience: ${profile.experience_years} years`);

  // Metrics line — combine onto one line like the validated fixture
  const metrics: string[] = [];
  if (profile.vma != null) metrics.push(`VMA: ${profile.vma} km/h`);
  if (profile.ftp != null) metrics.push(`FTP: ${profile.ftp}W`);
  if (profile.css_seconds_per100m != null) {
    const minutes = Math.floor(profile.css_seconds_per100m / 60);
    const seconds = profile.css_seconds_per100m % 60;
    metrics.push(`CSS: ${minutes}:${String(seconds).padStart(2, "0")}/100m`);
  }
  if (profile.max_hr != null) metrics.push(`Max HR: ${profile.max_hr} bpm`);
  if (metrics.length > 0) lines.push(metrics.join(" | "));

  return lines.length > 0 ? lines.join("\n") : "No profile details available.";
}

/**
 * Plan summary: current phase, week N of M, weeks remaining, recovery weeks ahead.
 * The fixture shape:
 *   "Currently in Week 6 of 10 — Build phase.
 *    Phase map: W1-3 Base, W4-5 Recovery, W6-7 Build, W8 Peak, W9-10 Taper.
 *    4 weeks remaining: Build (W7), Peak (W8), Taper (W9-10)."
 */
function formatPlanSummary(
  plan: TrainingPlan | null,
  weeks: PlanWeek[],
  currentWeek: PlanWeek | null
): string {
  if (!plan || weeks.length === 0) return "No active training plan.";

  const totalWeeks = plan.total_weeks;
  const currentWeekNum = currentWeek?.week_number ?? 1;
  const currentPhase = currentWeek?.phase ?? "Unknown";

  // Line 1: current position
  const lines: string[] = [];
  lines.push(`Currently in Week ${currentWeekNum} of ${totalWeeks} — ${currentPhase} phase.`);

  // Line 2: compact phase map (e.g. "W1-3 Base, W4-5 Recovery, W6-7 Build")
  // Group consecutive weeks with the same phase
  const phaseGroups: { phase: string; start: number; end: number }[] = [];
  for (const w of weeks) {
    const last = phaseGroups[phaseGroups.length - 1];
    if (last && last.phase === w.phase && last.end === w.week_number - 1) {
      last.end = w.week_number;
    } else {
      phaseGroups.push({ phase: w.phase, start: w.week_number, end: w.week_number });
    }
  }
  const phaseMapStr = phaseGroups
    .map((g) => (g.start === g.end ? `W${g.start} ${g.phase}` : `W${g.start}-${g.end} ${g.phase}`))
    .join(", ");
  lines.push(`Phase map: ${phaseMapStr}.`);

  // Line 3: weeks remaining
  const remainingWeeks = weeks.filter((w) => w.week_number > currentWeekNum);
  if (remainingWeeks.length > 0) {
    const remainingStr = remainingWeeks
      .map((w) => `${w.phase} (W${w.week_number})${w.is_recovery ? " [recovery]" : ""}`)
      .join(", ");
    lines.push(`${remainingWeeks.length} week${remainingWeeks.length !== 1 ? "s" : ""} remaining: ${remainingStr}.`);
  } else {
    lines.push("This is the final week of the plan.");
  }

  return lines.join("\n");
}

/**
 * Today's session(s) from the current week.
 * Format: "Saturday: BIKE Tempo (BIKE_Tempo_19), 180min — "notes". Already completed today."
 */
function formatTodaySession(
  sessions: PlanSession[],
  todayName: string
): string {
  const todaySessions = sessions
    .filter((s) => s.day === todayName)
    .sort((a, b) => a.order_in_day - b.order_in_day);

  if (todaySessions.length === 0) {
    return `${todayName} is a REST DAY (no scheduled training).`;
  }

  return todaySessions
    .map((s) => {
      const completed = s.matched_activity_id ? " Already completed today." : "";
      const notesStr = s.notes ? ` — "${s.notes}"` : "";
      return `${todayName}: ${s.sport.toUpperCase()} ${s.type} (${s.template_id}), ${s.duration_minutes}min${notesStr}.${completed}`;
    })
    .join("\n");
}

/**
 * Week map: day-by-day with completed/upcoming markers.
 * Format matches fixture: "Mon: SWIM Tempo 55min (done) — felt fast but cut short"
 */
function formatWeekMap(sessions: PlanSession[], todayName: string): string {
  if (sessions.length === 0) return "No sessions scheduled this week.";

  const DAYS_ORDER = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
  const DAY_ABBR: Record<string, string> = {
    Monday: "Mon", Tuesday: "Tue", Wednesday: "Wed", Thursday: "Thu",
    Friday: "Fri", Saturday: "Sat", Sunday: "Sun",
  };

  // Group sessions by day
  const byDay = new Map<string, PlanSession[]>();
  for (const s of sessions) {
    if (!byDay.has(s.day)) byDay.set(s.day, []);
    byDay.get(s.day)!.push(s);
  }

  // Sort each day's sessions by order
  for (const daySessions of byDay.values()) {
    daySessions.sort((a, b) => a.order_in_day - b.order_in_day);
  }

  const todayIdx = DAYS_ORDER.indexOf(todayName);

  const lines: string[] = [];
  for (const day of DAYS_ORDER) {
    if (!byDay.has(day)) continue; // skip rest days (only emit days that have sessions)
    const daySessions = byDay.get(day)!;
    const dayIdx = DAYS_ORDER.indexOf(day);
    const isToday = day === todayName;
    const isPast = dayIdx < todayIdx;

    const label = isToday ? `${DAY_ABBR[day]} (today)` : DAY_ABBR[day];
    const sessionStr = daySessions
      .map((s) => {
        const status = s.matched_activity_id
          ? "(done)"
          : isPast ? "(missed?)" : "(upcoming)";
        const feedbackNote = s.feedback ? ` — ${s.feedback}` : "";
        return `${s.sport.toUpperCase()} ${s.type} ${s.duration_minutes}min ${status}${feedbackNote}`;
      })
      .join(" + ");

    lines.push(`${label}: ${sessionStr}`);
  }

  return lines.length > 0 ? lines.join("\n") : "No sessions scheduled this week.";
}

/**
 * Last 3 completed sessions with lap data.
 *
 * Format mirrors the validated fixture in scripts/test-coach-chat.mjs ~line 55:
 *   "1) Sat (today): BIKE Tempo 180min — actual: 80km in 2h52, avg HR 132 (no power meter — watts unavailable).
 *       Lap-by-lap (5km laps, avg HR / max HR / km/h):
 *       L0  124/142 23   L1  130/136 25   ...
 *       Plan said "...notes...". Coach feedback noted: ..."
 *
 * The lap table uses "avg HR / max HR / km/h" columns with watts appended when available.
 * This exact shape was validated during Phase 1; deviating risks regression.
 */
function formatRecentCompleted(
  sessions: PlanSession[],
  lapsMap: Map<string, StravaActivityLap[]>
): string {
  // Filter to completed (matched) sessions, sort by most recent first
  // Sessions come from the current week — we emit up to 3
  const completed = sessions
    .filter((s) => s.matched_activity_id != null)
    .sort((a, b) => {
      // Sort by day descending (Sunday=6...Monday=0)
      const DAYS_ORDER = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
      return DAYS_ORDER.indexOf(b.day) - DAYS_ORDER.indexOf(a.day);
    })
    .slice(0, 3);

  if (completed.length === 0) return "No recent completed sessions.";

  const DAY_ABBR: Record<string, string> = {
    Monday: "Mon", Tuesday: "Tue", Wednesday: "Wed", Thursday: "Thu",
    Friday: "Fri", Saturday: "Sat", Sunday: "Sun",
  };

  return completed
    .map((s, i) => {
      const dayLabel = DAY_ABBR[s.day] ?? s.day;
      const header = `${i + 1}) ${dayLabel}: ${s.sport.toUpperCase()} ${s.type} ${s.duration_minutes}min`;

      const laps = s.matched_activity_id ? (lapsMap.get(s.matched_activity_id) ?? []) : [];
      laps.sort((a, b) => a.lap_index - b.lap_index);

      let lapSection = "";
      if (laps.length > 0) {
        // Detect if any lap has watts
        const hasWatts = laps.some((l) => l.average_watts != null && l.average_watts > 0);
        const colHeader = hasWatts
          ? "Lap-by-lap (avg HR / max HR / km/h / W):"
          : "Lap-by-lap (avg HR / max HR / km/h):";

        // Build compact lap rows — 4 per line, matching fixture layout
        const lapTokens = laps.map((l) => {
          const avgHr = l.average_heartrate != null ? Math.round(l.average_heartrate) : "?";
          const maxHr = l.max_heartrate != null ? Math.round(l.max_heartrate) : "?";
          const kmh = l.average_speed != null
            ? Math.round(l.average_speed * 3.6) // m/s → km/h
            : "?";
          const wStr = hasWatts
            ? ` ${l.average_watts != null ? Math.round(l.average_watts) : "?"}`
            : "";
          return `L${l.lap_index}  ${avgHr}/${maxHr} ${kmh}${wStr}`;
        });

        // Join into rows of 4
        const rows: string[] = [];
        for (let r = 0; r < lapTokens.length; r += 4) {
          rows.push("   " + lapTokens.slice(r, r + 4).join("   "));
        }
        lapSection = `\n   ${colHeader}\n${rows.join("\n")}`;
      } else {
        lapSection = "\n   No lap data available.";
      }

      // Power note — if no laps have watts, note absence explicitly (per fixture)
      const hasPowerData = laps.some((l) => l.average_watts != null && l.average_watts > 0);
      const powerNote = laps.length > 0 && !hasPowerData
        ? " (no power meter — watts unavailable)"
        : "";

      // Feedback from plan_sessions (AI-generated coaching commentary from session-feedback fn)
      const feedbackLine = s.feedback
        ? `\n   Coach feedback noted: ${s.feedback}`
        : "";

      const notesLine = s.notes
        ? `\n   Plan said: "${s.notes}".`
        : "";

      return `${header}${powerNote}.${lapSection}${notesLine}${feedbackLine}`;
    })
    .join("\n\n");
}

/**
 * Tomorrow's session(s).
 * Format: "Sunday: 1) RUN Tempo brick 90min — "notes". 2) SWIM Easy 45min."
 */
function formatTomorrowSession(
  sessions: PlanSession[],
  tomorrowName: string
): string {
  const tomorrowSessions = sessions
    .filter((s) => s.day === tomorrowName)
    .sort((a, b) => a.order_in_day - b.order_in_day);

  if (tomorrowSessions.length === 0) {
    return `${tomorrowName} is a REST DAY (no scheduled training).`;
  }

  if (tomorrowSessions.length === 1) {
    const s = tomorrowSessions[0];
    const notesStr = s.notes ? ` — "${s.notes}"` : "";
    return `${tomorrowName}: ${s.sport.toUpperCase()} ${s.type} ${s.duration_minutes}min${notesStr}.`;
  }

  // Multiple sessions
  const sessionLines = tomorrowSessions.map((s, i) => {
    const notesStr = s.notes ? ` — "${s.notes}"` : "";
    return `${i + 1}) ${s.sport.toUpperCase()} ${s.type} ${s.duration_minutes}min${notesStr}`;
  });
  return `${tomorrowName}: ${sessionLines.join(". ")}.`;
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

  // 4. Validate JWT — exact same pattern as strava-auth
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing Authorization header" }, 401);
  }
  const jwt = authHeader.replace("Bearer ", "");

  // Use anon-key client (or service role as fallback) for auth validation only
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? supabaseServiceRoleKey;
  const authClient = createClient(supabaseUrl, supabaseAnonKey);
  const { data: { user }, error: authError } = await authClient.auth.getUser(jwt);
  if (authError || !user) {
    return jsonResponse({ error: "Invalid token" }, 401);
  }

  // 5. Allowlist gate — V0 is restricted to a single user (defense in depth)
  if (user.email !== ALLOWED_EMAIL) {
    return jsonResponse({ error: "Not authorized" }, 403);
  }

  const userId = user.id;

  // Service-role client for all DB operations (bypasses RLS)
  const db = createClient(supabaseUrl, supabaseServiceRoleKey);

  try {
    // 6. Parse and validate request body
    let body: { message?: string };
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const { message } = body;
    if (!message || typeof message !== "string" || message.trim().length === 0) {
      return jsonResponse({ error: "Missing required field: message" }, 400);
    }
    if (message.length > 1000) {
      return jsonResponse({ error: "Message exceeds 1000 character limit" }, 400);
    }

    // 7. Determine today and tomorrow day names (UTC date → English full day name)
    // plan_weeks.start_date is stored as DATE; we find the active week by matching
    // today's date against [start_date, start_date + 7 days). Day names match
    // plan_sessions.day column values (e.g. "Saturday").
    const todayDate = new Date();
    const DAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    const todayName = DAY_NAMES[todayDate.getUTCDay()];
    const tomorrowDate = new Date(todayDate);
    tomorrowDate.setUTCDate(tomorrowDate.getUTCDate() + 1);
    const tomorrowName = DAY_NAMES[tomorrowDate.getUTCDay()];
    const todayStr = todayDate.toISOString().slice(0, 10); // "YYYY-MM-DD"

    // 8. Parallel fetch all context data
    const [
      historyResult,
      profileResult,
      planResult,
    ] = await Promise.all([
      // a) Last 50 messages DESC (newest first), reversed to chronological below
      db
        .from("chat_messages")
        .select("role, content")
        .eq("user_id", userId)
        .order("created_at", { ascending: false })
        .limit(50),

      // b) User profile (all fields used by formatAthleteProfile)
      db
        .from("users")
        .select(
          "race_objective, race_date, experience_years, vma, css_seconds_per100m, ftp, max_hr, current_weekly_hours, swim_days, bike_days, run_days"
        )
        .eq("id", userId)
        .single(),

      // c) Active training plan with all weeks (ordered ascending for phase map)
      db
        .from("training_plans")
        .select(`
          id,
          total_weeks,
          start_date,
          race_date,
          plan_weeks (
            id,
            week_number,
            phase,
            is_recovery,
            start_date
          )
        `)
        .eq("user_id", userId)
        .eq("status", "active")
        .order("week_number", { referencedTable: "plan_weeks", ascending: true })
        .single(),
    ]);

    // History is critical; bail on DB error
    if (historyResult.error) {
      console.error("chat_messages history fetch error:", historyResult.error.message);
      return jsonResponse({ error: "Failed to load chat history" }, 500);
    }

    // Non-critical: log but continue with graceful fallbacks
    if (profileResult.error) {
      console.error("user profile fetch warning:", profileResult.error.message);
    }
    if (planResult.error) {
      console.error("plan fetch warning:", planResult.error.message);
    }

    // 9. Resolve current week and fetch plan sessions for it
    const plan = planResult.data as (TrainingPlan & { plan_weeks: PlanWeek[] }) | null;
    const allWeeks: PlanWeek[] = plan?.plan_weeks ?? [];

    // Find the week whose date range contains today
    // plan_weeks.start_date is DATE stored as string "YYYY-MM-DD"
    const currentWeek = allWeeks.find((w) => {
      const weekStart = new Date(w.start_date + "T00:00:00Z");
      const weekEnd = new Date(weekStart);
      weekEnd.setUTCDate(weekEnd.getUTCDate() + 7);
      const today = new Date(todayStr + "T00:00:00Z");
      return today >= weekStart && today < weekEnd;
    }) ?? null;

    // Fetch plan sessions for current week (if we found one)
    let weekSessions: PlanSession[] = [];
    if (currentWeek) {
      const sessionsResult = await db
        .from("plan_sessions")
        .select("id, day, sport, type, template_id, duration_minutes, notes, feedback, matched_activity_id, order_in_day")
        .eq("week_id", currentWeek.id)
        .order("order_in_day", { ascending: true });

      if (sessionsResult.error) {
        console.error("plan_sessions fetch warning:", sessionsResult.error.message);
      } else {
        weekSessions = (sessionsResult.data ?? []) as PlanSession[];
      }
    }

    // 10. Fetch strava_activity_laps for all matched activities in this week.
    // This join is non-negotiable (Critical Decisions): without lap-level HR/speed data
    // the model gives generic or fabricated post-session feedback.
    const matchedActivityIds = weekSessions
      .map((s) => s.matched_activity_id)
      .filter((id): id is string => id != null);

    const lapsMap = new Map<string, StravaActivityLap[]>();
    if (matchedActivityIds.length > 0) {
      const lapsResult = await db
        .from("strava_activity_laps")
        .select("activity_id, lap_index, average_heartrate, max_heartrate, average_speed, average_watts")
        .in("activity_id", matchedActivityIds)
        .order("lap_index", { ascending: true });

      if (lapsResult.error) {
        console.error("strava_activity_laps fetch warning:", lapsResult.error.message);
      } else {
        for (const lap of (lapsResult.data ?? [])) {
          const actId: string = lap.activity_id;
          if (!lapsMap.has(actId)) lapsMap.set(actId, []);
          lapsMap.get(actId)!.push(lap as StravaActivityLap);
        }
      }
    }

    // 11. Build context strings
    const userProfile = profileResult.data as UserProfile | null;

    const athleteProfileStr = formatAthleteProfile(userProfile);
    const planSummaryStr = formatPlanSummary(
      plan as TrainingPlan | null,
      allWeeks,
      currentWeek
    );
    const todaySessionStr = formatTodaySession(weekSessions, todayName);
    const weekMapStr = formatWeekMap(weekSessions, todayName);
    const recentCompletedStr = formatRecentCompleted(weekSessions, lapsMap);
    const tomorrowSessionStr = formatTomorrowSession(weekSessions, tomorrowName);

    // 12. Render the DYNAMIC user message by substituting all placeholders
    const dynamicContent = DYNAMIC_TEMPLATE
      .replace("{{athlete_profile}}", athleteProfileStr)
      .replace("{{plan_summary}}", planSummaryStr)
      .replace("{{today_session}}", todaySessionStr)
      .replace("{{week_map}}", weekMapStr)
      .replace("{{recent_completed}}", recentCompletedStr)
      .replace("{{tomorrow_session}}", tomorrowSessionStr)
      .trim();

    // 13. Reverse history to chronological order (oldest first for context window)
    const historyMessages: ChatMessage[] = (
      (historyResult.data as ChatMessage[] | null) ?? []
    ).reverse();

    // 14. Insert user message BEFORE OpenAI call — ensures persistence even on AI failure
    const { error: userInsertError } = await db.from("chat_messages").insert({
      user_id: userId,
      role: "user",
      content: message,
    });
    if (userInsertError) {
      console.error("chat_messages user insert error:", userInsertError.message);
      return jsonResponse({ error: "Failed to save user message" }, 500);
    }

    // 15. Build OpenAI messages array.
    // Message ordering: [system(STATIC), user(DYNAMIC), ...history, user(message)]
    // - STATIC system message is stable across turns → OpenAI prefix-caches it
    // - DYNAMIC user block carries the full per-request context
    // - History turns follow (cached on subsequent turns with same context)
    // - New user message last
    const openAiMessages: OpenAI.Chat.ChatCompletionMessageParam[] = [
      { role: "system", content: STATIC_SYSTEM },
      { role: "user", content: dynamicContent },
      ...historyMessages.map((m) => ({
        role: m.role as "user" | "assistant",
        content: m.content,
      })),
      { role: "user", content: message },
    ];

    // 16. Call OpenAI — model + temperature + max_tokens validated in Phase 1, do not change
    const openai = new OpenAI({ apiKey: openaiApiKey });
    const completion = await openai.chat.completions.create({
      model: "gpt-4.1",
      temperature: 0.3,
      max_tokens: 400,
      messages: openAiMessages,
    });

    const responseText = completion.choices[0]?.message?.content?.trim() ?? "";

    if (!responseText) {
      console.error("OpenAI returned empty response for user:", userId);
      return jsonResponse({ error: "AI returned an empty response. Please try again." }, 502);
    }

    // Log token usage for observability (Step 8 verification)
    const usage = completion.usage;
    if (usage) {
      const cached = (usage as unknown as { prompt_tokens_details?: { cached_tokens?: number } })
        .prompt_tokens_details?.cached_tokens ?? 0;
      console.log(
        `tokens: prompt=${usage.prompt_tokens} (cached=${cached}) completion=${usage.completion_tokens}`
      );
    }

    // 17. Insert assistant message — V0: pure text, no status classification
    const { error: assistantInsertError } = await db.from("chat_messages").insert({
      user_id: userId,
      role: "assistant",
      content: responseText,
      status: null,
      constraint_summary: null,
    });
    if (assistantInsertError) {
      console.error("chat_messages assistant insert error:", assistantInsertError.message);
      return jsonResponse({ error: "Failed to save assistant message" }, 500);
    }

    // 18. Return conversational text to iOS client
    return jsonResponse({ response_text: responseText });
  } catch (err) {
    console.error(
      "Unhandled error in chat-adjust:",
      err instanceof Error ? err.message : String(err)
    );
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
