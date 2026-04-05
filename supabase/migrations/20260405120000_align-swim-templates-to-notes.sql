-- UP: Align swim session template_ids to match session notes (notes = truth)
-- Scoped to emmanuel's plan only.

-- W3 Mon: 2.5k with pull set (500wu + 8x150m fast 20s + 4x100m pull 20s + 400cd)
-- Reassign from SWIM_Intervals_11 (1.9k, missing pull set) to new SWIM_Intervals_15
UPDATE plan_sessions ps
SET template_id = 'SWIM_Intervals_15',
    duration_minutes = 60
FROM plan_weeks pw
JOIN training_plans tp ON tp.id = pw.plan_id
JOIN public.users u ON u.id = tp.user_id
WHERE ps.week_id = pw.id
  AND pw.week_number = 3
  AND ps.day = 'Monday'
  AND ps.sport = 'swim'
  AND u.email = 'ebreard4@gmail.com';

-- W4 Mon: 2k easy pull (was SWIM_Easy_06 = 1.5k, 35min)
UPDATE plan_sessions ps
SET template_id = 'SWIM_Easy_13',
    duration_minutes = 45
FROM plan_weeks pw
JOIN training_plans tp ON tp.id = pw.plan_id
JOIN public.users u ON u.id = tp.user_id
WHERE ps.week_id = pw.id
  AND pw.week_number = 4
  AND ps.day = 'Monday'
  AND ps.sport = 'swim'
  AND u.email = 'ebreard4@gmail.com';

-- W7 Sun: 2k easy pull (was SWIM_Easy_06 = 1.5k)
UPDATE plan_sessions ps
SET template_id = 'SWIM_Easy_13',
    duration_minutes = 45
FROM plan_weeks pw
JOIN training_plans tp ON tp.id = pw.plan_id
JOIN public.users u ON u.id = tp.user_id
WHERE ps.week_id = pw.id
  AND pw.week_number = 7
  AND ps.day = 'Sunday'
  AND ps.sport = 'swim'
  AND u.email = 'ebreard4@gmail.com';

-- W8 Mon: 1.9k simple intervals, 15s rest (was SWIM_Intervals_11 with 20s rest)
UPDATE plan_sessions ps
SET template_id = 'SWIM_Intervals_16',
    duration_minutes = 60
FROM plan_weeks pw
JOIN training_plans tp ON tp.id = pw.plan_id
JOIN public.users u ON u.id = tp.user_id
WHERE ps.week_id = pw.id
  AND pw.week_number = 8
  AND ps.day = 'Monday'
  AND ps.sport = 'swim'
  AND u.email = 'ebreard4@gmail.com';

-- W8 Tue: 2k easy pull (was SWIM_Easy_06 = 1.5k, 35min)
UPDATE plan_sessions ps
SET template_id = 'SWIM_Easy_13',
    duration_minutes = 45
FROM plan_weeks pw
JOIN training_plans tp ON tp.id = pw.plan_id
JOIN public.users u ON u.id = tp.user_id
WHERE ps.week_id = pw.id
  AND pw.week_number = 8
  AND ps.day = 'Tuesday'
  AND ps.sport = 'swim'
  AND u.email = 'ebreard4@gmail.com';

-- W9 Fri: 2k easy OW (was SWIM_Easy_06 = 1.5k)
UPDATE plan_sessions ps
SET template_id = 'SWIM_Easy_13',
    duration_minutes = 45
FROM plan_weeks pw
JOIN training_plans tp ON tp.id = pw.plan_id
JOIN public.users u ON u.id = tp.user_id
WHERE ps.week_id = pw.id
  AND pw.week_number = 9
  AND ps.day = 'Friday'
  AND ps.sport = 'swim'
  AND u.email = 'ebreard4@gmail.com';

-- W10 Fri: 1k OW easy (was SWIM_Easy_06 = 1.5k)
UPDATE plan_sessions ps
SET template_id = 'SWIM_Easy_14',
    duration_minutes = 25
FROM plan_weeks pw
JOIN training_plans tp ON tp.id = pw.plan_id
JOIN public.users u ON u.id = tp.user_id
WHERE ps.week_id = pw.id
  AND pw.week_number = 10
  AND ps.day = 'Friday'
  AND ps.sport = 'swim'
  AND u.email = 'ebreard4@gmail.com';

-- DOWN: Restore original assignments
-- (reverse of above — keep this for rollback reference)
-- UPDATE plan_sessions ps SET template_id = 'SWIM_Intervals_11', duration_minutes = 60
--   FROM plan_weeks pw JOIN training_plans tp ON tp.id = pw.plan_id JOIN public.users u ON u.id = tp.user_id
--   WHERE ps.week_id = pw.id AND pw.week_number = 3 AND ps.day = 'Monday' AND ps.sport = 'swim' AND u.email = 'ebreard4@gmail.com';
-- (add similar reversal for each UPDATE above)
