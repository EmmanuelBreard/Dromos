-- UP
ALTER TABLE public.strava_activities ADD COLUMN summary_polyline TEXT;

-- DOWN
-- ALTER TABLE public.strava_activities DROP COLUMN summary_polyline;
