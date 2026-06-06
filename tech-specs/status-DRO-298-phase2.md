# Status Report — DRO-298 Phase 2: Workout Library High-Fidelity Templates

**Branch:** `feature/DRO-298-workout-library-templates`
**PR:** → `feature/DRO-296-import-olympic-plan`
**Date:** 2026-06-06

---

## 1. Templates Added

| Sport     | Before | After | Added |
|-----------|--------|-------|-------|
| Bike      | 55     | 65    | +10   |
| Run       | 70     | 80    | +10   |
| Swim      | 45     | 53    | +8    |
| Race      | 2      | 3     | +1    |
| Strength  | 0      | 1     | +1    |
| **Total** |        |       | **30** |

### Bike (10 templates)
- `BIKE_Z2_endurance_90min` — single 90min Z2 with `ftp_pct_min/max` 65-75 + `hr_pct_max_max` 78, cadence 85
- `BIKE_SS_4x6min_245W` — 15min warmup + 4×(6min sweetspot `ftp_pct` 88-93 + 4min recovery) + 10min cooldown
- `BIKE_THR_2x15min_260W` — 15min warmup + 2×(15min @ `power_watts` 260 + 8min recovery) + 10min cooldown
- `BIKE_VO2_5x3min_290W` — 15min warmup + 5×(3min @ `power_watts_min/max` 290-300 + 3min recovery) + 10min cooldown
- `BIKE_VO2_5x4min_290W` — 15min warmup + 5×(4min @ `power_watts` 290 + 3min recovery) + 10min cooldown
- `BIKE_OU_2x10min_95_110` — 15min warmup + 2×(nested 3×(1min 110% + 3min 95%) + 6min recovery) + 10min cooldown
- `BIKE_RACE_40min_IF85` — 15min warmup + 40min @ `power_watts_min/max` 230-235 + 10min cooldown
- `BIKE_BRICK_75min_IF85` — 15min warmup + 40min @ `power_watts_min/max` 230-235 + 20min cooldown
- `BIKE_VO2_3x6min_295W` — 15min warmup + 3×(6min @ `power_watts` 295 + 4min recovery) + 10min cooldown
- `BIKE_OPENER_45min_3x3min` — 15min warmup + 3×(3min @ `power_watts` 295 + 3min recovery) + 12min cooldown

### Run (10 templates)
- `RUN_Z2_long_cap150bpm` — 75min single segment `hr_pct_max_max` 78
- `RUN_Z2_easy_cap140bpm` — 45min single segment `hr_pct_max_max` 73
- `RUN_TEMPO_4x4min_4_15km` — 15min warmup + 4×(4min @ `pace_per_km` "4:15" + 2min HR-capped recovery) + 10min cooldown
- `RUN_VO2_5x400m_3_35km` — 15min warmup + 5×(400m @ "3:35" + 400m jog distance recovery) + 10min cooldown
- `RUN_VO2_5x600m_3_45km` — 15min warmup + 5×(600m @ "3:45" + 90s rest) + 10min cooldown
- `RUN_VO2_4x800m_3_40km` — 15min warmup + 4×(800m @ "3:40" + 400m jog recovery) + 10min cooldown
- `RUN_VO2_5x800m_3_40km` — same as 4× version, ×5
- `RUN_RACE_4x1km_4_00km` — 15min warmup + 4×(1km @ "4:00" + 90s rest) + 4×(200m strides @ "3:20") + 10min cooldown
- `RUN_THR_3x10min_4_22km` — 15min warmup + 3×(10min @ "4:22" + 5min recovery) + 10min cooldown
- `RUN_BRICK_25min_15rp_10z2` — 15min @ "4:00" + 10min Z2 cooldown (no warmup — off-bike)

### Swim (8 templates)
- `SWIM_Z2_endurance_2500m` — single 2500m `pace: "easy"`
- `SWIM_THR_6x150_1_50` — 300m warmup + 6×(150m @ `pace_per_100m` "1:50" + 30s rest) + 200m cooldown
- `SWIM_CSS_8x100_1_45` — 400m warmup + 8×(100m @ "1:45" + 20s rest) + 200m cooldown
- `SWIM_RACE_2x750_1_48` — 300m warmup + 2×(750m @ "1:48" + 60s rest) + 200m cooldown
- `SWIM_VO2_8x50_fast` — 400m warmup + 8×(50m `pace: "fast"` + 15s rest) + 200m cooldown
- `SWIM_OPENER_1500m_race_pace` — 400m warmup + 1500m @ "1:48" + 200m cooldown
- `SWIM_TT_1500m` — 300m warmup + 1500m @ "1:45" TT + 200m cooldown
- `SWIM_DRILLS_1800m` — 300m warmup + 1000m drill mix (`label: "drill"`, `pace: "easy"`) + 500m steady

### Race (1 template)
- `RACE_OLYMPIC` — Full Olympic triathlon: swim 1500m → T1 → bike 40km @ 82% FTP → T2 → run 10km @ "4:10/km"

### Strength (1 template)
- `STRENGTH_NOTES_ONLY` — `template_id: "STRENGTH_NOTES_ONLY"`, `duration_minutes: 30`, `segments: []`

---

## 2. Deviations from Spec

