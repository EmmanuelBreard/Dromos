-- Migration: Add onboarding fields to users table
-- Description: Extends public.users with fields for onboarding flow (demographics, race goals, performance metrics)
-- Date: 2026-01-25
-- Task: DRO-10

-- ============================================================================
-- UP MIGRATION
-- ============================================================================

-- Add onboarding fields to users table
-- These fields capture user profile data collected during onboarding:
--   - Basic info: sex, birth_date, weight_kg
--   - Race goals: race_objective, race_date, time_objective_hours/minutes
--   - Performance metrics: vma, css_minutes/seconds, ftp, experience_years
--   - Status: onboarding_completed flag
ALTER TABLE public.users
ADD COLUMN sex TEXT,
ADD COLUMN birth_date DATE,
ADD COLUMN weight_kg DECIMAL(5,2),
ADD COLUMN race_objective TEXT,
ADD COLUMN race_date DATE,
ADD COLUMN time_objective_hours INT,
ADD COLUMN time_objective_minutes INT,
ADD COLUMN vma DECIMAL(4,2),
ADD COLUMN css_minutes INT,
ADD COLUMN css_seconds INT,
ADD COLUMN ftp INT,
ADD COLUMN experience_years INT,
ADD COLUMN onboarding_completed BOOLEAN DEFAULT FALSE NOT NULL;

-- Add CHECK constraints for data validation at database level
-- These ensure data integrity even if client-side validation is bypassed
ALTER TABLE public.users
ADD CONSTRAINT check_race_objective
  CHECK (race_objective IS NULL OR race_objective IN ('Sprint', 'Olympic', 'Ironman 70.3', 'Ironman')),
ADD CONSTRAINT check_weight_kg
  CHECK (weight_kg IS NULL OR (weight_kg BETWEEN 30 AND 300)),
ADD CONSTRAINT check_vma
  CHECK (vma IS NULL OR (vma BETWEEN 10 AND 25)),
ADD CONSTRAINT check_ftp
  CHECK (ftp IS NULL OR (ftp BETWEEN 50 AND 500)),
ADD CONSTRAINT check_css_seconds
  CHECK (css_seconds IS NULL OR (css_seconds BETWEEN 0 AND 59)),
ADD CONSTRAINT check_css_total
  CHECK ((css_minutes IS NULL AND css_seconds IS NULL) OR
         (css_minutes IS NOT NULL AND (css_minutes * 60 + COALESCE(css_seconds, 0)) BETWEEN 25 AND 300)),
ADD CONSTRAINT check_experience_years
  CHECK (experience_years IS NULL OR experience_years >= 0);

-- Note: Existing RLS policies already cover new columns (SELECT/UPDATE for own row)
-- No new policies needed as they operate at row level, not column level

-- ============================================================================
-- DOWN MIGRATION (run manually if rollback needed)
-- ============================================================================
-- Remove CHECK constraints first
-- ALTER TABLE public.users
-- DROP CONSTRAINT IF EXISTS check_race_objective,
-- DROP CONSTRAINT IF EXISTS check_weight_kg,
-- DROP CONSTRAINT IF EXISTS check_vma,
-- DROP CONSTRAINT IF EXISTS check_ftp,
-- DROP CONSTRAINT IF EXISTS check_css_seconds,
-- DROP CONSTRAINT IF EXISTS check_css_total,
-- DROP CONSTRAINT IF EXISTS check_experience_years;

-- Remove columns
-- ALTER TABLE public.users
-- DROP COLUMN IF EXISTS sex,
-- DROP COLUMN IF EXISTS birth_date,
-- DROP COLUMN IF EXISTS weight_kg,
-- DROP COLUMN IF EXISTS race_objective,
-- DROP COLUMN IF EXISTS race_date,
-- DROP COLUMN IF EXISTS time_objective_hours,
-- DROP COLUMN IF EXISTS time_objective_minutes,
-- DROP COLUMN IF EXISTS vma,
-- DROP COLUMN IF EXISTS css_minutes,
-- DROP COLUMN IF EXISTS css_seconds,
-- DROP COLUMN IF EXISTS ftp,
-- DROP COLUMN IF EXISTS experience_years,
-- DROP COLUMN IF EXISTS onboarding_completed;
