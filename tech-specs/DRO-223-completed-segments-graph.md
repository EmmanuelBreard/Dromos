# DRO-223 — Completed-session Segments Graph

**Linear:** [DRO-223](https://linear.app/dromosapp/issue/DRO-223/display-strava-lap-data-on-completed-sessions-segments-graph)
**Branch:** `ebreard4/dro-223-display-strava-lap-data-on-completed-sessions-segments-graph`
**Overall Progress:** `0%`

## TLDR

Render a horizontal bar segment graph from Strava lap data on every completed-session card in the Home tab. One bar per Strava lap; bar **width** flexes by lap distance; bar **height** encodes sport-normalized intensity using the same color gradient as the planned `WorkoutGraphView`. A drag-and-hold tooltip surfaces `duration · distance · pace · avg HR` per lap. Component sits **above** the optional route map and **below** `ActualMetricsView` inside `TodayCompletedCard`. Coexists with the existing planned-workout disclosure (no replacement).

## Critical Decisions

- **Build a new component, not extend `WorkoutGraphView`.** Different inputs (`StravaLap` vs `FlatSegment`), different X-axis (distance vs duration), different normalization. Reuse `Color.intensity(for:isRecovery:)` and the `DragGesture(minimumDistance: 0)` pattern; otherwise distinct file.
- **Selected-state visual differs from planned graph.** Selected bar gets a 1.5pt outline; the *other* bars dim to 45% opacity. Existing `WorkoutGraphView` does not dim — we intentionally diverge here because the completed graph has noisier data (auto-laps) and dimming sharpens focus during inspection.
- **Sport-aware intensity math lives in a dedicated helper** (`LapIntensityCalculator`) — keeps the row-shaped `StravaLap` model dumb and makes the formulas independently testable.
- **Lap fetch lives on `StravaService.fetchLaps(activityId:)`** — mirrors `fetchActivities` pattern. No new repo / no new service. RLS already permits authenticated SELECT (per `schema.md` line 210).
- **Brick handling: hide the section.** Detect via `session.sport.caseInsensitiveCompare("brick") == .orderedSame`. Multi-sport rendering deferred.
- **Reference-based normalization is the default; session-normalized is a fallback.** Reference values pulled from `User.vma` / `User.ftp` / `User.cssSecondsPer100m` / `User.maxHr`. If the relevant reference is missing, the calculator switches to session min/max for that lap set.
- **Bike fallback is per-activity, not per-lap.** If any lap has `average_watts == nil || average_watts == 0`, the entire activity falls back to HR-based normalization.
- **No memoization.** Intensity calc is sub-millisecond for ≤50 laps; revisit only if profiling flags it.

## Files to Touch

| File | Action | Changes |
|---|---|---|
| `Dromos/Dromos/Core/Models/StravaLap.swift` | CREATE | New `Codable, Identifiable` struct mirroring `strava_activity_laps` columns. |
| `Dromos/Dromos/Core/Services/StravaService.swift` | MODIFY | Add `fetchLaps(activityId: UUID) async -> [StravaLap]`. |
| `Dromos/Dromos/Core/Utils/ActivityFormatters.swift` | MODIFY | Add `formatDistanceCompact(meters:)` — meters under 1km, else delegates to existing `formatDistance`. |
| `Dromos/Dromos/Features/Home/LapIntensityCalculator.swift` | CREATE | Sport-aware intensity-percentage math + session-normalized fallback. Pure functions, no SwiftUI. |
| `Dromos/Dromos/Features/Home/CompletedSegmentGraphView.swift` | CREATE | The graph component. Bars + drag-tooltip + selected-state + X-axis labels + footnote. |
| `Dromos/Dromos/Features/Home/TodayCompletedCard.swift` | MODIFY | Insert `CompletedSegmentGraphView` between `ActualMetricsView` (line 78) and the optional `mapBlock` (line 80). Hold `@State` for laps + `.task` to fetch. |
| `Dromos/DromosTests/ActivityFormattersTests.swift` | MODIFY | Add tests for `formatDistanceCompact` (sub-1km, ≥1km, edge cases). |
| `Dromos/DromosTests/LapIntensityCalculatorTests.swift` | CREATE | Tests for run/bike/swim reference-based and session-normalized branches; bike per-activity HR fallback; equal-value edge case. |

## Context Doc Updates

- `architecture.md` — register the three new files (`StravaLap.swift`, `LapIntensityCalculator.swift`, `CompletedSegmentGraphView.swift`) under the Home feature folder; note that `TodayCompletedCard` now hosts a Strava-driven graph above the map.
- `schema.md` — no changes (no schema work).
- `ai-pipeline.md` — no changes.

## Resolved Decisions (locked during /ship setup)

- **Brick detection** — `session.sport.caseInsensitiveCompare("brick") == .orderedSame`. Bricks tagged via the sport string, no structure-based detection needed.
- **Equal-value double-fallback** — only triggers when **both**: (a) the athlete has no VMA/FTP/CSS reference set AND (b) every lap reports the same value for the chosen metric. In this narrow case, render all bars at **100% height** with the **default green/easy color** (`Color.intensity(for: nil)` returns green). Communicates "we have no basis to differentiate" without crashing or showing a blank chart. Reference-based normalization (default path) uses absolute % and is never affected by min == max.

## Tasks

- [ ] 🟥 **Phase 1: Data model + lap fetch**
  - [ ] 🟥 Create `StravaLap.swift` with fields: `id: UUID`, `activityId: UUID`, `lapIndex: Int`, `elapsedTime: Int`, `movingTime: Int`, `distance: Double?`, `averageSpeed: Double?`, `averageCadence: Double?`, `averageWatts: Double?`, `averageHeartrate: Double?`, `maxHeartrate: Double?`, `startIndex: Int?`, `endIndex: Int?`. `Codable, Identifiable`. Property names camelCase — relies on the global `convertFromSnakeCase` decoder pattern already used by `StravaActivity`.
  - [ ] 🟥 Add `StravaService.fetchLaps(activityId: UUID) async -> [StravaLap]` — `from("strava_activity_laps").select().eq("activity_id", value: activityId.uuidString).order("lap_index", ascending: true)`. Return `[]` on error, write to `errorMessage`.

- [ ] 🟥 **Phase 2: Distance formatter helper**
  - [ ] 🟥 Add `ActivityFormatters.formatDistanceCompact(meters: Double) -> String` — `meters < 1000 → "\(Int(meters.rounded())) m"`; otherwise delegate to existing `formatDistance(meters:)`.
  - [ ] 🟥 Tests in `ActivityFormattersTests`: 0 m → `"0 m"`, 549.6 m → `"550 m"`, 999 m → `"999 m"`, 1000 m → uses km path, 11200 m → `"11.2 km"` (matches existing rounding rule).

- [ ] 🟥 **Phase 3: Sport-aware intensity calculator**
  - [ ] 🟥 Create `LapIntensityCalculator.swift` with a single public entry point: `static func intensities(for laps: [StravaLap], sport: String, vma: Double?, ftp: Int?, css: Int?, maxHr: Int?) -> [Int?]` — returns intensity % per lap, same length and order as input. `nil` for laps that can't be normalized at all (zero distance, missing required metric).
  - [ ] 🟥 Internal sport-routing on `sport.lowercased()`:
    - `"run"`: speed_kmh = `averageSpeed * 3.6`. If `vma` present → `Int(((speed_kmh / vma) * 100).rounded())`. Else session-normalized on `averageSpeed`.
    - `"bike"`: detect power availability — if **every** lap has `averageWatts != nil && averageWatts! > 0`, use power. If `ftp` present → `Int(((watts / Double(ftp)) * 100).rounded())`. Else session-normalized on watts. If power unavailable on any lap, switch the **whole activity** to HR: if `maxHr` present → `Int(((bpm / Double(maxHr)) * 100).rounded())`. Else session-normalized on bpm.
    - `"swim"`: secondsPer100m = `100.0 / averageSpeed`. If `css` present → `Int(((Double(css) / secondsPer100m) * 100).rounded())`. Else session-normalized on `averageSpeed` (faster = taller).
    - Default / unknown sport: session-normalized on `averageSpeed`.
  - [ ] 🟥 Session-normalized helper: `((value - sessionMin) / (sessionMax - sessionMin)) * 100`. Handle equal-value case per Open Question #2 — default to 100 for now (flag in code comment).
  - [ ] 🟥 Unit tests covering: each sport's reference path; each sport's session-normalized fallback; bike per-activity power→HR fallback; equal-value session; lap with missing metric.

- [ ] 🟥 **Phase 4: `CompletedSegmentGraphView` component**
  - [ ] 🟥 Create the SwiftUI view. Inputs: `laps: [StravaLap]`, `sport: String`, `vma: Double?`, `ftp: Int?`, `css: Int?`, `maxHr: Int?`. State: `@State private var selectedLapIndex: Int?`, `@State private var tooltipXOffset: CGFloat = 0`, `@State private var graphWidth: CGFloat = 0`.
  - [ ] 🟥 Body: `VStack(alignment: .leading, spacing: 8)` containing section title `"Segments"` (`.headline`), graph `GeometryReader` (height 80), X-axis row, footnote.
  - [ ] 🟥 **Bar rendering:** computed `widthFractions = laps.map { $0.distance ?? 0 } / total`. Skip laps with `distance == nil || distance == 0`. Use `HStack(spacing: 2)`, each bar = `RoundedRectangle(cornerRadius: 3).fill(Color.intensity(for: pct, isRecovery: false)).frame(width: max(barWidth, 2), height: max(heightForPct(pct), 4))`. Height mapping reuses the bucket function from `WorkoutShape.swift:94` (`heightFraction(for:)`) — extract to shared helper or copy verbatim with a TODO consolidation note.
  - [ ] 🟥 **Drag gesture:** `DragGesture(minimumDistance: 0)` mirroring `WorkoutGraphView.swift` lines 77–110. `.onChanged` → find nearest bar by precomputed `barCenterXs`, set `selectedLapIndex` and `tooltipXOffset`. `.onEnded` → clear both.
  - [ ] 🟥 **Selected-state visual:** when `selectedLapIndex != nil`, every bar's opacity = `(idx == selectedLapIndex) ? 1.0 : 0.45`; selected bar gets `.overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary, lineWidth: 1.5))`.
  - [ ] 🟥 **Tooltip:** floating bubble using `.overlay(alignment: .topLeading)` + `.position(x:y:)` matching `WorkoutGraphView` clamping math. Layout: `Lap N` (uppercase caption) → primary metric (large semibold tabular-numeric) → `duration · distance` (caption) → `avg HR` (caption). Distance uses `ActivityFormatters.formatDistanceCompact`. Primary metric per sport:
    - Run: `formatPaceRunPerKm(speedMps:)`
    - Bike (power): `formatPower(watts:)`. Bike (HR fallback): `formatHR(bpm:)`.
    - Swim: `formatPaceSwimPer100m(speedMps:)`
  - [ ] 🟥 **X-axis labels:** quarter-point distance markers across the chart width — `0`, `~25%`, `~50%`, `~75%`, total. Use `formatDistance(meters:)` (km, not compact).
  - [ ] 🟥 **Footnote:** small secondary caption — `"Touch and drag across the chart to inspect each segment's pace, duration and average HR."`
  - [ ] 🟥 SwiftUI previews for: run-with-VMA (canonical scenario), bike-no-power-no-FTP (session-normalized HR), swim-no-CSS, single-lap (should not render — covered by parent guard), equal-intensity ride.

- [ ] 🟥 **Phase 5: Wire into `TodayCompletedCard`**
  - [ ] 🟥 Add `@State private var laps: [StravaLap] = []` and `@StateObject private var stravaService = StravaService()` (or inject — match how `CoachFeedbackBlock` does it; create new instance is fine since fetchLaps is stateless on the service).
  - [ ] 🟥 Add `.task(id: activity.id)` modifier on the root `VStack` to call `laps = await stravaService.fetchLaps(activityId: activity.id)`.
  - [ ] 🟥 Insert the new section between line 78 (`ActualMetricsView`) and line 80 (the `if let polyline …` map block). Render gate:
    ```swift
    if shouldShowSegmentGraph {
        CompletedSegmentGraphView(laps: laps, sport: session.sport,
                                  vma: vma, ftp: ftp, css: css, maxHr: maxHr)
    }
    ```
  - [ ] 🟥 Computed `shouldShowSegmentGraph`:
    - `false` if `laps.count < 2` (no laps or single-lap)
    - `false` if `session.sport.caseInsensitiveCompare("brick") == .orderedSame`
    - `true` otherwise

- [ ] 🟥 **Phase 6: QA + polish**
  - [ ] 🟥 Manual QA scenarios on simulator + device:
    1. Run with manual laps + VMA set (canonical) — bars vary in height by intensity bucket
    2. Run with auto-laps only (no VMA) — bars roughly equal width, session-normalized heights
    3. Bike with power + FTP set — power-driven heights
    4. Bike without power, with maxHr — HR fallback heights
    5. Swim pool with CSS — distance-driven widths, CSS-normalized heights
    6. Brick session — graph hidden
    7. Single-lap activity — graph hidden
    8. Manual / very short activity (no laps) — graph hidden
  - [ ] 🟥 Tooltip drag sweep — finger slides across bars, tooltip updates without jank, x-clamps at chart edges, dismisses on release.
  - [ ] 🟥 Update `architecture.md` with the new files + the new TodayCompletedCard composition note.

## Manual QA / Cannot-be-automated checks

- Tooltip floating-bubble x-clamping on edge bars (visual only)
- Drag-sweep responsiveness on real device (haptics not added; pure visual)
- Graph readability against light + dark backgrounds (verify intensity colors hold contrast)
- Session-normalized fallback shape for an actual no-VMA/no-FTP user — visually plausible

## Rollback

This is a pure additive UI feature with no schema or write-path changes.
- **Code rollback:** revert the merge commit. No data cleanup.
- **Toggle in production:** wrap the section render in `if Configuration.featureFlags.completedSegmentGraph` if needed — but feature is low-risk, no flag recommended for v1.
