# DRO-150: Completed Card Layout Flip

**Overall Progress:** `100%`

## TLDR

For completed session cards, flip the layout so actual Strava data (metrics + GPS map) is always visible as the primary content. The planned workout (steps + intensity graph) moves behind a locally-managed "Planned workout" collapsible disclosure at the bottom. Removes the parent-controlled expand/collapse mechanism entirely.

## Critical Decisions

- **Local `@State` for disclosure** — The "Planned workout" collapsible is managed by a `@State` inside `SessionCardView`, not by HomeView. This simplifies HomeView (removes `expandedCompletedIDs` state + toggle closure) and keeps the disclosure concern scoped to the card.
- **Remove `isExpanded`/`onToggleExpand` API** — These properties are deleted from `SessionCardView` since actual data is always visible. The header row tap gesture is also removed. This is a breaking API change but the only caller is HomeView.
- **Keep header unchanged** — Subtitle stays as planned duration (`session.formattedDuration`), not actual. No metric set changes.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Home/SessionCardView.swift` | MODIFY | Restructure completed card body: actual data always visible, planned workout behind `@State` disclosure. Remove `isExpanded`, `onToggleExpand` properties + header tap gesture. |
| `Dromos/Dromos/Features/Home/HomeView.swift` | MODIFY | Remove `expandedCompletedIDs` state, toggle closure, `isExpanded`/`onToggleExpand` from `SessionCardView` call site. Remove `expandedCompletedIDs = []` from scroll reset. |

## Context Doc Updates

- `architecture.md` — Update SessionCardView description: actual data always visible for completed, planned behind local disclosure, `isExpanded`/`onToggleExpand` removed.

## Tasks

- [x] 🟩 **Step 1: Restructure SessionCardView for completed sessions**
  - [x] 🟩 Remove `isExpanded: Bool` and `onToggleExpand: (() -> Void)?` properties (and their defaults)
  - [x] 🟩 Remove `.contentShape(Rectangle())` and `.onTapGesture { onToggleExpand?() }` from the header row HStack
  - [x] 🟩 Add `@State private var showPlannedWorkout = false`
  - [x] 🟩 Restructure `body` so that when `completionStatus` is `.completed(let activity)`:
    - After header row + brick indicator, show `Divider()` + `ActualMetricsView(activity:)` + `StravaRouteMapView` (if polyline)
    - Below that, if `template != nil`, show a "Planned workout" disclosure button (clipboard icon `doc.on.clipboard` + text + rotating chevron) that toggles `showPlannedWorkout` with `easeInOut` animation
    - When `showPlannedWorkout == true`: render the existing workout steps, intensity graph, and swim distance rows (same conditions as current rows 3-5)
  - [x] 🟩 For `.planned` and `.missed` statuses: keep the current layout unchanged (rows 3-5 render directly, no disclosure)

- [x] 🟩 **Step 2: Simplify HomeView call site**
  - [x] 🟩 Remove `@State private var expandedCompletedIDs: Set<UUID> = []`
  - [x] 🟩 Remove `expandedCompletedIDs = []` from the `scrollReset` onChange handler (line 150)
  - [x] 🟩 Remove the `let isExpanded = ...` and `let toggleClosure = ...` computations (lines 227-240)
  - [x] 🟩 Remove `isExpanded:` and `onToggleExpand:` parameters from the `SessionCardView(...)` initializer call (lines 251-252)

- [x] 🟩 **Step 3: Update context docs**
  - [x] 🟩 Update `architecture.md` — SessionCardView description: actual data always visible for completed cards, planned workout behind local `@State` disclosure, `isExpanded`/`onToggleExpand` removed from API
