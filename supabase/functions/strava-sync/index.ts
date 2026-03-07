import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const STRAVA_TOKEN_URL = "https://www.strava.com/oauth/token";
const STRAVA_ACTIVITIES_URL = "https://www.strava.com/api/v3/athlete/activities";

/** Activities per page — Strava max is 200 */
const PER_PAGE = 200;

/** Safety cap: max pages to fetch (200 * 10 = 2000 activities) */
const MAX_PAGES = 10;

/** Buffer window: fetch activities from `last_sync_at - 24 hours` to catch late uploads */
const SYNC_BUFFER_SECONDS = 24 * 60 * 60; // 24 hours

/** First-sync lookback window */
const FIRST_SYNC_LOOKBACK_DAYS = 90;

/** Token refresh if expiry is within 5 minutes */
const TOKEN_REFRESH_BUFFER_SECONDS = 5 * 60;

// ---------------------------------------------------------------------------
// Sport type normalization
// ---------------------------------------------------------------------------

type NormalizedSport = "run" | "bike" | "swim" | null;

function normalizeSportType(stravaType: string): NormalizedSport {
  const run = ["Run", "TrailRun", "VirtualRun"];
  const bike = ["Ride", "GravelRide", "MountainBikeRide", "VirtualRide"];
  const swim = ["Swim"];

  if (run.includes(stravaType)) return "run";
  if (bike.includes(stravaType)) return "bike";
  if (swim.includes(stravaType)) return "swim";
  return null;
}

// ---------------------------------------------------------------------------
// CORS headers (shared across all responses)
// ---------------------------------------------------------------------------

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------------------
// Strava API helpers
// ---------------------------------------------------------------------------

interface StravaTokenResponse {
  access_token: string;
  refresh_token: string;
  expires_at: number; // Unix epoch seconds
}

interface StravaLap {
  elapsed_time: number;
  moving_time: number;
  distance: number;
  average_speed: number;
  average_cadence?: number;
  average_watts?: number;
  average_heartrate?: number;
  max_heartrate?: number;
  start_index: number;
  end_index: number;
}

interface StravaStreamEntry {
  type: string;
  data: number[];
  series_type: string;
  original_size: number;
  resolution: string;
}

/** Stream keys to request from Strava activity streams endpoint */
const STRAVA_STREAM_KEYS = "time,heartrate,watts,cadence,velocity_smooth,distance";

interface StravaApiActivity {
  id: number;
  sport_type?: string;
  name?: string;
  start_date?: string;
  start_date_local?: string;
  elapsed_time?: number;
  moving_time?: number;
  distance?: number;
  total_elevation_gain?: number;
  average_speed?: number;
  average_heartrate?: number;
  average_watts?: number;
  manual?: boolean;
  map?: { summary_polyline?: string };
}

/**
 * Refresh a Strava access token using the stored refresh token.
 * Returns the new token data on success, throws on failure.
 */
async function refreshStravaToken(
  refreshToken: string,
  clientId: string,
  clientSecret: string
): Promise<StravaTokenResponse> {
  const res = await fetch(STRAVA_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    }),
  });

  if (!res.ok) {
    const errorBody = await res.text();
    throw new Error(
      `Strava token refresh failed (${res.status}): ${errorBody}`
    );
  }

  return res.json() as Promise<StravaTokenResponse>;
}

// ---------------------------------------------------------------------------
// Laps & Streams fetcher
// ---------------------------------------------------------------------------

/**
 * Fetch laps and streams for each upserted activity, then persist them.
 * Runs sequentially to respect Strava rate limits. Any failure here is
 * non-fatal — errors are logged but never propagated to the caller.
 */
