# DRO-211: Fix "Show next week" scroll jump

**Overall Progress:** `0%`

## TLDR
Tapping "Show next week" on the Home page causes the scroll view to jump up to the previous week's header instead of revealing the next week inline. Root cause: a dead `.id("week-N")` modifier on every week header that SwiftUI's `ScrollViewReader` uses as a re-anchor target when the content changes. Fix: remove the unused identifier.

## Critical Decisions
- **Remove the unused week-header `.id()` rather than switching scroll APIs** — The week-level IDs at [HomeView.swift:115](Dromos/Dromos/Features/Home/HomeView.swift#L115) are never referenced by any `proxy.scrollTo` call (confirmed via grep: only `"weekN-weekday"` composite IDs are used in `scrollToToday` at line 440). Removing them eliminates the anchor points SwiftUI is snapping to, without changing scroll APIs or refactoring the layout.
- **Keep the day-level composite `.id("weekN-weekday")` intact** — These are required by `scrollToToday` for auto-scroll on first load and tab re-selection. They are much smaller anchor targets than full week headers, so any residual re-anchoring effect during async updates should be imperceptible.
- **No iOS 17 `.scrollPosition()` migration in this fix** — Out of scope. If the minimal fix proves insufficient after device testing, we can revisit as a follow-up.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Home/HomeView.swift` | MODIFY | Remove the unused `.id("week-\(week.weekNumber)")` modifier on the week section header (line 115) |

## Context Doc Updates
None — no new files, services, tables, or patterns introduced.

## Tasks

- [ ] 🟥 **Step 1: Remove dead week-header scroll anchor**
  - [ ] 🟥 Delete `.id("week-\(week.weekNumber)")` on [HomeView.swift:115](Dromos/Dromos/Features/Home/HomeView.swift#L115)
  - [ ] 🟥 Verify no other file references `"week-N"` style IDs (confirmed during discovery — no other call sites)

- [ ] 🟥 **Step 2: Device QA**
  - [ ] 🟥 On a real device, tap "Show next week" — view must NOT scroll; next week appears inline below current content
  - [ ] 🟥 Tap "Show next week" multiple times in succession — each tap reveals one more week with zero scroll movement
  - [ ] 🟥 Regression check: first load auto-scrolls to today (unchanged behavior)
  - [ ] 🟥 Regression check: tapping the Home tab while already on Home resets weeks and scrolls back to today (unchanged behavior)
  - [ ] 🟥 Regression check: trigger a Strava sync and scroll down through the plan — confirm scroll no longer jumps up while scrolling
  - [ ] 🟥 Regression check: when AI feedback generation finishes (`planService.refreshPlan()` fires), confirm scroll position is not disturbed

- [ ] 🟥 **Step 3: If residual scroll jumps persist (fallback — only if Step 2 reveals issues)**
  - [ ] 🟥 Investigate whether day-level `.id()`s are also contributing — add a `.scrollTargetLayout()` + `.scrollPosition(id:)` migration if needed
  - [ ] 🟥 Alternative: guard `loadCompletionStatuses` writes so `completionStatuses` is only reassigned when values actually changed, reducing re-renders on async updates
  - [ ] 🟥 This step is contingent — do not implement proactively
