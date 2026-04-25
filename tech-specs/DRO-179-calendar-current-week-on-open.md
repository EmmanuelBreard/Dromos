# Feature Implementation Plan — DRO-179

**Overall Progress:** `0%`

## TLDR

Calendar tab always opens on week 1 instead of the current training week. Add `.onAppear` to set `currentWeekIndex` correctly on first render.

## Critical Decisions

- **`.onAppear` over `.task`:** The fix is one line in an existing `.onAppear`-equivalent slot. No async work needed, so `.task` would add unnecessary complexity. A simple `.onAppear` on the `NavigationStack` mirrors the existing `.onChange(of: calendarReset)` pattern already in the view.
- **No change to `calendarReset` logic:** Tab re-selection reset already works correctly via `.onChange(of: calendarReset)`. We're only fixing the initial load.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Plan/CalendarPlanView.swift` | MODIFY | Add `.onAppear` modifier to set `currentWeekIndex` from `plan.currentWeekIndex()` on first view load |

## Context Doc Updates

None — no new files, tables, or patterns introduced.

## Tasks

- [ ] 🟥 **Step 1: Fix initial week index on first appear**
  - [ ] 🟥 In `CalendarPlanView.body`, add `.onAppear` modifier on the `NavigationStack` (alongside existing `.onChange` modifiers) that sets `currentWeekIndex = planService.trainingPlan?.currentWeekIndex() ?? 0`
  - [ ] 🟥 Verify: on first app launch with an existing plan, Calendar tab opens on the correct current week (not week 1)
  - [ ] 🟥 Verify: tab re-selection still resets to current week via the existing `calendarReset` path (no regression)
