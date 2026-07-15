-- DRO-312: plan generation failures become permanent zombie plans.
-- The status CHECK forbade 'failed', so the generate-plan catch block's
-- UPDATE status='failed' was rejected (400) and plans stayed 'generating' forever.
-- Allow 'failed' and add columns to surface the failure cause.

-- UP
ALTER TABLE training_plans DROP CONSTRAINT training_plans_status_check;
ALTER TABLE training_plans ADD CONSTRAINT training_plans_status_check
  CHECK (status = ANY (ARRAY['generating'::text, 'active'::text, 'failed'::text]));

ALTER TABLE training_plans ADD COLUMN IF NOT EXISTS error_message text;
ALTER TABLE training_plans ADD COLUMN IF NOT EXISTS failed_at timestamptz;

-- DOWN
-- ALTER TABLE training_plans DROP COLUMN IF EXISTS failed_at;
-- ALTER TABLE training_plans DROP COLUMN IF EXISTS error_message;
-- ALTER TABLE training_plans DROP CONSTRAINT training_plans_status_check;
-- ALTER TABLE training_plans ADD CONSTRAINT training_plans_status_check
--   CHECK (status = ANY (ARRAY['generating'::text, 'active'::text]));
