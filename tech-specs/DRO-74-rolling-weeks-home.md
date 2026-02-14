# DRO-74: Rolling Weeks on Home Page

**Overall Progress:** `0%`

## TLDR
Replace the single-week HomeView with a scrollable multi-week view. Default shows current + next week. A "Show next week" CTA progressively reveals more weeks. Race Day indicator on the last day. Forward-only, no backward navigation.

## Critical Decisions
- **Composite scroll IDs**: Current `.id(dayInfo.weekday)` will collide across weeks. Switch to `"\(week.weekNumber)-\(weekday)"` composite IDs so auto-scroll-to-today works across multiple weeks.
- **State via `@State var lastVisibleWeekIndex`**: Tracks the furthest week shown. Initialized to `currentWeekIndex + 1` (or `currentWeekIndex` if on last week). CTA increments by 1.
- **No new files for week header**: Replace inline `weekHeader()` in HomeView with a new `multiWeekHeader()` that supports "Current Week" / "Next Week" / date-range-only modes. Keep it inside HomeView (not worth a separate component).
- **RaceDayCardView**: New small view in `SessionCardView.swift` (alongside `RestDayCardView`) to keep card components co-located.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Home/HomeView.swift` | MODIFY | Multi-week rendering, new state, CTA, updated headers, updated scroll IDs, updated auto-scroll |
| `Dromos/Dromos/Features/Home/SessionCardView.swift` | MODIFY | Add `RaceDayCardView` component |

## Context Doc Updates
- `architecture.md` — Update Home section description to reflect multi-week view + mention RaceDayCardView

## Tasks

- [ ] :red_square: **Step 1: Add RaceDayCardView**
  - [ ] :red_square: Add `RaceDayCardView` in `SessionCardView.swift` below `RestDayCardView`
  - [ ] :red_square: Design: flag/trophy icon + "Race Day" label + race objective (e.g., "Olympic") if available. Same card style as `RestDayCardView` but with accent color
  - [ ] :red_square: Add SwiftUI preview

- [ ] :red_square: **Step 2: Refactor HomeView to render multiple weeks**
  - [ ] :red_square: Add `@State private var lastVisibleWeekIndex: Int = 0` state
  - [ ] :red_square: Initialize in `.onAppear`: `lastVisibleWeekIndex = min(plan.currentWeekIndex() + 1, plan.planWeeks.count - 1)`
  - [ ] :red_square: Replace single-week rendering with a `ForEach` over `plan.planWeeks[currentWeekIndex...lastVisibleWeekIndex]`
  - [ ] :red_square: Each week section: header + `LazyVStack` of `daySectionView` (reuse existing)

- [ ] :red_square: **Step 3: New week section headers**
  - [ ] :red_square: Replace `weekHeader(week:)` with `weekSectionHeader(week:plan:currentWeekIndex:)` that returns:
    - Current week index → **"Current Week"** (bold) + date range subtitle (e.g., "Feb 16th - Feb 22nd")
    - Current + 1 → **"Next Week"** (bold) + date range subtitle
    - All others → **date range only** as title (e.g., "Feb 23rd - Mar 1st")
  - [ ] :red_square: Keep phase badge on all headers
  - [ ] :red_square: Add helper `weekDateRange(week:)` → formats "MMM dth - MMM dth" with ordinal suffixes

- [ ] :red_square: **Step 4: "Show next week" CTA**
  - [ ] :red_square: Add CTA button below the last visible week's day sections
  - [ ] :red_square: Only show when `lastVisibleWeekIndex < plan.planWeeks.count - 1`
  - [ ] :red_square: On tap: `lastVisibleWeekIndex += 1`
  - [ ] :red_square: Style: simple text button, secondary color, centered

- [ ] :red_square: **Step 5: Race Day indicator**
  - [ ] :red_square: In `daySectionView`, check if `dayInfo.date` matches `plan.raceDateAsDate` (using `Calendar.isDate(_:inSameDayAs:)`)
  - [ ] :red_square: If match, render `RaceDayCardView` below that day's sessions (or as the only card if rest day)
  - [ ] :red_square: On last week, no CTA shown (already handled by Step 4 condition)

- [ ] :red_square: **Step 6: Fix auto-scroll to today**
  - [ ] :red_square: Change `.id(dayInfo.weekday)` to `.id("\(week.weekNumber)-\(dayInfo.weekday)")` on each day section
  - [ ] :red_square: Update `scrollToToday()` to find today across all visible weeks and use the composite ID
  - [ ] :red_square: Pass the current week's days (not all visible days) to find today — today is guaranteed to be in the current week

- [ ] :red_square: **Step 7: Update context docs**
  - [ ] :red_square: Update `architecture.md` Home section to describe multi-week view + RaceDayCardView
