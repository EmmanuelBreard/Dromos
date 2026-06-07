# Status Report — DRO-296: Fix Tuesday Double-Quality Sessions

**Date:** 2026-06-07
**Operator:** Fio (CTO agent)
**Scope:** Olympic plan for ebreard4@gmail.com, project `cumbrfnguykvxhvdelru`

---

## Problem

Weeks where the source plan had 2 bike quality sessions resulted in both being placed on Tuesday AM + Friday AM after redistribution. Tuesday already had run quality PM. Result: Tuesday = bike quality AM + run quality PM — an unacceptable double high-impact quality day.

---

## Detection

Detection query found **5 affected weeks**. Weeks 14 and 15 were NOT flagged (clean, as expected).

| Week | Bike quality ID (moved) | Run quality ID (stays) |
|---|---|---|
| 4 | `752914e2-e9a4-4e84-87c0-b3464816c118` | `e7b895a1-d840-463f-af51-ffe5bf1c09a5` |
| 7 | `00a61eaf-690f-43d4-817f-40f21ae361f1` | `9978f5c7-aa9b-462e-9ccb-c5b121407583` |
| 8 | `8a1b9f9e-38d0-498d-9256-7ec6623e0613` | `661eb8c2-b436-43df-957b-fbfa473fdf61` |
| 10 | `d39c7c73-ee65-4c8c-8392-355e13466f92` | `fbd3375d-ebd3-47e5-8d07-2608093dbce1` |
| 13 | `f7bf084d-b926-4ee6-b335-21704bc66745` | `a27b63f7-298c-43bd-a230-6dbe7ac60843` |

---

## Feasibility validation

For all 5 weeks, Wednesday PM was confirmed to be a `sport='strength'` session at `order_in_day=1` before any UPDATEs were applied. All swap targets were clean — no aborts required.

---

## Swap applied

**Rule:** Bike quality (Tue AM, order=0) → Wed PM (order=1). Strength (Wed PM, order=1) → Tue AM (order=0).

10 UPDATEs executed in a single transaction (2 per week, 5 weeks). Only `day` and `order_in_day` columns modified — template_id, duration_minutes, notes, structure JSONB, sport, type, is_brick unchanged.

---

## Result per week (after swap)

| Day | Order | Sport | Type |
|---|---|---|---|
| **Tuesday** | 0 | strength | Easy |
| **Tuesday** | 1 | run | Intervals/Tempo |
| **Wednesday** | 0 | swim | Intervals |
| **Wednesday** | 1 | bike | Intervals/Tempo |

Both Wed sessions are quality but different sports/muscle groups — acceptable.

---

## Week 7 sample (full week layout after fix)

| Day | Order | Sport | Type | Duration |
|---|---|---|---|---|
| Monday | 0 | swim | Easy | 58 min |
| Monday | 1 | run | Easy | 50 min |
| **Tuesday** | **0** | **strength** | **Easy** | **35 min** |
| **Tuesday** | **1** | **run** | **Intervals** | **60 min** |
| **Wednesday** | **0** | **swim** | **Intervals** | **62 min** |
| **Wednesday** | **1** | **bike** | **Intervals** | **75 min** |
| Friday | 0 | bike | Intervals | 100 min |
| Friday | 1 | swim | Easy | 30 min |
| Saturday | 0 | bike | Easy | 90 min |
| Saturday | 1 | run | Tempo | 20 min |
| Saturday | 2 | strength | Easy | 35 min |
| Sunday | 0 | run | Easy | 85 min |

Before: Tue had bike Intervals (AM) + run Intervals (PM). After: Tue has strength (AM) + run Intervals (PM). Bike Intervals moved to Wed PM alongside swim Intervals.

---

## Validations passed

| Check | Result |
|---|---|
| Remaining Tue conflicts (bike quality + run quality same day) | **0 rows** |
| Total session count | **164** (unchanged) |
| Days with >2 sessions (non-Saturday) | **0** — only Saturdays in brick weeks have 3-4 sessions |
| Weeks 14 and 15 touched | **0 UPDATEs** |

---

## Files changed

- `miscellaneous/training-plan-olympic-sept-2026.md` — Tue/Wed rows updated for weeks 4, 7, 8, 10, 13
- `tech-specs/status-DRO-296-fix-tue-double-quality.md` — this file

---

## Total UPDATEs

**10 rows updated** (2 per affected week × 5 weeks).
