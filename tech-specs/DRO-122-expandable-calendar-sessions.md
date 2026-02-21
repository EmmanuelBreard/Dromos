# DRO-122: Expandable Session Details in Calendar Plan View

**Overall Progress:** `100%`

## TLDR
Tapping a session row in the Calendar Plan view expands it inline to show workout steps + intensity graph (same components as Home tab). Tapping again collapses it. All sessions default to collapsed; leaving the page resets state.

## Critical Decisions
- **Reuse existing components**: `WorkoutStepsView` and `WorkoutGraphView` are already built and tested — no new UI components needed.
- **Local `@State` only**: Expand/collapse state tracked via `@State private var expandedSessionIDs: Set<UUID>` in `CalendarPlanView`. No persistence, resets on tab switch via existing `calendarReset` binding.
- **Thread `profileService` through**: `CalendarPlanView` currently doesn't have access to athlete metrics (ftp, vma, css). Must pass `profileService` from `MainTabView` — same pattern as `HomeView`.
- **Extract shared helpers**: `shouldShowWorkoutSteps` and `formatDistance` extracted to `PlanSession` extension to avoid duplication with `SessionCardView`.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/App/MainTabView.swift` | MODIFY | Pass `profileService` to `CalendarPlanView` |
| `Dromos/Dromos/Features/Plan/CalendarPlanView.swift` | MODIFY | Accept `profileService`, add `expandedSessionIDs` state, reset on `calendarReset` and week navigation |
| `Dromos/Dromos/Features/Plan/DaySessionRow.swift` | MODIFY | Accept expand/collapse state + callbacks, show `WorkoutStepsView` + `WorkoutGraphView` when expanded, shared helpers extracted |
| `Dromos/Dromos/Features/Home/SessionCardView.swift` | MODIFY | Use shared `shouldShowWorkoutSteps` and `formatDistance` from `PlanSession` extension |

## Context Doc Updates
- `architecture.md` — Updated `CalendarPlanView` description to mention expandable sessions and `profileService` dependency.

## Tasks

- [x] 🟩 **Step 1: Thread `profileService` to Calendar tab**
  - [x] 🟩 `MainTabView.swift:65` — Add `profileService: profileService` to `CalendarPlanView` init
  - [x] 🟩 `CalendarPlanView.swift` — Add `@ObservedObject var profileService: ProfileService` property

- [x] 🟩 **Step 2: Add expand/collapse state to `CalendarPlanView`**
  - [x] 🟩 Add `@State private var expandedSessionIDs: Set<UUID> = []`
  - [x] 🟩 In `.onChange(of: calendarReset)` — add `expandedSessionIDs.removeAll()` to reset on tab re-selection
  - [x] 🟩 Pass `expandedSessionIDs` and a toggle closure down to `DaySessionRow`
  - [x] 🟩 Reset `expandedSessionIDs` on week navigation (prev/next)

- [x] 🟩 **Step 3: Make `DaySessionRow` expandable**
  - [x] 🟩 Add required params: `expandedSessionIDs: Set<UUID>`, `onToggleExpand: (UUID) -> Void`
  - [x] 🟩 Add optional athlete metrics: `ftp: Int?`, `vma: Double?`, `css: Int?`
  - [x] 🟩 Wrap session row in `.onTapGesture` that calls `onToggleExpand(session.id)`
  - [x] 🟩 Render `WorkoutStepsView` + `WorkoutGraphView` when expanded (gated by `shouldShowWorkoutSteps`)
  - [x] 🟩 Smooth expand/collapse via `withAnimation` in parent
  - [x] 🟩 Extract `shouldShowWorkoutSteps` + `formatDistance` to shared `PlanSession` extension
  - [x] 🟩 Update `SessionCardView` to use shared helpers
  - [x] 🟩 Update all previews

- [x] 🟩 **Step 4: Update `architecture.md`**
  - [x] 🟩 Update CalendarPlanView entry to mention expandable sessions and profileService dependency