### Materializer modified (FLAG)
The spec required `pace_per_km` and `pace_per_100m` as recognized `SourceSegment` fields. These were **not present** in the Phase 1 materializer — only the `pace` string (swim tag) existed.

**Changes made to `materialize-structure.ts`:**
1. Added `pace_per_km?: string` and `pace_per_100m?: string` to `SourceSegment` interface
2. Added range fields: `ftp_pct_min/max`, `hr_pct_max_min/max`, `power_watts`, `power_watts_min/max`
3. Extended `resolveTarget()` with priority-ordered resolution for all new fields
4. Added JSDoc update explaining Phase 2 extensions

This is an **additive, backward-compatible change** — all existing templates and tests pass unchanged.

### BIKE_Z2 HR cap representation
The spec says "single 90min Z2 segment with `ftp_pct` range 65-75 + `hr_pct_max` cap (max 78)". A segment can only materialise to one `Target`. Implemented as `ftp_pct_min/max` 65-75 for the primary target. **The `hr_pct_max_max: 78` field that was originally added as a secondary field has been removed in fix1** — the materializer does NOT preserve unpaired `_max` fields: when `hr_pct_max_max` is set without `hr_pct_max_min`, the range branch is skipped silently and the field is lost in the materialized output. The `cue` text carries the HR cap constraint: "ftp_pct 65-75%, cap HR at 78% HRmax (~150 bpm)".

### SWIM_DRILLS_1800m label field
The spec says use `label: "drill"`. The segment is a flat `drill` label on a 1000m block. This is correct — the materializer validates against the known label set and `"drill"` is valid.

---

## 3. Test Output

```
running 35 tests from ./supabase/functions/_shared/__tests__/materialize-structure.test.ts
... (all 35 tests) ...
ok | 35 passed | 0 failed (3ms)
```

New tests added (14):
- `hr_pct_max: single value`
- `hr_pct_max: min+max range form`
- `hr_zone: value 1 (lower boundary)`
- `hr_zone: value 5 (upper boundary)`
- `hr_zone: input 0 clamps to 1`
- `hr_zone: input 6 clamps to 5`
- `power_watts: single value`
- `power_watts: min+max range form`
- `pace_per_km: string passthrough`
- `pace_per_100m: string passthrough`
- `distance interval: work 400m + distance recovery 400m`
- `nested repeats with HR children: BIKE_OU over-under structure`
- `STRENGTH_NOTES_ONLY: materialises to { segments: [] }`
- `ftp_pct: min+max range form`

---

## 4. PR URL + Title

*To be filled once PR is created.*

---

## 5. Linear Status

DRO-298 updated to **In Review**.

---

## 4. Fix 1 Summary (Code Review DRO-298)

**Branch:** `feature/DRO-298-workout-library-templates`
**Date:** 2026-06-06

Changes applied:

### Critical fixes
- `RUN_Z2_easy_cap140bpm`: Added `hr_pct_max_min: 50` to pair with `hr_pct_max_max: 73` — unpaired `_max` alone was silently dropped by materializer
- `RUN_Z2_long_cap150bpm`: Added `hr_pct_max_min: 65` (Z2 band) to pair with `hr_pct_max_max: 78`
- `BIKE_Z2_endurance_90min`: Removed orphan `hr_pct_max_max: 78` — materializer cannot layer two targets; `ftp_pct_min/max` 65-75 is the primary target; HR cap moved to `cue` text
- `RUN_TEMPO_4x4min_4_15km` (recovery sub-segment): Added `hr_pct_max_min: 50` to pair
- `RUN_BRICK_25min_15rp_10z2` (cooldown): Added `hr_pct_max_min: 50` to pair

### High fixes
- `RACE_OLYMPIC`: Removed `duration_minutes` from swim/bike/run work segments (distance is authoritative for race segments); top-level `duration_minutes` set to 132

### Other fixes
- `BIKE_OU_2x10min_95_110`: Renamed to `BIKE_OU_2x12min_95_110` (actual inner set is 2×12min); inner "under" segment label `recovery` → `work` (95% FTP is high tempo); `duration_minutes` corrected to 61
- `BIKE_VO2_5x3min_290W`: Renamed to `BIKE_VO2_5x3min_295W` (average of 290-300W range)
- `BIKE_SS_4x6min_245W`: `duration_minutes` 59 → 65
- `BIKE_THR_2x15min_260W`: `duration_minutes` 63 → 71
- `BIKE_VO2_3x6min_295W`: `duration_minutes` 57 → 55
- `RUN_TEMPO_4x4min_4_15km`: `duration_minutes` 51 → 49
- `RUN_THR_3x10min_4_22km`: `duration_minutes` 60 → 70
- Template count corrected to **30** (not 35)

### Tests added (issue #5)
7 new negative tests pinning the silent-drop contract for unpaired `_min`/`_max` fields:
- `hr_pct_max: only _max set` → undefined
- `hr_pct_max: only _min set` → undefined
- `ftp_pct: only _min set` → undefined
- `ftp_pct: only _max set` → undefined
- `power_watts: only _min set` → undefined
- `power_watts: only _max set` → undefined
- `hr_pct_max: legacy single-value still works` (positive regression)

Also fixed existing BIKE_OU test: inner "under" segment asserts `label="work"` (not "recovery").

Total tests: **42** (35 existing + 7 new)
