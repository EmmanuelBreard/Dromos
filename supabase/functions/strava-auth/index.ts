import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// CORS headers — allow all origins (mobile app uses JWT auth, not cookies)
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, DELETE, OPTIONS",
};

// Helper: JSON response with CORS headers
function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

// Strava token exchange response shape
interface StravaTokenExchangeResponse {
  access_token: string;
  refresh_token: string;
  expires_at: number;
  athlete: { id: number };
  message?: string;
}

// ─── Main handler ─────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // Only POST and DELETE are supported
  if (req.method !== "POST" && req.method !== "DELETE") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  // ── Validate environment variables ────────────────────────────────────────
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const stravaClientId = Deno.env.get("STRAVA_CLIENT_ID");
  const stravaClientSecret = Deno.env.get("STRAVA_CLIENT_SECRET");

  if (!supabaseUrl || !supabaseServiceRoleKey) {
    return jsonResponse({ error: "Missing Supabase environment variables" }, 500);
  }

  // POST requires Strava credentials; check here so we fail fast before any
  // network call rather than only when we reach the Strava exchange below.
  if (req.method === "POST" && (!stravaClientId || !stravaClientSecret)) {
    return jsonResponse({ error: "Missing Strava environment variables" }, 500);
  }

  // ── Validate JWT via auth.getUser() (cryptographic verification) ──────────
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing Authorization header" }, 401);
  }
  const jwt = authHeader.replace("Bearer ", "");

  // Use an anon-key client just for auth validation — service role client
  // is created below for DB writes.
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? supabaseServiceRoleKey;
  const authClient = createClient(supabaseUrl, supabaseAnonKey);
  const { data: { user }, error: authError } = await authClient.auth.getUser(jwt);
  if (authError || !user) {
    return jsonResponse({ error: "Invalid token" }, 401);
  }
  const userId = user.id;

  // Service-role client for DB operations (bypasses RLS)
  const db = createClient(supabaseUrl, supabaseServiceRoleKey);

  try {
    // ────────────────────────────────────────────────────────────────────────
    // POST — OAuth token exchange
    // ────────────────────────────────────────────────────────────────────────
    if (req.method === "POST") {
      // Parse request body
      let body: { code?: string };
      try {
        body = await req.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON body" }, 400);
      }

      const { code } = body;
      if (!code) {
        return jsonResponse({ error: "Missing required field: code" }, 400);
      }

      // ── Exchange authorization code with Strava ──────────────────────────
      const stravaParams = new URLSearchParams({
        client_id: stravaClientId!,
        client_secret: stravaClientSecret!,
        code,
        grant_type: "authorization_code",
      });

      const stravaRes = await fetch("https://www.strava.com/oauth/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: stravaParams.toString(),
      });

      const stravaData = await stravaRes.json() as StravaTokenExchangeResponse;

      if (!stravaRes.ok) {
        // Forward Strava's error message so the client can surface it
        const message = stravaData?.message ?? "Strava token exchange failed";
        return jsonResponse({ error: message }, 502);
      }

      const {
        access_token,
        refresh_token,
        expires_at, // Strava returns Unix epoch (seconds)
        athlete,
      } = stravaData;

      if (!access_token || !refresh_token || !expires_at || !athlete?.id) {
        return jsonResponse({ error: "Unexpected response from Strava" }, 502);
      }

      const stravaAthleteId: number = athlete.id;

      // Convert Unix epoch → ISO 8601 string (Postgres timestamptz)
      const expiresAtIso = new Date(expires_at * 1000).toISOString();

      // ── Upsert strava_connections ────────────────────────────────────────
      const { error: upsertError } = await db
        .from("strava_connections")
        .upsert(
          {
            user_id: userId,
            strava_athlete_id: stravaAthleteId,
            access_token,
            refresh_token,
            expires_at: expiresAtIso,
            // The scope we requested in the OAuth URL. Strava does not echo it back
            // in the token exchange response, so we set it to the known requested value.
            scope: "activity:read_all",
          },
          { onConflict: "user_id" }
        );

      if (upsertError) {
        console.error("strava_connections upsert error:", upsertError.message);
        return jsonResponse({ error: "Failed to save Strava connection" }, 500);
      }

      // ── Update users.strava_athlete_id ───────────────────────────────────
      const { error: userUpdateError } = await db
        .from("users")
        .update({ strava_athlete_id: stravaAthleteId })
        .eq("id", userId);

      if (userUpdateError) {
        console.error("users update error:", userUpdateError.message);
        return jsonResponse({ error: "Failed to update user profile" }, 500);
      }

      return jsonResponse({ success: true, strava_athlete_id: stravaAthleteId });
    }

    // ────────────────────────────────────────────────────────────────────────
    // DELETE — Disconnect Strava
    // ────────────────────────────────────────────────────────────────────────
    if (req.method === "DELETE") {
      // Fetch the access_token before deleting the row so we can revoke it
      const { data: connection } = await db
        .from("strava_connections")
        .select("access_token")
        .eq("user_id", userId)
        .single();

      // Best-effort Strava token revocation (do not block disconnect on failure)
      if (connection?.access_token) {
        try {
          const revokeRes = await fetch("https://www.strava.com/oauth/deauthorize", {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: new URLSearchParams({ access_token: connection.access_token }),
          });
          if (!revokeRes.ok) {
            console.error("Strava token revocation failed:", revokeRes.status);
          }
        } catch (revokeErr) {
          console.error("Strava token revocation error:", revokeErr instanceof Error ? revokeErr.message : String(revokeErr));
        }
      }

      // Delete all synced activities for this user
      const { error: activitiesDeleteError } = await db
        .from("strava_activities")
        .delete()
        .eq("user_id", userId);

      if (activitiesDeleteError) {
        console.error("strava_activities delete error:", activitiesDeleteError.message);
        return jsonResponse({ error: "Failed to remove Strava activities" }, 500);
      }

      // Remove the connection row
      const { error: deleteError } = await db
        .from("strava_connections")
        .delete()
        .eq("user_id", userId);

      if (deleteError) {
        console.error("strava_connections delete error:", deleteError.message);
        return jsonResponse({ error: "Failed to remove Strava connection" }, 500);
      }

      // Null out the denormalised athlete id on the user row
      const { error: userUpdateError } = await db
        .from("users")
        .update({ strava_athlete_id: null })
        .eq("id", userId);

      if (userUpdateError) {
        console.error("users strava_athlete_id nullify error:", userUpdateError.message);
        return jsonResponse({ error: "Failed to update user profile" }, 500);
      }

      return jsonResponse({ success: true });
    }

    // Should be unreachable given the method check at the top, but TypeScript
    // needs a return path here.
    return jsonResponse({ error: "Method not allowed" }, 405);
  } catch (err) {
    console.error("Unhandled error in strava-auth:", err);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
