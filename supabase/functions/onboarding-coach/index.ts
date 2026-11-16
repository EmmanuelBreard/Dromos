import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import OpenAI from "npm:openai@4";

import promptTemplate from "./prompts/onboarding-coach-prompt.ts";
import { interpretCoachPayload, isRetryableError, parseModelJson, retryable } from "./lib/parse.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const STEPS = new Set([
  "race_type",
  "race_date",
  "target_time",
  "experience",
  "weekly_hours",
  "run",
  "swim",
  "bike",
  "max_hr",
  "swim_days",
  "bike_days",
  "run_days",
  "daily_duration",
  "limiters",
  "recap",
]);

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

async function callModel(openai: OpenAI, payload: unknown): Promise<string> {
  let lastError: unknown;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const response = await openai.chat.completions.create({
        model: "gpt-4.1",
        temperature: 0.3,
        max_tokens: 400,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: promptTemplate },
          { role: "user", content: JSON.stringify(payload) },
        ],
      });
      const content = response.choices[0]?.message?.content?.trim() ?? "";
      if (!content) throw retryable("The model returned an empty response.");
      parseModelJson(content);
      return content;
    } catch (error) {
      lastError = error;
      if (!isRetryableError(error) || attempt === 1) break;
      await new Promise((resolve) => setTimeout(resolve, 400));
    }
  }
  throw lastError instanceof Error ? lastError : new Error("The coach is unavailable.");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const openaiKey = Deno.env.get("OPENAI_API_KEY");
  if (!supabaseUrl || !serviceKey || !openaiKey) {
    return jsonResponse({ error: "coach_unavailable" }, 503);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonResponse({ error: "Missing Authorization header" }, 401);
  const jwt = authHeader.replace("Bearer ", "");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? serviceKey;
  const authClient = createClient(supabaseUrl, anonKey);
  const { data: { user }, error: authError } = await authClient.auth.getUser(jwt);
  if (authError || !user) return jsonResponse({ error: "Invalid token" }, 401);

  let body: { step?: unknown; mode?: unknown; purpose?: unknown; message?: unknown; answers?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const step = typeof body.step === "string" ? body.step : "";
  const purpose = body.purpose === "react" || body.purpose === "parse" ? body.purpose : "";
  const message = typeof body.message === "string" ? body.message.trim() : "";
  if (!STEPS.has(step) || !purpose || !message || message.length > 1000) {
    return jsonResponse({ error: "Missing or invalid step, purpose, or message" }, 400);
  }

  try {
    const openai = new OpenAI({ apiKey: openaiKey, timeout: 8_000, maxRetries: 0 });
    const content = await callModel(openai, {
      step,
      mode: typeof body.mode === "string" ? body.mode : "ask",
      purpose,
      message,
      answers: body.answers ?? {},
    });
    const turn = interpretCoachPayload(parseModelJson(content), step);
    if (purpose === "react") {
      return jsonResponse({ reply: turn.reply, follow_up: false, parsed: null });
    }
    return jsonResponse(turn);
  } catch (error) {
    console.error("[onboarding-coach]", error instanceof Error ? error.message : "failed");
    return jsonResponse({ error: "coach_unavailable" }, 503);
  }
});
