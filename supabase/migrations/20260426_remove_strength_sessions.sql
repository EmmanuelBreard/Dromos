-- DRO-222 / DRO-213 Phase 8 — destructive cleanup of legacy strength sessions.
--
-- Strength templates were removed from `workout-library.json` in DRO-215, and the
-- generate-plan pipeline was updated in DRO-216 to no longer produce strength sessions.
-- This migration sweeps the residual `plan_sessions` rows whose `sport='strength'`
-- pointed at template_ids that no longer exist (renderer would have shown them as
-- empty cards). The renderer's `template_id` fallback path also relies on those rows
-- being absent — once they're gone, the structure column is the single source of truth.
--
-- This is irreversible. Apply only after DRO-215, DRO-216, DRO-217, and the iOS
-- structure renderer are stable in production.

-- UP
DELETE FROM public.plan_sessions WHERE sport = 'strength';

-- DOWN
-- (irreversible — accept; no restore script)
