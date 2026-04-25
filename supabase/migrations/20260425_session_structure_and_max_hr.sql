-- UP: Additive migration — adds structure JSONB to plan_sessions
--     and max_hr / birth_year to users.
--     No destructive operations. Strength session deletion is deferred to Phase 8.

-- plan_sessions.structure: stores the materialised SessionStructure JSON blob.
-- Nullable so legacy rows (pre-backfill) continue to work with the template_id fallback.
ALTER TABLE public.plan_sessions
  ADD COLUMN IF NOT EXISTS structure JSONB;

-- users.max_hr: Maximum heart rate in BPM. Used by HR-zone and hr_pct_max targets.
-- Constrained to physiologically valid range (100-220). Nullable so existing users
-- are unaffected until they set it via Settings / onboarding.
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS max_hr INT CHECK (max_hr BETWEEN 100 AND 220);

-- users.birth_year: Supports the "220 − age" formula affordance in onboarding.
-- Constrained to reasonable range (1920-2020). Nullable.
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS birth_year INT CHECK (birth_year BETWEEN 1920 AND 2020);

-- DOWN (run manually if rollback needed — only safe before backfill writes structure):
-- ALTER TABLE public.plan_sessions DROP COLUMN IF EXISTS structure;
-- ALTER TABLE public.users DROP COLUMN IF EXISTS max_hr;
-- ALTER TABLE public.users DROP COLUMN IF EXISTS birth_year;
