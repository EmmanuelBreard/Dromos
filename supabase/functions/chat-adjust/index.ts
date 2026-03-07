import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import OpenAI from "npm:openai@4";

// Auto-generated prompt template — run scripts/sync-prompts.sh to regenerate
import promptTemplate from "./prompts/adjust-step1-v0-prompt.ts";

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
  experience_years?: number | null;
  vma?: number | null;
  css_seconds_per100m?: number | null;
  ftp?: number | null;
  current_weekly_hours?: number | null;
  swim_days?: string[] | null;
  bike_days?: string[] | null;
  run_days?: string[] | null;
}

interface PlanWeek {
  week_number: number;
  phase: string;
  is_recovery: boolean;
}

interface ParsedAIResponse {
  response_text: string;
  status: "ready" | "need_info" | "no_action" | "escalate";
  constraint_summary?: Record<string, unknown>;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Format the user profile into a readable string for the prompt template.
 * Omits any null/undefined fields to keep the prompt clean.
 */
function formatAthleteProfile(profile: UserProfile | null): string {
  if (!profile) return "No profile available.";

  const lines: string[] = [];

  if (profile.race_objective) lines.push(`Race objective: ${profile.race_objective}`);
  if (profile.experience_years != null) lines.push(`Experience: ${profile.experience_years} years`);
  if (profile.vma != null) lines.push(`VMA: ${profile.vma} km/h`);
  if (profile.css_seconds_per100m != null) {
    const minutes = Math.floor(profile.css_seconds_per100m / 60);
    const seconds = profile.css_seconds_per100m % 60;
    lines.push(`CSS: ${minutes}:${String(seconds).padStart(2, "0")}/100m`);
  }
  if (profile.ftp != null) lines.push(`FTP: ${profile.ftp} W`);
  if (profile.current_weekly_hours != null) lines.push(`Weekly training hours: ${profile.current_weekly_hours}h`);
  if (profile.swim_days?.length) lines.push(`Swim days: ${profile.swim_days.join(", ")}`);
  if (profile.bike_days?.length) lines.push(`Bike days: ${profile.bike_days.join(", ")}`);
  if (profile.run_days?.length) lines.push(`Run days: ${profile.run_days.join(", ")}`);

  return lines.length > 0 ? lines.join("\n") : "No profile details available.";
}

/**
 * Format the plan weeks into a readable string for the prompt template.
 * Returns "No active training plan." when no weeks are provided.
 */
function formatPhaseMap(weeks: PlanWeek[]): string {
  if (!weeks || weeks.length === 0) return "No active training plan.";

  return weeks
    .map((w) => {
      const phase = w.phase ?? "Unknown";
      const recovery = w.is_recovery ? " (Recovery)" : "";
      return `Week ${w.week_number}: ${phase}${recovery}`;
    })
    .join("\n");
}

/**
 * Safely extract the outermost JSON block from an LLM response string.
 * Strategy: find the first '{', then try progressively extending the substring
 * until JSON.parse succeeds. This avoids brittle regex matching.
 */
function extractJsonBlock(text: string): Record<string, unknown> | null {
  const firstBrace = text.indexOf("{");
  if (firstBrace === -1) return null;

  // Walk backwards from the end to find the last '}'
  const lastBrace = text.lastIndexOf("}");
  if (lastBrace === -1 || lastBrace <= firstBrace) return null;

  // Try the full span first (most common case — model outputs one clean JSON block)
  const candidate = text.slice(firstBrace, lastBrace + 1);
  try {
    const parsed = JSON.parse(candidate);
    if (typeof parsed === "object" && parsed !== null) {
      return parsed as Record<string, unknown>;
    }
  } catch {
    // Fall through to progressive scan
  }

  // Progressive scan: extend substring one '}' at a time
  let searchFrom = firstBrace;
  while (true) {
    const nextBrace = text.indexOf("}", searchFrom + 1);
    if (nextBrace === -1) break;
    try {
      const parsed = JSON.parse(text.slice(firstBrace, nextBrace + 1));
      if (typeof parsed === "object" && parsed !== null) {
        return parsed as Record<string, unknown>;
      }
    } catch {
      // Keep scanning
    }
    searchFrom = nextBrace;
  }

  return null;
}

/**
 * Parse the raw AI response string into a structured ParsedAIResponse.
 * If no valid JSON block is found, treat the entire response as conversational
 * (status: "need_info") — the model is still gathering information.
 */
function parseAIResponse(rawResponse: string): ParsedAIResponse {
  const jsonBlock = extractJsonBlock(rawResponse);

  if (jsonBlock && typeof jsonBlock["status"] === "string") {
    const validStatuses = new Set(["ready", "need_info", "no_action", "escalate"]);
    const status: ParsedAIResponse["status"] = validStatuses.has(jsonBlock["status"] as string)
      ? (jsonBlock["status"] as ParsedAIResponse["status"])
      : "need_info";
    const response_text =
      typeof jsonBlock["response_text"] === "string"
        ? jsonBlock["response_text"]
        : rawResponse.trim();
    const constraint_summary =
      typeof jsonBlock["constraint_summary"] === "object" &&
      jsonBlock["constraint_summary"] !== null
        ? (jsonBlock["constraint_summary"] as Record<string, unknown>)
        : undefined;

    return { response_text, status, constraint_summary };
  }

  // No structured JSON found — model is still in conversation mode
  return {
    response_text: rawResponse.trim(),
    status: "need_info",
  };
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

  // V0: No per-user rate limiting. Acceptable for small user base.
  // TODO(V1): Add rate limit check before OpenAI call.

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
  const userId = user.id;

  // Service-role client for all DB operations (bypasses RLS)
  const db = createClient(supabaseUrl, supabaseServiceRoleKey);

  try {
    // V0: No server-side concurrency guard. Client disables send button during requests.
    // If two requests race, both will get valid responses but may duplicate context.

    // 5. Parse and validate request body
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

    // 6. Fetch context in parallel — history, user profile, phase map
    const [historyResult, profileResult, phaseMapResult] = await Promise.all([
      // a) Last 50 messages, DESC so we get newest, then reverse for chronological order
      db
        .from("chat_messages")
        .select("role, content")
        .eq("user_id", userId)
        .order("created_at", { ascending: false })
        .limit(50),

      // b) User profile
      db
        .from("users")
        .select(
          "race_objective, experience_years, vma, css_seconds_per100m, ftp, current_weekly_hours, swim_days, bike_days, run_days"
        )
        .eq("id", userId)
        .single(),

      // c) Active training plan weeks
      db
        .from("training_plans")
        .select("plan_weeks(week_number, phase, is_recovery)")
        .eq("user_id", userId)
        .eq("status", "active")
        .order("week_number", { referencedTable: "plan_weeks", ascending: true })
        .single(),
    ]);

    // Check for critical errors — losing history context is unacceptable
    if (historyResult.error) {
      console.error("chat_messages history fetch error:", historyResult.error.message);
      return jsonResponse({ error: "Failed to load chat history" }, 500);
    }

    // Non-critical: log but continue with graceful fallbacks
    if (profileResult.error) {
      console.error("user profile fetch warning:", profileResult.error.message);
    }
    if (phaseMapResult.error) {
      console.error("phase map fetch warning:", phaseMapResult.error.message);
    }

    // Reverse history to get chronological order (oldest first for context window)
    const historyMessages: ChatMessage[] = (
      (historyResult.data as ChatMessage[] | null) ?? []
    ).reverse();

    const userProfile = profileResult.data as UserProfile | null;

    // Flatten plan_weeks from the join result
    const planWeeksRaw = phaseMapResult.data?.plan_weeks;
    const planWeeks: PlanWeek[] = Array.isArray(planWeeksRaw)
      ? (planWeeksRaw as PlanWeek[])
      : [];

    // 7. Insert user message BEFORE OpenAI call — ensures message is persisted
    // and in history for any subsequent requests, even if AI call fails.
    const { error: userInsertError } = await db.from("chat_messages").insert({
      user_id: userId,
      role: "user",
      content: message,
    });
    if (userInsertError) {
      console.error("chat_messages user insert error:", userInsertError.message);
      return jsonResponse({ error: "Failed to save user message" }, 500);
    }

    // 8. Build rendered prompt — replace template placeholders
    const renderedPrompt = promptTemplate
      .replace("{{athlete_profile}}", formatAthleteProfile(userProfile))
      .replace("{{phase_map}}", formatPhaseMap(planWeeks));

    // 9. Build OpenAI messages array
    const openAiMessages: OpenAI.Chat.ChatCompletionMessageParam[] = [
      { role: "system", content: renderedPrompt },
      ...historyMessages.map((m) => ({
        role: m.role as "user" | "assistant",
        content: m.content,
      })),
      { role: "user", content: message },
    ];

    // 10. Call OpenAI — gpt-4o, temperature 0 for deterministic classification
    const openai = new OpenAI({ apiKey: openaiApiKey });
    const completion = await openai.chat.completions.create({
      model: "gpt-4.1",
      temperature: 0,
      max_tokens: 1024,
      messages: openAiMessages,
    });

    const rawResponse = completion.choices[0]?.message?.content ?? "";

    if (!rawResponse) {
      console.error("OpenAI returned empty response for user:", userId);
      return jsonResponse({ error: "AI returned an empty response. Please try again." }, 502);
    }

    // 11. Parse structured response (JSON block) or treat as conversational
    const { response_text, status, constraint_summary } = parseAIResponse(rawResponse);

    // 12. Insert assistant message with parsed metadata
    const { error: assistantInsertError } = await db.from("chat_messages").insert({
      user_id: userId,
      role: "assistant",
      content: response_text,
      status,
      ...(constraint_summary ? { constraint_summary } : {}),
    });
    if (assistantInsertError) {
      console.error("chat_messages assistant insert error:", assistantInsertError.message);
      return jsonResponse({ error: "Failed to save assistant message" }, 500);
    }

    // 13. Return structured response to iOS client
    return jsonResponse({
      response_text,
      status,
      ...(constraint_summary ? { constraint_summary } : {}),
    });
  } catch (err) {
    console.error(
      "Unhandled error in chat-adjust:",
      err instanceof Error ? err.message : String(err)
    );
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
