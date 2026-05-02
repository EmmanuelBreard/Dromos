# DRO-252 — Calendar header scrolls away with content

**Linear:** [DRO-252](https://linear.app/dromosapp/issue/DRO-252/calendar-header-should-scroll-away-with-content-match-home-behavior)

**Overall Progress:** `0%`

## TLDR

Move `CalendarWeekHeader` from being pinned above the paged TabView to being the first element inside each TabView page's `ScrollView`. Header then translates off-screen with the day cards as the user scrolls up, mirroring the Home tab's pattern. Native nav bar (`Plan` + Edit/Done) stays pinned and unchanged. Add a "scroll-to-top" reset on every week change (swipe / chevron / re-tap) so the new active page always shows the header.

## Critical Decisions

- **Header lives inside each TabView page's `ScrollView`, not above the TabView.** Considered (and rejected) wrapping the TabView in an outer ScrollView — `TabView(.page)` does not size to its content and would have required abandoning the recently-stabilized paged-week architecture (DRO-247 / DRO-250). Per-page header is the smaller, safer change. Side-effect (desirable): header content animates horizontally with the page during a week swipe.
- **Native nav bar stays.** "Plan" title + Edit/Done button are NOT part of the scrolling-away header — they remain in the standard `NavigationStack` toolbar. No nav-bar hide, no button relocation, no loading/error/empty-state changes.
- **"Always scroll to top" implemented via a shared `@State` token (`UUID`) bumped on signal events.** Each page's `ScrollViewReader` observes the token and calls `proxy.scrollTo(...)`. Inactive pages silently scroll to top too — harmless and uniform. Considered passing `currentWeekIndex` into `weekContent` and conditionally scrolling — rejected because the token approach unifies all three trigger paths (currentWeekIndex change, calendarReset re-tap) without per-page conditionals.
- **Padding fix: header sits inside the page's outer container but OUTSIDE the LazyVStack's horizontal padding.** `CalendarWeekHeader` carries its own `.padding(.horizontal)` ([CalendarWeekHeader.swift:66](Dromos/Dromos/Features/Calendar/CalendarWeekHeader.swift#L66)). The LazyVStack also applies `.padding(.horizontal)` ([CalendarView.swift:222](Dromos/Dromos/Features/Calendar/CalendarView.swift#L222)). Wrap the page content as `VStack(spacing: 16) { CalendarWeekHeader(...); LazyVStack { … }.padding(.horizontal) }` so each component owns its own horizontal padding.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Calendar/CalendarView.swift` | MODIFY | Remove `CalendarWeekHeader(...)` from `contentBody`; inject it as the first element inside each page rendered by `weekContent(weekIndex:plan:)`. Add `@State private var scrollToTopToken: UUID = UUID()`. Wrap each page's `ScrollView` in a `ScrollViewReader`, give the header an `.id("weekTop")`, and add `.onChange(of: scrollToTopToken)` that scrolls to that anchor. Bump the token from the existing `.onChange(of: currentWeekIndex)` and `.onChange(of: calendarReset)` handlers. |
| `Dromos/Dromos/Features/Calendar/CalendarWeekHeader.swift` | UNCHANGED | Component is moved as-is. No prop, layout, or styling change. |

## Context Doc Updates

- `architecture.md` — minor update to the [`CalendarView.swift` line in the Folder Structure section](.claude/context/architecture.md) to note that `CalendarWeekHeader` now scrolls with day content (per-page) instead of being pinned above the TabView. Update the existing one-line description; no new section needed.

## Tasks

### Phase 1: Move header into per-page scroll content

- [ ] 🟥 **Step 1: Remove header from `contentBody`**
  - [ ] 🟥 In `CalendarView.swift` `contentBody(plan:currentWeek:weekStart:)` ([line 115-203](Dromos/Dromos/Features/Calendar/CalendarView.swift#L115-L203)), delete the `CalendarWeekHeader(...)` view block (lines 121-131) from the outer `VStack`.
  - [ ] 🟥 Collapse the outer `VStack(spacing: 0)` if it now contains only the `if didInitializeWeekIndex { TabView } else { ProgressView }` branch — keep the `didInitializeWeekIndex` gate intact.

- [ ] 🟥 **Step 2: Inject header inside each page's ScrollView**
  - [ ] 🟥 In `weekContent(weekIndex:plan:)` ([line 208-225](Dromos/Dromos/Features/Calendar/CalendarView.swift#L208-L225)), restructure the body so the page contains `VStack(spacing: 16) { CalendarWeekHeader(...); LazyVStack(spacing: 16) { …days… }.padding(.horizontal) }` inside the `ScrollView`.
  - [ ] 🟥 The `CalendarWeekHeader(...)` call uses the same arguments currently in `contentBody`: derive `weekNumber`, `phase`, `weekStartDate`, `titleVariant(for: weekIndex, plan: plan)`, `onPrevious: { goToWeek(weekIndex - 1, plan: plan) }`, `onNext: { goToWeek(weekIndex + 1, plan: plan) }`, `canGoPrevious: weekIndex > 0`, `canGoNext: weekIndex < plan.planWeeks.count - 1`.
  - [ ] 🟥 `weekStartDate` is `plan.planWeeks[weekIndex].startDateAsDate ?? Date()` — keep a non-optional fallback since `weekContent` is invoked by the existing guarded branch in `contentView` and we are inside a per-week page that already exists.
  - [ ] 🟥 Verify visually in Xcode preview / simulator: no double horizontal padding gap, no extra vertical gap between header and first day section, header chevrons remain tappable on first/last week.

- [ ] 🟥 **Step 3: Verify week-swipe + chevron-tap navigation still works**
  - [ ] 🟥 Horizontal swipe between weeks: `TabView(.page)` continuous-track behavior preserved (the TabView itself is untouched).
  - [ ] 🟥 Chevron taps: `goToWeek(_:plan:)` `withAnimation` page change still fires.
  - [ ] 🟥 Header content (week N/M, phase, dates) now animates horizontally with the page swipe — confirm this looks correct.
  - [ ] 🟥 First-paint init gate: `didInitializeWeekIndex == false` still shows the central `ProgressView` and no header (header lives inside pages, pages don't render until the gate flips).

### Phase 2: Always scroll to top on week change + tab re-tap

- [ ] 🟥 **Step 4: Add scroll-to-top trigger state**
  - [ ] 🟥 Add `@State private var scrollToTopToken: UUID = UUID()` to `CalendarView` (alongside the existing `@State` properties around [line 42-55](Dromos/Dromos/Features/Calendar/CalendarView.swift#L42-L55)).

- [ ] 🟥 **Step 5: Wire ScrollViewReader inside `weekContent`**
  - [ ] 🟥 Wrap the `ScrollView` body in `weekContent` with a `ScrollViewReader { proxy in … }`.
  - [ ] 🟥 Apply `.id("weekTop")` to the `CalendarWeekHeader` instance (top of the page).
  - [ ] 🟥 Add `.onChange(of: scrollToTopToken) { _, _ in withAnimation { proxy.scrollTo("weekTop", anchor: .top) } }` to the `ScrollView`.

- [ ] 🟥 **Step 6: Bump the token on signal events**
  - [ ] 🟥 In the existing `.onChange(of: currentWeekIndex) { _, newIdx in … }` handler ([line 162-167](Dromos/Dromos/Features/Calendar/CalendarView.swift#L162-L167)), set `scrollToTopToken = UUID()` synchronously before the `Task { … }` block.
  - [ ] 🟥 In the existing `.onChange(of: calendarReset) { _, _ in … }` handler ([line 171-192](Dromos/Dromos/Features/Calendar/CalendarView.swift#L171-L192)), set `scrollToTopToken = UUID()` synchronously at the top of the closure (before the `currentWeekIndex == target` branch). This guarantees scroll-to-top fires both when the re-tap stays on the same week AND when it snaps to a different week.

- [ ] 🟥 **Step 7: QA the scroll-to-top behavior**
  - [ ] 🟥 Scroll week 3 down ~200pt → swipe to week 4 → week 4 lands at top with header visible.
  - [ ] 🟥 Scroll week 3 down → tap chevron-right → week 4 lands at top with header visible.
  - [ ] 🟥 Scroll week 3 down → re-tap Calendar tab (already on current week) → page scrolls back to top, Strava refetch still fires.
  - [ ] 🟥 Scroll week 5 down → re-tap Calendar tab (snap-back to current week 3) → page is at top of week 3 with header visible.
  - [ ] 🟥 Swipe back to week 3 (after having visited week 4) → week 3 is at top (NOT at the previously-scrolled position).
  - [ ] 🟥 Verify the silent scroll-to-top on inactive pages does not produce visual jank during the page swipe transition.

### Phase 3: Documentation

- [ ] 🟥 **Step 8: Update architecture context doc**
  - [ ] 🟥 In `.claude/context/architecture.md`, update the `CalendarView.swift` and `CalendarWeekHeader.swift` lines (~line 59-60) to mention that the week header now scrolls with day content (per-page) and is no longer pinned above the TabView.
