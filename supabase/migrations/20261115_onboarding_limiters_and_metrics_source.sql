-- Conversational onboarding stores injuries and where each metric came from.
-- generate-plan already reads users.limiters; the column did not exist, so the
-- prompt always received "none".
--
-- metrics_source example:
-- {"vma":"estimated_from_race","css":"entered","ftp":"estimated_from_experience","max_hr":"estimated_from_age"}

-- ============================================================================
-- UP
-- ============================================================================

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS limiters TEXT,
  ADD COLUMN IF NOT EXISTS metrics_source JSONB;

ALTER TABLE public.users
  DROP CONSTRAINT IF EXISTS check_metrics_source_object;

ALTER TABLE public.users
  ADD CONSTRAINT check_metrics_source_object
  CHECK (metrics_source IS NULL OR jsonb_typeof(metrics_source) = 'object');

COMMENT ON COLUMN public.users.limiters IS
  'Injuries or weak spots from conversational onboarding. NULL means not answered. The word none means the athlete reported none.';

COMMENT ON COLUMN public.users.metrics_source IS
  'How vma, css, ftp, and max_hr were obtained: entered, estimated_from_race, estimated_from_experience, or estimated_from_age.';

-- ============================================================================
-- DOWN (run manually if rollback is needed)
-- ============================================================================
-- ALTER TABLE public.users DROP CONSTRAINT IF EXISTS check_metrics_source_object;
-- ALTER TABLE public.users DROP COLUMN IF EXISTS metrics_source;
-- ALTER TABLE public.users DROP COLUMN IF EXISTS limiters;
