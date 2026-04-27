# DRO-231: Build Today (Home) tab — Anchor + Shape design

**Overall Progress:** `100%` 🟩

> **Status: Shipped.** All 5 phases (DRO-233 through DRO-237) merged on `feature/DRO-231-build-today-home-tab`, plus 4 QA-driven follow-ups: tappable week-strip pills, external day label + week-strip reorder, planned distance from segments, and PR #67 (horizontal swipe) reverted at the user's request. Follow-up tickets DRO-238/239/240/241 capture deferred polish.

## TLDR

Replace the current Home tab placeholder (Dromos logo + "Coming soon" — landed via DRO-230) with a hero-focused Today screen: sport-progress strip on top, today's session card(s) as the unambiguous hero, 7-day week strip at the bottom. Eight session-state variations (planned single, planned multi, completed no-map, completed with-map, missed, rest, race, empty). Reuses `SessionMatcher`, `WorkoutLibraryService`, `IntensityColorHelper`, `StravaService` — does not introduce new edge functions or DB tables. Adds one derived computation in `PlanService` (`weeklySportTotals`) plus one new color asset (`Color.errorStrong`).

## Critical Decisions

- **No new shared components folder yet** — Existing pattern is component-per-file inside `Features/Home/` (e.g., [WorkoutGraphView.swift](Dromos/Dromos/Features/Home/WorkoutGraphView.swift), [WorkoutStepsView.swift](Dromos/Dromos/Features/Home/WorkoutStepsView.swift)). New components stay in `Features/Home/`. A formal `Core/Components/` migration is out of scope; revisit when a second tab needs the same components.
- **Tokens: `Color.errorStrong` only — no `Space` / `Radius` / `Typography` enums in this ticket** — DESIGN.md §3-4 calls for `Space` and `Radius` enums but they don't exist anywhere in the codebase yet. Introducing them in a single feature would either require a touch-everything refactor or create a tokens-vs-raw-numbers schism. Decision: spec uses **raw numbers consistent with DESIGN.md** (`16` for lg padding, `24` for card radius) and a separate ticket can later promote them. Only `Color.errorStrong` is added now because the missed-state copy needs it.
- **`Color.errorStrong` lives in the asset catalog** — Two new colorsets in [Assets.xcassets](Dromos/Dromos/Resources/Assets.xcassets): `ErrorStrong.colorset` (light `#FF3B30` / dark `#FF453A`). Per DESIGN.md §0 rule 2: "no hex literals in Swift code." Added alongside existing `AccentColor`, `CardSurface`, `PageSurface`. A `Color.errorStrong` Swift extension is added at the bottom of [IntensityColorHelper.swift](Dromos/Dromos/Features/Home/IntensityColorHelper.swift) to match the existing `Color.intensity()` / `Color.phaseColor()` pattern.
- **Reuse `WorkoutGraphView` and `WorkoutStepsView` as engines** — Don't rebuild from scratch. The new `WorkoutShape` and `WorkoutStepList` components in this spec are thin wrappers that adopt the new design tokens and constrain props but delegate flattening / step summary work to the existing implementations. Keeps the Calendar tab in sync — they share these views.
- **`StravaRouteMapView` polyline restyle is global** — Calendar tab uses the same map. Changing the stroke from `.blue` to `Color.accentColor` affects both surfaces. Per DESIGN.md, accent green is the single brand color — defensible to change globally.
- **Sport-progress derivation is client-side** — `PlanService.weeklySportTotals(for:with:)` is a pure function over already-loaded `[PlanSession]` and `[StravaActivity]`. No new DB query, no new RPC. Recomputed on view appear and on Strava sync completion (existing `stravaService.isSyncing` listener pattern, same as Calendar).
- **Multi-session ordering: planned-on-top, completed-at-bottom, then `order_in_day`** — Implemented as a stable sort: `sortedSessions = sessions.sorted { ($0.isCompleted ? 1 : 0, $0.orderInDay) < ($1.isCompleted ? 1 : 0, $1.orderInDay) }`. Tied with `order_in_day` keeps source-of-truth ordering inside completion buckets.
- **Midnight rollover is implicit** — No new timer or notification. `SessionMatcher.match()` already uses calendar-day boundaries (`sessionDayStart < todayStart`), so when the user opens Home after midnight, the data naturally reflects the new day. View `.task` re-runs on first appear after backgrounding.
- **Pull-to-refresh wraps the entire scroll area** — A single `.refreshable { await stravaService.syncActivities() }` on the outermost `ScrollView`. Not per-section. Simpler.
- **No edit mode on Home** — `.toolbar` block omitted entirely. Edit mode lives only on Calendar (per DRO-230's spec).
- **Tab re-tap behavior** — New `homeReset` binding in [MainTabView.swift](Dromos/Dromos/App/MainTabView.swift) (mirrors existing `calendarReset` plumbing). Toggled on Home tab re-tap. HomeView listens via `.onChange(of: homeReset)`, triggers `await stravaService.syncActivities()` and scrolls the outer `ScrollView` to top via `ScrollViewReader`.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Home/HomeView.swift` | MODIFY | Replace placeholder body with full Today implementation. Receive `authService`, `planService`, `profileService`, `stravaService`, `homeReset` bindings (mirror Calendar). Compose `SportProgressStrip` + today-hero state-router + `WeekDayStrip`. Implement `loadCompletionStatuses`, `weeklySportTotals` recomputation, scroll-to-top on tab re-tap. |
| `Dromos/Dromos/App/MainTabView.swift` | MODIFY | Add `@State private var homeReset = false`. Wire to `tabSelection` setter (toggle when `.home` is re-tapped). Pass services + `homeReset` binding into `HomeView()`. Match the existing `calendarReset` pattern at [MainTabView.swift:38-67](Dromos/Dromos/App/MainTabView.swift#L38-L67). |
| `Dromos/Dromos/Features/Home/SportProgressStrip.swift` | CREATE | Three-column sport-progress component. Inputs: `[Sport: (doneMinutes: Int, totalMinutes: Int)]`. Renders SWIM / BIKE / RUN labels, `H:MM / H:MM` numbers, 4pt accent fill bar capped at 100%. |
| `Dromos/Dromos/Features/Home/TodayPlannedCard.swift` | CREATE | Renders State A (single planned). Wrapped by parent for State B (multi-session — array of cards). Inputs: `session: PlanSession`, athlete metrics (`ftp`, `vma`, `css`, `maxHr`), optional `template: WorkoutTemplate?`, `sequenceContext: (index: Int, total: Int)?` (nil = single). Composes header row, name, rationale, `WorkoutShape`, `WorkoutStepList`. |
| `Dromos/Dromos/Features/Home/TodayCompletedCard.swift` | CREATE | Renders State C / D (completed, optional GPS map). Inputs: `session`, `activity: StravaActivity`, athlete metrics, `template`, `sequenceContext`. Composes `CompletedTag`, name, `CoachFeedbackBlock`, `ActualVsPlannedTable`, optional `StravaRouteMapView` (when `summaryPolyline` non-nil), disclosure with inline-expanded planned workout. |
| `Dromos/Dromos/Features/Home/TodayMissedCard.swift` | CREATE | Renders State E (tag-only). Inputs: `session`. Tag (`✗ NOT COMPLETED` in `Color.errorStrong`) + dimmed name. No rationale, no shape, no steps, no CTA. |
| `Dromos/Dromos/Features/Home/WeekDayStrip.swift` | CREATE | 7 day-pills, equal flex width. Inputs: `weekSessions: [Weekday: [PlanSession]]`, `completionStatuses: [UUID: SessionCompletionStatus]`, `today: Weekday`. Pill states: today / completed / planned / missed / rest. Glyph rules: `Run` / `Bike` / `Swim` / `Brick` (when `isBrick`) / `Run+Sw` etc. for multi-session / `Race` (sport=race) / `Rest` (no sessions). |
| `Dromos/Dromos/Features/Home/WorkoutShape.swift` | CREATE | Lightweight wrapper around the bar-chart subset of `WorkoutGraphView` for use in cards. Inputs: `[FlatSegment]`. Renders the 56pt-tall horizontal bar (no axis, no tap popover). Reuses `Color.intensity(for:isRecovery:)`. |
| `Dromos/Dromos/Features/Home/WorkoutStepList.swift` | CREATE | Reusable wrapper around `WorkoutStepsView` adding the `RepeatBlock` accent treatment for nested repeats. Inputs: `[StepSummary]`. Renders rows with right-aligned duration, target line below, repeat blocks with multiplier prefix and accent left-border. |
| `Dromos/Dromos/Features/Home/CoachFeedbackBlock.swift` | CREATE | Soft accent fill block with label `COACH FEEDBACK`. Inputs: `feedback: String?` and `isLoading: Bool`. Three states: filled (text), loading (silent skeleton — three accent-tinted shimmer bars, 2.6s `ease-in-out`, staggered), missing (component returns `EmptyView()`). Honors `accessibilityReduceMotion`. |
| `Dromos/Dromos/Features/Home/ActualVsPlannedTable.swift` | CREATE | 3-column grid (Metric / Actual / Planned). Inputs: `session: PlanSession`, `activity: StravaActivity`. Sport-aware row construction: run = duration/distance/avg-pace/HR, bike = duration/avg-watts (hidden if nil)/distance/HR, swim = duration/distance/avg-pace/HR. |
| `Dromos/Dromos/Features/Home/EmptyHomeHero.swift` | CREATE | State H (no plan). Dromos mark + headline "Generate your first plan" + body copy + primary CTA routing to `PlanGenerationView`. |
| `Dromos/Dromos/Features/Home/SessionCardView.swift` | MODIFY | Restyle `RestDayCardView` and `RaceDayCardView` to new Home tokens (24pt radius, header row pattern, monochrome metadata). Per Stance #1 — phase color stays out of these cards. Calendar tab continues to use the restyled versions (cosmetic-only change there). |
| `Dromos/Dromos/Features/Home/StravaRouteMapView.swift` | MODIFY | Change `MapPolyline.stroke(.blue, lineWidth: 3)` → `MapPolyline.stroke(Color.accentColor, lineWidth: 3)`. |
| `Dromos/Dromos/Features/Home/IntensityColorHelper.swift` | MODIFY | Add `Color.errorStrong` extension (1 line) referencing the new asset. Existing extensions untouched. |
| `Dromos/Dromos/Resources/Assets.xcassets/ErrorStrong.colorset/Contents.json` | CREATE | New colorset. Light `#FF3B30`, dark `#FF453A`. Mirror the structure of `AccentColor.colorset`. |
| `Dromos/Dromos/Core/Services/PlanService.swift` | MODIFY | Add `func weeklySportTotals(for week: PlanWeek, with activities: [StravaActivity]) -> [String: (done: Int, total: Int)]`. Pure function. Per-sport: `total` = sum of `session.durationMinutes` grouped by `lower(session.sport)`; `done` = sum of `activity.movingTime / 60` for activities matched via `SessionMatcher.match()` on the week's sessions. |
| `.claude/context/architecture.md` | MODIFY | Update `Features/Home/` description: lightweight placeholder → full Today screen with hero session card, sport-progress strip, week strip. Add new component files. Update Tab navigation behavior (Home now has services + reset binding like Calendar). |

## Component specs

### `SportProgressStrip`

```swift
struct SportProgressStrip: View {
    let totals: [String: SportTotals]   // keyed by lowercased sport: "swim", "bike", "run"

    struct SportTotals {
        let doneMinutes: Int
        let totalMinutes: Int
    }
}
```

- Container: `HStack(spacing: 12)`, card surface (`Color.cardSurface`), 16pt corner radius, 12pt vertical padding, 16pt horizontal padding.
- Per column (`VStack(spacing: 6)`): label (`.caption`, `.secondary`, uppercase via `.textCase(.uppercase)`, `.tracking(2)`) → numbers `done / total` formatted `H:MM` (`.caption`, tabular-nums, `done` in `.primary` semibold, `/total` in `.secondary` regular) → 4pt-tall track with accent fill (`min(done/total, 1.0) * width`).
- If `totalMinutes == 0` (no planned sessions for that sport this week), bar is at 0 with no fill, label still shown.

### `TodayPlannedCard`

```swift
struct TodayPlannedCard: View {
    let session: PlanSession
    let template: WorkoutTemplate?
    let ftp: Int?
    let vma: Double?
    let css: Int?
    let maxHr: Int?
    let sequenceContext: (index: Int, total: Int)?  // nil = single-session day
}
```

- Container: card surface, 24pt radius, 16pt padding.
- **Header row** (`HStack`):
  - If `sequenceContext == nil`: `TODAY` label (left, `.caption`, `.secondary`, uppercase, tracked).
  - Else: `SessionSequenceBadge(index: ctx.index)` + `"{Sport} · {type.lowercased()}"` (`.caption`, `.secondary`).
  - Spacer.
  - Right: `"{formattedDuration} · {sport.lowercased()}"` (`.caption`, `.secondary`, tabular-nums).
- **Session name**: `Text(session.displayName)`, `.title2.bold()`, `-0.02em` tracking via `.kerning(-0.4)`.
- **Rationale paragraph**: `if let notes = session.notes, !notes.isEmpty { Text(notes).font(.body).foregroundColor(.secondary) }`. Hidden if empty.
- **Workout shape**: `WorkoutShape(segments: workoutLibrary.flattenedSegments(for: session, ftp: ftp, vma: vma, css: css, maxHr: maxHr))` — only if non-empty.
- **Step list**: `Divider()` then `WorkoutStepList(steps: workoutLibrary.stepSummaries(for: session, ftp: ftp, vma: vma, css: css, maxHr: maxHr))` — only if non-empty.
- **Card NOT tappable.** No `.onTapGesture`.

### `TodayCompletedCard`

```swift
struct TodayCompletedCard: View {
    let session: PlanSession
    let activity: StravaActivity
    let template: WorkoutTemplate?
    let ftp: Int?
    let vma: Double?
    let css: Int?
    let maxHr: Int?
    let sequenceContext: (index: Int, total: Int)?

    @State private var showPlannedWorkout = false
}
```

- Container: same as planned.
- **Header row**: `CompletedTag()` (left) + Spacer + `"{formattedActualDuration} · {sport.lowercased()}"` (right).
- **Session name**: same as planned.
- **CoachFeedbackBlock**:
  - `feedback = session.feedback`
  - `isLoading = session.feedback == nil && shouldExpectFeedback(session, activity)` — true when activity is matched but feedback row hasn't been written yet.
  - `shouldExpectFeedback` heuristic: `activity.id != nil && session.matchedActivityId == activity.id` (the feedback edge function should have been triggered).
- **ActualVsPlannedTable** with `session` + `activity`.
- **GPS Map** (only when `summaryPolyline != nil && !summaryPolyline.isEmpty`): `StravaRouteMapView(encodedPolyline: polyline)` followed by a small overlay row showing `"{distance} · +{elevation}m"`.
- **Disclosure**: `Button { withAnimation { showPlannedWorkout.toggle() } } label: { ... "View planned workout" + chevron }`. When toggled on: render `WorkoutShape` + `WorkoutStepList` (same as planned card, rationale skipped).

### `TodayMissedCard`

```swift
struct TodayMissedCard: View {
    let session: PlanSession
    let sequenceContext: (index: Int, total: Int)?
}
```

- Container: card surface, 24pt radius, **12pt padding** (smaller than planned/completed — reduces visual weight).
- **Header row** (`HStack`):
  - If single: `MissedTag()` (left). Else: `SessionSequenceBadge(index: ctx.index)` + `"{Sport} · {type}"`.
  - Spacer + `"{formattedDuration} · {sport.lowercased()}"` (`.caption`, `.secondary`).
- **Session name**: `Text(session.displayName)`, `.headline`, `.foregroundColor(.secondary)` (semantic dim, no opacity).
- **No rationale, no shape, no step list, no CTA.**

### `CompletedTag` and `MissedTag`

```swift
struct CompletedTag: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
            Text("COMPLETED TODAY")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(1)
        }
        .foregroundColor(Color.accentColor)
    }
}

struct MissedTag: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
            Text("NOT COMPLETED")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(1)
        }
        .foregroundColor(Color.errorStrong)
    }
}
```

### `SessionSequenceBadge`

```swift
struct SessionSequenceBadge: View {
    let index: Int  // 1-based
    var body: some View {
        Text("\(index)")
            .font(.caption2.weight(.bold))
            .foregroundColor(Color.cardSurface)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Color.primary))
    }
}
```

### `WorkoutShape`

```swift
struct WorkoutShape: View {
    let segments: [FlatSegment]
}
```

- `HStack(alignment: .bottom, spacing: 2)` of bars.
- Per bar: width `flex` proportional to `segment.durationMinutes` (with min 2pt enforced via `.frame(minWidth: 2)`). Height = intensity-based mapping (see DRO-231 Workout-shape rendering rules — 5 buckets, 25-100%). Color = `Color.intensity(for: segment.intensityPct, isRecovery: segment.isRecovery)`. Corner radius 3pt.
- Outer height: 56pt.

### `WorkoutStepList`

```swift
struct WorkoutStepList: View {
    let steps: [StepSummary]
}
```

- Renders rows with right-aligned duration text and target sub-line. Repeat blocks (`step.isRepeatBlock == true`) get a 2pt accent left-border, 12pt left-padding, with the multiplier prefix (`5×`) in accent semibold.
- Sub-task: confirm `StepSummary` already exposes a way to detect repeat blocks (per architecture.md it does — `isRepeatBlock`). If repeat-inner steps need separate treatment, extend `StepSummary` (defer to subtask in Step 2).

### `CoachFeedbackBlock`

```swift
struct CoachFeedbackBlock: View {
    let feedback: String?
    let isLoading: Bool
}
```

- Container: `Color.accentColor.opacity(0.12)` fill, 12pt radius, 12pt padding.
- Label `COACH FEEDBACK` (`.caption`, `.secondary`, uppercase, tracked).
- Body:
  - `feedback != nil`: `Text(feedback!).font(.body)`.
  - `feedback == nil && isLoading`: 3 stacked `SkeletonBar` views, staggered animation. `@State private var phase = 0` → animated via `Timer.publish` or `.task` running an `await Task.sleep` loop. Honor `@Environment(\.accessibilityReduceMotion)` — if true, render bars at 0.5 opacity static.
  - `feedback == nil && !isLoading`: `EmptyView()` (caller doesn't render parent block).

### `WeekDayStrip`

```swift
struct WeekDayStrip: View {
    let days: [DayPill]   // exactly 7

    struct DayPill: Identifiable {
        let id = UUID()
        let weekday: Weekday
        let glyph: String          // "Run" | "Bike" | "Swim" | "Brick" | "Run+Sw" | "Race" | "Rest"
        let durationLabel: String? // "1h", "55'", nil for rest
        let state: PillState
    }

    enum PillState { case today, completed, planned, missed, rest }
}
```

- `HStack(spacing: 8)`, each pill `.frame(maxWidth: .infinity)`, 12pt radius, 60pt min height, vertical center, 2pt internal spacing.
- Backgrounds:
  - `.today` → `Color.primary` (white text overlay).
  - `.completed` → `Color.accentColor.opacity(0.12)`.
  - `.planned` → `Color.cardSurface`.
  - `.missed` → `Color.errorStrong.opacity(0.12)`.
  - `.rest` → `Color.cardSurface` (lower-contrast text via `.tertiary`).

## Sport totals computation

```swift
extension PlanService {
    /// Returns per-sport (done, total) totals in minutes for a single week.
    /// `done` derives from matched Strava activity moving time; `total` from planned durations.
    /// Brick sessions count toward their `sport` field only (no double-count).
    func weeklySportTotals(
        for week: PlanWeek,
        with activities: [StravaActivity]
    ) -> [String: (done: Int, total: Int)] {
        let sessions = week.allSessions  // existing accessor

        // Match each session to its activity (reuse SessionMatcher).
        let matched = SessionMatcher.match(sessions: sessions, activities: activities)

        var result: [String: (done: Int, total: Int)] = [
            "swim": (0, 0), "bike": (0, 0), "run": (0, 0)
        ]
        for session in sessions {
            let key = session.sport.lowercased()
            guard result[key] != nil else { continue }  // ignore non-tri sports
            result[key]!.total += session.durationMinutes

            if case .completed(let activity) = matched[session.id] ?? .planned {
                result[key]!.done += Int(activity.movingTime / 60)
            }
        }
        return result
    }
}
```

Note: `PlanWeek.allSessions` may not exist — confirm during implementation; fall back to flattening `sessionsByDay`.

## Lifecycle wiring

In `HomeView`:

```swift
@Binding var homeReset: Bool

@State private var completionStatuses: [UUID: SessionCompletionStatus] = [:]
@State private var sportTotals: [String: (done: Int, total: Int)] = [:]
@State private var activities: [StravaActivity] = []

private var currentWeek: PlanWeek? { planService.trainingPlan?.currentWeek() }

var body: some View {
    NavigationStack {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 24) {
                    SportProgressStrip(totals: ...)
                    TodayHero(...)
                    WeekDayStrip(...)
                }
                .padding(.horizontal, 16)
                .id("top")
            }
            .refreshable { await stravaService.syncActivities() }
            .task { await loadCompletionAndTotals() }
            .onChange(of: stravaService.isSyncing) { _, isSyncing in
                if !isSyncing { Task { await loadCompletionAndTotals() } }
            }
            .onChange(of: homeReset) { _, _ in
                Task {
                    await stravaService.syncActivities()
                    withAnimation { scrollProxy.scrollTo("top", anchor: .top) }
                }
            }
        }
    }
}

private func loadCompletionAndTotals() async {
    guard let week = currentWeek else { return }
    activities = await stravaService.fetchActivities(from: week.startDate, to: week.endDate)
    completionStatuses = SessionMatcher.match(sessions: week.allSessions, activities: activities)
    sportTotals = planService.weeklySportTotals(for: week, with: activities)
}
```

## Tasks

- [ ] 🟥 **Step 1: Tokens + asset (`Color.errorStrong`)**
  - [ ] 🟥 Create `Dromos/Dromos/Resources/Assets.xcassets/ErrorStrong.colorset/Contents.json` (light `#FF3B30`, dark `#FF453A`) — mirror `AccentColor.colorset` structure.
  - [ ] 🟥 Add `Color.errorStrong` extension at the bottom of `IntensityColorHelper.swift`.
  - [ ] 🟥 Update `DESIGN.md` §1 color table to include the new token.

- [ ] 🟥 **Step 2: Workout primitives (`WorkoutShape`, `WorkoutStepList`)**
  - [ ] 🟥 Create `WorkoutShape.swift`. Reuse `Color.intensity()`. Snapshot test with simple, complex, and swim segments.
  - [ ] 🟥 Create `WorkoutStepList.swift`. Wrap `WorkoutStepsView` if signature aligns; else port the rendering and add `RepeatBlock` accent treatment for `step.isRepeatBlock`. Snapshot test with the real Tuesday VO2 structure (5×3').

- [ ] 🟥 **Step 3: Status tags + feedback block**
  - [ ] 🟥 Create `CompletedTag` and `MissedTag` (one file each, ~15 LoC).
  - [ ] 🟥 Create `SessionSequenceBadge`.
  - [ ] 🟥 Create `CoachFeedbackBlock` with the silent skeleton loading state. Honor `accessibilityReduceMotion`. Snapshot tests for all three states (filled / loading / missing).

- [ ] 🟥 **Step 4: Sport-progress strip + data**
  - [ ] 🟥 Add `PlanService.weeklySportTotals(for:with:)`. Confirm `PlanWeek.allSessions` accessor or use `sessionsByDay.values.flatMap`.
  - [ ] 🟥 Create `SportProgressStrip.swift`. Cap bar at 100% visually, numbers honest.
  - [ ] 🟥 Unit test the totals function with a brick session, multi-session days, and partial completion.

- [ ] 🟥 **Step 5: `TodayPlannedCard`**
  - [ ] 🟥 Create `TodayPlannedCard.swift`. Wire to `WorkoutLibraryService.flattenedSegments` + `stepSummaries`.
  - [ ] 🟥 Render `sequenceContext` variants (single → `TODAY` label; multi → badge + `Sport · type`).
  - [ ] 🟥 Hide rationale block when `session.notes` is empty/nil.
  - [ ] 🟥 Verify card is NOT tappable (no `.onTapGesture`).

- [ ] 🟥 **Step 6: `TodayCompletedCard` (no map → with map)**
  - [ ] 🟥 Create `ActualVsPlannedTable.swift` with sport-aware row builders (run / bike / swim).
  - [ ] 🟥 Hide bike avg-power row when `activity.averageWatts == nil`.
  - [ ] 🟥 Create `TodayCompletedCard.swift`. Compose tag + name + feedback + table + map (conditional) + disclosure.
  - [ ] 🟥 Update `StravaRouteMapView`: change `.stroke(.blue, lineWidth: 3)` → `.stroke(Color.accentColor, lineWidth: 3)`.
  - [ ] 🟥 `shouldExpectFeedback(session, activity)` heuristic for the loading skeleton.
  - [ ] 🟥 Inline-expand "View planned workout" disclosure with `WorkoutShape` + `WorkoutStepList`.

- [ ] 🟥 **Step 7: `TodayMissedCard`**
  - [ ] 🟥 Create `TodayMissedCard.swift` per the tag-only spec. 12pt padding (lighter than planned/completed). No rationale/shape/steps/CTA.

- [ ] 🟥 **Step 8: Restyle existing cards + empty state**
  - [ ] 🟥 Restyle `RestDayCardView` in `SessionCardView.swift`: 24pt radius, header row pattern (`TODAY` + `Rest day`), `session.notes` rationale only when present.
  - [ ] 🟥 Restyle `RaceDayCardView`: new tokens, keep race-leg list, ensure it coexists with sport-progress + week-strip (no full-screen takeover).
  - [ ] 🟥 Create `EmptyHomeHero.swift`. Dromos mark + headline + body + CTA → `PlanGenerationView` route.

- [ ] 🟥 **Step 9: `WeekDayStrip`**
  - [ ] 🟥 Create `WeekDayStrip.swift`. Glyph rules: `Run` / `Bike` / `Swim` / `Brick` / `Run+Sw` (2 sports) / `Race` (sport=race) / `Rest`.
  - [ ] 🟥 5 pill states wired (today / completed / planned / missed / rest).
  - [ ] 🟥 Pills are NOT tappable in v1.

- [ ] 🟥 **Step 10: `HomeView` assembly + lifecycle**
  - [ ] 🟥 Modify `MainTabView.swift`: add `@State homeReset`, wire to `tabSelection` setter on `.home` re-tap, pass services + binding into `HomeView()`.
  - [ ] 🟥 Modify `HomeView.swift`: replace placeholder with full implementation. Receive services + `homeReset`. Compose strip + hero state-router + week-strip in a `ScrollView` with `.refreshable`.
  - [ ] 🟥 Implement `loadCompletionAndTotals()`. Trigger on `.task`, on `stravaService.isSyncing` going false, and on `homeReset` toggle (after sync).
  - [ ] 🟥 Hero state router: empty plan → `EmptyHomeHero`; today's sessions = 0 → `RestDayCardView`; today is race day → `RaceDayCardView`; one session → `TodayPlannedCard` or `TodayCompletedCard` or `TodayMissedCard` per `SessionMatcher` status; multi-session → `Today · N sessions` header + ordered card stack (planned-on-top, then completed, ascending `order_in_day`).
  - [ ] 🟥 `ScrollViewReader` + scroll-to-top on tab re-tap.
  - [ ] 🟥 No `.toolbar` (no edit mode).

- [ ] 🟥 **Step 11: Cleanup + context docs**
  - [ ] 🟥 Update `.claude/context/architecture.md`: Home section, new components in `Features/Home/`, `MainTabView` Tab navigation behavior (Home receives services + reset binding).
  - [ ] 🟥 Manual QA on a real plan with: planned single, multi-session day, completed (with + without map), missed, rest, race, empty (no plan).
  - [ ] 🟥 Verify pull-to-refresh triggers Strava sync + status refreshes.
  - [ ] 🟥 Verify tab re-tap scrolls to top + refreshes.
  - [ ] 🟥 Verify midnight rollover with a sample completed-yesterday session (overnight rotation).

## Context Doc Updates

After implementation:
- `architecture.md` — Home section description, new components list, MainTabView Tab navigation behavior, color extensions list (add `Color.errorStrong`).
- `schema.md` — no schema changes.
- `ai-pipeline.md` — no AI pipeline changes.

## Open Questions

None — all resolved during `/discover` (see [DRO-231](https://linear.app/dromosapp/issue/DRO-231) description).
