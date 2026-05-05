# DRO-263 — Completed-card metrics row (replaces Actual/Planned table)

**Linear:** [DRO-263](https://linear.app/dromosapp/issue/DRO-263/replace-actualplanned-table-with-sport-specific-top-metrics-on)
**Overall Progress:** `25%`

## TLDR
Replace `ActualVsPlannedTable` on the completed home card with a refactored `ActualMetricsView` rendered as a horizontal label-above-value metric row. The same component (after refactor) serves both Home and Calendar. Extract shared static formatters into `Core/Utils/ActivityFormatters.swift`. No DB changes.

## Critical Decisions

- **Option A — single source of truth.** Refactor `ActualMetricsView` and use it on Home; delete `ActualVsPlannedTable`. Calendar inherits the new look automatically (intentional visual change). Confirmed in discovery.
- **Formatter location: `Core/Utils/ActivityFormatters.swift`** — not `Core/Formatting/`. Matches the existing `Core/Utils/PaceMath.swift` precedent. Keeps it discoverable and testable (mirrors `PaceMathTests.swift` pattern).
- **Don't extend `PaceMath`.** PaceMath operates in seconds/km and seconds/100m and serves the calculator UI. ActivityFormatters operate on `StravaActivity` fields (m/s, meters, watts, bpm). Different responsibility — keep separate.
- **Typography: `.title3` system bold + `.monospacedDigit()`** for value; `.caption` secondary for label. System font, not rounded. Per product call (see Linear description).
- **Layout: `LazyVGrid` with `GridItem(.adaptive(minimum: 90))`** — handles 4-metric (Run/Swim, Bike-no-power) and 5-metric (Bike-with-power) cases without conditional layouts. Exact `minimum` value to be tuned during implementation.
- **Formatter contract**: callers pre-check for nil/zero and skip rendering; formatters take non-optional and return non-empty String. Simpler contract, no hidden `—` fallbacks. Matches the "hide nil cells entirely" product requirement.
- **`formatPlannedDuration(minutes:)` is dead post-refactor** — only the deleted table used it. Don't migrate.
- **Dead code spotted**: [TodayCompletedCard.swift:62-64](Dromos/Dromos/Features/Home/TodayCompletedCard.swift#L62-L64) declares `formattedActualDuration` but no caller in the file references it. Delete during Phase 3.
- **Architecture doc reversal**: the doc currently labels `ActualMetricsView` as legacy and `ActualVsPlannedTable` as the new equivalent. We're reversing that — architecture.md must be updated in Phase 4.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Core/Utils/ActivityFormatters.swift` | CREATE | New `enum ActivityFormatters` with 7 static formatters: `formatDuration(seconds:)`, `formatDistance(meters:)`, `formatPaceRunPerKm(speedMps:)`, `formatPaceSwimPer100m(speedMps:)`, `formatSpeedKmh(speedMps:)`, `formatPower(watts:)`, `formatHR(_:)` |
| `Dromos/DromosTests/ActivityFormattersTests.swift` | CREATE | Pure-function tests for all 7 formatters — boundary cases (0 m/s, sub-minute durations, exact-km distances, fractional rounding) |
| `Dromos/Dromos/Features/Home/ActualMetricsView.swift` | MODIFY | (1) Replace inline formatters with `ActivityFormatters.*` calls. (2) Update orderings per spec (Run/Swim already match; Bike with power: Duration → Distance → Power → HR → Speed; Bike without power: Duration → Distance → HR → Speed). (3) Switch from fixed 2-col to `GridItem(.adaptive(minimum: 90))`. (4) Update typography: `.title3` bold + `.monospacedDigit()` for value, `.caption` for label. |
| `Dromos/Dromos/Features/Home/TodayCompletedCard.swift` | MODIFY | (1) Line 93-97: replace `ActualVsPlannedTable(session:activity:plannedDistanceMeters:)` with `ActualMetricsView(activity: activity)`. (2) Delete dead `formattedActualDuration` computed property at lines 62-64 + private `private var plannedDistanceMeters` at lines 49-52 (only the deleted table consumed it). (3) Line 157: replace `ActualVsPlannedTable.formatDistance(meters: activity.distance)` with `activity.distance.flatMap(ActivityFormatters.formatDistance(meters:))`. |
| `Dromos/Dromos/Features/Home/ActualVsPlannedTable.swift` | DELETE | Remove file entirely after Phases 1–3 land. |
| `.claude/context/architecture.md` | MODIFY | (1) Remove the `ActualVsPlannedTable.swift` line. (2) Update `ActualMetricsView.swift` description to "Sport-specific metric row used by both Home (TodayCompletedCard) and Calendar (SessionCardView). Adaptive `LazyVGrid` cells." (3) Add `Core/Utils/ActivityFormatters.swift` to the folder tree. (4) Note: closes DRO-240. |

## Context Doc Updates
- `architecture.md` — folder tree (new `ActivityFormatters.swift`, deleted `ActualVsPlannedTable.swift`), updated `ActualMetricsView` description, DRO-240 reference resolved.
- `schema.md` — N/A (no DB changes).
- `ai-pipeline.md` — N/A.

## Tasks

### Phase 1: Shared formatters extraction

- [x] 🟩 **Step 1.1: Create `Core/Utils/ActivityFormatters.swift`**
  - [x] 🟩 New file with `enum ActivityFormatters` namespace (matching `enum PaceMath` precedent).
  - [x] 🟩 Implement `formatDuration(seconds: Int) -> String` — `H'MM'` when ≥ 1 hour (e.g. `1h 30'`), `MM'` otherwise (e.g. `52'`). Mirrors current `ActualVsPlannedTable.formatDuration`.
  - [x] 🟩 Implement `formatDistance(meters: Double) -> String` — `X.X km` (1 decimal) or `X km` (clean integer when fractional part is < 0.05 or > 0.95). Mirrors current table logic. Takes non-optional Double; callers handle nil.
  - [x] 🟩 Implement `formatPaceRunPerKm(speedMps: Double) -> String` — `M:SS/km` from `1000 / mps`. Round total seconds first, then decompose (avoids the `5:00/km` boundary bug noted in the existing table).
  - [x] 🟩 Implement `formatPaceSwimPer100m(speedMps: Double) -> String` — `M:SS/100m` from `100 / mps`. Same rounding strategy.
  - [x] 🟩 Implement `formatSpeedKmh(speedMps: Double) -> String` — `X.X km/h` from `mps × 3.6`.
  - [x] 🟩 Implement `formatPower(watts: Double) -> String` — `N W` (integer-rounded).
  - [x] 🟩 Implement `formatHR(_ hr: Double) -> String` — `N bpm` (integer-rounded).
  - [x] 🟩 Add doc comments matching the style in `PaceMath.swift`.

- [x] 🟩 **Step 1.2: Add `ActivityFormattersTests.swift`**
  - [x] 🟩 Mirror `PaceMathTests.swift` structure — XCTest case per formatter.
  - [x] 🟩 Cover boundary cases: 0 m/s, sub-1-min durations (e.g. 30 sec → `0'`), exactly 60 min (`1h 00'`), distance < 50m (still renders `0.0 km`? — match current table behaviour), pace boundary at 359.7s (must NOT round to `5:00/km` for 4:59 m/s pace), 1.0 km clean integer rendering.

### Phase 2: Refactor `ActualMetricsView`

- [ ] 🟥 **Step 2.1: Update grid + typography**
  - [ ] 🟥 In `body`, change `LazyVGrid` columns from `[GridItem(.flexible()), GridItem(.flexible())]` to `[GridItem(.adaptive(minimum: 90))]`.
  - [ ] 🟥 Update each cell's value `Text`: `.font(.title3).fontWeight(.bold).monospacedDigit()` (was `.subheadline` bold).
  - [ ] 🟥 Keep label `.font(.caption).foregroundColor(.secondary)`.
  - [ ] 🟥 Visual sanity check via the existing `#Preview` blocks (run/bike-with-power/bike-no-power/swim).

- [ ] 🟥 **Step 2.2: Update metric ordering per spec**
  - [ ] 🟥 Run branch: Duration → Distance → Avg pace → Avg HR (already matches; verify).
  - [ ] 🟥 Swim branch: Duration → Distance → Avg pace → Avg HR (already matches; verify).
  - [ ] 🟥 Bike branch (with power): Duration → Distance → Avg power → Avg HR → Avg speed. (Current is Power → HR → Speed; need to ensure Duration + Distance lead — already added at lines 33-39 — but power must come BEFORE HR which must come BEFORE speed. Verify.)
  - [ ] 🟥 Bike branch (no power): Duration → Distance → Avg HR → Avg speed. (Current order under no-power path is HR → Speed which already matches; verify Duration + Distance leads.)

- [ ] 🟥 **Step 2.3: Replace inline formatters with `ActivityFormatters`**
  - [ ] 🟥 Replace the 5 private static helpers (`formatDuration`, `formatDistance`, `formatRunPace`, `formatSwimPace`, plus implicit speed/power/HR strings inline) with calls to `ActivityFormatters.*`.
  - [ ] 🟥 Delete the now-unused private helper functions.
  - [ ] 🟥 Add `import Foundation` if not present (the file currently only imports SwiftUI; ActivityFormatters lives in Core/Utils so it's the same module).

### Phase 3: Migrate `TodayCompletedCard`

- [ ] 🟥 **Step 3.1: Swap the component**
  - [ ] 🟥 At [TodayCompletedCard.swift:93-97](Dromos/Dromos/Features/Home/TodayCompletedCard.swift#L93-L97), replace `ActualVsPlannedTable(session: session, activity: activity, plannedDistanceMeters: plannedDistanceMeters)` with `ActualMetricsView(activity: activity)`.
  - [ ] 🟥 Verify the card visually with the file's existing `#Preview` blocks (with map / no map / loading / missing / swim / bike no power).

- [ ] 🟥 **Step 3.2: Migrate the map-overlay formatter call**
  - [ ] 🟥 At [TodayCompletedCard.swift:157](Dromos/Dromos/Features/Home/TodayCompletedCard.swift#L157), replace `ActualVsPlannedTable.formatDistance(meters: activity.distance)` with `activity.distance.flatMap(ActivityFormatters.formatDistance(meters:)) ?? "—"`. The fallback to `"—"` preserves current behaviour for the map overlay specifically (the parent code at lines 162-163 then filters out `"—"` from the joined parts).

- [ ] 🟥 **Step 3.3: Delete dead code**
  - [ ] 🟥 Delete `formattedActualDuration` computed property at [TodayCompletedCard.swift:62-64](Dromos/Dromos/Features/Home/TodayCompletedCard.swift#L62-L64) (no caller — confirmed by grep).
  - [ ] 🟥 Delete `plannedDistanceMeters` computed property at [TodayCompletedCard.swift:49-52](Dromos/Dromos/Features/Home/TodayCompletedCard.swift#L49-L52) (only fed the deleted table parameter).
  - [ ] 🟥 Verify no other call sites of `ActualVsPlannedTable` remain in the file.

### Phase 4: Delete `ActualVsPlannedTable` + cleanup

- [ ] 🟥 **Step 4.1: Delete the file**
  - [ ] 🟥 Confirm zero remaining references via `grep -rn "ActualVsPlannedTable" --include="*.swift"`.
  - [ ] 🟥 Delete [Dromos/Dromos/Features/Home/ActualVsPlannedTable.swift](Dromos/Dromos/Features/Home/ActualVsPlannedTable.swift).
  - [ ] 🟥 Remove from Xcode project file references if not auto-managed.

- [ ] 🟥 **Step 4.2: Update `.claude/context/architecture.md`**
  - [ ] 🟥 Folder tree: remove the `ActualVsPlannedTable.swift` line. Update `ActualMetricsView.swift` description to "Sport-specific metric row used by both Home (TodayCompletedCard) and Calendar (SessionCardView). Adaptive LazyVGrid cells; hides nil values entirely."
  - [ ] 🟥 Folder tree: add `Core/Utils/ActivityFormatters.swift` line — "Static formatters for `StravaActivity` display (duration, distance, pace, speed, power, HR). Mirrors `PaceMath` pattern."
  - [ ] 🟥 Note in `Key Shared Components` section: update the `ActualMetricsView` line. Note that DRO-240 is closed by this PR.

- [ ] 🟥 **Step 4.3: Manual QA pass**
  - [ ] 🟥 Run app, open Today tab on a day with a completed run — verify 4 cells (Duration / Distance / Avg pace / Avg HR), bold tabular nums, no `—`, no table chrome.
  - [ ] 🟥 Verify Today tab on a completed bike WITH power — 5 cells in order (Duration / Distance / Avg power / Avg HR / Avg speed), wrapping to 2nd row.
  - [ ] 🟥 Verify Today tab on a completed bike WITHOUT power — 4 cells (Duration / Distance / Avg HR / Avg speed).
  - [ ] 🟥 Verify Today tab on a completed swim — 4 cells (Duration / Distance / Avg pace / Avg HR).
  - [ ] 🟥 Verify Today tab on a manual entry (no Strava) — only Duration cell.
  - [ ] 🟥 Verify Calendar tab — same component, same metrics, larger typography than before.
  - [ ] 🟥 Verify the "View planned workout" disclosure still expands correctly.
  - [ ] 🟥 Verify the GPS map overlay still shows distance correctly.

## Risks / Notes
- **Calendar visual change** is intentional but may surprise; flag in PR description.
- **Tabular numerals** — must verify `.monospacedDigit()` is applied to every value Text. Without it, the row jitters as values change between sessions.
- **Adaptive grid `minimum`** — 90pt is a starting point; tune if cells look cramped or sparse on small devices (iPhone SE / mini).
- **No DB migration**, no edge function change, no Strava sync change.
