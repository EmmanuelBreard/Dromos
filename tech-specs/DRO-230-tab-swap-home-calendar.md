# DRO-230 — Swap Home & Calendar tabs

**Linear:** https://linear.app/dromosapp/issue/DRO-230
**Overall Progress:** `100%`

## TLDR

Move the existing single-week paged view (currently the Home tab) into the Calendar tab as a full replacement. Replace the Home tab content with a lightweight branded placeholder. Delete the old Calendar tab implementation entirely. Pure UI / wiring change — no schema, edge function, or service changes.

## Critical Decisions

- **Folder structure** — Move only the two top-level view files (`HomeView` paged view, `HomeWeekHeader`) into a new `Features/Calendar/` folder, renamed. Leave supporting components (`SessionCardView`, `WorkoutGraphView`, `ActualMetricsView`, `WorkoutStepsView`, `StravaRouteMapView`, `IntensityColorHelper`) in `Features/Home/` since they are generic, reusable widgets that may serve future Home content. **Rationale:** minimizes file churn and preserves the option to reuse session-card-level components on a future Home dashboard without coupling them to the Calendar feature.
- **No new file for the Home placeholder** — Reuse the file path `Features/Home/HomeView.swift`. The current contents are moved/renamed wholesale to `Features/Calendar/CalendarView.swift`, then `HomeView.swift` is rewritten as the placeholder. **Rationale:** avoids two `HomeView` symbols ever co-existing and keeps the naming convention `Features/<Tab>/<Tab>View.swift`.
- **Tab re-tap behavior on Calendar** — Wires the existing `calendarReset` binding (already defined in `MainTabView`) to drive the Strava-cache-purge + week-snap logic that previously lived behind `homeScrollReset`. The old "collapse expanded sessions" logic is dropped because the new view has no expansion state. **Rationale:** keeps the user-facing refresh gesture identical to today's Home tab.
- **`AppTab` enum order unchanged** — `.home` remains the first case and the cold-launch default, even though it shows a placeholder. Confirmed in discovery.
- **Comment cleanup** — Stale references to `CalendarPlanView` / `DaySessionRow` in unrelated files (`TrainingPlan.swift`, `SessionCardView.swift`) are updated to point at `CalendarView` or removed.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Calendar/CalendarView.swift` | CREATE | Verbatim move of current `Features/Home/HomeView.swift` contents. Rename type `HomeView` → `CalendarView`. Rename `@Binding var scrollReset` → `@Binding var calendarReset`. Rename internal `.onChange(of: scrollReset)` → `.onChange(of: calendarReset)`. Update `titleVariant` return type to `CalendarWeekHeader.TitleVariant`. Update preview to use `calendarReset:`. Add `.navigationTitle("Plan")` (replacing current `.navigationTitle("")`). Keep `.navigationBarTitleDisplayMode(.inline)`. Edit toolbar button stays as-is. |
| `Dromos/Dromos/Features/Calendar/CalendarWeekHeader.swift` | CREATE | Verbatim move of current `Features/Home/HomeWeekHeader.swift`. Rename type `HomeWeekHeader` → `CalendarWeekHeader`. Update Previews. |
| `Dromos/Dromos/Features/Home/HomeView.swift` | MODIFY (rewrite) | Replace contents with a minimal placeholder view: centered Dromos logo + "Coming soon" caption. No services, no toolbar, no nav title. Same struct name `HomeView`. |
| `Dromos/Dromos/Features/Home/HomeWeekHeader.swift` | DELETE | Moved to `Features/Calendar/CalendarWeekHeader.swift`. |
| `Dromos/Dromos/Features/Plan/CalendarPlanView.swift` | DELETE | Replaced by `CalendarView`. No other callers (verified). |
| `Dromos/Dromos/Features/Plan/WeekHeaderView.swift` | DELETE | Used only by `CalendarPlanView` (verified). |
| `Dromos/Dromos/Features/Plan/DaySessionRow.swift` | DELETE | Used only by `CalendarPlanView` (verified). The lone reference in `SessionCardView.swift:216` is an internal comment — updated, not deleted. |
| `Dromos/Dromos/App/MainTabView.swift` | MODIFY | (1) Delete `@State private var homeScrollReset` and the `.home` branch in the `tabSelection` setter. (2) `.home` Tab now wires the new placeholder `HomeView()` (no service params). (3) `.calendar` Tab swaps `CalendarPlanView(...)` for `CalendarView(authService:planService:profileService:stravaService:calendarReset:)`. (4) Update doc comment that says "scroll reset on Home re-selection". |
| `Dromos/Dromos/Core/Models/TrainingPlan.swift` | MODIFY | Line 407 doc-comment: replace "Used by both HomeView and CalendarPlanView" with "Used by `CalendarView`". Also add `PlanSession.sportColor` and `PlanSession.formatDistance(_:)` UI helper extensions (previously orphaned in deleted `DaySessionRow.swift`). |
| `Dromos/Dromos/Features/Home/SessionCardView.swift` | MODIFY | Line 216 stale comment referencing `DaySessionRow` — drop the "vs DaySessionRow" clause; keep the substantive comment. |
| `Dromos/Dromos/Features/Home/IntensityColorHelper.swift` | MODIFY | Add `Color.phaseColor(for:)` extension (previously orphaned in deleted `WeekHeaderView.swift`). |
| `Dromos/Dromos/Features/Plan/PlanGenerationView.swift` | UNCHANGED | Used by `RootView`. Stays. |

## Context Doc Updates

- `architecture.md` — update tab navigation section, folder structure tree, and "Key Shared Components" list:
  - Folder tree: drop `Features/Plan/CalendarPlanView.swift`, `WeekHeaderView.swift`, `DaySessionRow.swift`. Drop `Features/Home/HomeWeekHeader.swift`. Add `Features/Calendar/CalendarView.swift` and `Features/Calendar/CalendarWeekHeader.swift`. Replace `Features/Home/HomeView.swift` description with "Lightweight placeholder (Coming soon)".
  - Tab navigation: Home → placeholder; Calendar → `CalendarView` (paged single-week, formerly Home).
  - "Key Shared Components": remove `WeekHeaderView` and `DaySessionRow` lines.
  - Re-tap behavior bullets: drop the Home re-tap entry; update Calendar re-tap to describe the cache-purge + week-snap behavior (formerly Home's).

## Tasks

- [x] 🟩 **Step 1: Move + rename paged view to Calendar feature folder**
  - [x] 🟩 Create `Dromos/Dromos/Features/Calendar/CalendarWeekHeader.swift` with content moved from `Features/Home/HomeWeekHeader.swift`. Rename type `HomeWeekHeader` → `CalendarWeekHeader`. Update Previews.
  - [x] 🟩 Delete `Dromos/Dromos/Features/Home/HomeWeekHeader.swift`.
  - [x] 🟩 Create `Dromos/Dromos/Features/Calendar/CalendarView.swift` with content moved from `Features/Home/HomeView.swift`. Rename type `HomeView` → `CalendarView`. Rename `@Binding var scrollReset: Bool` → `@Binding var calendarReset: Bool`. Update `.onChange(of: scrollReset)` → `.onChange(of: calendarReset)`. Update `titleVariant(for:plan:)` return type to `CalendarWeekHeader.TitleVariant`. Update `HomeWeekHeader(...)` call site to `CalendarWeekHeader(...)`.
  - [x] 🟩 In `CalendarView`, replace `.navigationTitle("")` with `.navigationTitle("Plan")`. Keep `.navigationBarTitleDisplayMode(.inline)` and the Edit toolbar button.
  - [x] 🟩 Update the `#Preview` block to construct `CalendarView(..., calendarReset: .constant(false))`.

