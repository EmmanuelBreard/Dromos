# DRO-247 — Smooth Slide Transitions on Today and Calendar

**Overall Progress:** `50%`

## TLDR

Replace the "hard-replace" feeling on day-to-day (Today) and week-to-week (Calendar) navigation with a **clean horizontal push-slide** transition: pure translate, no fade. Same direction logic (forward = exit-left / enter-right; backward = mirrored) regardless of trigger — swipe, pill tap, chevron tap, or tab re-tap. Animation: 0.25s ease-in-out (unchanged from current).

## Critical Decisions

1. **Replace `TabView(.page)` on Calendar with the same pattern Today uses.**
   - **Why:** `TabView(.page)`'s `.animation(value:)` modifier does not reliably animate programmatic page changes (chevron taps, tab re-tap) — well-known SwiftUI quirk. To get consistent push-slide animation across all four triggers, we mirror Today's `.id() + .transition() + DragGesture` pattern.
   - **Trade-off accepted:** lose native UIKit "page peek during drag" — gesture becomes complete-then-animate instead of continuous-during-drag. Matches Today's existing swipe feel; net win for consistency across tabs.
   - **Side effect:** per-week ScrollView scroll position resets to top on every week change (each week gets a new view identity). Today also doesn't preserve scroll across days, so this is now consistent. Flag for QA verification.

2. **Shared transition helper.** Extract `SlideDirection` enum + `AnyTransition.horizontalSlide(direction:)` to a small `Core/SlideTransition.swift` file. Both tabs reference it. Avoids duplicating the asymmetric-move logic in two places.

3. **Today: drop the opacity fade.** Existing `heroTransition` uses `.move(edge:).combined(with: .opacity)`. The opacity is what makes it feel like a "hard replace" rather than a clean push-slide — remove it. Pure `.move(edge:)` only.

4. **Direction is computed from the date/index delta**, not gesture direction. Already true on Today via `handlePillTap`'s index comparison, but needs to be tightened (re-tap of currently-selected pill is incidentally correct today; we'll make it deterministic) and extended to `homeReset` and Calendar's chevron + tab-reset paths.

5. **Calendar tab re-tap snap-back = instant (no animation).** When the user is multiple weeks away and taps the Calendar tab, animating a single slide across many weeks would look jarring. Suppress the animation on this specific code path via `withTransaction(Transaction(animation: nil))`.

