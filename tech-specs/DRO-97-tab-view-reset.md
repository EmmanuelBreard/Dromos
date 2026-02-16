# DRO-97: Reset Home & Calendar View State on Tab Switch and App Relaunch

**Overall Progress:** `100%`

## TLDR
When switching tabs (or re-tapping the active tab), Home scrolls to today's day section and Calendar resets to the current week — matching fresh-load behavior. App relaunch already works (no change needed).

## Critical Decisions
- **Custom `Binding<AppTab>` for re-tap detection**: SwiftUI's `onChange(of: selectedTab)` doesn't fire when the user taps the already-selected tab. Use a computed `Binding` wrapper that intercepts the setter — it fires for both new-tab and same-tab taps, letting us trigger reset in both cases.
- **Simplified binding conditions**: `if newValue == .home` covers both tab switches and re-taps (no need for redundant second condition). Clean and readable.
- **Reuse existing `scrollReset: Bool` toggle pattern**: CalendarPlanView gets a `@Binding var calendarReset: Bool` mirroring HomeView's `scrollReset`. Simple, consistent, no new patterns introduced.
- **Home reset = scroll to today (not top)**: Changed `onChange(of: scrollReset)` to call the existing `scrollToToday()` helper so tab-return matches first-load behavior. Removed dead `"scrollTop"` anchor.
- **Show next week — no animation/scroll**: Content appears naturally below; user scrolls down themselves. Avoids ScrollView animation glitches.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/App/MainTabView.swift` | MODIFY | Add `calendarReset` state, custom `Binding<AppTab>` for reset detection, pass binding to CalendarPlanView |
| `Dromos/Dromos/Features/Home/HomeView.swift` | MODIFY | Scroll to today on reset, remove dead scrollTop anchor, add week header IDs, simplify show-next-week |
| `Dromos/Dromos/Features/Plan/CalendarPlanView.swift` | MODIFY | Add `@Binding var calendarReset: Bool`, `onChange` handler to reset `currentWeekIndex` |

## Context Doc Updates
- `architecture.md` — Updated Tab navigation section with reset behavior and custom binding pattern

## Tasks

- [x] 🟩 **Step 1: MainTabView — reset plumbing + re-tap detection**
  - [x] 🟩 Add `@State private var calendarReset: Bool = false`
  - [x] 🟩 Replace `TabView(selection: $selectedTab)` with `TabView(selection: tabSelection)` using simplified `Binding<AppTab>`
  - [x] 🟩 Remove the existing `.onChange(of: selectedTab)` block (logic moves into binding setter)
  - [x] 🟩 Pass `calendarReset` to CalendarPlanView

- [x] 🟩 **Step 2: HomeView — scroll to today on reset**
  - [x] 🟩 Change `onChange(of: scrollReset)` to call `scrollToToday()` instead of scrolling to `"scrollTop"`
  - [x] 🟩 Remove dead `Color.clear.frame(height: 0).id("scrollTop")` anchor
  - [x] 🟩 Add `.id("week-\(week.weekNumber)")` to week section headers
  - [x] 🟩 Simplify `showNextWeekButton` — no animation or programmatic scroll

- [x] 🟩 **Step 3: CalendarPlanView — reset week index on signal**
  - [x] 🟩 Add `@Binding var calendarReset: Bool` property
  - [x] 🟩 Add `.onChange(of: calendarReset)` to reset `currentWeekIndex`
  - [x] 🟩 Update `#Preview` to pass `.constant(false)`

- [x] 🟩 **Step 4: Update context docs**
  - [x] 🟩 Update `architecture.md` Tab navigation section
