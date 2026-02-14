# DRO-69: Add 15 Classic Interval Running Sessions

**Overall Progress:** `100%`

## TLDR
Add 15 proven interval running sessions (from Running Romand Magazine) to the workout library. Main-set segments use distance-based format (`distance_meters`) while warmup/cooldown stay time-based. All 3 copies of `workout-library.json` must be synced. A new `name` field is added to each template for future UI use.

## Critical Decisions
- **Distance-based main sets**: Work segments use `distance_meters` + `mas_pct` instead of `duration_minutes` — schema already supports this via `WorkoutSegment.distanceMeters`
- **Time-based warmup/cooldown**: ~10min warmup (65% MAS) + ~5-10min cooldown (65% MAS) added to every session (article only describes main sets)
- **Top-level `duration_minutes`**: Computed using reference paces (easy=11, 10K=14, VMA=18 km/h) including warmup+cooldown — required by `buildSimplifiedLibrary()`
- **`mas_pct` follows existing convention**: Easy=70%, Tempo=85-90%, Intervals=95-112% (NOT the reference-pace-derived percentages, which are only for duration conversion)
- **Only existing types**: All sessions mapped to Intervals (8) or Tempo (7) — no new types
- **`name` field added**: Swift `WorkoutTemplate` ignores unknown fields; will be used in frontend later (DRO-73)
- **iOS distance UI deferred**: DRO-73 tracks rendering `distance_meters` in run segment UI

## Reference: Pace-to-Duration Conversion Table

| Zone | Speed | Pace/km | MAS% |
|------|-------|---------|------|
| Easy | 11 km/h | 5:27 | 65-70% |
| Marathon | ~12.5 km/h | 4:48 | ~69% |
| Half-marathon | ~13.5 km/h | 4:27 | ~75% |
| 10K | 14 km/h | 4:17 | ~78% |
| Threshold | ~15.5 km/h | 3:52 | ~86% |
| VMA | 18 km/h | 3:20 | 100% |

## Template ID Mapping

| # | Session Name | Type | Template ID |
|---|-------------|------|-------------|
| 1 | Bernard Brun | Intervals | `RUN_Intervals_11` |
| 2 | Pyramide | Intervals | `RUN_Intervals_12` |
| 3 | Billat | Intervals | `RUN_Intervals_13` |
| 4 | Super-10K | Intervals | `RUN_Intervals_14` |
| 5 | Fartlek | Intervals | `RUN_Intervals_15` |
| 6 | 1000 | Intervals | `RUN_Intervals_16` |
| 7 | Colline | Intervals | `RUN_Intervals_17` |
| 8 | Zatopek | Intervals | `RUN_Intervals_18` |
| 9 | Viktor Röthlin | Tempo | `RUN_Tempo_11` |
| 10 | Pierre Morath | Tempo | `RUN_Tempo_12` |
| 11 | Progressive Marathon | Tempo | `RUN_Tempo_13` |
| 12 | Endurance Kényane | Tempo | `RUN_Tempo_14` |
| 13 | 10 Miles | Tempo | `RUN_Tempo_15` |
| 14 | 3x3 | Tempo | `RUN_Tempo_16` |
| 15 | Demi-10K | Tempo | `RUN_Tempo_17` |

## Tasks

- [x] :white_check_mark: **Step 1: Build the 15 workout templates in JSON**
  - [x] :white_check_mark: Create 8 Intervals templates (RUN_Intervals_11 to _18) with `name`, `template_id`, `duration_minutes`, and `segments[]`
  - [x] :white_check_mark: Create 7 Tempo templates (RUN_Tempo_11 to _17) with same structure
  - [x] :white_check_mark: Each template: time-based warmup (10min, 65% MAS) + distance-based main set (`distance_meters` + `mas_pct`) + time-based cooldown (5-10min, 65% MAS)
  - [x] :white_check_mark: Compute top-level `duration_minutes` for each using reference pace table (include warmup+cooldown)
  - [x] :white_check_mark: Variable-duration sessions: Fartlek ~40min, Pyramide ~35min, Kényane ~45min (total including warmup/cooldown)

- [x] :white_check_mark: **Step 2: Add templates to `ai/context/workout-library.json`**
  - [x] :white_check_mark: Append 8 Intervals templates to `run` array after existing `RUN_Intervals_10`
  - [x] :white_check_mark: Append 7 Tempo templates to `run` array after existing `RUN_Tempo_10`

- [x] :white_check_mark: **Step 3: Sync all 3 copies**
  - [x] :white_check_mark: Copy updated file to `Dromos/Dromos/Resources/workout-library.json`
  - [x] :white_check_mark: Copy updated file to `supabase/functions/generate-plan/context/workout-library.json`

- [x] :white_check_mark: **Step 4: Validate**
  - [x] :white_check_mark: Verify JSON parses correctly (no syntax errors)
  - [x] :white_check_mark: Verify `buildSimplifiedLibrary()` output includes all 15 new templates with correct type and duration
  - [x] :white_check_mark: Spot-check 2-3 templates: confirm `duration_minutes` math is correct vs reference paces
  - [x] :white_check_mark: Confirm total run template count = 41 (26 existing + 15 new)

## Implementation Notes

- **Actual existing count was 26** (10 Tempo + 10 Intervals + 6 Easy), not 30 as estimated. Total is 41, not 45.
- All 15 templates include `name` field for future DRO-73 UI use.
- Duration math spot-checked: Billat (42min), 3x3 (63min), Zatopek (65min) — all correct.
- All 3 file copies verified identical via `diff`.
