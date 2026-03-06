-- UP: Add feedback columns to plan_sessions
ALTER TABLE public.plan_sessions
  ADD COLUMN feedback TEXT,
  ADD COLUMN matched_activity_id UUID REFERENCES public.strava_activities(id);

-- No RLS changes needed:
-- iOS already has SELECT on plan_sessions (via join to training_plans).
-- Edge Function writes via service_role (bypasses RLS).

-- DOWN:
-- ALTER TABLE public.plan_sessions
--   DROP COLUMN feedback,
--   DROP COLUMN matched_activity_id;
