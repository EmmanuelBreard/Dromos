# DRO-100: Session Graph — Final Time Label + Formatting

**Overall Progress:** `50%`

## TLDR
The workout graph x-axis is missing the final duration label and uses raw minute format for all values. Fix the axis layout to always show the endpoint, format labels using hour notation for 60min+, and prevent overlap between the final label and nearby interval ticks.

## Critical Decisions
- **ZStack over HStack**: Replace the current `HStack` layout (which causes the squeeze-out bug) with a `ZStack` + proportional `.position(x:)` offsets. Each label sits at `minutes / totalDurationMinutes * availableWidth`, solving the space allocation issue entirely.
- **3-minute overlap threshold**: If the total duration is within 3 minutes of an interval tick, that tick is dropped. The final label always wins.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Home/WorkoutGraphView.swift` | MODIFY | Rewrite `timeAxisView`, add `formatTimeLabel(_:)` helper, add `timeTickMinutes` computed property |

## Context Doc Updates
- `architecture.md` — Minor: update the `WorkoutGraphView` description to mention hour-format labels and overlap prevention. One-liner update.

## Tasks

- [x] 🟨 **Step 1: Add `formatTimeLabel(_:)` helper**
  - Add a `private func formatTimeLabel(_ minutes: Double) -> String` to `WorkoutGraphView`
  - Logic:
    - `minutes == 0` → `"0'"`
    - `minutes < 60` → `"\(Int(minutes))'"`
    - `minutes` is exact hour → `"\(Int(minutes/60))h"`
    - else → `"\(Int(minutes/60))h\(Int(minutes.truncatingRemainder(dividingBy: 60)))"`
  - Place it in the `// MARK: - Time Axis` section, after `timeInterval`

- [x] 🟨 **Step 2: Add `timeTickMinutes` computed property**
  - Add a `private var timeTickMinutes: [Double]` computed property
  - Logic:
    1. Generate interval ticks: `stride(from: 0, through: totalDurationMinutes, by: timeInterval)` — but cap at `< totalDurationMinutes` (do NOT include the endpoint if it lands exactly on an interval; it will be added as the final tick)
    2. Append `totalDurationMinutes` as the final tick (always)
    3. Deduplicate: if the final tick equals the last interval tick, don't add it twice (this handles the exact-boundary case like 45min with 15min intervals)
    4. Filter: remove any interval tick that is within 3 minutes of the final tick (overlap prevention). The `0'` tick and the final tick are never removed.
  - Result: a sorted array of minute values to render as labels

- [x] 🟨 **Step 3: Rewrite `timeAxisView` using ZStack positioning**
  - Replace the current `HStack`-based `timeAxisView` with:
    ```swift
    private var timeAxisView: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let ticks = timeTickMinutes

            ZStack(alignment: .leading) {
                ForEach(ticks, id: \.self) { minutes in
                    Text(formatTimeLabel(minutes))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize()
                        .position(
                            x: (minutes / totalDurationMinutes) * availableWidth,
                            y: axisHeight / 2
                        )
                }
            }
        }
    }
    ```
  - Labels are centered on their tick position via `.position(x:y:)` (SwiftUI `.position` centers the view at the given point)
  - `.fixedSize()` ensures labels aren't compressed

- [ ] 🟨 **Step 4: Verify with existing previews**
  - The 4 existing `#Preview` blocks cover: 45min bike intervals, 40min run tempo, ~15min swim, 180min long ride
  - Confirm labels render correctly in Xcode previews:
    - Bike intervals (51min total): `0'  15'  30'  45'  51'`
    - Run tempo (40min): `0'  15'  30'  40'` (no conflict)
    - Swim (15.5min): `0'  15.5'` → actually `0'  16'` (rounded) — just `0'` and final
    - Long ride (180min): `0'  30'  1h  1h30  2h  2h30  3h`
  - No new previews needed — existing ones cover the key scenarios
