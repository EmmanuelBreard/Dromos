# DRO-193 — Graph Segment Tooltip on Press

**Overall Progress:** `100%`

## TLDR
Replace the tap-toggle + below-graph display of segment data with a press-and-hold floating tooltip that appears **above** the tapped bar, centered on it, and disappears on finger release. Single-file change in `WorkoutGraphView.swift`.

## Critical Decisions

- **Gesture: `DragGesture(minimumDistance: 0)` not `LongPressGesture`** — SwiftUI has no native "finger down / finger up" primitive. `DragGesture(minimumDistance: 0)` fires `.onChanged` immediately on touch-down and `.onEnded` on release. `LongPressGesture` would require holding for a delay, which is wrong UX here.
- **Tooltip as overlay inside existing `GeometryReader`** — The bars are already rendered inside a `GeometryReader`. We add a `.overlay` on that same `GeometryReader` so `geometry.size.width` is accessible for x-clamping. The tooltip uses `.offset(y: -(graphHeight + tooltipHeight / 2 + 6))` (approximate — Mamma Aiuto can refine) to float above the bars. Set `.allowsHitTesting(false)` so it doesn't intercept sibling gestures.
- **Remove "tap outside to dismiss" background** — No longer needed; tooltip auto-hides on finger lift.
- **Remove tooltip from VStack below** — The `if let index = selectedSegmentIndex` block below `timeAxisView` is deleted entirely.
- **New state: `tooltipXOffset: CGFloat`** — Computed in the gesture handler from bar index + bar widths within the `GeometryReader` closure where `usableWidth` and `barWidth` are already in scope.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Home/WorkoutGraphView.swift` | MODIFY | Replace gesture, add tooltip state, reposition tooltip as overlay above bars |

## Context Doc Updates
None — no new files, tables, or architectural patterns introduced.

## Tasks

- [x] 🟩 **Step 1: Add tooltip x-offset state**
  - [x] 🟩 Add `@State private var tooltipXOffset: CGFloat = 0` below the existing `@State private var selectedSegmentIndex: Int?`

- [x] 🟩 **Step 2: Replace `onTapGesture` with `DragGesture(minimumDistance: 0)`**
  - [x] 🟩 On each `RoundedRectangle` bar, replace `.onTapGesture { ... }` with `.gesture(DragGesture(minimumDistance: 0) ...)`
  - [x] 🟩 In `.onChanged`: compute bar center x as the sum of preceding bar widths (respecting `max(barWidth, 2)` floor and `+2` spacing per bar) + half the current bar width. Store in `tooltipXOffset`. Set `selectedSegmentIndex = index` (no animation needed on show — instant feel is better).
  - [x] 🟩 In `.onEnded`: `withAnimation(.easeInOut(duration: 0.15)) { selectedSegmentIndex = nil }`

- [x] 🟩 **Step 3: Remove "tap outside" background gesture**
  - [x] 🟩 Delete the `.background { Color.clear.contentShape(Rectangle()).onTapGesture { ... } }` block from the `HStack`

- [x] 🟩 **Step 4: Add tooltip overlay above the bars**
  - [x] 🟩 On the `GeometryReader` (the one wrapping the `HStack` of bars), add `.overlay(alignment: .topLeading)` containing a conditional tooltip
  - [x] 🟩 Inside the overlay: render `segmentTooltipView(for: segments[index])` with `.fixedSize()` (let it size to content)
  - [x] 🟩 Position with `.position(x: clampedX, y: 0)` then offset upward so it sits above the bar top. Use a hardcoded upward offset (e.g. `-tooltipEstimatedHeight - 6`). Clamp x: `min(max(tooltipXOffset, tooltipHalfWidth), geometry.size.width - tooltipHalfWidth)` — use a reasonable constant like `80` for half-width since the tooltip is short text.
  - [x] 🟩 Add `.allowsHitTesting(false)` to the tooltip so it doesn't intercept surrounding gestures
  - [x] 🟩 Add `.transition(.opacity)` for a clean fade

- [x] 🟩 **Step 5: Remove below-graph tooltip display**
  - [x] 🟩 Delete the `if let index = selectedSegmentIndex, index < segments.count { segmentTooltipView(...).transition(...) }` block from the `VStack` (lines 82–85)

- [x] 🟩 **Step 6: Verify previews**
  - [x] 🟩 Confirm all four `#Preview` blocks still compile and the tooltip appears above bars in each sport variant (bike, run, swim, long ride)