async function fetchLapsAndStreams(
  accessToken: string,
  activityInfos: Array<{ dbId: string; stravaActivityId: number; isManual: boolean }>,
  db: ReturnType<typeof createClient>
): Promise<number> {
  // Manual activities have no GPS/sensor data — skip them
  const nonManual = activityInfos.filter((a) => !a.isManual);
  let lapsFetchedCount = 0;

  for (const { dbId, stravaActivityId } of nonManual) {
    // --- Fetch laps ---
    const lapsRes = await fetch(
      `https://www.strava.com/api/v3/activities/${stravaActivityId}/laps`,
      { headers: { Authorization: `Bearer ${accessToken}` } }
    );

    if (lapsRes.status === 429) {
      console.warn(`Rate limited fetching laps for activity ${stravaActivityId} — stopping`);
      break;
    }

    if (!lapsRes.ok) {
      console.error(`Failed to fetch laps for activity ${stravaActivityId}: ${lapsRes.status}`);
      continue;
    }

    // --- Fetch streams ---
    const streamsRes = await fetch(
      `https://www.strava.com/api/v3/activities/${stravaActivityId}/streams?keys=${STRAVA_STREAM_KEYS}&key_by_type=true`,
      { headers: { Authorization: `Bearer ${accessToken}` } }
    );

    if (streamsRes.status === 429) {
      console.warn(`Rate limited fetching streams for activity ${stravaActivityId} — stopping`);
      break;
    }

    if (!streamsRes.ok) {
      console.error(`Failed to fetch streams for activity ${stravaActivityId}: ${streamsRes.status}`);
      continue;
    }

    // --- Persist laps (only when >1 lap, i.e. actual splits) ---
    const laps: StravaLap[] = await lapsRes.json();
    if (laps.length > 1) {
      const lapRows = laps.map((lap, index) => ({
        activity_id: dbId,
        lap_index: index,
        elapsed_time: lap.elapsed_time,
        moving_time: lap.moving_time,
        distance: lap.distance,
        average_speed: lap.average_speed,
        average_cadence: lap.average_cadence ?? null,
        average_watts: lap.average_watts ?? null,
        average_heartrate: lap.average_heartrate ?? null,
        max_heartrate: lap.max_heartrate ?? null,
        start_index: lap.start_index,
        end_index: lap.end_index,
      }));

      const { error: lapsError } = await db
        .from("strava_activity_laps")
        .upsert(lapRows, { onConflict: "activity_id,lap_index" });

      if (lapsError) {
        console.error(`Failed to upsert laps for activity ${stravaActivityId}: ${lapsError.message}`);
      } else {
        lapsFetchedCount++;
      }
    }

    // --- Persist streams data on the activity row ---
    const streamsJson = await streamsRes.json();
    const { error: streamsError } = await db
      .from("strava_activities")
      .update({ streams_data: streamsJson })
      .eq("id", dbId);

    if (streamsError) {
      console.error(`Failed to update streams for activity ${stravaActivityId}: ${streamsError.message}`);
    }
  }

  return lapsFetchedCount;
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  // Only POST is supported
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  // ---------------------------------------------------------------------------
  // 1. Extract user_id from JWT Authorization header
  // ---------------------------------------------------------------------------

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing Authorization header" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const stravaClientId = Deno.env.get("STRAVA_CLIENT_ID");
  const stravaClientSecret = Deno.env.get("STRAVA_CLIENT_SECRET");

  if (!supabaseUrl || !supabaseServiceRoleKey) {
    return jsonResponse({ error: "Missing Supabase environment variables" }, 500);
  }

  if (!stravaClientId || !stravaClientSecret) {
    return jsonResponse({ error: "Missing Strava environment variables" }, 500);
  }

  // Cryptographically validate the JWT via auth.getUser()
  const jwt = authHeader.replace("Bearer ", "");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? supabaseServiceRoleKey;
  const authClient = createClient(supabaseUrl, supabaseAnonKey);
  const { data: { user }, error: authError } = await authClient.auth.getUser(jwt);
  if (authError || !user) {
    return jsonResponse({ error: "Invalid token" }, 401);
  }
  const userId = user.id;

  // ---------------------------------------------------------------------------
  // 2. Service-role DB client
  // ---------------------------------------------------------------------------

  const db = createClient(supabaseUrl, supabaseServiceRoleKey);

  try {
    // -------------------------------------------------------------------------
    // 3. Fetch strava_connections row
    // -------------------------------------------------------------------------

    const { data: connection, error: connError } = await db
      .from("strava_connections")
      .select(
        "access_token, refresh_token, expires_at, last_sync_at"
      )
      .eq("user_id", userId)
      .single();

    if (connError || !connection) {
      return jsonResponse({ error: "Strava not connected" }, 404);
    }

    // -------------------------------------------------------------------------
    // 4. Token refresh if expired or expiring within 5 minutes
    // -------------------------------------------------------------------------

    let accessToken: string = connection.access_token;
    const nowEpoch = Math.floor(Date.now() / 1000);

    const expiresAtEpoch = Math.floor(new Date(connection.expires_at).getTime() / 1000);
    if (expiresAtEpoch <= nowEpoch + TOKEN_REFRESH_BUFFER_SECONDS) {
      let newTokens: StravaTokenResponse;
      try {
        newTokens = await refreshStravaToken(
          connection.refresh_token,
          stravaClientId,
          stravaClientSecret
        );
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return jsonResponse(
          { error: `Token refresh failed: ${message}` },
          502
        );
      }

      // Persist refreshed tokens
      const { error: updateErr } = await db
        .from("strava_connections")
        .update({
          access_token: newTokens.access_token,
          refresh_token: newTokens.refresh_token,
          expires_at: new Date(newTokens.expires_at * 1000).toISOString(),
        })
        .eq("user_id", userId);

      if (updateErr) {
        return jsonResponse(
          { error: `Failed to persist refreshed token: ${updateErr.message}` },
          500
        );
      }

      accessToken = newTokens.access_token;
    }

    // -------------------------------------------------------------------------
    // 5. Determine `after` timestamp for activity fetch
    // -------------------------------------------------------------------------

    let afterEpoch: number;

    if (connection.last_sync_at) {
      // Use last_sync_at minus 24-hour buffer to catch late uploads
      const lastSyncMs = new Date(connection.last_sync_at).getTime();
      afterEpoch = Math.floor(lastSyncMs / 1000) - SYNC_BUFFER_SECONDS;
    } else {
      // First sync: go back 90 days
      const lookbackMs =
        Date.now() - FIRST_SYNC_LOOKBACK_DAYS * 24 * 60 * 60 * 1000;
      afterEpoch = Math.floor(lookbackMs / 1000);
    }

    // -------------------------------------------------------------------------
    // 6. Paginated activity fetch from Strava
    // -------------------------------------------------------------------------

    const allActivities: StravaApiActivity[] = [];
    let rateLimited = false;

    for (let page = 1; page <= MAX_PAGES; page++) {
      const url = new URL(STRAVA_ACTIVITIES_URL);
      url.searchParams.set("after", String(afterEpoch));
      url.searchParams.set("per_page", String(PER_PAGE));
      url.searchParams.set("page", String(page));

      const res = await fetch(url.toString(), {
        headers: { Authorization: `Bearer ${accessToken}` },
      });

      // Rate limited — stop pagination but do not fail the sync
      if (res.status === 429) {
        rateLimited = true;
        break;
      }

      if (!res.ok) {
        const errorBody = await res.text();
        return jsonResponse(
          {
            error: `Strava API error on page ${page} (${res.status}): ${errorBody}`,
          },
          502
        );
      }

      const activities: StravaApiActivity[] = await res.json();

      // Empty page means we have fetched everything
      if (activities.length === 0) break;

      allActivities.push(...activities);

      // If this page returned fewer than PER_PAGE we're on the last page
      if (activities.length < PER_PAGE) break;
    }

    // -------------------------------------------------------------------------
    // 7. Normalize and batch upsert into strava_activities
    // -------------------------------------------------------------------------

    let lapsFetchedCount = 0;

    if (allActivities.length > 0) {
      // Filter out activities missing required NOT NULL date fields
      const validActivities = allActivities.filter(
        (a) => a.start_date != null && a.start_date_local != null
      );

      const rows = validActivities.map((a) => ({
        user_id: userId,
        strava_activity_id: a.id,
        sport_type: a.sport_type ?? "Unknown",
        normalized_sport: normalizeSportType(a.sport_type ?? ""),
        name: a.name ?? null,
        start_date: a.start_date,
        start_date_local: a.start_date_local,
        elapsed_time: a.elapsed_time ?? 0,
        moving_time: a.moving_time ?? 0,
        distance: a.distance ?? null,
        total_elevation_gain: a.total_elevation_gain ?? null,
        average_speed: a.average_speed ?? null,
        average_heartrate: a.average_heartrate ?? null,
        average_watts: a.average_watts ?? null,
        is_manual: a.manual ?? false,
        summary_polyline: a.map?.summary_polyline || null,
      }));

      const { data: upsertedData, error: upsertError } = await db
        .from("strava_activities")
        .upsert(rows, { onConflict: "user_id,strava_activity_id" })
        .select("id, strava_activity_id");

      if (upsertError) {
        return jsonResponse(
          { error: `Failed to upsert activities: ${upsertError.message}` },
          500
        );
      }

      // -----------------------------------------------------------------------
      // 7b. Fetch laps & streams for upserted activities (non-fatal)
      // -----------------------------------------------------------------------

      if (upsertedData && upsertedData.length > 0) {
        // Build a lookup from strava_activity_id → isManual using original data
        const manualLookup = new Map<number, boolean>();
        for (const a of allActivities) {
          manualLookup.set(a.id, a.manual ?? false);
        }

        const activityInfos = upsertedData.map((row: { id: string; strava_activity_id: number }) => ({
          dbId: row.id,
          stravaActivityId: row.strava_activity_id,
          isManual: manualLookup.get(row.strava_activity_id) ?? false,
        }));

        try {
          lapsFetchedCount = await fetchLapsAndStreams(accessToken, activityInfos, db);
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          console.error("fetchLapsAndStreams failed (non-fatal):", msg);
        }
      }
    }

    // -------------------------------------------------------------------------
    // 8. Update last_sync_at on strava_connections
    // -------------------------------------------------------------------------

    const { error: syncUpdateErr } = await db
      .from("strava_connections")
      .update({ last_sync_at: new Date().toISOString() })
      .eq("user_id", userId);

    if (syncUpdateErr) {
      // Non-fatal: log but don't fail the response
      console.error("Failed to update last_sync_at:", syncUpdateErr.message);
    }

    // -------------------------------------------------------------------------
    // 9. Fetch total activity count for this user
    // -------------------------------------------------------------------------

    const { count: totalActivities, error: countError } = await db
      .from("strava_activities")
      .select("*", { count: "exact", head: true })
      .eq("user_id", userId);

    if (countError) {
      console.error("Failed to count total activities:", countError.message);
    }

    // -------------------------------------------------------------------------
    // 10. Return summary
    // -------------------------------------------------------------------------

    return jsonResponse({
      synced_count: allActivities.length,
      total_activities: totalActivities ?? 0,
      rate_limited: rateLimited,
      laps_fetched_count: lapsFetchedCount,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("strava-sync unhandled error:", message);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
