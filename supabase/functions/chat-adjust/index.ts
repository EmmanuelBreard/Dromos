import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

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

// ── Timezone helpers — V0 single-user ────────────────────────────────────────
// V0 single-user allowlist — hardcode the user's timezone.
// When V0 expands, store this on `users` and look it up per user.
const USER_TIMEZONE = "Europe/Paris";

function todayInUserTz(): { date: string; day: string } {
  const now = new Date();
  const dateFmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: USER_TIMEZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const dayFmt = new Intl.DateTimeFormat("en-US", {
    timeZone: USER_TIMEZONE,
    weekday: "long",
  });
  return { date: dateFmt.format(now), day: dayFmt.format(now) };
}

function tomorrowInUserTz(): { date: string; day: string } {
  const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000);
  const dateFmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: USER_TIMEZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const dayFmt = new Intl.DateTimeFormat("en-US", {
    timeZone: USER_TIMEZONE,
    weekday: "long",
  });
  return { date: dateFmt.format(tomorrow), day: dayFmt.format(tomorrow) };
}

function yesterdayInUserTz(): { date: string; day: string } {
  const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const dateFmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: USER_TIMEZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const dayFmt = new Intl.DateTimeFormat("en-US", {
    timeZone: USER_TIMEZONE,
    weekday: "long",
  });
  return { date: dateFmt.format(yesterday), day: dayFmt.format(yesterday) };
}

// Parse a "YYYY-MM-DD" date string as UTC midnight for calendar-day diff.
function dateStrToUTCMidnight(dateStr: string): number {
  return new Date(dateStr + "T00:00:00Z").getTime();
}

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

interface StravaActivityLapRow extends StravaActivityLap {
  activity_id: string;
}

interface StravaActivity {
  id: string;
  distance?: number | null;       // metres
  elapsed_time?: number | null;   // seconds
  average_heartrate?: number | null;
  average_watts?: number | null;
}

// A completed session enriched with its week start_date (for sorting) and
// an optional Strava activity summary.
interface CompletedSessionWithWeek {
  session: PlanSession;
  weekStartDate: string; // "YYYY-MM-DD"
  activity?: StravaActivity | null;
}

// Local OpenAI message type — avoids dragging in the full SDK just for a type annotation.
type OpenAiMessage = { role: "system" | "user" | "assistant"; content: string };

// ParsedUsage — extracted from the final OpenAI usage chunk (stream_options.include_usage: true).
// prompt_tokens_details is supported by gpt-4.1 but is not guaranteed in older SDK type exports.
interface ParsedUsage {
  prompt_tokens: number;
  completion_tokens: number;
  cached_tokens: number;
}

function parseUsage(raw: Record<string, unknown>): ParsedUsage {
  const details = raw?.prompt_tokens_details as Record<string, unknown> | undefined;
  return {
    prompt_tokens: (raw?.prompt_tokens as number) ?? 0,
    completion_tokens: (raw?.completion_tokens as number) ?? 0,
    cached_tokens: (details?.cached_tokens as number) ?? 0,
  };
}

// ── Module-scope day-order constants ─────────────────────────────────────────
const WEEKDAYS_MON_FIRST = [
  "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
];
const WEEKDAYS_SUN_FIRST = [
  "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
];
const DAY_ABBR: Record<string, string> = {
  Monday: "Mon", Tuesday: "Tue", Wednesday: "Wed", Thursday: "Thu",
  Friday: "Fri", Saturday: "Sat", Sunday: "Sun",
};

// ── Context formatters ────────────────────────────────────────────────────────

/**
 * Athlete profile: race objective, race date, experience, VMA, FTP, CSS, max HR.
 * The fixture shape from scripts/test-coach-chat.mjs is:
 *   "Race objective: Ironman 70.3 on 2026-05-31 (29 days away)
 *    Experience: 2 years
 *    VMA: 18 km/h | FTP: 275W | CSS: 1:55/100m | Max HR: 192 bpm"
 */
