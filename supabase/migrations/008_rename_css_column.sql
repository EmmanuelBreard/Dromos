-- Migration: Rename css_seconds_per_100m to css_seconds_per100m
-- Description: Aligns DB column name with Swift's .convertToSnakeCase encoding
--   (cssSecondsPer100m encodes to css_seconds_per100m, not css_seconds_per_100m)
-- Date: 2026-02-01
-- Task: DRO-24 (hotfix)

-- ============================================================================
-- UP MIGRATION
-- ============================================================================

-- Drop constraint that references old column name
ALTER TABLE public.users
DROP CONSTRAINT IF EXISTS check_css_seconds_per_100m;

-- Rename column
ALTER TABLE public.users
RENAME COLUMN css_seconds_per_100m TO css_seconds_per100m;

-- Re-add constraint with new column name
ALTER TABLE public.users
ADD CONSTRAINT check_css_seconds_per100m
  CHECK (css_seconds_per100m IS NULL OR css_seconds_per100m BETWEEN 25 AND 300);

-- ============================================================================
-- DOWN MIGRATION (run manually if rollback needed)
-- ============================================================================
-- ALTER TABLE public.users DROP CONSTRAINT IF EXISTS check_css_seconds_per100m;
-- ALTER TABLE public.users RENAME COLUMN css_seconds_per100m TO css_seconds_per_100m;
-- ALTER TABLE public.users ADD CONSTRAINT check_css_seconds_per_100m
--   CHECK (css_seconds_per_100m IS NULL OR css_seconds_per_100m BETWEEN 25 AND 300);
