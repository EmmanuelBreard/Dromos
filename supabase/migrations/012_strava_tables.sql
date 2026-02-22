-- Migration: Strava integration tables
-- Description: Adds strava_athlete_id to users, and creates strava_connections and
--              strava_activities tables. strava_connections is service_role-only (tokens
--              never exposed to the client). strava_activities has SELECT-own RLS.
-- Date: 2026-02-22
-- Related: DRO-139, DRO-140

-- ============================================================================
-- UP MIGRATION
-- ============================================================================

-- Add strava_athlete_id to users for quick athlete lookup without joining strava_connections
ALTER TABLE public.users
    ADD COLUMN strava_athlete_id BIGINT;

COMMENT ON COLUMN public.users.strava_athlete_id IS 'Strava athlete ID, set on OAuth connect and cleared on disconnect. Mirrors strava_connections.strava_athlete_id for fast lookup.';

-- Create strava_connections table
-- Stores OAuth tokens for each connected Strava user.
-- NO client-facing RLS policies — only service_role can read/write (tokens must never be exposed to the client).
CREATE TABLE public.strava_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
    strava_athlete_id BIGINT NOT NULL,
    access_token TEXT NOT NULL,
    refresh_token TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    scope TEXT NOT NULL,
    last_sync_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.strava_connections IS 'Strava OAuth tokens per user. Service_role access only — tokens must never be exposed to the client.';
COMMENT ON COLUMN public.strava_connections.strava_athlete_id IS 'Strava athlete ID returned at OAuth time';
COMMENT ON COLUMN public.strava_connections.access_token IS 'Short-lived Strava access token (refreshed automatically by Edge Function)';
COMMENT ON COLUMN public.strava_connections.refresh_token IS 'Long-lived Strava refresh token';
COMMENT ON COLUMN public.strava_connections.expires_at IS 'UTC expiry time of the current access_token';
COMMENT ON COLUMN public.strava_connections.scope IS 'OAuth scopes granted by the athlete (e.g. activity:read_all)';
COMMENT ON COLUMN public.strava_connections.last_sync_at IS 'Timestamp of the last successful activity sync from Strava';

-- Enable RLS on strava_connections with NO client-facing policies
-- Only service_role bypasses RLS and can read/write this table
ALTER TABLE public.strava_connections ENABLE ROW LEVEL SECURITY;

-- Auto-update updated_at on strava_connections
CREATE TRIGGER update_strava_connections_updated_at
    BEFORE UPDATE ON public.strava_connections
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at();

-- Create strava_activities table
-- Stores imported Strava activities. SELECT-own RLS allows the iOS client to read
-- its own activities directly. Writes are service_role-only (via Edge Function sync).
CREATE TABLE public.strava_activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    strava_activity_id BIGINT NOT NULL,
    sport_type TEXT NOT NULL,
    normalized_sport TEXT,
    name TEXT,
    start_date TIMESTAMPTZ NOT NULL,
    start_date_local TIMESTAMPTZ NOT NULL,
    elapsed_time INT NOT NULL,
    moving_time INT NOT NULL,
    distance DECIMAL(10,2),
    total_elevation_gain DECIMAL(8,2),
    average_speed DECIMAL(6,3),
    average_heartrate DECIMAL(5,1),
    average_watts DECIMAL(6,1),
    is_manual BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, strava_activity_id)
);

COMMENT ON TABLE public.strava_activities IS 'Strava activities imported per user. Written by service_role via Edge Function sync; readable by the owning user via RLS.';
COMMENT ON COLUMN public.strava_activities.strava_activity_id IS 'Strava-assigned activity ID (unique per athlete on Strava)';
COMMENT ON COLUMN public.strava_activities.sport_type IS 'Raw sport type string from Strava API (e.g. Ride, Run, Swim)';
COMMENT ON COLUMN public.strava_activities.normalized_sport IS 'Dromos-normalised sport category (bike, run, swim, other)';
COMMENT ON COLUMN public.strava_activities.elapsed_time IS 'Total elapsed time in seconds (includes stopped time)';
COMMENT ON COLUMN public.strava_activities.moving_time IS 'Moving time in seconds (excludes stopped time)';
COMMENT ON COLUMN public.strava_activities.distance IS 'Distance in metres';
COMMENT ON COLUMN public.strava_activities.average_speed IS 'Average speed in metres per second';
COMMENT ON COLUMN public.strava_activities.average_heartrate IS 'Average heart rate in bpm';
COMMENT ON COLUMN public.strava_activities.average_watts IS 'Average power output in watts (cycling only)';
COMMENT ON COLUMN public.strava_activities.is_manual IS 'True if the activity was manually entered on Strava (no GPS data)';

-- Enable RLS on strava_activities
ALTER TABLE public.strava_activities ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can SELECT their own activities
CREATE POLICY "select_own"
    ON public.strava_activities
    FOR SELECT
    USING (auth.uid() = user_id);

-- Index for the primary query pattern: fetch a user's activities ordered by date
CREATE INDEX idx_strava_activities_user_date ON public.strava_activities(user_id, start_date DESC);

-- ============================================================================
-- DOWN MIGRATION (run manually if rollback needed)
-- ============================================================================
-- DROP INDEX IF EXISTS idx_strava_activities_user_date;
-- DROP POLICY IF EXISTS "select_own" ON public.strava_activities;
-- DROP TABLE IF EXISTS public.strava_activities;
-- DROP TRIGGER IF EXISTS update_strava_connections_updated_at ON public.strava_connections;
-- DROP TABLE IF EXISTS public.strava_connections;
-- ALTER TABLE public.users DROP COLUMN IF EXISTS strava_athlete_id;
