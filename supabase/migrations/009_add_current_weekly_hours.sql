-- Migration: Add current weekly training hours to users table
-- DRO-65: Capture athlete's current training volume for plan baseline
--
-- Stores the athlete's self-reported average weekly training hours over the
-- last 4 weeks. Used in Step 1 prompt so week 1 starts near the athlete's
-- actual baseline rather than an arbitrary point.
--
-- Constraints:
-- - Range: 0.0-25.0 hours (DECIMAL(3,1) for 0.5h step granularity)
-- - Nullable: existing users won't have this field yet

-- UP
ALTER TABLE public.users
  ADD COLUMN current_weekly_hours DECIMAL(3,1);

ALTER TABLE public.users
  ADD CONSTRAINT check_current_weekly_hours
    CHECK (current_weekly_hours IS NULL OR (current_weekly_hours >= 0 AND current_weekly_hours <= 25));

-- DOWN
ALTER TABLE public.users
  DROP CONSTRAINT IF EXISTS check_current_weekly_hours;

ALTER TABLE public.users
  DROP COLUMN IF EXISTS current_weekly_hours;
