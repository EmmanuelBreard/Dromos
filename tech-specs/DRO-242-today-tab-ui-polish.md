# DRO-242 — Today Tab UI Polish

**Overall Progress:** `0%`

## TLDR

Bundle of small UI improvements to the Today/Home tab: (A) keep the today-pill anchored with a green border that moves to the selected day instead of being lost, (B) render one SF Symbol per session inline on multi-session pills, (C) collapse the session-card title into a single line `[icon] Tempo Bike - 1h30` and drop the redundant right-side caption, (D) re-add horizontal swipe between days with `.easeInOut(duration: 0.25)` animation parity for pill taps. Re-attempts the swipe feature reverted in commit `8db7bdd` due to a fixed-height TabView spacing regression.

Scope: Today tab only (`TodayPlannedCard` / `TodayCompletedCard` / `TodayMissedCard`). Calendar tab's `SessionCardView` is untouched.

## Critical Decisions

- **Swipe implementation: `DragGesture` + state swap with `.transition`, NOT `TabView(.page)`.** The previous attempt (PR #67, commit `93800f1`) wrapped the hero in a paged `TabView` with `idealHeight: 720`. Paged TabView centres its content in a fixed frame, so a 200pt rest-day card sat in a 720pt container — that's the "weird spacing between the date and the session card" the user reported. A `DragGesture` on the hero container + a `selectedDay`-driven swap with `.transition(.asymmetric(...))` keeps the hero content-sized (no fixed frame), which mechanically eliminates the regression. Trade-off: the swipe is a discrete swap rather than a finger-follow page; acceptable for day navigation on the Today screen since users only need next/prev affordance.

- **`isSelected` semantics extended to today.** Currently `WeekDayStrip` excludes today from the accent-outline overlay (`pill.state != .today`). Removing that guard + marking today's pill `isSelected = true` when `selectedDay == nil` is a one-line behavioural change in `weekPills(...)` and a one-line guard removal in `WeekDayStrip.swift`. The today pill's solid `Color.primary` background is preserved.

- **`DayPill.glyph: String` → `glyphs: [String]`.** Required to render multiple SF Symbols inline. Single-glyph callers pass `[oneGlyph]`. No back-compat shim — `DayPill` is private to the Home feature.

- **Drop the right-side header caption (`52' · run`) on Today cards.** With the new `[icon] Tempo Bike - 1h30` title, the right-side caption duplicates both the duration and the sport. Keep the multi-session badge + `Sport · type` left side of the header for sequence context.

- **Duration format mirrors the existing `formatPillDuration` in `HomeView`.** `60 → "1h"`, `90 → "1h30"`, `45 → "45'"`, `120 → "2h"`. The current `formatDurationApostrophe` static on `TodayPlannedCard` / `TodayMissedCard` is similar but emits `"1h 30'"` (with apostrophe) for non-round hours — replace with the pill formatter to match the user-confirmed `1h30` format.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Home/WeekDayStrip.swift` | MODIFY | `DayPill.glyph: String` → `glyphs: [String]`. Render glyphs in an HStack on the icon row. Remove `pill.state != .today` guard in the `strokeBorder` overlay so today shows the accent border when `isSelected`. Update both `#Preview` blocks to pass `glyphs:` arrays. |
| `Dromos/Dromos/Features/Home/HomeView.swift` | MODIFY | (1) `weekPills(selected:)` returns `isSelected = true` for today's pill when `selected == nil`; non-today pills as today. (2) New helper `glyphs(for:sessions:)` returns `[String]` — array form of the existing `glyph(for:sessions:)` rules: `["bed.double.fill"]` for rest, `["flag.checkered"]` for race, `[first.sportIcon]` if brick, `sessions.map(\.sportIcon)` for multi. (3) Replace `todayHero` with a swipe wrapper: a container holding the day-routed cards, with a `DragGesture` that calls `goToDay(...)` on horizontal swipe past a 50pt threshold. (4) Wrap pill-tap state changes in `withAnimation(.easeInOut(duration: 0.25))`. (5) Add `goToDay(_ direction: SwipeDirection)` helper that advances `selectedDay` ±1 within the current week, clamped at Mon/Sun, with the same animation. (6) Replace `formatTotalDuration` reuse for pill — use the existing `formatPillDuration` for both. |
| `Dromos/Dromos/Features/Home/TodayPlannedCard.swift` | MODIFY | Replace the standalone `Text(session.displayName)` block with a single HStack title row: `Image(systemName: session.sportIcon)` + `Text("\(session.displayName) - \(formatPillDuration(...))")`, both `.title2 / .bold / .kerning(-0.4) / .foregroundColor(.primary)`. Remove the `Text("\(formatDurationApostrophe(...)) · \(session.sport.lowercased())")` from the header HStack (right-side caption). Replace local `formatDurationApostrophe` with `formatPillDuration` (consistent with `HomeView`). Update previews to reflect the new layout. |
| `Dromos/Dromos/Features/Home/TodayCompletedCard.swift` | MODIFY | Same treatment as `TodayPlannedCard`: title row becomes `[icon] DisplayName - <duration>`. Duration here is the **planned** duration (`session.durationMinutes`) — the actual Strava duration stays in `ActualVsPlannedTable`. Remove the right-side `formattedActualDuration · sport` caption from the header. |
| `Dromos/Dromos/Features/Home/TodayMissedCard.swift` | MODIFY | Same treatment as the other two. Title row uses `.headline` (matches the missed card's reduced visual weight) but with the icon prefix and inline duration. Remove the right-side caption. Replace local `formatDurationApostrophe` with `formatPillDuration`. |

## Context Doc Updates

- `architecture.md` — Update the WeekDayStrip line (`pills not tappable in v1` → `pills tappable, today shows green border by default, multi-session pills render multiple SF Symbols`). Update the Today card descriptions to mention the inline `[icon] name - duration` title row. No new files, no schema changes.

## Open Questions

(none — discovery resolved all product questions)

## Tasks

### - [ ] 🟥 **Phase 1: WeekDayStrip — multi-glyph + always-on today border**

Goal: green border can be applied to today; multi-session pills show one SF Symbol per session inline.

  - [ ] 🟥 In `WeekDayStrip.swift`, change `DayPill.glyph: String` to `glyphs: [String]`. Update the doc-comment.
  - [ ] 🟥 Replace the single `Image(systemName: pill.glyph)` in `pillView(for:)` with an HStack rendering one `Image(systemName:)` per glyph in `pill.glyphs`. Spacing 4pt. Same `.font(.caption.weight(.semibold))` and `GlyphTextStyle(state:)` modifier as today.
  - [ ] 🟥 Remove the `pill.state != .today` clause from the `strokeBorder` `lineWidth` ternary so the accent outline renders whenever `pill.isSelected` is true, including for the today pill.
  - [ ] 🟥 Update both `#Preview` blocks (`mixed week` + `selected non-today pill`) to pass `glyphs:` arrays. Add a third preview demonstrating today + multi-session day with two glyphs (e.g., swim + run on Thursday).
  - [ ] 🟥 In `HomeView.weekPills(selected:)`, when computing each pill set `isSelected = (selected == nil ? day == todayWeekday() : selected == day)`. Net: today is the default selected pill; tapping a non-today pill moves selection (and the green border) to that pill.
  - [ ] 🟥 In `HomeView`, add `glyphs(for day: Weekday, sessions: [PlanSession]) -> [String]`. Rules: empty → `["bed.double.fill"]`; race → `["flag.checkered"]`; brick (single brick session) → `[first.sportIcon]`; otherwise → `sessions.map(\.sportIcon)`. Replace the call to `glyph(...)` in `weekPills(...)` with a call to `glyphs(...)`. Delete the now-unused `glyph(...)`.
  - [ ] 🟥 Build + run: confirm today pill shows green border by default; tapping another day moves the border; multi-session days show 2 icons side-by-side. Visual sanity check across light + dark mode.

### - [ ] 🟥 **Phase 2: Today hero session cards — single-line title with icon + duration**

Goal: cards display `[icon] Tempo Bike - 1h30` on one line; redundant right-side caption removed.

  - [ ] 🟥 Add a shared duration formatter. Decision: keep it private-static on each card (matches existing `formatDurationApostrophe` pattern) but with the pill-formatter logic — `60→"1h"`, `90→"1h30"`, `45→"45'"`. Naming: `formatTitleDuration(minutes:)`. (If `HomeView.formatPillDuration` is needed in 2+ files, promote to a `Weekday`/`PlanSession` extension; otherwise keep duplicated.)
  - [ ] 🟥 In `TodayPlannedCard.body`, replace:
    ```swift
    Text(session.displayName)
        .font(.title2)
        .fontWeight(.bold)
        .kerning(-0.4)
        .foregroundColor(.primary)
    ```
    with:
    ```swift
    HStack(spacing: 8) {
        Image(systemName: session.sportIcon)
        Text("\(session.displayName) - \(Self.formatTitleDuration(minutes: session.durationMinutes))")
    }
    .font(.title2)
    .fontWeight(.bold)
    .kerning(-0.4)
    .foregroundColor(.primary)
    ```
  - [ ] 🟥 In `TodayPlannedCard.header`, drop the trailing `Text("\(formatDurationApostrophe(...)) · \(session.sport.lowercased())")` element. Keep the badge + sport·type left side. The `Spacer(minLength: 8)` can stay or be removed (no right-side element to push against).
  - [ ] 🟥 Repeat in `TodayCompletedCard.body` (title row) and `header` (drop `formattedActualDuration · sport`). Title duration = `session.durationMinutes` (planned), not the Strava actual — the actual stays in `ActualVsPlannedTable`.
  - [ ] 🟥 Repeat in `TodayMissedCard.body`. Title row HStack uses `.headline` (not `.title2`) + `.secondary` foreground (preserve missed-card visual hierarchy). Drop the right-side caption from `header`.
  - [ ] 🟥 Update each card's `#Preview` blocks: the new title is the most visible change so previews must show it correctly across run / bike / swim sessions.
  - [ ] 🟥 Build + run: confirm icon + name + duration all render on one line on the iPhone 13 mini width (smallest target) for all sport icons, including longer names like "Intervals Bike" and "Endurance Run". If overflow occurs, plan a fallback (truncate display name with `lineLimit(1)` + `truncationMode(.tail)`).

### - [ ] 🟥 **Phase 3: Day swipe + animation parity**

Goal: horizontal swipe on the hero changes day with `.easeInOut(0.25)`; pill taps animate with the same transition; spacing between the day label and the card is unchanged from today.

  - [ ] 🟥 In `HomeView`, define `private enum SwipeDirection { case next, previous }` and a helper:
    ```swift
    private func goToDay(_ direction: SwipeDirection) {
        let current = effectiveSelectedDay
        guard let idx = Weekday.allCases.firstIndex(of: current) else { return }
        let target: Int = direction == .next ? idx + 1 : idx - 1
        guard Weekday.allCases.indices.contains(target) else { return }  // hard stop at Mon/Sun
        let newDay = Weekday.allCases[target]
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedDay = (newDay == todayWeekday()) ? nil : newDay
        }
    }
    ```
  - [ ] 🟥 Wrap `todayHero` in a container that owns the swipe gesture. Pattern:
    ```swift
    todayHero
        .id(effectiveSelectedDay)  // forces view identity per day for transition
        .transition(
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        )
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > 50, abs(dx) > abs(dy) else { return }  // 50pt horizontal threshold, mostly-horizontal motion
                    goToDay(dx < 0 ? .next : .previous)
                }
        )
    ```
    Critical: do NOT add `.frame(...)` height constraints. The container sizes to its content, eliminating the prior regression.
  - [ ] 🟥 Wrap pill-tap mutations in `handlePillTap(_:)` with `withAnimation(.easeInOut(duration: 0.25)) { ... }` so pill taps animate the hero swap identically to swipes.
  - [ ] 🟥 Verify the empty-plan branch (`EmptyHomeHero`) is NOT wrapped in the swipe gesture — only the `todayHero` inside the `if let _ = planService.trainingPlan` branch.
  - [ ] 🟥 Cross-state QA: swipe through Mon→Tue→...→Sun, including a day with a planned card, a completed card, a missed card, a multi-session day, a rest day, and (if practical to mock) a race day. Confirm the spacing between the external day label and the card top stays at the existing 24pt VStack spacing on every variant — no whitespace bloom under short cards. Verify hard stop at Monday (left) and Sunday (right) — swipe past the edge does nothing.
  - [ ] 🟥 Confirm vertical scroll inside the outer `ScrollView` still works: drag vertically on the card should scroll the page, not trigger the swipe gesture. The `abs(dx) > abs(dy)` guard handles this.

### - [ ] 🟥 **Phase 4: Context doc + PR**

  - [ ] 🟥 Update `.claude/context/architecture.md` lines describing `WeekDayStrip` and the three Today cards to reflect the new behaviour (today border default, multi-glyph pills, single-line title).
  - [ ] 🟥 Open PR `feature/DRO-242-today-tab-polish` against `main`. Title: `feat(DRO-242): today tab polish — week strip, session card title, day swipe`. Body must call out the swipe regression fix (drag gesture instead of fixed-height TabView) so the reviewer can spot-check the spacing claim.
  - [ ] 🟥 Self-QA checklist in PR description: pill green border default, pill green border movement on tap, multi-session glyph rendering, title row layout on smallest device, swipe in both directions, edge stop at Mon/Sun, animation parity between swipe and tap, vertical scroll preserved.
