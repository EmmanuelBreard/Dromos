-- Migration: Convert DATE columns to TIMESTAMPTZ
-- Description: Changes birth_date and race_date from DATE to TIMESTAMPTZ for consistent ISO-8601 encoding
-- Date: 2026-01-25
-- Reason: Simplifies client-side date handling - all temporal columns now use standard ISO-8601 format

-- ============================================================================
-- UP MIGRATION
-- ============================================================================

-- Convert birth_date from DATE to TIMESTAMPTZ
-- Existing values like '1986-01-24' become '1986-01-24 00:00:00+00'
ALTER TABLE public.users
ALTER COLUMN birth_date TYPE TIMESTAMPTZ USING birth_date::TIMESTAMPTZ;

-- Convert race_date from DATE to TIMESTAMPTZ
-- Existing values like '2026-05-31' become '2026-05-31 00:00:00+00'
ALTER TABLE public.users
ALTER COLUMN race_date TYPE TIMESTAMPTZ USING race_date::TIMESTAMPTZ;

-- ============================================================================
-- DOWN MIGRATION (run manually if rollback needed)
-- ============================================================================
-- Convert back to DATE (loses time component, keeps only date)
-- ALTER TABLE public.users
-- ALTER COLUMN birth_date TYPE DATE USING birth_date::DATE;
--
-- ALTER TABLE public.users
-- ALTER COLUMN race_date TYPE DATE USING race_date::DATE;
