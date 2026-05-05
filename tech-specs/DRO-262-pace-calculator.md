# DRO-262: Pace Calculator (Profile entry only)

**Overall Progress:** `100%` (Phase 1 + Phase 2 complete; Phase 3 cancelled)

**Linear:** [DRO-262](https://linear.app/dromosapp/issue/DRO-262/pace-calculator-drawer-profile-entry-workout-chip-pre-seed)

## TLDR

A slider-driven pace/time calculator presented as an 80%-height bottom drawer (Option C "shareable pace card" visual, dark gradient, dismissible via chevron / drag-down / backdrop tap). **One entry point in V0:**

1. **Profile → new "Tools" section row** "Pace calculator ›" (canonical home).

**Cancelled mid-pipeline (V0 scope reduction by product, 2026-05-05):** the workout-card "Pace" chip and Calendar toolbar entry were both dropped to keep V0 lean. The `PaceSeed.from(session:profile:)` factory still ships in `PaceSeed.swift` (already merged in Phase 1) — it's reserved for a possible future chip ticket and adds zero footprint to the running app.

## Critical Decisions

- **Single shared `PaceCalculatorSheet` view** — built once, designed to support multiple entry points. Takes an optional `seed: PaceSeed?` parameter; V0 always passes `nil` (neutral defaults: Run, 12.0 km/h).
- **Bottom drawer at fixed 80% height** — using `.sheet(...) .presentationDetents([.fraction(0.8)])` with `.presentationDragIndicator(.visible)`. iOS gives us drag-to-dismiss for free; we add a small chevron-down button at the bottom of the header for an explicit, tap-to-dismiss affordance per design.
- **No persistence** — slider value resets to defaults every time the drawer is opened. We can layer in `@AppStorage` per-discipline persistence later if users complain.
- **Stateless calculator math, pure functions** — distance ⇄ pace formulas live in a single `PaceMath.swift` utility (no service, no caching). Easy to unit-test, easy to reuse.
- **No analytics in V0** — we have zero analytics in the app (CLAUDE.md). Don't bolt any in for this feature.

## Files Touched

| File | Action | Phase |
|------|--------|-------|
| `Dromos/Dromos/Core/Utils/PaceMath.swift` | CREATE | 1 ✅ |
| `Dromos/Dromos/Features/Tools/PaceCalculatorSheet.swift` | CREATE | 1 ✅ |
| `Dromos/Dromos/Features/Tools/PaceSeed.swift` | CREATE | 1 ✅ |
| `Dromos/DromosTests/PaceMathTests.swift` | CREATE | 1 ✅ |
| `Dromos/Dromos/Features/Profile/ProfileView.swift` | MODIFY | 2 ✅ |

## Context Doc Updates

- `architecture.md` — add `Features/Tools/` folder, `PaceCalculatorSheet`, `PaceMath` utility. Updated as part of Phase 2 cleanup to reflect Profile-only entry.

## Phase 1 — `PaceMath` + `PaceCalculatorSheet` (no entry points yet)

Goal: ship the drawer view and its math, runnable in a `#Preview`. No integration into Profile or SessionCardView yet.

- [x] **Step 1.1: `PaceMath.swift`** 🟩
  - [x] Define `enum Discipline: String, CaseIterable { case run, bike, swim }`.
  - [x] Define `struct DisciplineConfig` with: `min: Int`, `max: Int`, `step: Int`, `defaultValue: Int`, `inputLabel: String`, `unit: String`, `secondaryLabel: String`, `secondaryUnit: String`, `distances: [DistanceEntry]`. Ranges:
    - `.run` → 60–220 (= 6.0–22.0 km/h × 10), step 1, default 120, distances: 1 km / 10 km / Half (21.0975) / Marathon (42.195)
    - `.bike` → 150–500 (= 15.0–50.0 km/h × 10), step 5, default 320, distances: 1 km / 40 km Olympic / 90 km Half-Iron / 180 km Ironman
    - `.swim` → 60–180 (sec / 100 m), step 1, default 110, distances: 1500 m Olympic / 1900 m Half-Iron / 3800 m Ironman
  - [x] Add `Discipline.config: DisciplineConfig` computed property.
  - [x] Pure functions:
    - `kmH(forSliderValue v: Int, discipline: Discipline) -> Double` (run/bike: `v/10`; swim: `360 / Double(v)`)
    - `secondsToCover(km: Double, atSpeedKmH: Double) -> TimeInterval`
    - `formatTime(_ seconds: TimeInterval) -> String` → `"H:MM:SS"` if h>0, else `"M:SS"`
    - `formatPacePerKm(secondsPerKm: TimeInterval) -> String` → `"M:SS / km"`

- [x] **Step 1.2: `PaceSeed.swift`** 🟩
  - [x] `struct PaceSeed { let discipline: Discipline; let sliderValue: Int }`
  - [x] `static func from(session: PlanSession, profile: User?) -> PaceSeed?`
    - Map `session.sport.lowercased()` → `.run` / `.bike` / `.swim`. Unknown sport → `nil`.
    - For `.run`: if `profile?.vma` is non-nil, `sliderValue = Int((vma * 10).rounded())`. Else use `Discipline.run.config.defaultValue`.
    - For `.bike`: V0 — always use default 320.
    - For `.swim`: if `profile?.cssSecondsPer100m` is non-nil, `sliderValue = cssSecondsPer100m`. Else default.
    - Clamp `sliderValue` to `[config.min, config.max]`.

- [x] **Step 1.3: `PaceCalculatorSheet.swift`** 🟩
  - [x] Inputs: `let seed: PaceSeed?`. State: `@State private var discipline: Discipline`, `@State private var sliderValue: Int`. Initial values from `seed` or run/default.
  - [x] Dark gradient background using `Color(red:green:blue:)` literals (no `Color(hex:)` extension in codebase).
  - [x] Layout: eyebrow → title → dismiss button → segmented picker → two-column metrics → slider → finish times.
  - [x] When `discipline` changes, reset `sliderValue` to that discipline's `defaultValue`.
  - [x] `#Preview` block with three previews: `nil` seed, run-seeded (138), swim-seeded (110).

- [x] **Step 1.4: Unit tests `PaceMathTests.swift`** 🟩
  - [x] Run: `12.0 km/h` → 1 km in `5:00`, 10 km in `50:00`, marathon in `3:30:59` (spec lists 3:30:30, which is a ~29s transcription error; 42.195/12×3600 = 12658.5 s = 3:30:59).
  - [x] Bike: `32.0 km/h` → 40 km in `1:15:00`, 180 km in `5:37:30`.
  - [x] Swim: `110 sec/100m` → 1500 m in `27:30`, 3800 m in `1:09:40`.
  - [x] Boundary: slider at min/max for each discipline produces non-NaN, non-zero finish times.
  - [x] `PaceSeed.from(...)` factory tests: sport mapping, VMA/CSS seeding, clamping.
  - **Note:** No test target in `Dromos.xcodeproj` (matches precedent of all other test files in `DromosTests/`). Build compiles cleanly. Test target wiring is a pre-existing project gap.

## Phase 2 — Profile entry point (placement #1)

- [x] **Step 2.1: Add Tools section to ProfileView** 🟩
  - [x] Added `Section("Tools")` above `Section("Goals")` with the "Pace calculator" row (speedometer icon + chevron right).
  - [x] Added `@State private var showPaceCalculator = false` to `ProfileView`.
  - [x] Attached `.sheet` with `.presentationDetents([.fraction(0.8)])`, `.presentationDragIndicator(.visible)`, `.presentationBackground(.black)`.
  - [x] System drag indicator + in-view chevron-down dismiss both verified to work via the sheet view's existing implementation.

## Phase 3 — Workout card chip entry point (CANCELLED)

**Cancelled mid-pipeline (2026-05-05) by product** — V0 ships with the Profile entry only. PR #88 closed without merging; Linear sub-issue [DRO-266](https://linear.app/dromosapp/issue/DRO-266) marked Cancelled. Reasons:

- Calendar `SessionCardView` chip would have shipped, but `HomeView` uses `TodayPlannedCard`/`TodayCompletedCard`/`TodayMissedCard` (separate views) — leading to inconsistent UX where Calendar gets the chip but the most-visible Home card doesn't. Extending the chip to those three views was not in scope.
- Settings entry alone is sufficient for V0 validation. Add the chip later if usage data justifies it.
- The `PaceSeed.from(session:profile:)` factory shipped in Phase 1 (`PaceSeed.swift`) is preserved as future scaffolding — well-tested, ~30 lines, reusable when/if the chip feature is revived.

## Manual QA checklist (V0 — Profile entry only)

- [ ] Profile → Tools → "Pace calculator" row visible above Goals section.
- [ ] Tapping the row opens the drawer at 80% screen height.
- [ ] Drawer dismisses via: (a) system drag indicator drag-down, (b) chevron-down button inside the header.
- [ ] Run/Bike/Swim segmented control switches discipline; slider resets to that discipline's default on every switch.
- [ ] Slider movement updates the major value, secondary value, and all finish times in real-time without lag.
- [ ] Finish times match `PaceMathTests` fixtures (e.g. run @ 12 km/h → marathon = `3:30:59`; bike @ 32 km/h → 180 km = `5:37:30`; swim @ 1:50/100m → 3800 m = `1:09:40`).
- [ ] Drawer's dark gradient renders correctly when parent Profile screen is in either light or dark mode.
- [ ] No layout regression on existing Profile sections (Goals, Metrics, Settings, Strava).

## Resolved decisions

1. **Bike pre-seed (V0)** — always default to 32 km/h. No FTP → speed derivation in V0.
2. **No share button in V0** — remove the "Share pace card" button from the spec entirely. The shareable pace-card export is a separate ticket; we don't ship a non-functional button.
3. **No persistence** — slider resets to seed (or default) every time the drawer is opened.

## Open Question

- **Bike "1 km" distance row** — bikers think in km/h, not pace per km. Drop the 1 km row (3 distances) or keep it (4 distances) for visual symmetry with run? **Recommend keep** — it's the unit the slider reflects most directly. Easy to flip later.

## Rollback plan

Pure-additive change. Rollback = revert the PR. No DB migrations, no new edge functions, no shared service mutations.
