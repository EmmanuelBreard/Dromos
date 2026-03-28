-- UP: Add strength and race sport types, Race session type
ALTER TABLE plan_sessions DROP CONSTRAINT plan_sessions_sport_check;
ALTER TABLE plan_sessions ADD CONSTRAINT plan_sessions_sport_check
  CHECK (sport IN ('swim', 'bike', 'run', 'strength', 'race'));

ALTER TABLE plan_sessions DROP CONSTRAINT plan_sessions_type_check;
ALTER TABLE plan_sessions ADD CONSTRAINT plan_sessions_type_check
  CHECK (type IN ('Easy', 'Tempo', 'Intervals', 'Race'));

-- DOWN (manual rollback):
-- ALTER TABLE plan_sessions DROP CONSTRAINT plan_sessions_sport_check;
-- ALTER TABLE plan_sessions ADD CONSTRAINT plan_sessions_sport_check
--   CHECK (sport IN ('swim', 'bike', 'run'));
-- ALTER TABLE plan_sessions DROP CONSTRAINT plan_sessions_type_check;
-- ALTER TABLE plan_sessions ADD CONSTRAINT plan_sessions_type_check
--   CHECK (type IN ('Easy', 'Tempo', 'Intervals'));