6. **Bring the date label inside the Today slide unit.** Currently `Text(dayLabel(for: effectiveSelectedDay))` at [HomeView.swift:123-128](Dromos/Dromos/Features/Home/HomeView.swift#L123) sits OUTSIDE the `.id()` + `.transition()` boundary (intentional per the comment at line 144). Per the spec ("date + card slide together"), we wrap both into a single sliding `Group`/`VStack` and lift the modifiers to that wrapper.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Core/SlideTransition.swift` | CREATE | New file: `enum SlideDirection { case next, previous }` + `extension AnyTransition { static func horizontalSlide(direction: SlideDirection) -> AnyTransition }`. Pure asymmetric `.move(edge:)`, no opacity. |
| `Dromos/Dromos/Features/Home/HomeView.swift` | MODIFY | (1) Delete local `SwipeDirection` enum + `heroTransition` computed property; reuse shared `SlideDirection` + `AnyTransition.horizontalSlide(direction:)`. (2) Wrap the day-anchor `Text` + `todayHero` into a single sliding `VStack` and lift `.id(effectiveSelectedDay) + .transition(...) + .animation(...) + DragGesture` to that wrapper. (3) Refactor `handlePillTap` to compute direction from actual `before → after` destination (handles re-tap-currently-selected correctly). (4) In `.onChange(of: homeReset)` compute direction from `effectiveSelectedDay → today` before resetting `selectedDay`. |
| `Dromos/Dromos/Features/Calendar/CalendarView.swift` | MODIFY | (1) Remove `TabView` + `ForEach(.indices) { weekContent.tag(idx) }` + `.tabViewStyle(.page(...))` at lines 133-140. Replace with direct `weekContent(weekIndex: currentWeekIndex, plan: plan)` wrapped with `.id(currentWeekIndex) + .transition(.horizontalSlide(...)) + .animation(.easeInOut(0.25), value: currentWeekIndex)`. (2) Add `@State private var slideDirection: SlideDirection = .next`. (3) Update `goToWeek(_:plan:)` to set `slideDirection` from index delta before mutating `currentWeekIndex` (route both chevron handlers through it). (4) Add horizontal `DragGesture(minimumDistance: 20)` mirroring Today's (50pt threshold + `abs(dx) > abs(dy)` guard) that calls `goToWeek`. (5) Wrap the `calendarReset` mutation at lines 161-177 in `withTransaction(Transaction(animation: nil)) { currentWeekIndex = target }` to suppress animation on tab re-tap snap. |
| `.claude/context/architecture.md` | MODIFY | Update HomeView description (pure-translate transition, date label now inside slide unit). Update CalendarView description (no longer `TabView(.page)`; uses `.id()` + `DragGesture` matching Today). Add `Core/SlideTransition.swift` to the Core tree. |
| `CHANGELOG.md` | MODIFY | Add DRO-247 entry. |

## Context Doc Updates

- **`architecture.md`** — Today + Calendar tab descriptions; new `Core/SlideTransition.swift` helper.

## Risks

- **Calendar drag gesture vs vertical scroll**: must replicate the same `abs(dx) > abs(dy)` guard Today uses, or vertical scrolling inside a week's day list will trigger horizontal navigation.
- **Edit-mode in Calendar**: existing edit-mode animation on session-card move arrows ([CalendarView.swift:78](Dromos/Dromos/Features/Calendar/CalendarView.swift#L78), [CalendarView.swift:288](Dromos/Dromos/Features/Calendar/CalendarView.swift#L288)) must remain unaffected. Do not collapse `withAnimation` calls.
- **Per-week completion cache** (`completionCacheByWeek`): keyed on week index, independent of view identity. Should not be affected by removing `TabView`. Verify no behavioral change.
- **Slide direction on cold launch / first appear**: `slideDirection` defaults to `.next` but no transition fires (no `.id()` swap on initial render). Verify no flash.
- **Animation testing**: SwiftUI animations are not unit-testable in a meaningful way. This relies on manual QA per phase. Document QA checklist in tasks.

## Tasks

- [x] 🟩 **Phase 1: Shared slide transition helper**
  - [x] 🟩 Create `Dromos/Dromos/Core/SlideTransition.swift`:
    ```swift
    import SwiftUI

    enum SlideDirection {
        case next      // forward navigation: incoming from trailing, outgoing to leading
        case previous  // backward navigation: incoming from leading, outgoing to trailing
    }

    extension AnyTransition {
        static func horizontalSlide(direction: SlideDirection) -> AnyTransition {
            switch direction {
            case .next:
                return .asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                )
            case .previous:
                return .asymmetric(
                    insertion: .move(edge: .leading),
                    removal: .move(edge: .trailing)
                )
            }
        }
    }
    ```
  - [x] 🟩 Add file to Xcode target (Dromos → Sources).
  - [x] 🟩 Build verifies file compiles (no usages yet).

- [x] 🟩 **Phase 2: Today tab — pure horizontal slide + correct direction on all triggers**
  - [x] 🟩 In `HomeView.swift`: delete local `SwipeDirection` enum + `heroTransition` computed property (lines ~540-553). Rename `swipeDirection` state to use shared `SlideDirection`.
  - [x] 🟩 Wrap `Text(dayLabel(for: effectiveSelectedDay))` + `todayHero` into a single `VStack(alignment: .leading, spacing: 8)`. Apply to the wrapper:
    - `.id(effectiveSelectedDay)`
    - `.transition(.horizontalSlide(direction: swipeDirection))`
    - `.animation(.easeInOut(duration: 0.25), value: effectiveSelectedDay)`
    - The existing `DragGesture(minimumDistance: 20)` (move from `todayHero` to wrapper)
  - [x] 🟩 Confirmed SportProgressStrip + WeekDayStrip remain OUTSIDE this wrapper (they stay pinned).
  - [x] 🟩 Refactor `handlePillTap(_:)` to compute direction from before→after destination:
    ```swift
    private func handlePillTap(_ tappedWeekday: Weekday) {
        let today = todayWeekday()
        let newSelection: Weekday? = (tappedWeekday == today || selectedDay == tappedWeekday) ? nil : tappedWeekday
        let from = effectiveSelectedDay
        let to = newSelection ?? today
        let fromIdx = Weekday.allCases.firstIndex(of: from) ?? 0
        let toIdx = Weekday.allCases.firstIndex(of: to) ?? 0
        swipeDirection = toIdx > fromIdx ? .next : .previous
        selectedDay = newSelection
    }
    ```
  - [x] 🟩 In `.onChange(of: homeReset)`, compute direction from `effectiveSelectedDay → today` BEFORE setting `selectedDay = nil`.
  - [ ] 🟥 Manual QA checklist:
    - [ ] Swipe forward (e.g., today → tomorrow): card + date label slide as one unit, exit-left / enter-right, no fade
    - [ ] Swipe backward: mirror direction
    - [ ] Tap a future-day pill: forward slide
    - [ ] Tap a past-day pill: backward slide
    - [ ] Re-tap currently-selected (non-today) pill: returns to today with correct direction (from selected back toward today)
    - [ ] Tab re-tap from non-today: returns to today with correct direction
    - [ ] Tab re-tap from today: no-op (no flash)
    - [ ] Vertical scroll inside hero card: does NOT trigger horizontal slide (50pt threshold + dy guard intact)
    - [ ] Multi-session day, rest day, race day: all slide identically
    - [ ] SportProgressStrip + WeekDayStrip stay pinned (do not slide)

- [ ] 🟥 **Phase 3: Calendar tab — replace TabView(.page) with shared slide pattern**
  - [ ] 🟥 In `CalendarView.swift`: remove `TabView(selection:) { ForEach { weekContent(...).tag(idx) } } .tabViewStyle(.page(indexDisplayMode: .never)) .animation(...)` block (lines 133-140). Replace with:
    ```swift
    weekContent(weekIndex: currentWeekIndex, plan: plan)
        .id(currentWeekIndex)
        .transition(.horizontalSlide(direction: slideDirection))
        .animation(.easeInOut(duration: 0.25), value: currentWeekIndex)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > 50, abs(dx) > abs(dy) else { return }
                    let target = currentWeekIndex + (dx < 0 ? 1 : -1)
                    goToWeek(target, plan: plan)
                }
        )
    ```
  - [ ] 🟥 Add `@State private var slideDirection: SlideDirection = .next` to `CalendarView`.
  - [ ] 🟥 Update `goToWeek(_:plan:)` ([CalendarView.swift:383-386](Dromos/Dromos/Features/Calendar/CalendarView.swift#L383)) to set direction before mutating index:
    ```swift
    private func goToWeek(_ idx: Int, plan: TrainingPlan) {
        guard idx >= 0, idx < plan.planWeeks.count else { return }
        slideDirection = idx > currentWeekIndex ? .next : .previous
        currentWeekIndex = idx
    }
    ```
  - [ ] 🟥 Verify chevron handlers (`onPrevious`, `onNext` passed to `CalendarWeekHeader`) funnel through `goToWeek` so direction is computed correctly.
  - [ ] 🟥 Wrap the `calendarReset` mutation at [CalendarView.swift:161-177](Dromos/Dromos/Features/Calendar/CalendarView.swift#L161) so the snap is instant:
    ```swift
    .onChange(of: calendarReset) { _, _ in
        let target = plan.currentWeekIndex()
        completionCacheByWeek.removeValue(forKey: target)
        if currentWeekIndex == target {
            Task { await loadIfNeeded(...) }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                currentWeekIndex = target
            }
            Task { await loadIfNeeded(...) }
        }
    }
    ```
  - [ ] 🟥 Manual QA checklist:
    - [ ] Native horizontal swipe forward: week content slides exit-left / enter-right, header pinned
    - [ ] Native horizontal swipe backward: mirror
    - [ ] Right chevron tap: forward slide (animated, not hard cut)
    - [ ] Left chevron tap: backward slide (animated)
    - [ ] Tab re-tap from a far week: instant snap to current week (NO animation across many weeks)
    - [ ] Tab re-tap from current week: no-op (no flash)
    - [ ] Edit-mode toggle still animates session-card move arrows correctly
    - [ ] Session card move arrows transition (existing) unaffected
    - [ ] Vertical scroll inside week content: does NOT trigger horizontal slide
    - [ ] Per-week completion border (green/red) renders correctly after week change
    - [ ] First appear / cold launch: no flash, no incorrect-direction slide
    - [ ] Bounds: at week 0 swipe-back is no-op; at last week swipe-forward is no-op (chevron disabled state already handles this)

- [ ] 🟥 **Phase 4: Documentation + CHANGELOG**
  - [ ] 🟥 Update `.claude/context/architecture.md`:
    - HomeView description: pure-translate transition (no fade), date label now inside slide unit
    - CalendarView description: replaced `TabView(.page)` with `.id()` + `DragGesture` pattern; tab re-tap snap is instant
    - Core tree: add `SlideTransition.swift` reference
  - [ ] 🟥 Add `CHANGELOG.md` entry under `[Unreleased]` (or appropriate version): "DRO-247: smooth horizontal push-slide transition on Today day navigation and Calendar week navigation".
