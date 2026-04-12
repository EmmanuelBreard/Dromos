import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// CORS headers — allow all origins (mobile app uses JWT auth, not cookies)
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "DELETE, OPTIONS",
};

// Helper: JSON response with CORS headers
function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

// ─── Main handler ─────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // Only DELETE is supported
  if (req.method !== "DELETE") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  // ── Validate environment variables ────────────────────────────────────────
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

  if (!supabaseUrl || !supabaseServiceRoleKey || !supabaseAnonKey) {
    return jsonResponse({ error: "Missing Supabase environment variables" }, 500);
  }

  // ── Validate JWT via auth.getUser() (cryptographic verification) ──────────
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing Authorization header" }, 401);
  }
  const jwt = authHeader.replace("Bearer ", "");

  // Use an anon-key client just for auth validation — service role client
  // is created below for the admin delete call.
  const authClient = createClient(supabaseUrl, supabaseAnonKey);
  const { data: { user }, error: authError } = await authClient.auth.getUser(jwt);
  if (authError || !user) {
    return jsonResponse({ error: "Invalid token" }, 401);
  }
  const userId = user.id;

  // Service-role client for admin operations (bypasses RLS)
  const db = createClient(supabaseUrl, supabaseServiceRoleKey);

  try {
    // ── DELETE — Delete the authenticated user's account ───────────────────
    const { error: deleteError } = await db.auth.admin.deleteUser(userId);

    if (deleteError) {
      console.error("auth.admin.deleteUser error:", deleteError.message);
      return jsonResponse({ error: "Failed to delete account" }, 500);
    }

    return jsonResponse({});
  } catch (err) {
    console.error("Unhandled error in delete-account:", err);
    return jsonResponse({ error: "Failed to delete account" }, 500);
  }
});
