# Fix Report — DRO-298 Phase 2: Code Review Fixes (PR #114)

**Branch:** `feature/DRO-298-workout-library-templates`
**PR:** #114
**Date:** 2026-06-06
**Fixes:** 11 issues (2 critical, 1 high, 5 medium, 3 low)

---

## Summary

Code review of PR #114 found that 5 templates used `hr_pct_max_max` without a paired `hr_pct_max_min`. The materializer's range branch requires BOTH fields — an unpaired `_max` is silently dropped, resulting in `target: undefined` for those segments. This was the most impactful bug: two Z2 run templates had no intensity target at all, and one race had intensity data silently discarded.

Additional findings: 6 templates had declared `duration_minutes` that didn't match actual segment math, the BIKE_OU template mislabeled 95% FTP as "recovery", and two templates needed IDs corrected.

---

## Issues Fixed

### CRITICAL — hr_pct_max unpaired fields

| Template | Segment | Old state | Fix applied |
|----------|---------|-----------|-------------|
| `RUN_Z2_easy_cap140bpm` | work | `hr_pct_max_max: 73` only | Added `hr_pct_max_min: 50` → range 50-73 |
| `RUN_Z2_long_cap150bpm` | work | `hr_pct_max_max: 78` only | Added `hr_pct_max_min: 65` → Z2 band 65-78 |
| `BIKE_Z2_endurance_90min` | work | `ftp_pct_min/max: 65-75` + orphan `hr_pct_max_max: 78` | Removed `hr_pct_max_max`; HR cap moved to `cue` text |
| `RUN_TEMPO_4x4min_4_15km` | recovery sub-seg | `hr_pct_max_max: 65` only | Added `hr_pct_max_min: 50` → range 50-65 |
| `RUN_BRICK_25min_15rp_10z2` | cooldown | `hr_pct_max_max: 78` only | Added `hr_pct_max_min: 50` → range 50-78 |

**Root cause:** The materializer requires BOTH `hr_pct_max_min` AND `hr_pct_max_max` to emit a range target. If only `_max` is set, the range branch is skipped and `target` is `undefined`. This is by design (prevents malformed targets) but was not documented or tested before this fix.

### HIGH — RACE_OLYMPIC distance/duration conflict

RACE_OLYMPIC swim/bike/run `work` segments had both `distance_meters` AND `duration_minutes`. The XOR rule in `resolveMeasure()` makes `duration_minutes` win, silently dropping the distance. For a race template, distance is the authoritative measure.

**Fix:** Removed `duration_minutes` from all 3 work segments (swim 1500m, bike 40km, run 10km). T1/T2 recovery segments retain `duration_minutes`. Top-level `duration_minutes` set to 132 (corrected from 120).

### MEDIUM — Duration mismatches (declared vs computed)

| Template | Old | New | Computation |
|----------|-----|-----|-------------|
| `BIKE_SS_4x6min_245W` | 59 | 65 | 15 + 4×(6+4) + 10 |
| `BIKE_THR_2x15min_260W` | 63 | 71 | 15 + 2×(15+8) + 10 |
| `BIKE_OU_2x12min_95_110` | 67 | 61 | 15 + 2×(3×(1+3)+6) + 10 |
| `BIKE_VO2_3x6min_295W` | 57 | 55 | 15 + 3×(6+4) + 10 |
| `RUN_TEMPO_4x4min_4_15km` | 51 | 49 | 15 + 4×(4+2) + 10 |
| `RUN_THR_3x10min_4_22km` | 60 | 70 | 15 + 3×(10+5) + 10 |

### MEDIUM — New negative tests (7 tests)

Added 7 tests to `materialize-structure.test.ts` pinning the silent-drop contract:
- `hr_pct_max: only _max set` → `undefined`
- `hr_pct_max: only _min set` → `undefined`
- `ftp_pct: only _min set` → `undefined`
- `ftp_pct: only _max set` → `undefined`
- `power_watts: only _min set` → `undefined`
- `power_watts: only _max set` → `undefined`
- `hr_pct_max: legacy single-value` → `{ type: "hr_pct_max", value: 73 }` (positive regression)

Also fixed existing BIKE_OU test: inner "under" segment now asserts `label="work"` (matches the fix in issue #3).

**Total test count: 42** (35 existing + 7 new). All pass.

### LOW — Template ID renames

| Old ID | New ID | Reason |
|--------|--------|--------|
| `BIKE_VO2_5x3min_290W` | `BIKE_VO2_5x3min_295W` | Range is 290-300W; 295 is the midpoint |
| `BIKE_OU_2x10min_95_110` | `BIKE_OU_2x12min_95_110` | Inner set is actually 3×(1+3) = 12min per over-under block |

### LOW — BIKE_OU inner "under" label

The inner "under" segment (95% FTP) was labeled `recovery`. 95% FTP is threshold, not recovery.

**Fix:** Changed `label: "recovery"` → `label: "work"` on the 95% FTP "under" segments.

### LOW — Status doc corrections

- Template count corrected: **30** (not 35) in `status-DRO-298-phase2.md`
- `BIKE_Z2` deviation section updated to reflect actual fix taken

---

## Context Docs Updated

- `.claude/context/architecture.md`: Updated "Shared Materializer" section — Phase 2 field families, priority order, unpaired min/max warning, test count 42, `strength` as 5th top-level array
- `.claude/context/ai-pipeline.md`: Added DRO-298 paragraph noting new vocabulary, updated race templates count to 3, added TODO for `buildSimplifiedLibrary()` surfacing new fields

---

## Out of Scope (Follow-up)

- `RUN_Tempo_21` duplicate template_id (pre-existing, not introduced by this PR) — follow-up Linear issue filed separately
- `buildSimplifiedLibrary()` not surfacing `power_watts`/`pace_per_km` to LLM Step 3 — documented as TODO in `ai-pipeline.md`

---

## Verification

```
deno test supabase/functions/_shared/__tests__/materialize-structure.test.ts
ok | 42 passed | 0 failed
```

JSON well-formed: `jq '.' ai/context/workout-library.json > /dev/null && echo OK`
Template counts unchanged: bike=65, run=80, swim=53, race=3, strength=1
