# DRO-297 Phase 1 — Fix Pass 1

**Date:** 2026-06-06
**Branch:** `feature/DRO-297-renderer-target-types`
**Commit:** 7964976
**PR:** #113

---

## What was changed

### HIGH priority

**1. `hrZoneBounds` corrected** (`WorkoutLibraryService.swift`)
- Old values: `(0.00,0.60), (0.60,0.72), (0.72,0.82), (0.82,0.92), (0.92,1.00)`
- New values: `(0.50,0.65), (0.65,0.78), (0.78,0.85), (0.85,0.92), (0.92,1.00)`
- Source: `training-plan-olympic-sept-2026.md` lines 48-52
- Z1 floor set to 0.50 (not 0.00) to avoid "Z1 HR (0–X bpm)" nonsense display
- Added inline comments labelling each zone

**2. `StructureRenderTests.swift` test expectations updated** (`DromosTests/`)
- `test_displayString_hrZone_resolvesToBpmRange`: changed from `"140–160 bpm"` to `"Z3 HR (156–170 bpm)"` (Z3 with maxHR=200, new bounds 0.78-0.85, plus correct "Z\(zone) HR" zone-name prefix)
- `test_displayString_hrZone_noMaxHrShowsZoneLabel`: changed from `"Z3 (set max HR in profile)"` to `"Z3 HR (set max HR in profile)"`
- `test_intensityPct_hrZoneFollowsTable`: changed Z1 expectation from 55→58 and Z5 from 95→96 (new midpoints)

### MEDIUM priority

**3. `TodayCompletedCard.swift` — strength suppression added**
- Added `if session.sport.lowercased() != "strength" { }` guard around `WorkoutShape` + `WorkoutStepList` inside the `showPlannedWorkout` block
- Mirrors the convention already applied to `TodayPlannedCard`

**4. `intensityPct(.hrZone)` fixed** (`WorkoutLibraryService.swift`)
- Replaced hardcoded `switch value { case 1: return 55; case 2: return 65; ... }` with midpoint derivation from `Self.hrZoneBounds`
- New midpoints: Z1=58, Z2=72, Z3=82, Z4=89, Z5=96
- Bar height and bar color now share one source of truth

**5. `architecture.md` updated** (`.claude/context/`)
- Workout Library section: added `maxHr:` param to `flattenedSegments` and `stepSummaries` signatures
- FlatSegment section: added `hrPctMaxForColor: Double?` field description
- IntensityColorHelper section: added `Color.intensity(forHRPctMax:isRecovery:)` description
- SessionCardView section: added strength rendering convention note

### LOW priority

**6. `TodayPlannedCard.swift` — notes block deduplication**
- Notes block hoisted above strength conditional, eliminating the duplicate `if let notes` in both branches
- Clean `if sport != "strength"` guard for graph/steps only

**7. `FormatMetricTargetTests.swift` — force-unwrap removal + hrZone expectations**
- Updated Z1-Z5 bpm range expectations to match new bounds (maxHR=200)
- Updated `test_intensityPct_hrZone_mapsToTable` expectations to 58/72/82/89/96
- Replaced `XCTAssertNotNil(pct)` + `pct!` with `try XCTUnwrap(pct)` on four test methods
- Marked those methods `throws`

**8. `IntensityColorHelper.swift` — doc anchor fix**
- Rewrote doc comment to accurately describe the actual 60–95% linear hue sweep: `"60%→green, 78%→yellow, 95%→red"`

---

## File/line summary

| File | Lines changed | Nature |
|------|--------------|--------|
| `Dromos/Core/Services/WorkoutLibraryService.swift` | ~916-930 (hrZoneBounds), ~826-830 (intensityPct) | Correctness |
| `Dromos/Features/Home/TodayCompletedCard.swift` | ~118-130 | Feature gap |
| `Dromos/Features/Home/TodayPlannedCard.swift` | ~71-96 | Cleanup |
| `Dromos/Features/Home/IntensityColorHelper.swift` | ~64-72 | Doc fix |
| `Dromos/DromosTests/FormatMetricTargetTests.swift` | ~49-82 (hr_zone tests), ~183-217 (intensityPct + throws) | Test alignment |
| `Dromos/DromosTests/StructureRenderTests.swift` | ~66-75, ~119-122 | Test alignment |
| `.claude/context/architecture.md` | Workout Library, IntensityColorHelper, SessionCardView, Color Extensions sections | Docs |

---

## Out-of-scope follow-up

DRO-302 filed: "Wire DromosTests Xcode target" — tests compile correctly but cannot run until the Xcode test target is added.

---

## Build confirmation

```
** BUILD SUCCEEDED **
xcodebuild -scheme Dromos -configuration Debug -destination "generic/platform=iOS Simulator"
```
Zero errors, zero new warnings.

---

## bpm display at maxHR=193 (spec requirement)

| Zone | Expected | Actual |
|------|----------|--------|
| Z1 | ~96–125 | 97–125 |
| Z2 | ~125–150 | 125–151 |
| Z3 | ~150–164 | 151–164 |
| Z4 | ~164–178 | 164–178 |
| Z5 | ~178–193 | 178–193 |

Rounding differences of ±1 bpm from `Int((193 * bound).rounded())` — within spec.
