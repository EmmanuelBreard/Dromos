-- Migration: Strava activity laps and streams
-- Description: Creates strava_activity_laps table for per-lap data and adds
--              streams_data JSONB column to strava_activities for raw stream arrays.
-- Date: 2026-03-07
-- Related: DRO-164, DRO-165

-- ============================================================================
-- UP MIGRATION
-- ============================================================================

-- Create strava_activity_laps table
-- Stores per-lap breakdown of Strava activities. Each lap maps to an activity
-- via activity_id FK. Writes are service_role-only (via Edge Function sync);
-- readable by the owning user via RLS join on strava_activities.
CREATE TABLE public.strava_activity_laps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activity_id UUID NOT NULL REFERENCES public.strava_activities(id) ON DELETE CASCADE,
    lap_index INT NOT NULL,
    elapsed_time INT NOT NULL,
    moving_time INT NOT NULL,
    distance DOUBLE PRECISION,
    average_speed DOUBLE PRECISION,
    average_cadence DOUBLE PRECISION,
    average_watts DOUBLE PRECISION,
    average_heartrate DOUBLE PRECISION,
    max_heartrate DOUBLE PRECISION,
    start_index INT,
    end_index INT,
    UNIQUE(activity_id, lap_index)
);

COMMENT ON TABLE public.strava_activity_laps IS 'Per-lap breakdown of Strava activities. Written by service_role via Edge Function sync; readable by the owning user via RLS join.';
COMMENT ON COLUMN public.strava_activity_laps.activity_id IS 'FK to strava_activities.id — the parent activity this lap belongs to';
COMMENT ON COLUMN public.strava_activity_laps.lap_index IS 'Zero-based lap order within the activity';
COMMENT ON COLUMN public.strava_activity_laps.elapsed_time IS 'Total elapsed time for this lap in seconds';
COMMENT ON COLUMN public.strava_activity_laps.moving_time IS 'Moving time for this lap in seconds';
COMMENT ON COLUMN public.strava_activity_laps.distance IS 'Lap distance in metres';
COMMENT ON COLUMN public.strava_activity_laps.average_speed IS 'Average speed in metres per second';
COMMENT ON COLUMN public.strava_activity_laps.average_cadence IS 'Average cadence in RPM (running) or RPM (cycling)';
COMMENT ON COLUMN public.strava_activity_laps.average_watts IS 'Average power output in watts';
COMMENT ON COLUMN public.strava_activity_laps.average_heartrate IS 'Average heart rate in bpm';
COMMENT ON COLUMN public.strava_activity_laps.max_heartrate IS 'Max heart rate in bpm';
COMMENT ON COLUMN public.strava_activity_laps.start_index IS 'Start index in the activity streams arrays';
COMMENT ON COLUMN public.strava_activity_laps.end_index IS 'End index in the activity streams arrays';

-- Enable RLS on strava_activity_laps
ALTER TABLE public.strava_activity_laps ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can SELECT laps for their own activities (via join)
CREATE POLICY "Users can read own activity laps"
    ON public.strava_activity_laps
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.strava_activities sa
            WHERE sa.id = activity_id AND sa.user_id = auth.uid()
        )
    );

-- Index for the primary query pattern: fetch all laps for a given activity
CREATE INDEX idx_strava_activity_laps_activity_id ON public.strava_activity_laps(activity_id);

-- Add streams_data JSONB column to strava_activities
-- Stores raw Strava stream arrays for detailed analysis and charting.
ALTER TABLE public.strava_activities ADD COLUMN streams_data JSONB;

COMMENT ON COLUMN public.strava_activities.streams_data IS 'Raw Strava streams (time, heartrate, watts, cadence, velocity_smooth, distance arrays). NULL if not yet fetched or fetch failed.';

-- ============================================================================
-- DOWN MIGRATION (run manually if rollback needed)
-- ============================================================================
-- ALTER TABLE public.strava_activities DROP COLUMN IF EXISTS streams_data;
-- DROP INDEX IF EXISTS idx_strava_activity_laps_activity_id;
-- DROP POLICY IF EXISTS "Users can read own activity laps" ON public.strava_activity_laps;
-- DROP TABLE IF EXISTS public.strava_activity_laps;
