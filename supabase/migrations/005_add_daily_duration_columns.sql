-- Migration: Add daily training duration columns to users table
-- DRO-37: Add daily training duration collection to onboarding flow
--
-- Adds 7 nullable INT columns (one per day of week) to store total training
-- duration per day in minutes. Only days marked as available (union of
-- swim/bike/run days) will have values; off-days remain NULL.
--
-- Constraints:
-- - Range: 30-420 minutes (30min to 7hr)
-- - Increments: 15 minutes (handled in UI)
-- - Nullable: Off-days stay NULL

-- UP
ALTER TABLE public.users
  ADD COLUMN mon_duration INT,
  ADD COLUMN tue_duration INT,
  ADD COLUMN wed_duration INT,
  ADD COLUMN thu_duration INT,
  ADD COLUMN fri_duration INT,
  ADD COLUMN sat_duration INT,
  ADD COLUMN sun_duration INT;

-- Add CHECK constraints to enforce valid range (30-420 minutes)
ALTER TABLE public.users
  ADD CONSTRAINT check_mon_duration CHECK (mon_duration IS NULL OR (mon_duration >= 30 AND mon_duration <= 420)),
  ADD CONSTRAINT check_tue_duration CHECK (tue_duration IS NULL OR (tue_duration >= 30 AND tue_duration <= 420)),
  ADD CONSTRAINT check_wed_duration CHECK (wed_duration IS NULL OR (wed_duration >= 30 AND wed_duration <= 420)),
  ADD CONSTRAINT check_thu_duration CHECK (thu_duration IS NULL OR (thu_duration >= 30 AND thu_duration <= 420)),
  ADD CONSTRAINT check_fri_duration CHECK (fri_duration IS NULL OR (fri_duration >= 30 AND fri_duration <= 420)),
  ADD CONSTRAINT check_sat_duration CHECK (sat_duration IS NULL OR (sat_duration >= 30 AND sat_duration <= 420)),
  ADD CONSTRAINT check_sun_duration CHECK (sun_duration IS NULL OR (sun_duration >= 30 AND sun_duration <= 420));

-- DOWN
ALTER TABLE public.users
  DROP CONSTRAINT IF EXISTS check_mon_duration,
  DROP CONSTRAINT IF EXISTS check_tue_duration,
  DROP CONSTRAINT IF EXISTS check_wed_duration,
  DROP CONSTRAINT IF EXISTS check_thu_duration,
  DROP CONSTRAINT IF EXISTS check_fri_duration,
  DROP CONSTRAINT IF EXISTS check_sat_duration,
  DROP CONSTRAINT IF EXISTS check_sun_duration;

ALTER TABLE public.users
  DROP COLUMN IF EXISTS mon_duration,
  DROP COLUMN IF EXISTS tue_duration,
  DROP COLUMN IF EXISTS wed_duration,
  DROP COLUMN IF EXISTS thu_duration,
  DROP COLUMN IF EXISTS fri_duration,
  DROP COLUMN IF EXISTS sat_duration,
  DROP COLUMN IF EXISTS sun_duration;

