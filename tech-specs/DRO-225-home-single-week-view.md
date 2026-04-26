# DRO-225: Home — single-week view with chevron + swipe navigation

**Overall Progress:** `90%`

## TLDR
Replace Home's progressively-revealing multi-week ScrollView with a paged single-week view. Top header gets two lines: a chevron-flanked semantic title (`Current Week - 3/16`) and a Calendar-style phase + date label on one line. Navigation via prev/next chevrons or left/right swipe. Removes auto-scroll-to-today, the "Show next week" button, and the "Home" navigation title. Strava completion fetch is scoped to the displayed week with a per-week in-memory cache; cards skeleton-render via `.redacted` while loading.

## Critical Decisions

- **Paged `TabView` over manual `DragGesture`** — Use `TabView(selection: $currentWeekIndex) { ForEach(plan.planWeeks) ... }` with `.tabViewStyle(.page(indexDisplayMode: .never))`. Native swipe + arrow taps both drive the same `selection` binding; SwiftUI handles the animation. Inner vertical `ScrollView` per week coexists fine with horizontal paging.
- **New `HomeWeekHeader` component (don't generalize `WeekHeaderView`)** — The existing [WeekHeaderView.swift](Dromos/Dromos/Features/Plan/WeekHeaderView.swift) is a 3-row centered layout (arrows row, phase row, date row). The new spec is 2 rows with phase + date inline. Adding a variant flag would muddy both; cleaner to keep them separate. Calendar tab is untouched.
- **Skeleton via `.redacted(reason: .placeholder)`** — No custom skeleton component. Apply `.redacted` to the `SessionCardView` instances in the day list while the displayed week's completion fetch is in flight (and only when Strava is connected). `RestDayCardView` and `RaceDayCardView` are NOT redacted (they have no Strava-derived state).
- **Per-week cache keyed by week index** — `@State var completionCacheByWeek: [Int: [UUID: SessionCompletionStatus]] = [:]`. Backtracking is instant. Cache invalidates on Strava sync completion (existing `stravaService.isSyncing` listener) — purge all entries, re-fetch only the displayed week.
- **`scrollToToday` removed entirely** — No replacement. User lands at top of week's day list (Monday). Eliminates the Sunday edge case and any layout-timing bugs.
- **Pending feedback scoped to displayed week only** — `generatePendingFeedback` runs over completed sessions in the currently displayed week, not the whole plan. Avoids silent fan-out as the user paginates.
- **Tab re-tap behavior** — `scrollReset` toggle resets `currentWeekIndex` to `plan.currentWeekIndex()`. No scroll. Existing `MainTabView` plumbing ([MainTabView.swift:39-58](Dromos/Dromos/App/MainTabView.swift#L39-L58)) is unchanged.
- **Edit mode unchanged** — Move-up/down arrows on `SessionCardView` still operate within the displayed week only (same as today). No cross-week moves introduced.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Home/HomeView.swift` | MODIFY | Drop `lastVisibleWeekIndex`, `showNextWeekButton`, `weekSectionHeader`, `scrollToToday`. Add `currentWeekIndex` state, `completionCacheByWeek`, `loadingWeeks`. Replace `ScrollViewReader` + multi-week `ForEach` with paged `TabView`. Remove `.navigationTitle("Home")`. Scope `loadCompletionStatuses` and `generatePendingFeedback` to one week. |
| `Dromos/Dromos/Features/Home/HomeWeekHeader.swift` | CREATE | New 2-row header component: row 1 chevrons + semantic title, row 2 phase badge + date range inline. |
| `.claude/context/architecture.md` | MODIFY | Update Home section description: single-week paged view with HomeWeekHeader; remove "auto-scroll to today" + "rolling weeks" wording. Update tab-reset description to remove "progressive disclosure". |

## Component Specs

### `HomeWeekHeader`

```swift
struct HomeWeekHeader: View {
    let weekNumber: Int            // 1-indexed
    let totalWeeks: Int
    let phase: String
    let weekStartDate: Date
    let titleVariant: TitleVariant // .currentWeek | .lastWeek | .nextWeek | .other
    let onPrevious: () -> Void
    let onNext: () -> Void
    let canGoPrevious: Bool
    let canGoNext: Bool
}

enum TitleVariant {
    case currentWeek   // "Current Week - {N}/{Total}"
    case lastWeek      // "Last Week - {N}/{Total}"
    case nextWeek      // "Next Week - {N}/{Total}"
    case other         // "Week {N} / {Total}"
}
```

**Layout:**
- Row 1 (`HStack`): chevron-left (slightly grey: `Color.secondary.opacity(0.6)`, fades to `Color.secondary.opacity(0.25)` when disabled) — Spacer — title (`.title2`, `.bold`) — Spacer — chevron-right (same styling).
- Row 2 (`HStack`): phase dot (8×8 circle, `Color.phaseColor(for: phase)`) + `"{phase} phase"` (`.subheadline`, phase color) — small spacer (e.g., 12pt) — date range (`.caption`, `.secondary`). Use the existing `weekDateRange` formatting (`"Feb 10th - 16th"` / `"Feb 28th - Mar 6th"`) — move that helper from HomeView into a shared location OR duplicate inline (small enough). **Recommend: keep `weekDateRange` + `ordinal` as private statics on `HomeWeekHeader`** to keep HomeView lean.
- Container: `VStack(spacing: 8)`, `.padding(.vertical, 8)`, `.padding(.horizontal)`.

### `HomeView` — new state

```swift
@State private var currentWeekIndex: Int = 0
@State private var completionCacheByWeek: [Int: [UUID: SessionCompletionStatus]] = [:]
@State private var loadingWeeks: Set<Int> = []
```

Removed: `lastVisibleWeekIndex`, `completionStatuses` (replaced by `completionCacheByWeek[currentWeekIndex] ?? [:]`).

### `HomeView` — content body shape

```swift
private func contentView(plan: TrainingPlan) -> some View {
    VStack(spacing: 0) {
        HomeWeekHeader(
            weekNumber: plan.planWeeks[currentWeekIndex].weekNumber,
            totalWeeks: plan.planWeeks.count,
            phase: plan.planWeeks[currentWeekIndex].phase,
            weekStartDate: plan.planWeeks[currentWeekIndex].startDateAsDate ?? Date(),
            titleVariant: titleVariant(for: currentWeekIndex, plan: plan),
            onPrevious: { goToWeek(currentWeekIndex - 1, plan: plan) },
            onNext:     { goToWeek(currentWeekIndex + 1, plan: plan) },
            canGoPrevious: currentWeekIndex > 0,
            canGoNext: currentWeekIndex < plan.planWeeks.count - 1
        )

        TabView(selection: $currentWeekIndex) {
            ForEach(plan.planWeeks.indices, id: \.self) { idx in
                weekContent(weekIndex: idx, plan: plan)
                    .tag(idx)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: 0.25), value: currentWeekIndex)
    }
    .background(Color.pageSurface)
    .task { await loadIfNeeded(weekIndex: currentWeekIndex, plan: plan) }
    .onChange(of: currentWeekIndex) { _, newIdx in
        Task {
            await loadIfNeeded(weekIndex: newIdx, plan: plan)
            await generatePendingFeedback(plan: plan, weekIndex: newIdx)
        }
    }
    .onChange(of: scrollReset) { _, _ in
        currentWeekIndex = plan.currentWeekIndex()
    }
    .onChange(of: stravaService.isSyncing) { oldValue, newValue in
        if oldValue && !newValue {
            completionCacheByWeek.removeAll()
            Task {
                await loadIfNeeded(weekIndex: currentWeekIndex, plan: plan)
                await generatePendingFeedback(plan: plan, weekIndex: currentWeekIndex)
            }
        }
    }
}
```

Where `weekContent(weekIndex:plan:)` is the inner `ScrollView` containing the day list (existing `daySectionView` calls), wrapped with `.redacted(reason: loadingWeeks.contains(weekIndex) ? .placeholder : [])` only on the `SessionCardView` instances (not the day header / rest / race cards).

### `HomeView` — title variant logic

```swift
private func titleVariant(for index: Int, plan: TrainingPlan) -> TitleVariant {
    let current = plan.currentWeekIndex()
    switch index {
    case current:     return .currentWeek
    case current - 1: return .lastWeek
    case current + 1: return .nextWeek
    default:          return .other
    }
}
```

### `HomeView` — load + cache

```swift
private func loadIfNeeded(weekIndex: Int, plan: TrainingPlan) async {
    guard profileService.user?.isStravaConnected == true else { return }
    guard completionCacheByWeek[weekIndex] == nil else { return }
    guard !loadingWeeks.contains(weekIndex) else { return }

    loadingWeeks.insert(weekIndex)
    defer { loadingWeeks.remove(weekIndex) }

    let week = plan.planWeeks[weekIndex]
    let days = plan.daysForWeek(week)
    let dates = days.map(\.date)
    guard let from = dates.min(), let to = dates.max() else { return }

    let paddedFrom = calendar.date(byAdding: .day, value: -1, to: from)!
    let paddedTo   = calendar.date(byAdding: .day, value:  1, to: to)!
    let activities = await stravaService.fetchActivities(from: paddedFrom, to: paddedTo)

    var sessionTuples: [(session: PlanSession, date: Date)] = []
    guard let weekStartDate = week.startDateAsDate else { return }
    for dayInfo in days {
        for session in dayInfo.sessions {
            let resolved = Weekday(fullName: session.day)
                .map { $0.date(relativeTo: weekStartDate) } ?? dayInfo.date
            sessionTuples.append((session, resolved))
        }
    }
    completionCacheByWeek[weekIndex] = SessionMatcher.match(
        sessions: sessionTuples,
        activities: activities
    )
}
```

The `daySectionView` reads `let status = (completionCacheByWeek[currentWeekIndex] ?? [:])[session.id] ?? .planned`.

### `HomeView` — feedback generation, scoped

```swift
private func generatePendingFeedback(plan: TrainingPlan, weekIndex: Int) async {
    guard profileService.user?.isStravaConnected == true else { return }
    guard let statuses = completionCacheByWeek[weekIndex] else { return }

    let weekSessionIds = Set(plan.planWeeks[weekIndex].planSessions.map(\.id))
    var didGenerate = false

    for (sessionId, status) in statuses {
        guard weekSessionIds.contains(sessionId) else { continue }
        guard case .completed(let activity) = status else { continue }
        let session = plan.planWeeks[weekIndex].planSessions.first { $0.id == sessionId }
        guard let session, session.feedback == nil else { continue }

        let feedback = await stravaService.generateSessionFeedback(
            sessionId: sessionId, activityId: activity.id
        )
        if feedback != nil { didGenerate = true }
    }

    if didGenerate { await planService.refreshPlan(userId: plan.userId) }
}
```

### `HomeView` — `goToWeek` helper

```swift
private func goToWeek(_ idx: Int, plan: TrainingPlan) {
    guard idx >= 0, idx < plan.planWeeks.count else { return }
    withAnimation(.easeInOut(duration: 0.25)) { currentWeekIndex = idx }
}
```

## Context Doc Updates
- `architecture.md` — Update Home section (line ~37-38, 100-103): replace "Multi-week rolling dashboard" + "Rolling week view with auto-scroll to today + edit mode + completion status display" with "Single-week paged dashboard with chevron + swipe navigation; per-week Strava completion cache". Update tab-reset description: "Home: toggles `homeScrollReset` → HomeView resets `currentWeekIndex` to current week" (drop "scrolls to today" + "progressive disclosure"). Add `HomeWeekHeader.swift` to the file tree under `Features/Home/`.

## Tasks

- [x] 🟩 **Step 1: Create `HomeWeekHeader.swift`**
  - [x] 🟩 New file `Dromos/Dromos/Features/Home/HomeWeekHeader.swift` with the struct + `TitleVariant` enum per spec.
  - [x] 🟩 Internal `weekDateRange(start:)` + `ordinal(_:)` helpers (copy from HomeView).
  - [x] 🟩 Chevrons disabled style: `Color.secondary.opacity(0.25)`; enabled: `Color.secondary.opacity(0.6)`.
  - [x] 🟩 SwiftUI preview with all 4 `TitleVariant` cases.

- [x] 🟩 **Step 2: Replace HomeView state**
  - [x] 🟩 Remove `@State lastVisibleWeekIndex`, `@State completionStatuses`.
  - [x] 🟩 Add `@State currentWeekIndex`, `@State completionCacheByWeek`, `@State loadingWeeks`.

- [x] 🟩 **Step 3: Replace HomeView body with paged TabView**
  - [x] 🟩 Remove the `ScrollViewReader` + multi-week `ForEach` block.
  - [x] 🟩 Build new `contentView(plan:)` per the shape above: `HomeWeekHeader` + `TabView` + `tabViewStyle(.page(indexDisplayMode: .never))`.
  - [x] 🟩 Initial `currentWeekIndex` = `plan.currentWeekIndex()` on first appear (set inside `.task` if `currentWeekIndex == 0` and plan is loaded — guard against re-init on every appear).
  - [x] 🟩 Inner per-week scroll: keep `ScrollView` + `LazyVStack` + existing `daySectionView` calls.
  - [x] 🟩 Update `daySectionView` to read status from `completionCacheByWeek[currentWeekIndex]`.

- [x] 🟩 **Step 4: Remove `.navigationTitle("Home")`**
  - [x] 🟩 Drop the navigation title. Keep the toolbar Edit button (its `ToolbarItem` placement on `.topBarTrailing` works without a title).
  - [x] 🟩 Verify the Edit button still renders correctly without a title bar text. If iOS hides the toolbar entirely without a title, set `.navigationTitle("")` + `.navigationBarTitleDisplayMode(.inline)` to keep the bar visible.

- [x] 🟩 **Step 5: Scoped completion + skeleton loading**
  - [x] 🟩 Implement `loadIfNeeded(weekIndex:plan:)` per spec.
  - [x] 🟩 Apply `.redacted(reason: loadingWeeks.contains(weekIndex) ? .placeholder : [])` on `SessionCardView` only (not RestDayCardView / RaceDayCardView / day header label).
  - [x] 🟩 Wire `.task` and `.onChange(of: currentWeekIndex)` to call `loadIfNeeded`.
  - [x] 🟩 Wire `.onChange(of: stravaService.isSyncing)` to purge cache and reload current week.

- [x] 🟩 **Step 6: Scoped feedback generation**
  - [x] 🟩 Replace existing `generatePendingFeedback(plan:)` with `generatePendingFeedback(plan:weekIndex:)` per spec.
  - [x] 🟩 Call after each successful `loadIfNeeded` and on Strava sync completion.

- [x] 🟩 **Step 7: Tab re-tap reset**
  - [x] 🟩 In `.onChange(of: scrollReset)`, set `currentWeekIndex = plan.currentWeekIndex()`. No scroll.
  - [x] 🟩 Confirm transition animates via the existing `withAnimation` wrapper on TabView selection.

- [x] 🟩 **Step 8: Delete dead code**
  - [x] 🟩 Remove `scrollToToday(proxy:plan:currentWeekIndex:)` and all references.
  - [x] 🟩 Remove `weekSectionHeader(week:currentWeekIndex:weekIndex:)`.
  - [x] 🟩 Remove `showNextWeekButton`.
  - [x] 🟩 Remove `weekDateRange` + `ordinal` from HomeView (now in `HomeWeekHeader`).
  - [x] 🟩 Remove the static `dayDateFormatter` + `monthFormatter` if no longer referenced (verify against `dayHeaderLabel` — `dayDateFormatter` is still used there, keep it; `monthFormatter` was only used by `weekDateRange`, drop it).

- [ ] 🟥 **Step 9: Manual QA**
  - [ ] 🟥 Land on current week; chevrons + swipe both navigate ±1 week.
  - [ ] 🟥 Chevrons disabled at week 1 and last week (visually faded, non-tappable).
  - [ ] 🟥 Title variants render: `Current Week - 3/16`, `Last Week - 2/16`, `Next Week - 4/16`, `Week 6 / 16`.
  - [ ] 🟥 Phase + date row sits on one line at standard text size.
  - [ ] 🟥 Skeleton placeholders appear over session cards on week change while Strava fetch is in flight (Strava-connected user only).
  - [ ] 🟥 Backtracking to a previously visited week → instant render, no skeleton.
  - [ ] 🟥 Strava sync completion → cache purges, current week refetches.
  - [ ] 🟥 Strava-disconnected user: no skeletons, all sessions show as `.planned`.
  - [ ] 🟥 Tab re-tap from another week → snaps back to current week.
  - [ ] 🟥 Edit mode still works within the displayed week (move arrows visible, completed sessions suppress arrows).
  - [ ] 🟥 Race day: `RaceDayCardView` renders correctly when displayed week contains race date.
  - [ ] 🟥 No "Home" title in the navigation bar.

- [ ] 🟥 **Step 10: Update context docs**
  - [ ] 🟥 Update `.claude/context/architecture.md` per the section above.
