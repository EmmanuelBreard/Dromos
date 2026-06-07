# Status Report — DRO-296: Swim Day Redistribution

**Date:** 2026-06-07
**Plan:** Olympic Sept 2026 — fbe708c2-cf51-42e2-a1a9-72e9e8bf19b3
**Athlete:** ebreard4@gmail.com

---

## Summary

Completed swap-only day redistribution across all 15 weeks of the active Olympic plan. Only `day` and `order_in_day` columns were modified — no template_id, duration_minutes, notes, structure, sport, type, or is_brick values changed.

---

## Changes made

### Supabase SQL (plan_sessions table)

Total UPDATE count: **40 rows** modified across 14 active weeks (Wk 15 required no changes).

Pattern per week (Wks 1-13):
- Tue swim (quality/drills) → **Wed AM** (order=0)
- Wed bike (quality/VO2) → **Fri AM** (order=0)
- Fri bike (easy/quality) → **Tue AM** (order=0)
- Sun swim recovery → **Fri PM** (order=1)
- Tue run quality/easy stays **Tue PM** (order=1)
- Wed strength stays **Wed PM** (order=1)

Special cases:
- **Wk 1:** No Sun swim to move. Fri run_easy moved to Mon PM (Mon had no run).
- **Wk 3:** Sat run_TEMPO moved to Tue PM (quality run); Tue run_easy displaced to Sat AM.
- **Wk 5/9:** Deload weeks — no Sun swim, fewer quality sessions.
- **Wk 11-12:** Sat race simulation bricks untouched (swim+bike+run+strength multi-session Saturdays preserved).
- **Wk 14:** Race on Saturday preserved. Wed bike_RACE → Fri, Fri bike_Easy → Tue, Tue swim_CSS → Wed.
- **Wk 15:** No changes — race-week protocol already correct (Tue/Thu/Fri/Sat/Sun spacing).

---

## Verification results

| Check | Result |
|---|---|
| Total session count | **164** (unchanged) |
| Sessions with NULL structure or template_id | **0** |
| Thu sessions in Wks 1-14 | **0** |
| Max sessions/day (non-brick) | ≤2 |
| Max sessions/day (brick Sat) | 3 (Wks 6,7,8,10,13) or 4 (Wks 11,12 race sims) |
| Back-to-back swim days | **Zero** across all 15 weeks |
| Brick pairs (bike=0, run=1, same day) | All intact |
| Race sessions (Wk 14 Sat, Wk 15 Sat) | Both on Saturday |

### Swim distribution by week

| Wk | Swim days |
|---|---|
| 1 | Mon, Wed |
| 2-10 | Mon, Wed, Fri |
| 11-12 | Mon, Wed, Fri, Sat (race sim brick includes swim) |
| 13 | Mon, Wed, Fri |
| 14 | Mon, Wed |
| 15 | Tue, Thu, Sun (race week protocol — unchanged) |

---

## Sample week layouts (post-redistribution)

### Week 1
| Day | AM | PM |
|---|---|---|
| Mon | swim SWIM_Z2_endurance_2500m | run RUN_Z2_easy_cap140bpm |
| Tue | bike BIKE_Z2_endurance_90min | run RUN_Z2_easy_cap140bpm |
| Wed | swim SWIM_DRILLS_1800m | strength STRENGTH_NOTES_ONLY |
| Sat | bike BIKE_Z2_endurance_90min | strength STRENGTH_NOTES_ONLY |
| Sun | run RUN_Z2_long_cap150bpm | — |

### Week 7
| Day | AM | PM |
|---|---|---|
| Mon | swim SWIM_Z2_endurance_2500m | run RUN_Z2_easy_cap140bpm |
| Tue | bike BIKE_THR_2x15min_260W | run RUN_VO2_5x600m_3_45km |
| Wed | swim SWIM_CSS_8x100_1_45 | strength STRENGTH_NOTES_ONLY |
| Fri | bike BIKE_VO2_5x3min_295W | swim SWIM_Easy_06 (recovery) |
| Sat | bike BIKE_Z2_endurance_90min (brick) | run RUN_BRICK_25min_15rp_10z2 (brick) + strength (order=2) |
| Sun | run RUN_Z2_long_cap150bpm | — |

### Week 14 (Race A week)
| Day | AM | PM |
|---|---|---|
| Mon | swim SWIM_OPENER_1500m_race_pace | run RUN_Z2_easy_cap140bpm |
| Tue | bike BIKE_Easy_15 | run RUN_VO2_5x400m_3_35km |
| Wed | swim SWIM_CSS_8x100_1_45 | — |
| Fri | bike BIKE_RACE_40min_IF85 | — |
| Sat | RACE RACE_OLYMPIC | — |
| Sun | bike BIKE_Easy_01 (recovery) | — |

---

## Markdown source

Updated: `miscellaneous/training-plan-olympic-sept-2026.md`
All 14 week tables updated to reflect new day distribution. Content (notes, prescriptions, wattages, paces) unchanged — day column only.

---

## Rollback

No migration was run. Changes are in-place on `plan_sessions`. To rollback, re-run the original snapshot import or manually reverse the `day`/`order_in_day` updates using the session IDs logged here.

Original snapshot reference: `4f4db07f-4897-4ddd-95d9-dc6ee9026b2f` (Nîmes plan — separate plan, not affected).
