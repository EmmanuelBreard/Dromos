-- Migration: Drop demographic columns from users table
-- Description: Remove sex, birth_date, weight_kg columns that are no longer used
-- These fields were part of the original onboarding but are not used by the AI pipeline

-- UP
ALTER TABLE public.users
DROP CONSTRAINT IF EXISTS check_weight_kg,
DROP COLUMN IF EXISTS sex,
DROP COLUMN IF EXISTS birth_date,
DROP COLUMN IF EXISTS weight_kg;

-- DOWN (rollback - run manually if needed)
-- ALTER TABLE public.users
-- ADD COLUMN sex TEXT,
-- ADD COLUMN birth_date TIMESTAMPTZ,
-- ADD COLUMN weight_kg DECIMAL(5,2),
-- ADD CONSTRAINT check_weight_kg
--   CHECK (weight_kg IS NULL OR (weight_kg BETWEEN 30 AND 300));