- [x] 🟩 **Step 2: Rewrite `HomeView.swift` as placeholder**
  - [x] 🟩 Replace `Features/Home/HomeView.swift` contents with a minimal `HomeView: View` that takes no parameters and renders: centered `Image("DromosLogo")` (renderingMode `.original`, scaled to ~80×48pt) + a `Text("Coming soon")` caption in `.subheadline` / `.secondary`. No services, no NavigationStack, no toolbar.
  - [x] 🟩 Add a `#Preview { HomeView() }` block.

- [x] 🟩 **Step 3: Delete old Calendar implementation**
  - [x] 🟩 Delete `Dromos/Dromos/Features/Plan/CalendarPlanView.swift`.
  - [x] 🟩 Delete `Dromos/Dromos/Features/Plan/WeekHeaderView.swift`.
  - [x] 🟩 Delete `Dromos/Dromos/Features/Plan/DaySessionRow.swift`.
  - [x] 🟩 Verify `Dromos/Dromos/Features/Plan/PlanGenerationView.swift` is untouched and still referenced from `RootView.swift:39`.

- [x] 🟩 **Step 4: Rewire `MainTabView.swift`**
  - [x] 🟩 Remove `@State private var homeScrollReset: Bool = false` and the `if newValue == .home { homeScrollReset.toggle() }` line in `tabSelection`.
  - [x] 🟩 In the `.home` Tab block, replace the `HomeView(...)` call (with all 5 service/binding params) with a no-arg `HomeView()`.
  - [x] 🟩 In the `.calendar` Tab block, replace `CalendarPlanView(authService: ..., planService: ..., profileService: ..., calendarReset: $calendarReset)` with `CalendarView(authService: authService, planService: planService, profileService: profileService, stravaService: stravaService, calendarReset: $calendarReset)`.
  - [x] 🟩 Update the doc comment on `calendarReset` (line ~42) to describe the new behavior (cache purge + snap to current week).
  - [x] 🟩 Update the class-level doc comment (line ~17) so it matches the new tab content split.

- [x] 🟩 **Step 5: Cleanup stale references**
  - [x] 🟩 `Dromos/Dromos/Core/Models/TrainingPlan.swift:407` — update doc comment to reference `CalendarView` instead of `HomeView`/`CalendarPlanView`.
  - [x] 🟩 `Dromos/Dromos/Features/Home/SessionCardView.swift:216` — drop the parenthetical "vs DaySessionRow" comment; keep the rest of the line.
  - [x] 🟩 Run a repo-wide grep for `HomeWeekHeader`, `CalendarPlanView`, `WeekHeaderView`, `DaySessionRow`, `scrollReset`, `homeScrollReset` to confirm zero remaining references.

- [x] 🟩 **Step 6: Build + manual QA**
  - [x] 🟩 Build cleanly in Xcode (no warnings about missing types or unused bindings).
  - [ ] 🟥 Manual QA — Calendar tab: paging via chevrons + horizontal swipe; auto-opens to current week; Edit/Done toolbar enters edit mode and shows up/down arrows; Strava completion borders (green/red) render once sync completes; skeleton appears while a week's Strava fetch is in flight; race day card renders on race date; loading + empty + error states display correctly.
  - [ ] 🟥 Manual QA — Calendar tab re-tap: snaps to current week, purges current-week cache, refetches Strava completion (mirror of today's Home re-tap behavior).
  - [ ] 🟥 Manual QA — Home tab: renders Dromos logo + "Coming soon" centered. Re-tap is a no-op (no animation, no crash).
  - [ ] 🟥 Manual QA — Profile tab: untouched, still functional.

- [x] 🟩 **Step 7: Update context docs**
  - [x] 🟩 Update `.claude/context/architecture.md` per the "Context Doc Updates" section above.
