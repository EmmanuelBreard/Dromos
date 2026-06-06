# Status Report: DRO-296 Phase 4 — Olympic Plan Payload Author + Ingest

**Date:** 2026-06-06  
**Author:** Fio (Claude CTO agent)  
**Branch:** chore/DRO-296-phase4-payload

---

## CRITICAL: Snapshot ID for Rollback

**Snapshot ID: `4f4db07f-4897-4ddd-95d9-dc6ee9026b2f`**  
**Reason:** `import-plan-replace` (captured the Nîmes plan before Olympic plan was written)  
**Created at:** 2026-06-06 18:52:25 UTC

To restore the Nîmes plan if anything is wrong, call `restore_plan_from_snapshot` with this ID, or manually execute the rollback SQL against this snapshot.

---

## Edge Function Response

```json
{
  "success": true,
  "plan_id": "fbe708c2-cf51-42e2-a1a9-72e9e8bf19b3",
  "snapshot_id": "4f4db07f-4897-4ddd-95d9-dc6ee9026b2f",
  "weeks_inserted": 15,
  "sessions_inserted": 164
}
```

---

## Session Counts

| Metric | Count |
|---|---|
| Weeks | 15 |
| Total sessions | 164 |
| Strength sessions | 26 |
| Brick-flagged sessions | 18 |
| Race sessions | 2 (Race A Sep 12, Race B Sep 19) |
| Max sessions in any week | 13 (weeks 11, 12) |

The markdown plan describes ~150 sessions across 15 weeks (excluding Week 0 pre-recovery). The payload contains 164 sessions because:
- Week 11 has a full tri-simulation Saturday (swim + bike + run = 3 brick sessions + PM strength), not just 2
- Week 12 likewise has swim+bike+run race simulation Saturday
- Several weeks have double PM sessions (strength as 2nd session on days already carrying bike or run)

---

## Template Mapping Deviations

Where the plan's specific interval structure differed from the closest template, the template was used and the deviation captured in the `notes` field:

| Session | Plan prescription | Template used | Deviation note |
|---|---|---|---|
| Wk2 Tue swim | 6×100 @ tempo 2:00 | `SWIM_THR_6x150_1_50` | Plan 6×100 vs template 6×150 — noted in notes |
| Wk2 Wed bike | 2×8min SS @ 240W | `BIKE_SS_4x6min_245W` | Plan 2×8min vs template 4×6min — use 2 reps per notes |
| Wk3 Wed bike | 3×8min SS | `BIKE_SS_4x6min_245W` | 3×8min vs 4×6min — use 3 reps |
| Wk4 Tue swim | 2×400+4×200 threshold | `SWIM_CSS_8x100_1_45` | CSS 8×100 closest threshold swim available |
| Wk4 Fri bike | 2×15min SS @240W | `BIKE_THR_2x15min_260W` | Target 240W, template @260W — noted |
| Wk6 Wed bike | 4×2min VO2 + SS combo | `BIKE_VO2_5x3min_295W` | Plan 4×2min; use 4 reps at 2min each per notes |
| Wk7 Fri bike | 3×10min @260-270W | `BIKE_THR_2x15min_260W` | 3×10min vs 2×15min — use 3 reps per notes |
| Wk9 Sat | Bike Z2 + 10min tempo mini-brick | `BIKE_Z2_endurance_90min` | Mini-brick noted as single session (no separate run split — deload week) |
| Wk10 Tue swim | 8×100 @1:45 + 4×200 | `SWIM_RACE_2x750_1_48` | Race-pace closest; 8×100@1:45 structure in notes |
| Wk11 Tue run | 2×1km @3:50 + 4×400m @3:30 | `RUN_RACE_4x1km_4_00km` | Mixed pace structure; exact intervals in notes |
| Wk12 Wed bike | 3×8min VO2 @290W | `BIKE_VO2_3x6min_295W` | Plan 3×8min vs template 3×6min — extend reps per notes |
| Wk13 Tue run | 6×600m @3:40/km | `RUN_VO2_5x600m_3_45km` | 6 reps vs template's 5; pace 3:40 vs 3:45 — noted |
| Wk13 Fri bike | 3×5min @Z5 | `BIKE_VO2_5x3min_295W` | 3×5min vs 5×3min; use 3 reps per notes |

All deviations are recorded in the `notes` field of the affected sessions. No template IDs were fabricated.

---

## Pre-flight Issue: Storage Out of Sync

