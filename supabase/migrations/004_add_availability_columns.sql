-- Migration: Add availability columns to users table
-- Description: Adds JSONB columns for storing weekly training availability (swim/bike/run days)
-- Date: 2026-01-26
-- Task: DRO-28 (Phase 1 of DRO-25)

-- ============================================================================
-- UP MIGRATION
-- ============================================================================

-- Add availability columns to users table
-- These columns store arrays of day names (e.g., ["Monday", "Wednesday", "Friday"])
-- Default to empty array for new users
-- JSONB format allows efficient querying and is LLM-friendly for training plan generation
ALTER TABLE public.users
ADD COLUMN swim_days JSONB DEFAULT '[]'::jsonb,
ADD COLUMN bike_days JSONB DEFAULT '[]'::jsonb,
ADD COLUMN run_days JSONB DEFAULT '[]'::jsonb;

-- Note: Existing RLS policies already cover new columns (SELECT/UPDATE for own row)
-- No new policies needed as they operate at row level, not column level

-- ============================================================================
-- DOWN MIGRATION (run manually if rollback needed)
-- ============================================================================
-- Remove availability columns
-- ALTER TABLE public.users
--   DROP COLUMN IF EXISTS swim_days,
--   DROP COLUMN IF EXISTS bike_days,
--   DROP COLUMN IF EXISTS run_days;

