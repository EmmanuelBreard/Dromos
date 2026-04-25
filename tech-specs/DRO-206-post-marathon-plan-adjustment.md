# Feature Implementation Plan — DRO-206

**Overall Progress:** `100%`

## TLDR
Two targeted SQL updates to `plan_sessions` for ebreard4@gmail.com's Week 4 (Recovery, Apr 13–19). User ran Paris Marathon on Apr 12 at Z3 effort (avg HR 151, 3h50) — the originally generated plan needs two adjustments to avoid overloading recovering legs.

## Critical Decisions

- **Monday rest vs. easy swim:** Remove the Monday swim entirely (delete the row) rather than replacing with a rest placeholder. The plan has no "rest" session type — absence of a session is rest.
- **Sunday brick run:** Update `template_id`, `type`, and `notes` in-place rather than deleting + inserting. Preserves `is_brick = true` and `order_in_day` integrity for the brick pairing.
- **Use service_role:** RLS on `plan_sessions` restricts writes to the owning user. Run via Supabase SQL editor (service_role context) or a migration — not from the app.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `public.plan_sessions` (DB) | DELETE | Remove Monday swim row for this user's week 4 |
| `public.plan_sessions` (DB) | UPDATE | Change Sunday brick run template to easy |

## Context Doc Updates
None — no schema changes, no new files, no new patterns.

## Tasks

- [ ] 🟥 **Step 1: Delete Monday swim session**

  Execute via Supabase SQL editor (service_role):

  ```sql
  -- UP: Remove post-marathon Monday swim (Day 1 — full rest instead)
  DELETE FROM plan_sessions
  WHERE id = '45154bf8-30d7-427a-bae9-64684262e695';

  -- DOWN: Restore if needed
  -- INSERT INTO plan_sessions (id, week_id, day, sport, type, template_id, duration_minutes, is_brick, notes, order_in_day)
  -- VALUES (
  --   '45154bf8-30d7-427a-bae9-64684262e695',
  --   (SELECT id FROM plan_weeks WHERE start_date = '2026-04-13' AND plan_id = (SELECT id FROM training_plans tp JOIN users u ON tp.user_id = u.id WHERE u.email = 'ebreard4@gmail.com')),
  --   'Monday', 'swim', 'Easy', 'SWIM_Easy_13', 45, false,
  --   '2k @2:20/100m easy — post-marathon recovery swim', 0
  -- );
  ```

  - [ ] 🟥 Verify row exists before deleting: `SELECT id, day, sport, template_id FROM plan_sessions WHERE id = '45154bf8-30d7-427a-bae9-64684262e695';`
  - [ ] 🟥 Execute DELETE
  - [ ] 🟥 Confirm 0 rows remain for Monday swim that week

- [ ] 🟥 **Step 2: Swap Sunday brick run to easy**

  ```sql
  -- UP: Replace threshold brick run with easy run (post-marathon day 7 — no intensity)
  UPDATE plan_sessions
  SET
    template_id = 'RUN_Easy_08',
    type        = 'Easy',
    notes       = '55min easy run off the bike — post-marathon recovery, HR <140'
  WHERE id = '525b4197-4462-4b73-9442-4b205b03bac2';

  -- DOWN: Restore original
  -- UPDATE plan_sessions
  -- SET template_id = 'RUN_Tempo_21', type = 'Tempo',
  --     notes = 'Brick run: first 7k @5:15/km easy, last 3k @4:10/km (threshold)'
  -- WHERE id = '525b4197-4462-4b73-9442-4b205b03bac2';
  ```

  - [ ] 🟥 Verify current state: `SELECT id, day, template_id, type, notes FROM plan_sessions WHERE id = '525b4197-4462-4b73-9442-4b205b03bac2';`
  - [ ] 🟥 Execute UPDATE
  - [ ] 🟥 Confirm `template_id = 'RUN_Easy_08'` and `type = 'Easy'`

- [ ] 🟥 **Step 3: Smoke check full week**

  ```sql
  SELECT ps.day, ps.sport, ps.type, ps.template_id, ps.duration_minutes, ps.notes
  FROM plan_sessions ps
  JOIN plan_weeks pw ON ps.week_id = pw.id
  JOIN training_plans tp ON pw.plan_id = tp.id
  JOIN users u ON tp.user_id = u.id
  WHERE u.email = 'ebreard4@gmail.com'
    AND pw.start_date = '2026-04-13'
  ORDER BY ps.day, ps.order_in_day;
  ```

  Expected result:
  - Monday: **no rows** (rest day)
  - Tuesday: `SWIM_Easy_07` + `BIKE_Easy_15`
  - Wednesday: `BIKE_Intervals_12`
  - Thursday: `RUN_Easy_07`
  - Friday: `BIKE_Easy_13` + `SWIM_Easy_06`
  - Saturday: `BIKE_Easy_07`
  - Sunday: `BIKE_Tempo_17` (brick bike) + `RUN_Easy_08` (brick run, Easy) + `SWIM_Easy_06`

  - [ ] 🟥 Run smoke check query and confirm expected output
