-- Migration: Consolidate split time fields into single integer columns
-- Description: Replaces 4 split time columns (css_minutes + css_seconds, time_objective_hours + time_objective_minutes) with 2 consolidated integer columns (css_seconds_per_100m, time_objective_minutes). UI stays identical — conversion happens at client/display layer.
-- Date: 2026-02-01
-- Task: DRO-24

-- ============================================================================
-- UP MIGRATION
-- ============================================================================

-- Step 1: Add new consolidated columns
ALTER TABLE public.users
ADD COLUMN css_seconds_per_100m INT,
ADD COLUMN time_objective_total_min INT;

-- Step 2: Compute values from old split columns and populate new columns
-- css_seconds_per_100m = css_minutes * 60 + css_seconds (if both exist)
-- time_objective_total_min = time_objective_hours * 60 + time_objective_minutes (if both exist)
UPDATE public.users
SET css_seconds_per_100m = CASE
    WHEN css_minutes IS NOT NULL THEN css_minutes * 60 + COALESCE(css_seconds, 0)
    ELSE NULL
END,
time_objective_total_min = CASE
    WHEN time_objective_hours IS NOT NULL THEN time_objective_hours * 60 + COALESCE(time_objective_minutes, 0)
    ELSE NULL
END;

-- Step 3: Drop old CHECK constraints that reference the old columns
ALTER TABLE public.users
DROP CONSTRAINT IF EXISTS check_css_seconds,
DROP CONSTRAINT IF EXISTS check_css_total;

-- Step 4: Drop old split columns
ALTER TABLE public.users
DROP COLUMN IF EXISTS css_minutes,
DROP COLUMN IF EXISTS css_seconds,
DROP COLUMN IF EXISTS time_objective_hours,
DROP COLUMN IF EXISTS time_objective_minutes;

-- Step 5: Rename time_objective_total_min to time_objective_minutes
ALTER TABLE public.users
RENAME COLUMN time_objective_total_min TO time_objective_minutes;

-- Step 6: Add new CHECK constraints for consolidated columns
ALTER TABLE public.users
ADD CONSTRAINT check_css_seconds_per_100m
  CHECK (css_seconds_per_100m IS NULL OR css_seconds_per_100m BETWEEN 25 AND 300),
ADD CONSTRAINT check_time_objective_minutes
  CHECK (time_objective_minutes IS NULL OR time_objective_minutes > 0);

-- ============================================================================
-- DOWN MIGRATION (run manually if rollback needed)
-- ============================================================================
-- Step 1: Drop new CHECK constraints
-- ALTER TABLE public.users
-- DROP CONSTRAINT IF EXISTS check_css_seconds_per_100m,
-- DROP CONSTRAINT IF EXISTS check_time_objective_minutes;

-- Step 2: Add back old split columns
-- ALTER TABLE public.users
-- ADD COLUMN css_minutes INT,
-- ADD COLUMN css_seconds INT,
-- ADD COLUMN time_objective_hours INT,
-- ADD COLUMN time_objective_minutes INT;

-- Step 3: Compute values from consolidated columns back to split columns
-- UPDATE public.users
-- SET css_minutes = CASE
--     WHEN css_seconds_per_100m IS NOT NULL THEN css_seconds_per_100m / 60
--     ELSE NULL
-- END,
-- css_seconds = CASE
--     WHEN css_seconds_per_100m IS NOT NULL THEN css_seconds_per_100m % 60
--     ELSE NULL
-- END,
-- time_objective_hours = CASE
--     WHEN time_objective_minutes IS NOT NULL THEN time_objective_minutes / 60
--     ELSE NULL
-- END,
-- time_objective_minutes = CASE
--     WHEN time_objective_minutes IS NOT NULL THEN time_objective_minutes % 60
--     ELSE NULL
-- END;

-- Step 4: Rename time_objective_minutes back to time_objective_total_min temporarily
-- ALTER TABLE public.users
-- RENAME COLUMN time_objective_minutes TO time_objective_total_min;

-- Step 5: Add back old CHECK constraints
-- ALTER TABLE public.users
-- ADD CONSTRAINT check_css_seconds
--   CHECK (css_seconds IS NULL OR css_seconds BETWEEN 0 AND 59),
-- ADD CONSTRAINT check_css_total
--   CHECK ((css_minutes IS NULL AND css_seconds IS NULL) OR
--          (css_minutes IS NOT NULL AND (css_minutes * 60 + COALESCE(css_seconds, 0)) BETWEEN 25 AND 300));

-- Step 6: Drop consolidated columns
-- ALTER TABLE public.users
-- DROP COLUMN IF EXISTS css_seconds_per_100m,
-- DROP COLUMN IF EXISTS time_objective_total_min;

