//
//  WeekDayStrip.swift
//  Dromos
//
//  DRO-236 — Phase 4 of DRO-231.
//  Compact 7-pill strip showing each day of the current week with a state-driven
//  background, a sport glyph, and an optional duration label.
//
//  DRO-231 follow-up (week-strip tap): pills are now tappable when the parent
//  supplies an `onPillTap` callback, and a non-today pill can be marked
//  `isSelected` to show an accent-color outline (today retains its solid
//  background regardless of `isSelected`).
//

import SwiftUI

// MARK: - DayPill

/// One pill in the WeekDayStrip. Carries weekday label, an SF Symbol glyph,
/// optional duration label, the visual state (today / completed / planned / missed / rest),
/// and a `isSelected` flag for the "selected but not today" outline state.
struct DayPill: Identifiable {
    /// Stable identity derived from `weekday` (each weekday is unique within a 7-pill strip).
    /// Avoids regenerating IDs on parent re-renders, which would defeat SwiftUI diffing.
    var id: Weekday { weekday }
    let weekday: Weekday
    let glyph: String
    let durationLabel: String?
    let state: PillState
    /// True iff the parent has marked this pill as the "previewed" day. Renders an
    /// accent-color outline on top of the state's normal background. Ignored when
    /// `state == .today` (today already has its own distinctive solid background).
    var isSelected: Bool = false
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
/// Pills become tappable when `onPillTap` is non-nil. Callers that don't wire
/// the callback get the original display-only behavior (default = nil → no-op).
/// Layout uses equal-width flex pills in an HStack so the strip fills the
/// available width without scrolling.
struct WeekDayStrip: View {
    /// The 7 day pills to render. Caller must provide exactly 7.
    let days: [DayPill]
    /// Optional tap handler. When nil, pills render but do not respond to taps
    /// (preserves the original Phase-4 contract for callers that haven't been
    /// updated). When set, the entire pill rect is tappable via `.contentShape`.
    var onPillTap: ((Weekday) -> Void)? = nil

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
        // Selected-but-not-today: 2pt accent outline overlays the state background.
        // Skipped for `.today` because today's solid background is already a strong
        // visual identifier — overlaying an outline would muddy the distinction
        // between "today" and "previewed".
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    Color.accentColor,
                    lineWidth: (pill.isSelected && pill.state != .today) ? 2 : 0
                )
        )
        // Whole-rect tap target — without `.contentShape`, taps would only register
        // on the rendered text/glyph pixels, not the surrounding pill area.
        .contentShape(Rectangle())
        .onTapGesture {
            onPillTap?(pill.weekday)
        }
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

#Preview("WeekDayStrip — selected non-today pill") {
    // Demonstrates the "previewed day" state: Saturday is selected (accent outline)
    // while Thursday remains today (solid background). Tap callback is wired but
    // no-ops in the preview.
    let days: [DayPill] = [
        DayPill(weekday: .monday,    glyph: "figure.pool.swim", durationLabel: "45m", state: .completed),
        DayPill(weekday: .tuesday,   glyph: "bicycle",          durationLabel: "1h",  state: .completed),
        DayPill(weekday: .wednesday, glyph: "figure.run",       durationLabel: "40m", state: .missed),
        DayPill(weekday: .thursday,  glyph: "bicycle",          durationLabel: "1h",  state: .today),
        DayPill(weekday: .friday,    glyph: "bed.double.fill",  durationLabel: nil,   state: .rest),
        DayPill(weekday: .saturday,  glyph: "figure.run",       durationLabel: "1h30", state: .planned, isSelected: true),
        DayPill(weekday: .sunday,    glyph: "bicycle",          durationLabel: "2h",  state: .planned)
    ]

    return WeekDayStrip(days: days, onPillTap: { _ in })
        .padding()
        .background(Color.pageSurface)
}
