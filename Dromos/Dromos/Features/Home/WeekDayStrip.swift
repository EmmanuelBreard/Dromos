//
//  WeekDayStrip.swift
//  Dromos
//
//  DRO-236 — Phase 4 of DRO-231.
//  Compact 7-pill strip showing each day of the current week with a state-driven
//  background, a sport glyph, and an optional duration label. Pills are NOT tappable.
//

import SwiftUI

// MARK: - DayPill

/// One pill in the WeekDayStrip. Carries weekday label, an SF Symbol glyph,
/// optional duration label, and the visual state (today / completed / planned / missed / rest).
struct DayPill: Identifiable {
    /// Stable identity derived from `weekday` (each weekday is unique within a 7-pill strip).
    /// Avoids regenerating IDs on parent re-renders, which would defeat SwiftUI diffing.
    var id: Weekday { weekday }
    let weekday: Weekday
    let glyph: String
    let durationLabel: String?
    let state: PillState
}

/// Visual state of a `DayPill`. Drives background and text color.
enum PillState {
    case today
    case completed
    case planned
    case missed
    case rest
}

// MARK: - WeekDayStrip

/// Horizontal strip of 7 day-pills representing the current week.
///
/// Pills are non-tappable (display only). Layout uses equal-width flex pills
/// in an HStack so the strip fills the available width without scrolling.
struct WeekDayStrip: View {
    /// The 7 day pills to render. Caller must provide exactly 7.
    let days: [DayPill]

    var body: some View {
        // Debug-only invariant: callers must provide exactly 7 pills (one per weekday).
        // `assert` is stripped from release builds, so this is free at runtime in production.
        assert(days.count == 7, "WeekDayStrip expects exactly 7 pills")
        return HStack(spacing: 8) {
            ForEach(days) { pill in
                pillView(for: pill)
            }
        }
    }

    // MARK: - Pill Rendering

    @ViewBuilder
    private func pillView(for pill: DayPill) -> some View {
        VStack(spacing: 2) {
            // Day-of-week label (Mon/Tue/...)
            // For `.today` we explicitly invert to `cardSurface` because the pill background
            // is `Color.primary`. SwiftUI's HierarchicalShapeStyle does not auto-invert against
            // custom backgrounds, so we override here rather than rely on `.foregroundStyle(.secondary)`.
            Text(pill.weekday.abbreviation)
                .font(.caption2)
                .modifier(DowTextStyle(state: pill.state))
                .textCase(.uppercase)
                .tracking(0.8)

            // Sport / state glyph
            Image(systemName: pill.glyph)
                .font(.caption.weight(.semibold))
                .modifier(GlyphTextStyle(state: pill.state))

            if let durationLabel = pill.durationLabel {
                Text(durationLabel)
                    .font(.caption2)
                    .modifier(DurationTextStyle(state: pill.state))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 60)
        .padding(.vertical, 8)
        .background(background(for: pill.state))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Style helpers

    /// Background for each state.
    @ViewBuilder
    private func background(for state: PillState) -> some View {
        switch state {
        case .today:
            Color.primary
        case .completed:
            Color.accentColor.opacity(0.12)
        case .planned:
            Color.cardSurface
        case .missed:
            Color.errorStrong.opacity(0.12)
        case .rest:
            Color.cardSurface
        }
    }
}

// MARK: - Pill text styles

/// Day-of-week label styling.
/// `.today` inverts to `cardSurface` (sits on `Color.primary` background); everything else
/// uses the SwiftUI hierarchical `.secondary` shape style.
private struct DowTextStyle: ViewModifier {
    let state: PillState

    func body(content: Content) -> some View {
        switch state {
        case .today:
            content.foregroundStyle(Color.cardSurface)
        default:
            content.foregroundStyle(.secondary)
        }
    }
}

/// Glyph styling.
/// `.today` inverts to `cardSurface`; `.rest` uses `.tertiary` (genuinely lower contrast,
/// distinguishing it from `.planned` even on the same `cardSurface` background); everything
/// else uses `.primary`.
private struct GlyphTextStyle: ViewModifier {
    let state: PillState

    func body(content: Content) -> some View {
        switch state {
        case .today:
            content.foregroundStyle(Color.cardSurface)
        case .rest:
            content.foregroundStyle(.tertiary)
        case .completed, .planned, .missed:
            content.foregroundStyle(.primary)
        }
    }
}

/// Duration-label styling.
/// `.today` uses `cardSurface.opacity(0.6)` for de-emphasis on the inverted background;
/// everything else uses `.tertiary`.
private struct DurationTextStyle: ViewModifier {
    let state: PillState

    func body(content: Content) -> some View {
        switch state {
        case .today:
            content.foregroundStyle(Color.cardSurface.opacity(0.6))
        default:
            content.foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Previews

#Preview("WeekDayStrip — mixed week") {
    let days: [DayPill] = [
        DayPill(weekday: .monday,    glyph: "figure.pool.swim", durationLabel: "45m", state: .completed),
        DayPill(weekday: .tuesday,   glyph: "bicycle",          durationLabel: "1h",  state: .completed),
        DayPill(weekday: .wednesday, glyph: "figure.run",       durationLabel: "40m", state: .missed),
        DayPill(weekday: .thursday,  glyph: "bicycle",          durationLabel: "1h",  state: .today),
        DayPill(weekday: .friday,    glyph: "bed.double.fill",  durationLabel: nil,   state: .rest),
        DayPill(weekday: .saturday,  glyph: "figure.run",       durationLabel: "1h30", state: .planned),
        DayPill(weekday: .sunday,    glyph: "bicycle",          durationLabel: "2h",  state: .planned)
    ]

    return WeekDayStrip(days: days)
        .padding()
        .background(Color.pageSurface)
}
