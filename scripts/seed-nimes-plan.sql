-- =============================================================================
-- Seed: 10-Week Nîmes Training Plan for ebreard4@gmail.com
-- Race: Triathlon Monumental Nîmes Pont du Gard — 2026-05-31 (Ironman 70.3)
-- Plan window: 2026-03-23 → 2026-05-31
--
-- Usage: Run as service_role / postgres superuser in Supabase SQL editor.
-- WARNING: Deletes existing training_plans for ebreard4@gmail.com (CASCADE).
-- Total sessions: 105
-- =============================================================================

DO $$
DECLARE
  v_user_id  UUID;
  v_plan_id  UUID;
  v_w1_id    UUID; v_w2_id  UUID; v_w3_id  UUID; v_w4_id  UUID; v_w5_id  UUID;
  v_w6_id    UUID; v_w7_id  UUID; v_w8_id  UUID; v_w9_id  UUID; v_w10_id UUID;
BEGIN

  -- -------------------------------------------------------------------------
  -- 1. Resolve user
  -- -------------------------------------------------------------------------
  SELECT id INTO v_user_id FROM auth.users WHERE email = 'ebreard4@gmail.com';
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'User ebreard4@gmail.com not found in auth.users';
  END IF;

  -- -------------------------------------------------------------------------
  -- 2. Wipe existing plan (CASCADE removes plan_weeks + plan_sessions)
  -- -------------------------------------------------------------------------
  DELETE FROM training_plans WHERE user_id = v_user_id;

  -- -------------------------------------------------------------------------
  -- 3. Create training plan
  -- -------------------------------------------------------------------------
  INSERT INTO training_plans (user_id, status, race_date, race_objective, total_weeks, start_date)
  VALUES (v_user_id, 'active', '2026-05-31', 'Ironman 70.3', 10, '2026-03-23')
  RETURNING id INTO v_plan_id;

  -- -------------------------------------------------------------------------
  -- 4. Create 10 plan weeks
  -- -------------------------------------------------------------------------

  -- Week 1 — Base (Mar 23-29)
  INSERT INTO plan_weeks (plan_id, week_number, phase, is_recovery, start_date, rest_days, notes)
  VALUES (v_plan_id, 1, 'Base', false, '2026-03-23', '[]', 'Ramp-up: introduce doubles, build easy volume')
  RETURNING id INTO v_w1_id;

  -- Week 2 — Base (Mar 30 - Apr 5)
  INSERT INTO plan_weeks (plan_id, week_number, phase, is_recovery, start_date, rest_days, notes)
  VALUES (v_plan_id, 2, 'Base', false, '2026-03-30', '[]', 'Ramp-up: first brick, push long bike to 80km')
  RETURNING id INTO v_w2_id;

  -- Week 3 — Base (Apr 6-12) — Pre-marathon: front-load Mon-Thu, marathon Sunday
  INSERT INTO plan_weeks (plan_id, week_number, phase, is_recovery, start_date, rest_days, notes)
  VALUES (v_plan_id, 3, 'Base', false, '2026-04-06', '["Saturday"]', 'Pre-marathon: front-load quality Mon-Thu, marathon Sunday')
  RETURNING id INTO v_w3_id;

  -- Week 4 — Recovery (Apr 13-19)
  INSERT INTO plan_weeks (plan_id, week_number, phase, is_recovery, start_date, rest_days, notes)
  VALUES (v_plan_id, 4, 'Recovery', true, '2026-04-13', '[]', 'Post-marathon recovery + restart. 3:1 cycle.')
  RETURNING id INTO v_w4_id;

  -- Week 5 — Build (Apr 20-26)
  INSERT INTO plan_weeks (plan_id, week_number, phase, is_recovery, start_date, rest_days, notes)
  VALUES (v_plan_id, 5, 'Build', false, '2026-04-20', '[]', 'Build 1: rebuild volume, reintroduce bricks')
  RETURNING id INTO v_w5_id;

  -- Week 6 — Build (Apr 27 - May 3)
  INSERT INTO plan_weeks (plan_id, week_number, phase, is_recovery, start_date, rest_days, notes)
  VALUES (v_plan_id, 6, 'Build', false, '2026-04-27', '[]', 'Build 1: push bike to 90km, race nutrition test')
  RETURNING id INTO v_w6_id;

  -- Week 7 — Peak (May 4-10) KEY WEEK
  INSERT INTO plan_weeks (plan_id, week_number, phase, is_recovery, start_date, rest_days, notes)
  VALUES (v_plan_id, 7, 'Peak', false, '2026-05-04', '[]', 'KEY WEEK: biggest volume, first 100km ride, race-pace brick')
  RETURNING id INTO v_w7_id;

  -- Week 8 — Peak (May 11-17) PEAK VOLUME
  INSERT INTO plan_weeks (plan_id, week_number, phase, is_recovery, start_date, rest_days, notes)
  VALUES (v_plan_id, 8, 'Peak', false, '2026-05-11', '[]', 'PEAK VOLUME: full 90km race sim, longest brick run')
  RETURNING id INTO v_w8_id;

  -- Week 9 — Taper (May 18-24) Pre-taper
  INSERT INTO plan_weeks (plan_id, week_number, phase, is_recovery, start_date, rest_days, notes)
  VALUES (v_plan_id, 9, 'Taper', false, '2026-05-18', '[]', 'Pre-taper: reduce volume 30%, keep sharp hard touches')
  RETURNING id INTO v_w9_id;

  -- Week 10 — Taper (May 25-31) TAPER + RACE
  INSERT INTO plan_weeks (plan_id, week_number, phase, is_recovery, start_date, rest_days, notes)
  VALUES (v_plan_id, 10, 'Taper', false, '2026-05-25', '[]', 'TAPER + RACE: rest, sharpen, execute')
  RETURNING id INTO v_w10_id;

  -- =========================================================================
  -- 5. Insert plan_sessions (~99 rows)
  -- =========================================================================

  -- ---------------------------------------------------------------------------
  -- WEEK 1 (Mar 23-29) — 10 sessions
  -- ---------------------------------------------------------------------------

  -- Monday: swim easy (drills + easy 100s)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w1_id, 'Monday', 'swim', 'Easy', 'SWIM_Easy_10', 60, false, 0,
    '400 warmup, 8x50m drills (catch-up, fingertip drag), 4x100m @2:15 easy, 200 cooldown');

  -- Tuesday: run intervals + swim easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w1_id, 'Tuesday', 'run', 'Intervals', 'RUN_Intervals_01', 60, false, 0,
    '2km warmup @5:30, 5x3min @3:25/km (VO2max) w/ 2min jog, 2km cooldown');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w1_id, 'Tuesday', 'swim', 'Easy', 'SWIM_Easy_06', 35, false, 1,
    '1.5k easy technique focus: catch + pull, all @2:15/100m');

  -- Wednesday: bike easy
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w1_id, 'Wednesday', 'bike', 'Easy', 'BIKE_Easy_12', 60, false, 0,
    'All Z2 @170-190W, steady cadence 85-90rpm');

  -- Thursday: run easy
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w1_id, 'Thursday', 'run', 'Easy', 'RUN_Easy_07', 45, false, 0,
    '8k easy @5:20-5:30/km (HR <140)');

  -- Friday: bike easy + swim easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w1_id, 'Friday', 'bike', 'Easy', 'BIKE_Easy_13', 50, false, 0,
    'Recovery spin @160-180W');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w1_id, 'Friday', 'swim', 'Easy', 'SWIM_Easy_07', 30, false, 1,
    '1.2k drills only (catch-up, fingertip drag, fist drill)');

  -- Saturday: long bike
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w1_id, 'Saturday', 'bike', 'Easy', 'BIKE_Easy_07', 150, false, 0,
    '2h30 outdoor — 55-60km, 400-500m D+, avg 175-185W (all Z2)');

  -- Sunday: tempo run + swim easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w1_id, 'Sunday', 'run', 'Tempo', 'RUN_Tempo_18', 87, false, 0,
    '16k — 12k @5:20/km Z2, then last 4k @4:10/km (threshold)');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w1_id, 'Sunday', 'swim', 'Easy', 'SWIM_Easy_06', 35, false, 1,
    '1.5k easy @2:15/100m');

  -- ---------------------------------------------------------------------------
  -- WEEK 2 (Mar 30 - Apr 5) — 11 sessions
  -- ---------------------------------------------------------------------------

  -- Monday: swim tempo + strength (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w2_id, 'Monday', 'swim', 'Tempo', 'SWIM_Tempo_11', 50, false, 0,
    '400 warmup, 6x150m @1:52 CSS (20s rest), 200 cooldown');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w2_id, 'Monday', 'strength', 'Easy', 'STRENGTH_Easy_01', 30, false, 1,
    'Core/strength 30min');

  -- Tuesday: run easy + swim easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w2_id, 'Tuesday', 'run', 'Easy', 'RUN_Easy_08', 55, false, 0,
    '10k easy @5:20-5:30/km (HR <140)');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w2_id, 'Tuesday', 'swim', 'Easy', 'SWIM_Easy_06', 35, false, 1,
    '1.5k easy @2:15/100m');

  -- Wednesday: bike intervals
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w2_id, 'Wednesday', 'bike', 'Intervals', 'BIKE_Intervals_11', 60, false, 0,
    '10min warmup @165W, 5x4min @295-310W (VO2max) w/ 3min easy @140W, 10min cooldown');

  -- Thursday: run easy
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w2_id, 'Thursday', 'run', 'Easy', 'RUN_Easy_07', 45, false, 0,
    '8k easy @5:25/km');

  -- Friday: bike easy + swim easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w2_id, 'Friday', 'bike', 'Easy', 'BIKE_Easy_02', 45, false, 0,
    'Easy @160-180W');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w2_id, 'Friday', 'swim', 'Easy', 'SWIM_Easy_06', 35, false, 1,
    '1.5k pull buoy focus, easy pace');

  -- Saturday: long outdoor bike
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w2_id, 'Saturday', 'bike', 'Easy', 'BIKE_Easy_08', 180, false, 0,
    '3h outdoor — 80km, 600-700m D+, avg 175-185W (Z2, eat 60g carbs/h)');

  -- Sunday: brick (bike tempo + run tempo)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w2_id, 'Sunday', 'bike', 'Tempo', 'BIKE_Tempo_11', 45, true, 0,
    'Brick bike: 25min @180W Z2 → last 20min @235-250W / 85-90% FTP');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w2_id, 'Sunday', 'run', 'Tempo', 'RUN_Tempo_19', 55, true, 1,
    'Brick run: first 6k @5:15/km easy, last 4k @4:10/km (threshold)');

  -- ---------------------------------------------------------------------------
  -- WEEK 3 (Apr 6-12) — 9 sessions (Saturday = rest day)
  -- ---------------------------------------------------------------------------

  -- Monday: swim intervals + strength (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w3_id, 'Monday', 'swim', 'Intervals', 'SWIM_Intervals_11', 60, false, 0,
    '400 warmup, 8x150m @1:50 (fast, 20s rest), 300 cooldown');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w3_id, 'Monday', 'strength', 'Easy', 'STRENGTH_Easy_01', 30, false, 1,
    'Core/strength 30min');

  -- Tuesday: run easy + swim easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w3_id, 'Tuesday', 'run', 'Easy', 'RUN_Easy_07', 45, false, 0,
    '8k easy @5:25/km');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w3_id, 'Tuesday', 'swim', 'Easy', 'SWIM_Easy_06', 35, false, 1,
    '1.5k easy technique');

  -- Wednesday: bike intervals
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w3_id, 'Wednesday', 'bike', 'Intervals', 'BIKE_Intervals_11', 60, false, 0,
    '10min warmup, 5x4min @295-310W (VO2max) w/ 3min easy, 10min cooldown');

  -- Thursday: brick (bike easy + run easy)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w3_id, 'Thursday', 'bike', 'Easy', 'BIKE_Easy_14', 40, true, 0,
    'Brick bike: 40min @175-185W (Z2, all easy)');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w3_id, 'Thursday', 'run', 'Easy', 'RUN_Easy_09', 30, true, 1,
    'Brick run: 5k easy @5:20/km (practice transition)');

  -- Friday: swim easy
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w3_id, 'Friday', 'swim', 'Easy', 'SWIM_Easy_06', 35, false, 0,
    '1.5k easy @2:20/100m (drills + easy laps)');

  -- Saturday: REST (in rest_days — no session)

  -- Sunday: Paris Marathon race
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w3_id, 'Sunday', 'race', 'Race', 'RACE_Race_02', 220, false, 0,
    'PARIS MARATHON — 5:20-5:40/km, Z2 effort, HR <145. Walk aid stations if needed. Practice 60g carbs/h.');

  -- ---------------------------------------------------------------------------
  -- WEEK 4 (Apr 13-19) — 11 sessions (Recovery week post-marathon)
  -- ---------------------------------------------------------------------------

  -- Monday: swim easy
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w4_id, 'Monday', 'swim', 'Easy', 'SWIM_Easy_06', 45, false, 0,
    '2k easy @2:20/100m (long pulls, relaxed — flush the legs)');

  -- Tuesday: swim easy + bike easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w4_id, 'Tuesday', 'swim', 'Easy', 'SWIM_Easy_07', 30, false, 0,
    '1.5k drills');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w4_id, 'Tuesday', 'bike', 'Easy', 'BIKE_Easy_15', 30, false, 1,
    'Very easy @150W');

  -- Wednesday: bike intervals
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w4_id, 'Wednesday', 'bike', 'Intervals', 'BIKE_Intervals_12', 60, false, 0,
    '10min warmup, 4x4min @295-310W (VO2max) w/ 3min easy, 15min cooldown');

  -- Thursday: run easy
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w4_id, 'Thursday', 'run', 'Easy', 'RUN_Easy_07', 45, false, 0,
    '8k easy @5:25-5:35/km (HR <140)');

  -- Friday: bike easy + swim easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w4_id, 'Friday', 'bike', 'Easy', 'BIKE_Easy_13', 50, false, 0,
    'Easy @160-175W');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w4_id, 'Friday', 'swim', 'Easy', 'SWIM_Easy_06', 35, false, 1,
    '1.5k technique');

  -- Saturday: long outdoor bike
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w4_id, 'Saturday', 'bike', 'Easy', 'BIKE_Easy_07', 150, false, 0,
    '2h30 outdoor — 60km, 350-400m D+, 175-185W (Z2, no efforts)');

  -- Sunday: brick (bike tempo + run tempo) + swim easy (triple)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w4_id, 'Sunday', 'bike', 'Tempo', 'BIKE_Tempo_13', 40, true, 0,
    'Brick bike: 20min @180W Z2 → last 20min @235-250W / 85-90% FTP');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w4_id, 'Sunday', 'run', 'Tempo', 'RUN_Tempo_19', 55, true, 1,
    'Brick run: 7k @5:15/km easy, last 3k @4:10/km (threshold test)');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w4_id, 'Sunday', 'swim', 'Easy', 'SWIM_Easy_06', 35, false, 2,
    '1.5k easy');

  -- ---------------------------------------------------------------------------
  -- WEEK 5 (Apr 20-26) — 11 sessions
  -- ---------------------------------------------------------------------------

  -- Monday: swim intervals + strength (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w5_id, 'Monday', 'swim', 'Intervals', 'SWIM_Intervals_13', 55, false, 0,
    '400 warmup, 10x100m @1:50 (15s rest), 200 cooldown');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w5_id, 'Monday', 'strength', 'Easy', 'STRENGTH_Easy_01', 30, false, 1,
    'Core/strength 30min');

  -- Tuesday: run intervals + swim easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w5_id, 'Tuesday', 'run', 'Intervals', 'RUN_Intervals_19', 60, false, 0,
    '2km warmup, 6x3min @3:25/km (VO2max) w/ 2min jog, 2km cooldown');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w5_id, 'Tuesday', 'swim', 'Easy', 'SWIM_Easy_06', 35, false, 1,
    '1.5k easy @2:15/100m');

  -- Wednesday: bike easy
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w5_id, 'Wednesday', 'bike', 'Easy', 'BIKE_Easy_12', 60, false, 0,
    'Z2 endurance @175-190W, cadence drills: alternate 80/100rpm every 5min');

  -- Thursday: run easy
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w5_id, 'Thursday', 'run', 'Easy', 'RUN_Easy_07', 45, false, 0,
    '8k easy @5:20/km');

  -- Friday: bike easy + swim easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w5_id, 'Friday', 'bike', 'Easy', 'BIKE_Easy_13', 50, false, 0,
    'Easy @160-175W');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w5_id, 'Friday', 'swim', 'Easy', 'SWIM_Easy_06', 35, false, 1,
    '1.5k technique/drills');

  -- Saturday: long outdoor bike with threshold climbs
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w5_id, 'Saturday', 'bike', 'Tempo', 'BIKE_Tempo_15', 180, false, 0,
    '3h outdoor — 75km, 500-600m D+, mostly Z2 @175-185W, include 2x8min @260-275W (threshold) on steepest climbs');

  -- Sunday: brick (bike tempo + run easy)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w5_id, 'Sunday', 'bike', 'Tempo', 'BIKE_Tempo_12', 50, true, 0,
    'Brick bike: 30min @180W Z2 → last 20min @220-240W / 80-87% FTP');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w5_id, 'Sunday', 'run', 'Easy', 'RUN_Easy_13', 65, true, 1,
    'Brick run: 12k @5:10-5:20/km all easy — focus on running relaxed off pre-fatigued legs, practice nutrition');

  -- ---------------------------------------------------------------------------
  -- WEEK 6 (Apr 27 - May 3) — 12 sessions
  -- ---------------------------------------------------------------------------

  -- Monday: swim tempo + strength (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w6_id, 'Monday', 'swim', 'Tempo', 'SWIM_Tempo_12', 55, false, 0,
    '400 warmup, 5x200m @1:52 CSS (20s rest), 200 cooldown');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w6_id, 'Monday', 'strength', 'Easy', 'STRENGTH_Easy_01', 30, false, 1,
    'Core/strength 30min');

  -- Tuesday: run easy + swim easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w6_id, 'Tuesday', 'run', 'Easy', 'RUN_Easy_14', 60, false, 0,
    '11k easy @5:15-5:25/km (HR <140)');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w6_id, 'Tuesday', 'swim', 'Easy', 'SWIM_Easy_06', 35, false, 1,
    '1.5k easy @2:15/100m');

  -- Wednesday: bike intervals + run easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w6_id, 'Wednesday', 'bike', 'Intervals', 'BIKE_Intervals_11', 60, false, 0,
    '10min warmup, 5x4min @295-310W (VO2max) w/ 3min easy, 10min cooldown');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w6_id, 'Wednesday', 'run', 'Easy', 'RUN_Easy_09', 30, false, 1,
    '5k easy @5:30/km');

  -- Thursday: run easy
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w6_id, 'Thursday', 'run', 'Easy', 'RUN_Easy_07', 45, false, 0,
    '8k easy @5:25/km');

  -- Friday: bike easy + swim easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w6_id, 'Friday', 'bike', 'Easy', 'BIKE_Easy_13', 50, false, 0,
    'Easy @160-175W');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w6_id, 'Friday', 'swim', 'Easy', 'SWIM_Easy_09', 45, false, 1,
    '2k drills (catch-up, sculling, bilateral breathing)');

  -- Saturday: long outdoor bike — race nutrition test
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w6_id, 'Saturday', 'bike', 'Easy', 'BIKE_Easy_09', 210, false, 0,
    '3h30 outdoor — 90km, 700-800m D+, avg 175-185W (Z2). Test race nutrition: gels/drink mix, 60-80g carbs/h');

  -- Sunday: brick (bike tempo + run tempo)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w6_id, 'Sunday', 'bike', 'Tempo', 'BIKE_Tempo_12', 50, true, 0,
    'Brick bike: 30min @180W Z2 → last 20min @240-260W / 87-95% FTP');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w6_id, 'Sunday', 'run', 'Tempo', 'RUN_Tempo_20', 75, true, 1,
    'Brick run: 10k @5:10/km easy, last 4k @4:10/km (threshold) — simulate race finish push');

  -- ---------------------------------------------------------------------------
  -- WEEK 7 (May 4-10) — KEY WEEK — 12 sessions
  -- ---------------------------------------------------------------------------

  -- Monday: swim intervals + strength (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w7_id, 'Monday', 'swim', 'Intervals', 'SWIM_Intervals_12', 60, false, 0,
    '400 warmup, 6x200m @1:50 (15s rest), 200 cooldown');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w7_id, 'Monday', 'strength', 'Easy', 'STRENGTH_Easy_01', 30, false, 1,
    'Core 30min');

  -- Tuesday: run intervals + swim easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w7_id, 'Tuesday', 'run', 'Intervals', 'RUN_Intervals_20', 65, false, 0,
    '2km warmup, 5x4min @3:25/km (VO2max) w/ 3min jog, 2km cooldown');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w7_id, 'Tuesday', 'swim', 'Easy', 'SWIM_Easy_06', 35, false, 1,
    '1.5k easy @2:15/100m');

  -- Wednesday: run easy (strides day)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w7_id, 'Wednesday', 'run', 'Easy', 'RUN_Easy_10', 35, false, 0,
    '6k easy @5:30/km + 6x100m strides');

  -- Thursday: bike easy (Z2 endurance)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w7_id, 'Thursday', 'bike', 'Easy', 'BIKE_Easy_12', 60, false, 0,
    'Z2 endurance @175-190W, steady cadence 85-90rpm');

  -- Friday: bike easy + swim easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w7_id, 'Friday', 'bike', 'Easy', 'BIKE_Easy_13', 50, false, 0,
    'Easy @160-175W');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w7_id, 'Friday', 'swim', 'Easy', 'SWIM_Easy_06', 35, false, 1,
    '1.5k easy @2:15/100m');

  -- Saturday: first 100km outdoor ride
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w7_id, 'Saturday', 'bike', 'Easy', 'BIKE_Easy_10', 240, false, 0,
    '4h outdoor — 100km, 800-900m D+, avg 175-185W (Z2). Eat 60-80g carbs/h. Time in the saddle, not power.');

  -- Sunday: brick (bike tempo + run tempo) + swim easy (triple)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w7_id, 'Sunday', 'bike', 'Tempo', 'BIKE_Tempo_12', 50, true, 0,
    'Brick bike: 25min @180W Z2 → last 25min @240-260W / 87-95% FTP');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w7_id, 'Sunday', 'run', 'Tempo', 'RUN_Tempo_20', 87, true, 1,
    'Brick run: 10k @5:10/km easy, last 6k @4:15/km (threshold) — longest race-sim run off pre-fatigued legs');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w7_id, 'Sunday', 'swim', 'Easy', 'SWIM_Easy_06', 45, false, 2,
    '2k easy @2:20/100m');

  -- ---------------------------------------------------------------------------
  -- WEEK 8 (May 11-17) — PEAK VOLUME — 11 sessions
  -- ---------------------------------------------------------------------------

  -- Monday: swim intervals + strength (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w8_id, 'Monday', 'swim', 'Intervals', 'SWIM_Intervals_11', 60, false, 0,
    '400 warmup, 8x150m @1:48 (fast, 15s rest), 300 cooldown');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w8_id, 'Monday', 'strength', 'Easy', 'STRENGTH_Easy_01', 30, false, 1,
    'Core 30min');

  -- Tuesday: run intervals + swim easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w8_id, 'Tuesday', 'run', 'Intervals', 'RUN_Intervals_19', 60, false, 0,
    '2km warmup, 6x3min @3:20/km (VO2max) w/ 2min jog, 2km cooldown');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w8_id, 'Tuesday', 'swim', 'Easy', 'SWIM_Easy_06', 45, false, 1,
    '2k easy @2:15/100m');

  -- Wednesday: run easy
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w8_id, 'Wednesday', 'run', 'Easy', 'RUN_Easy_10', 35, false, 0,
    '6k easy @5:30/km');

  -- Thursday: bike easy (save legs)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w8_id, 'Thursday', 'bike', 'Easy', 'BIKE_Easy_12', 60, false, 0,
    'Z2 endurance @175-190W, save legs for Sat+Sun');

  -- Friday: bike easy + swim easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w8_id, 'Friday', 'bike', 'Easy', 'BIKE_Easy_02', 45, false, 0,
    'Easy @160-175W');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w8_id, 'Friday', 'swim', 'Easy', 'SWIM_Easy_06', 35, false, 1,
    '1.5k easy @2:15/100m');

  -- Saturday: full 90km race sim
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w8_id, 'Saturday', 'bike', 'Easy', 'BIKE_Easy_10', 240, false, 0,
    '4h outdoor — FULL 90km RACE SIM. Find route with ~739m D+. Full race nutrition protocol: 60-80g carbs/h. Z2 ride, do NOT race it.');

  -- Sunday: brick (bike tempo + run tempo)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w8_id, 'Sunday', 'bike', 'Tempo', 'BIKE_Tempo_13', 40, true, 0,
    'Brick bike: 15min @180W Z2 → last 25min @240-260W / 87-95% FTP');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w8_id, 'Sunday', 'run', 'Tempo', 'RUN_Tempo_20', 95, true, 1,
    'Brick run: 12k @5:10/km easy, last 6k @4:15/km (threshold) — can you hold threshold off truly fatigued legs for 6k?');

  -- ---------------------------------------------------------------------------
  -- WEEK 9 (May 18-24) — Pre-Taper — 10 sessions
  -- ---------------------------------------------------------------------------

  -- Monday: swim tempo (OW if possible)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w9_id, 'Monday', 'swim', 'Tempo', 'SWIM_Tempo_13', 50, false, 0,
    'OW if possible. 400 easy, 4x200m @1:52 CSS (20s rest), 200 easy. Practice sighting.');

  -- Tuesday: run easy + swim easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w9_id, 'Tuesday', 'run', 'Easy', 'RUN_Easy_07', 45, false, 0,
    '8k easy @5:20/km');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w9_id, 'Tuesday', 'swim', 'Easy', 'SWIM_Easy_06', 35, false, 1,
    '1.5k easy @2:15/100m');

  -- Wednesday: bike intervals (short & sharp)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w9_id, 'Wednesday', 'bike', 'Intervals', 'BIKE_Intervals_12', 60, false, 0,
    '10min warmup, 4x4min @295-310W (VO2max) w/ 3min easy, 15min cooldown — short and sharp');

  -- Thursday: run easy
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w9_id, 'Thursday', 'run', 'Easy', 'RUN_Easy_10', 35, false, 0,
    '6k easy @5:30/km');

  -- Friday: swim easy (OW — wetsuit comfort)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w9_id, 'Friday', 'swim', 'Easy', 'SWIM_Easy_06', 45, false, 0,
    '2k easy OW (practice sighting, current awareness, wetsuit comfort)');

  -- Saturday: mini brick + swim easy (triple)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w9_id, 'Saturday', 'bike', 'Tempo', 'BIKE_Tempo_14', 30, true, 0,
    'Brick bike: 10min @180W Z2 → last 20min @240-255W / 87-93% FTP');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w9_id, 'Saturday', 'run', 'Tempo', 'RUN_Tempo_19', 30, true, 1,
    'Brick run: 2k @5:15/km easy, 3k @4:10/km (race pace+) — just a taste');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w9_id, 'Saturday', 'swim', 'Easy', 'SWIM_Easy_06', 35, false, 2,
    '1.5k easy');

  -- Sunday: easy outdoor ride (keep legs fresh)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w9_id, 'Sunday', 'bike', 'Easy', 'BIKE_Easy_07', 120, false, 0,
    '2h outdoor — 50km, 300-400m D+, avg 175-185W (Z2, enjoy the ride, keep legs fresh)');

  -- ---------------------------------------------------------------------------
  -- WEEK 10 (May 25-31) — TAPER + RACE — 8 sessions
  -- ---------------------------------------------------------------------------

  -- Monday: swim easy + run easy (double)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w10_id, 'Monday', 'swim', 'Easy', 'SWIM_Easy_08', 35, false, 0,
    '1.5k — 400 warmup, 4x100m @1:55 (feeling the water), 300 cooldown');
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w10_id, 'Monday', 'run', 'Easy', 'RUN_Easy_09', 30, false, 1,
    '5k easy @5:25/km + 4x100m strides');

  -- Tuesday: bike easy (openers)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w10_id, 'Tuesday', 'bike', 'Easy', 'BIKE_Easy_11', 40, false, 0,
    '15min warmup @165W, 2x5min @230W (opener, NOT threshold), 10min cooldown @160W');

  -- Wednesday: run easy (shakeout)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w10_id, 'Wednesday', 'run', 'Easy', 'RUN_Easy_11', 25, false, 0,
    '4k easy @5:30/km + 4 strides');

  -- Thursday: bike easy (leg activation)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w10_id, 'Thursday', 'bike', 'Easy', 'BIKE_Easy_15', 30, false, 0,
    '30min easy @160W + 4x20s high-cadence sprints (leg activation)');

  -- Friday: swim easy (OW — wetsuit check)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w10_id, 'Friday', 'swim', 'Easy', 'SWIM_Easy_06', 25, false, 0,
    '1k OW easy — sight practice, feel the water, wetsuit check');

  -- Saturday: jog + strides (rack bike, prep nutrition)
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w10_id, 'Saturday', 'run', 'Easy', 'RUN_Easy_12', 15, false, 0,
    '15min jog + 4 strides. Rack bike. Prep nutrition. Early sleep.');

  -- Sunday: RACE DAY
  INSERT INTO plan_sessions (week_id, day, sport, type, template_id, duration_minutes, is_brick, order_in_day, notes)
  VALUES (v_w10_id, 'Sunday', 'race', 'Race', 'RACE_Race_01', 300, false, 0,
    'RACE — Triathlon Monumental Nîmes Pont du Gard');

  RAISE NOTICE 'Seed complete. Plan ID: %', v_plan_id;

END $$;