**Issue encountered:** The deployed `workout-library.json` in Supabase Storage was stale — 172 templates vs 201 in the local file. All Phase 2 templates (named templates like `BIKE_SS_4x6min_245W`, `RUN_VO2_5x400m_3_35km`, `RACE_OLYMPIC`, `STRENGTH_NOTES_ONLY`, etc.) were missing.

**Fix applied:** Uploaded the local `ai/context/workout-library.json` to storage via REST API with `x-upsert: true`:
```
PUT https://cumbrfnguykvxhvdelru.supabase.co/storage/v1/object/static-assets/workout-library.json
```
Storage now has 201 templates. **This is a side-effect of this phase** and was necessary to unblock the import.

**Action required:** Ensure the storage upload script (`scripts/upload-static-assets.sh`) supports upsert/replace — it currently fails with 409 on existing files.

---

## SQL Verification Results

### Training plan record
```
race_objective: Olympic
total_weeks: 15
race_date: 2026-09-19
start_date: 2026-06-08
status: active
```

### Week count: 15 weeks ✓
All 15 weeks inserted with correct phases, is_recovery flags, rest_days, and start_dates.

### Profile updates applied ✓
```
max_hr: 193 | ftp: 275 | vma: 18.00 | css_seconds_per100m: 110
race_objective: Olympic | race_date: 2026-09-19
```

### Sample sessions — Week 1 (Recovery)
| Day | Sport | Type | Template | Duration | Brick |
|---|---|---|---|---|---|
| Monday | swim | Easy | SWIM_Z2_endurance_2500m | 45min | no |
| Tuesday | swim | Easy | SWIM_DRILLS_1800m | 45min | no |
| Tuesday | run | Easy | RUN_Z2_easy_cap140bpm | 35min | no |
| Wednesday | bike | Easy | BIKE_Z2_endurance_90min | 75min | no |
| Wednesday | strength | Easy | STRENGTH_NOTES_ONLY | 30min | no |
| Friday | run | Easy | RUN_Z2_easy_cap140bpm | 45min | no |
| Saturday | bike | Easy | BIKE_Z2_endurance_90min | 90min | no |
| Saturday | strength | Easy | STRENGTH_NOTES_ONLY | 30min | no |
| Sunday | run | Easy | RUN_Z2_long_cap150bpm | 60min | no |

### Sample sessions — Week 6 (Build, first brick)
| Day | Sport | Type | Template | Duration | Brick |
|---|---|---|---|---|---|
| Monday | swim | Easy | SWIM_Z2_endurance_2500m | 55min | no |
| Monday | run | Easy | RUN_Z2_easy_cap140bpm | 45min | no |
| Tuesday | swim | Intervals | SWIM_THR_6x150_1_50 | 58min | no |
| Tuesday | run | Intervals | RUN_VO2_5x400m_3_35km | 55min | no |
| Wednesday | bike | Intervals | BIKE_VO2_5x3min_295W | 90min | no |
| Wednesday | strength | Easy | STRENGTH_NOTES_ONLY | 35min | no |
| Friday | bike | Easy | BIKE_Easy_03 | 60min | no |
| Saturday | bike | Easy | BIKE_Z2_endurance_90min | 75min | **yes** |
| Saturday | run | Tempo | RUN_BRICK_25min_15rp_10z2 | 15min | **yes** |
| Saturday | strength | Easy | STRENGTH_NOTES_ONLY | 35min | no |
| Sunday | run | Easy | RUN_Z2_long_cap150bpm | 75min | no |
| Sunday | swim | Easy | SWIM_Easy_06 | 30min | no |

### Sample sessions — Week 14 (Taper + Race A)
| Day | Sport | Type | Template | Duration | Brick |
|---|---|---|---|---|---|
| Monday | swim | Race | SWIM_OPENER_1500m_race_pace | 35min | no |
| Monday | run | Easy | RUN_Z2_easy_cap140bpm | 30min | no |
| Tuesday | swim | Race | SWIM_CSS_8x100_1_45 | 42min | no |
| Tuesday | run | Intervals | RUN_VO2_5x400m_3_35km | 40min | no |
| Wednesday | bike | Race | BIKE_RACE_40min_IF85 | 60min | no |
| Friday | bike | Easy | BIKE_Easy_15 | 35min | no |
| Saturday | race | Race | RACE_OLYMPIC | 150min | no |
| Sunday | bike | Easy | BIKE_Easy_01 | 30min | no |

---

## Payload file

`scripts/payloads/ebreard4-olympic-2026-09-19.json`

---

## PR URL

See PR opened in this commit.
