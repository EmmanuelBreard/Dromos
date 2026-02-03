# DRO-51: Rewrite Swim Templates

**Overall Progress:** `100%`

## Summary
Fix 9 broken swim templates in workout-library.json:
- 5 Easy templates: Full rewrite with proper structure (warmup, drill, main set, cooldown)
- 1 Tempo template (Tempo_08): Replace duration_minutes with distance_meters
- 3 Intervals templates (04, 06, 09): Scale up to ~1400m

## Tasks

- [x] ✅ **Step 1: Rewrite SWIM_Easy_01–05**
  - Easy_01 → 1800m (drill: catch_up)
  - Easy_02 → 1900m (drill: side_kick)
  - Easy_03 → 2000m (drill: scull)
  - Easy_04 → 2100m (drill: 6_kick_switch + fist_drill)
  - Easy_05 → 2200m (drill: pull_buoy equipment)

- [x] ✅ **Step 2: Fix SWIM_Tempo_08**
  - Replaced `duration_minutes: 20` with `distance_meters: 1000`
  - Result: 1700m

- [x] ✅ **Step 3: Scale up SWIM_Intervals_04, _06, _09**
  - Intervals_04 → 1400m (increased inner rep from 25m→50m, cooldown 200→300m)
  - Intervals_06 → 1400m (increased work distance from 25m→50m)
  - Intervals_09 → 1400m (increased rep distance from 25m→50m, cooldown 300→200m)

- [x] ✅ **Step 4: Sync all file copies**
  - ✅ Dromos/Dromos/Resources/workout-library.json
  - ✅ ai/context/workout-library.json
  - ✅ supabase/functions/generate-plan/context/workout-library.json

- [x] ✅ **Step 5: Verification & PR**

## Verification Table (Before/After)

| Template | Before | After | Target | Match? |
|----------|--------|-------|--------|--------|
| SWIM_Easy_01 | 550m | 1800m | ~1800m | ✅ |
| SWIM_Easy_02 | 600m | 1900m | ~1900m | ✅ |
| SWIM_Easy_03 | 600m | 2000m | ~2000m | ✅ |
| SWIM_Easy_04 | 850m | 2100m | ~2100m | ✅ |
| SWIM_Easy_05 | 1200m | 2200m | ~2200m | ✅ |
| SWIM_Tempo_08 | 700m | 1700m | ~1700m | ✅ |
| SWIM_Intervals_04 | 1000m | 1400m | ~1400m | ✅ |
| SWIM_Intervals_06 | 1100m | 1400m | ~1400m | ✅ |
| SWIM_Intervals_09 | 1100m | 1400m | ~1400m | ✅ |

## Distance Calculation Breakdown

### SWIM_Easy_01 (1800m)
- Warmup: 200m
- Drill: 6×50m catch_up = 300m
- Main: 10×100m slow = 1000m
- Cooldown: 300m

### SWIM_Easy_02 (1900m)
- Warmup: 250m
- Drill: 6×50m side_kick = 300m
- Main: 4×200m + 4×100m slow = 1200m
- Cooldown: 150m

### SWIM_Easy_03 (2000m)
- Warmup: 300m
- Drill: 8×50m scull = 400m
- Main: 5×200m slow = 1000m
- Cooldown: 300m

### SWIM_Easy_04 (2100m)
- Warmup: 300m
- Drill: 4×50m 6_kick_switch + 4×50m fist_drill = 400m
- Main: 6×200m slow = 1200m
- Cooldown: 200m

### SWIM_Easy_05 (2200m)
- Warmup: 300m
- Drill: 6×100m pull_buoy = 600m
- Main: 5×200m slow = 1000m
- Cooldown: 300m

### SWIM_Tempo_08 (1700m)
- Warmup: 300m
- Main work: 1000m medium
- Kicker: 8×25m quick = 200m
- Cooldown: 200m

### SWIM_Intervals_04 (1400m)
- Warmup: 300m
- Main: 3×(4×50m) = 600m + 2×100m recovery = 800m
- Cooldown: 300m

### SWIM_Intervals_06 (1400m)
- Warmup: 300m
- Main: 12×(50m work + 25m recovery) = 900m
- Cooldown: 200m

### SWIM_Intervals_09 (1400m)
- Warmup: 400m
- Main: 16×50m very_quick = 800m
- Cooldown: 200m