function formatAthleteProfile(profile: UserProfile | null, todayStr: string): string {
  if (!profile) return "No profile available.";

  const lines: string[] = [];

  // Race objective + date
  if (profile.race_objective) {
    if (profile.race_date) {
      // Use calendar-day diff in user timezone to avoid off-by-one after ~22:00 CET
      const daysAway = Math.round(
        (dateStrToUTCMidnight(profile.race_date) - dateStrToUTCMidnight(todayStr)) /
          86_400_000
      );
      lines.push(
        `Race objective: ${profile.race_objective} on ${profile.race_date} (${daysAway} days away)`
      );
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
 * Yesterday's session(s) — identical shape to formatTodaySession but includes the
 * actual activity summary and lap data when matched.
 * Format: "Friday: BIKE Easy 50min Z1 recovery (done) — actual: 38km in 1h01, avg HR 143 (no power meter)"
 * If no session was scheduled, returns a REST DAY / no-data message so the model
 * never needs to infer what yesterday was.
 */
function formatYesterdaySession(
  sessions: PlanSession[],
  yesterdayName: string,
  yesterdayStr: string,
  activitiesMap: Map<string, StravaActivity>,
  lapsMap: Map<string, StravaActivityLap[]>,
): string {
  const yesterdaySessions = sessions
    .filter((s) => s.day === yesterdayName)
    .sort((a, b) => a.order_in_day - b.order_in_day);

  if (yesterdaySessions.length === 0) {
    return `${yesterdayName} (yesterday): REST DAY (no scheduled training).`;
  }

  return yesterdaySessions
    .map((s) => {
      // Activity summary line (same logic as formatRecentCompleted)
      let activitySummary = "";
      const powerNote = (() => {
        if (!s.matched_activity_id) return "";
        const laps = lapsMap.get(s.matched_activity_id) ?? [];
        const hasPower = laps.some((l) => l.average_watts != null && l.average_watts > 0);
        return laps.length > 0 && !hasPower ? " (no power meter)" : "";
      })();

      if (s.matched_activity_id) {
        const act = activitiesMap.get(s.matched_activity_id);
        if (act) {
          const distKm = act.distance != null ? Math.round(act.distance / 100) / 10 : null;
          let durationStr = "";
          if (act.elapsed_time != null) {
            const h = Math.floor(act.elapsed_time / 3600);
            const m = Math.floor((act.elapsed_time % 3600) / 60);
            durationStr = h > 0 ? `${h}h${String(m).padStart(2, "0")}` : `${m}min`;
          }
          const hrStr = act.average_heartrate != null
            ? `avg HR ${Math.round(act.average_heartrate)}`
            : null;
          const parts: string[] = [];
          if (distKm != null) parts.push(`${distKm}km`);
          if (durationStr) parts.push(`in ${durationStr}`);
          if (hrStr) parts.push(hrStr);
          if (parts.length > 0) activitySummary = ` — actual: ${parts.join(", ")}${powerNote}`;
        }
      }

      const completedStr = s.matched_activity_id ? " (done)" : " (not completed)";
      const notesStr = s.notes ? ` — "${s.notes}"` : "";
      return `${yesterdayName} (yesterday): ${s.sport.toUpperCase()} ${s.type} ${s.duration_minutes}min${completedStr}${notesStr}${activitySummary}.`;
    })
    .join("\n");
}

/**
 * Week map: day-by-day with completed/upcoming markers.
 * Format matches fixture: "Mon: SWIM Tempo 55min (done) — felt fast but cut short"
 */
function formatWeekMap(sessions: PlanSession[], todayName: string): string {
  if (sessions.length === 0) return "No sessions scheduled this week.";

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

  const todayIdx = WEEKDAYS_MON_FIRST.indexOf(todayName);

  const lines: string[] = [];
  for (const day of WEEKDAYS_MON_FIRST) {
    if (!byDay.has(day)) continue; // skip rest days (only emit days that have sessions)
    const daySessions = byDay.get(day)!;
    const dayIdx = WEEKDAYS_MON_FIRST.indexOf(day);
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
 *       L 0  124/142 23   L 1  130/136 25   ...
 *       Plan said "...notes...". Coach feedback noted: ..."
 *
 * The lap table uses "avg HR / max HR / km/h" columns with watts appended when available.
 * This exact shape was validated during Phase 1; deviating risks regression.
 */
function formatRecentCompleted(
  recentSessions: CompletedSessionWithWeek[],
  lapsMap: Map<string, StravaActivityLap[]>,
  todayStr: string
): string {
  if (recentSessions.length === 0) return "No recent completed sessions.";

  return recentSessions
    .map((item, i) => {
      const s = item.session;
      const isToday = item.weekStartDate !== undefined &&
        (() => {
          // Check if session date matches today: compute session's calendar date
          const dayIdx = WEEKDAYS_MON_FIRST.indexOf(s.day);
          const weekMonIdx = 0; // Monday is index 0 in WEEKDAYS_MON_FIRST
          // week_start is Monday; session date offset = WEEKDAYS_MON_FIRST.indexOf(day)
          const sessionDateMs =
            dateStrToUTCMidnight(item.weekStartDate) + dayIdx * 86_400_000;
          const sessionDateStr = new Date(sessionDateMs).toISOString().slice(0, 10);
          return sessionDateStr === todayStr;
        })();
      const dayAbbr = DAY_ABBR[s.day] ?? s.day;
      const dayLabel = isToday ? `${dayAbbr} (today)` : dayAbbr;

      // Activity summary line (requires strava_activities data)
      let activitySummary = "";
      if (item.activity) {
        const act = item.activity;
        const distKm = act.distance != null ? Math.round(act.distance / 100) / 10 : null;
        let durationStr = "";
        if (act.elapsed_time != null) {
          const h = Math.floor(act.elapsed_time / 3600);
          const m = Math.floor((act.elapsed_time % 3600) / 60);
          durationStr = h > 0 ? `${h}h${String(m).padStart(2, "0")}` : `${m}min`;
        }
        const hrStr = act.average_heartrate != null
          ? `avg HR ${Math.round(act.average_heartrate)}`
          : null;
        const parts: string[] = [];
        if (distKm != null) parts.push(`${distKm}km`);
        if (durationStr) parts.push(`in ${durationStr}`);
        if (hrStr) parts.push(hrStr);
        activitySummary = parts.length > 0 ? ` — actual: ${parts.join(", ")}` : "";
      }

      const laps = s.matched_activity_id ? (lapsMap.get(s.matched_activity_id) ?? []) : [];
      // Don't mutate the shared lapsMap array — sort a copy
      const sortedLaps = [...laps].sort((a, b) => a.lap_index - b.lap_index);

      // Power note — if no laps have watts, note absence explicitly (per fixture)
      const hasPowerData = sortedLaps.some((l) => l.average_watts != null && l.average_watts > 0);
      const powerNote = sortedLaps.length > 0 && !hasPowerData
        ? " (no power meter — watts unavailable)"
        : "";

      const header = `${i + 1}) ${dayLabel}: ${s.sport.toUpperCase()} ${s.type} ${s.duration_minutes}min${activitySummary}${powerNote}.`;

      let lapSection = "";
      if (sortedLaps.length > 0) {
        // Detect if any lap has watts
        const hasWatts = hasPowerData;
        const colHeader = hasWatts
          ? "Lap-by-lap (avg HR / max HR / km/h / W):"
          : "Lap-by-lap (avg HR / max HR / km/h):";

        // Build compact lap rows — 4 per line, matching fixture layout
        // Pad lap index to width 2 so single- and double-digit indexes align
        const lapTokens = sortedLaps.map((l) => {
          const idx = String(l.lap_index).padStart(2, " ");
          const avgHr = l.average_heartrate != null ? Math.round(l.average_heartrate) : "?";
          const maxHr = l.max_heartrate != null ? Math.round(l.max_heartrate) : "?";
          const kmh = l.average_speed != null
            ? Math.round(l.average_speed * 3.6) // m/s → km/h
            : "?";
          const wStr = hasWatts
            ? ` ${l.average_watts != null ? Math.round(l.average_watts) : "?"}`
            : "";
          return `L${idx}  ${avgHr}/${maxHr} ${kmh}${wStr}`;
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

      // Feedback from plan_sessions (AI-generated coaching commentary from session-feedback fn)
      const feedbackLine = s.feedback
        ? `\n   Coach feedback noted: ${s.feedback}`
        : "";

      const notesLine = s.notes
        ? `\n   Plan said: "${s.notes}".`
        : "";

      return `${header}${lapSection}${notesLine}${feedbackLine}`;
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

    // 7. Determine today and tomorrow day names in the user's timezone (Europe/Paris).
    // Using UTC helpers silently misroutes after ~22:00 CET/CEST.
    // plan_weeks.start_date is stored as DATE; we find the active week by matching
    // today's date against [start_date, start_date + 7 days). Day names match
    // plan_sessions.day column values (e.g. "Saturday").
    const { date: todayStr, day: todayName } = todayInUserTz();
    const { day: tomorrowName } = tomorrowInUserTz();
    const { date: yesterdayStr, day: yesterdayName } = yesterdayInUserTz();

    // 8. Parallel fetch all context data
    const [
      historyResult,
      profileResult,
      planResult,
    ] = await Promise.all([
      // a) Last 10 messages DESC (newest first), reversed to chronological below
      db
        .from("chat_messages")
        .select("role, content")
        .eq("user_id", userId)
        .order("created_at", { ascending: false })
        .limit(10),

      // b) User profile (fields consumed by formatAthleteProfile only)
      db
        .from("users")
        .select(
          "race_objective, race_date, experience_years, vma, css_seconds_per100m, ftp, max_hr"
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
        .maybeSingle(),
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

    // Defensive sort: don't rely on PostgREST ordering for correctness
    const allWeeks: PlanWeek[] = (plan?.plan_weeks ?? [])
      .slice()
      .sort((a, b) => a.week_number - b.week_number);

    // Find the week whose date range contains today
    // plan_weeks.start_date is DATE stored as string "YYYY-MM-DD"
    const currentWeek = allWeeks.find((w) => {
      const weekStartMs = dateStrToUTCMidnight(w.start_date);
      const weekEndMs = weekStartMs + 7 * 86_400_000;
      const todayMs = dateStrToUTCMidnight(todayStr);
      return todayMs >= weekStartMs && todayMs < weekEndMs;
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
    const weekMatchedIds = weekSessions
      .map((s) => s.matched_activity_id)
      .filter((id): id is string => id != null);

    const lapsMap = new Map<string, StravaActivityLap[]>();
    if (weekMatchedIds.length > 0) {
      const lapsResult = await db
        .from("strava_activity_laps")
        .select("activity_id, lap_index, average_heartrate, max_heartrate, average_speed, average_watts")
        .in("activity_id", weekMatchedIds)
        .order("lap_index", { ascending: true });

      if (lapsResult.error) {
        console.error("strava_activity_laps fetch warning:", lapsResult.error.message);
      } else {
        for (const lap of ((lapsResult.data ?? []) as StravaActivityLapRow[])) {
          const actId = lap.activity_id;
          if (!lapsMap.has(actId)) lapsMap.set(actId, []);
          lapsMap.get(actId)!.push(lap);
        }
      }
    }

    // 10b. Fetch last 3 completed sessions across the WHOLE plan (not just this week).
    // On Monday morning the user may have 0 completed sessions this week even though
    // Sat+Sun just happened — the cross-plan query fixes that.
    let recentCompletedSessions: CompletedSessionWithWeek[] = [];
    if (plan) {
      const recentCompletedResult = await db
        .from("plan_sessions")
        .select(
          "id, day, sport, type, template_id, duration_minutes, notes, feedback, matched_activity_id, order_in_day, plan_weeks!inner(plan_id, start_date, week_number)"
        )
        .eq("plan_weeks.plan_id", plan.id)
        .not("matched_activity_id", "is", null)
        .order("start_date", { referencedTable: "plan_weeks", ascending: false })
        .limit(20); // fetch more than needed; sort+slice in JS

      if (recentCompletedResult.error) {
        console.error("recent_completed fetch warning:", recentCompletedResult.error.message);
        // Fallback: use this week's completed sessions
        recentCompletedSessions = weekSessions
          .filter((s) => s.matched_activity_id != null)
          .map((s) => ({ session: s, weekStartDate: currentWeek?.start_date ?? "" }));
      } else {
        // Sort by (week.start_date DESC, WEEKDAYS_MON_FIRST.indexOf(day) DESC), slice top 3
        const rawRows = (recentCompletedResult.data ?? []) as (PlanSession & {
          plan_weeks: { plan_id: string; start_date: string; week_number: number };
        })[];

        const sorted = rawRows.slice().sort((a, b) => {
          const aStart = a.plan_weeks.start_date;
          const bStart = b.plan_weeks.start_date;
          if (bStart !== aStart) return bStart.localeCompare(aStart); // DESC
          return (
            WEEKDAYS_MON_FIRST.indexOf(b.day) - WEEKDAYS_MON_FIRST.indexOf(a.day)
          ); // DESC within week
        });

        const top3 = sorted.slice(0, 3);

        // Fetch strava_activities for these matched IDs to get activity summary
        const top3Ids = top3
          .map((r) => r.matched_activity_id)
          .filter((id): id is string => id != null);

        const activitiesMap = new Map<string, StravaActivity>();
        if (top3Ids.length > 0) {
          const activitiesResult = await db
            .from("strava_activities")
            .select("id, distance, elapsed_time, average_heartrate, average_watts")
            .in("id", top3Ids);

          if (activitiesResult.error) {
            console.error("strava_activities fetch warning:", activitiesResult.error.message);
          } else {
            for (const act of ((activitiesResult.data ?? []) as StravaActivity[])) {
              activitiesMap.set(act.id, act);
            }
          }

          // Also ensure lapsMap is populated for all top3 IDs (week laps already loaded above)
          const missingIds = top3Ids.filter((id) => !lapsMap.has(id));
          if (missingIds.length > 0) {
            const extraLapsResult = await db
              .from("strava_activity_laps")
              .select("activity_id, lap_index, average_heartrate, max_heartrate, average_speed, average_watts")
              .in("activity_id", missingIds)
              .order("lap_index", { ascending: true });

            if (!extraLapsResult.error) {
              for (const lap of ((extraLapsResult.data ?? []) as StravaActivityLapRow[])) {
                const actId = lap.activity_id;
                if (!lapsMap.has(actId)) lapsMap.set(actId, []);
                lapsMap.get(actId)!.push(lap);
              }
            }
          }
        }

        recentCompletedSessions = top3.map((r) => ({
          session: r as unknown as PlanSession,
          weekStartDate: r.plan_weeks.start_date,
          activity: r.matched_activity_id ? (activitiesMap.get(r.matched_activity_id) ?? null) : null,
        }));
      }
    }

    // 10c. Resolve yesterday's sessions. Yesterday may fall in currentWeek (Mon–Sat today)
    // or in the previous week (today is Sunday or Monday and yesterday was the last day of
    // the prior week). We search allWeeks for the week that contains yesterdayStr.
    const yesterdayWeek = allWeeks.find((w) => {
      const weekStartMs = dateStrToUTCMidnight(w.start_date);
      const weekEndMs = weekStartMs + 7 * 86_400_000;
      const yMs = dateStrToUTCMidnight(yesterdayStr);
      return yMs >= weekStartMs && yMs < weekEndMs;
    }) ?? null;

    let yesterdaySessions: PlanSession[] = [];
    const yesterdayActivitiesMap = new Map<string, StravaActivity>();

    if (yesterdayWeek) {
      // If yesterday is in the same week as today, reuse weekSessions (already fetched).
      // Otherwise fetch the previous week's sessions.
      const sourceSessionsForYesterday: PlanSession[] = yesterdayWeek.id === currentWeek?.id
        ? weekSessions
        : await (async () => {
            const res = await db
              .from("plan_sessions")
              .select("id, day, sport, type, template_id, duration_minutes, notes, feedback, matched_activity_id, order_in_day")
              .eq("week_id", yesterdayWeek.id)
              .order("order_in_day", { ascending: true });
            if (res.error) {
              console.error("yesterday plan_sessions fetch warning:", res.error.message);
              return [] as PlanSession[];
            }
            return (res.data ?? []) as PlanSession[];
          })();

      yesterdaySessions = sourceSessionsForYesterday.filter((s) => s.day === yesterdayName);

      // Fetch activities + laps for yesterday's matched sessions (if not already in lapsMap)
      const yMatchedIds = yesterdaySessions
        .map((s) => s.matched_activity_id)
        .filter((id): id is string => id != null);

      if (yMatchedIds.length > 0) {
        const yActivitiesRes = await db
          .from("strava_activities")
          .select("id, distance, elapsed_time, average_heartrate, average_watts")
          .in("id", yMatchedIds);

        if (!yActivitiesRes.error) {
          for (const act of ((yActivitiesRes.data ?? []) as StravaActivity[])) {
            yesterdayActivitiesMap.set(act.id, act);
          }
        }

        const yLapsMissing = yMatchedIds.filter((id) => !lapsMap.has(id));
        if (yLapsMissing.length > 0) {
          const yLapsRes = await db
            .from("strava_activity_laps")
            .select("activity_id, lap_index, average_heartrate, max_heartrate, average_speed, average_watts")
            .in("activity_id", yLapsMissing)
            .order("lap_index", { ascending: true });
          if (!yLapsRes.error) {
            for (const lap of ((yLapsRes.data ?? []) as StravaActivityLapRow[])) {
              if (!lapsMap.has(lap.activity_id)) lapsMap.set(lap.activity_id, []);
              lapsMap.get(lap.activity_id)!.push(lap);
            }
          }
        }
      }
    }

    // 11. Build context strings
    const userProfile = profileResult.data as UserProfile | null;

    const athleteProfileStr = formatAthleteProfile(userProfile, todayStr);
    const planSummaryStr = formatPlanSummary(
      plan as TrainingPlan | null,
      allWeeks,
      currentWeek
    );
    const todaySessionStr = formatTodaySession(weekSessions, todayName);
    const yesterdaySessionStr = formatYesterdaySession(
      yesterdaySessions,
      yesterdayName,
      yesterdayStr,
      yesterdayActivitiesMap,
      lapsMap,
    );
    const weekMapStr = formatWeekMap(weekSessions, todayName);
    const recentCompletedStr = formatRecentCompleted(recentCompletedSessions, lapsMap, todayStr);
    const tomorrowSessionStr = formatTomorrowSession(weekSessions, tomorrowName);

    // 12. Render the DYNAMIC user message by substituting all placeholders
    const dynamicContent = DYNAMIC_TEMPLATE
      .replace("{{athlete_profile}}", athleteProfileStr)
      .replace("{{plan_summary}}", planSummaryStr)
      .replace("{{today_session}}", todaySessionStr)
      .replace("{{yesterday_session}}", yesterdaySessionStr)
      .replace("{{week_map}}", weekMapStr)
      .replace("{{recent_completed}}", recentCompletedStr)
      .replace("{{tomorrow_session}}", tomorrowSessionStr)
      .trim();

    // 13. Reverse history to chronological order (oldest first for context window)
    const historyMessages: ChatMessage[] = (
      (historyResult.data as ChatMessage[] | null) ?? []
    ).reverse();

    // Insert user message BEFORE the OpenAI call so we never lose user input on AI failure.
    // On retry, the prior history will include this orphan; the next user message will follow it.
    // V1 may add an "(error placeholder)" assistant row to keep the conversational frame clean.
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
    const openAiMessages: OpenAiMessage[] = [
      { role: "system", content: STATIC_SYSTEM },
      { role: "user", content: dynamicContent },
      ...historyMessages.map((m) => ({
        role: m.role as "user" | "assistant",
        content: m.content,
      })),
      { role: "user", content: message },
    ];

    // 16. Open SSE stream to OpenAI — model + temperature + max_tokens validated in Phase 1.
    // We use raw fetch instead of the OpenAI SDK so we can pipe the response body directly
    // through a TransformStream to the iOS client without buffering the full response.
    // stream_options.include_usage: true adds a final chunk with token counts (gpt-4.1+).
    const upstream = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${openaiApiKey}`,
      },
      body: JSON.stringify({
        model: "gpt-4.1",
        temperature: 0.3,
        max_tokens: 400,
        stream: true,
        stream_options: { include_usage: true },
        messages: openAiMessages,
      }),
    });

    // If OpenAI returned a non-200, bail before entering streaming mode.
    // The upstream body may contain an error JSON — log it for observability.
    if (upstream.status !== 200 || !upstream.body) {
      let upstreamError = "(no body)";
      try {
        upstreamError = await upstream.text();
      } catch (_) { /* ignore read errors */ }
      console.error("OpenAI upstream error:", upstream.status, upstreamError);
      return jsonResponse({ error: "OpenAI upstream error. Please try again." }, 502);
    }

    // 17. Build a TransformStream that:
    //   a) Forwards every upstream byte verbatim to the iOS client (the OpenAI SSE wire
    //      format is exactly what the client parses — no re-encoding needed).
    //   b) In parallel, accumulates delta.content server-side by parsing each SSE line.
    //   c) On the [DONE] sentinel: persists the full assistant message to chat_messages
    //      and emits the token-usage log line.
    //   d) On a per-chunk parse error: tolerated — the bytes were already forwarded to the
    //      client (which only consumes the bytes from upstream, not our parser), so the
    //      user-visible response is unaffected. We log and skip accumulation for that chunk.
    //   e) On an upstream connection abort mid-stream: pipeThrough rejects naturally, the
    //      stream closes for the client, flush() does NOT run, and no partial assistant
    //      message is persisted (spec requirement: no half-rows in DB).
    //
    // Implementation note: we split on "\n" (not "\n\n") because the decoder may batch
    // multiple lines per chunk. We track a lineBuffer for incomplete lines across chunks.
    const decoder = new TextDecoder();
    let lineBuffer = "";
    let accumulated = "";
    let lastUsage: ParsedUsage | null = null;

    const transform = new TransformStream<Uint8Array, Uint8Array>({
      transform(chunk, controller) {
        // a) Forward bytes verbatim — client receives the raw OpenAI SSE stream.
        controller.enqueue(chunk);

        // b) Parse for server-side bookkeeping (accumulation + usage extraction).
        lineBuffer += decoder.decode(chunk, { stream: true });
        const lines = lineBuffer.split("\n");
        // Keep the last (potentially incomplete) segment in the buffer.
        lineBuffer = lines.pop() ?? "";

        for (const line of lines) {
          if (!line.startsWith("data: ")) continue;
          const payload = line.slice(6).trim();
          // The [DONE] sentinel marks the end of the stream; content already forwarded.
          if (payload === "[DONE]") continue;

          try {
            const json = JSON.parse(payload) as Record<string, unknown>;

            // Accumulate delta content from each choice chunk.
            const choices = json?.choices as Array<Record<string, unknown>> | undefined;
            const delta = choices?.[0]?.delta as Record<string, unknown> | undefined;
            if (typeof delta?.content === "string") {
              accumulated += delta.content;
            }

            // Capture the final usage chunk (present when choices is empty/absent and
            // stream_options.include_usage: true was set).
            if (json?.usage) {
              lastUsage = parseUsage(json.usage as Record<string, unknown>);
            }
          } catch (_) {
            // Tolerate occasional parse failures on malformed chunks — the bytes were
            // already forwarded, so the client is unaffected. Log for debugging only.
            console.error("SSE chunk parse error — skipping:", line.slice(0, 120));
          }
        }
      },

      async flush(_controller) {
        // flush() runs after upstream closes cleanly (after [DONE]). On a mid-stream
        // upstream abort the stream rejects and flush() does NOT run — that's the
        // intended path for "no half-rows in DB."

        if (accumulated.length > 0) {
          // Persist the complete assistant message — V0: no status classification.
          const { error: assistantInsertError } = await db.from("chat_messages").insert({
            user_id: userId,
            role: "assistant",
            content: accumulated,
            status: null,
            constraint_summary: null,
          });
          if (assistantInsertError) {
            // The client has already received [DONE] and closed its read loop, so emitting
            // an SSE error event here is futile — log only. The message is shown to the
            // user via streaming but won't appear on next history fetch. Acceptable for V0.
            console.error("chat_messages assistant insert error:", assistantInsertError.message);
          }
        }

        // Log token usage for observability — structured for easy grep / dashboarding.
        // Same event shape as Phase A's blocking call (no regression on the log format).
        if (lastUsage) {
          console.log(JSON.stringify({
            event: "chat-adjust-tokens",
            user_id: userId,
            prompt_tokens: lastUsage.prompt_tokens,
            completion_tokens: lastUsage.completion_tokens,
            cached_tokens: lastUsage.cached_tokens,
          }));
        }
      },
    });

    // Pipe upstream body through our transform and return the transformed stream to the client.
    // The iOS client receives raw OpenAI SSE events (data: {...}\n\n) plus our error events.
    const transformedStream = upstream.body.pipeThrough(transform);

    // 18. Return the SSE response — headers match the SSE spec and iOS URLSession expectations.
    return new Response(transformedStream, {
      headers: {
        "Content-Type": "text/event-stream; charset=utf-8",
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
        ...corsHeaders,
      },
    });
  } catch (err) {
    console.error(
      "Unhandled error in chat-adjust:",
      err instanceof Error ? err.message : String(err)
    );
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
