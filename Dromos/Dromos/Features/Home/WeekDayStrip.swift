//
//  WeekDayStrip.swift
//  Dromos
//
//  DRO-236 — Phase 4 of DRO-231.
//  Compact 7-pill strip showing each day of the current week with a state-driven
//  background, one or more sport glyphs, and an optional duration label.
//
//  DRO-231 follow-up (week-strip tap): pills are now tappable when the parent
//  supplies an `onPillTap` callback, and a non-today pill can be marked
//  `isSelected` to show an accent-color outline.
//
//  DRO-244 (Phase 1 of DRO-242): pills now carry `glyphs: [String]` so multi-
//  session days render one SF Symbol per session, and the accent outline
//  renders on `.today` too — today is the default selected pill, so the green
//  border lives on today by default and follows the user's tap to other days.
//

import SwiftUI

// MARK: - DayPill

/// One pill in the WeekDayStrip. Carries weekday label, one or more SF Symbol
/// glyphs (one per session for multi-session days), optional duration label,
/// the visual state (today / completed / planned / missed / rest), and a
/// `isSelected` flag for the accent-outline state.
struct DayPill: Identifiable {
    /// Stable identity derived from `weekday` (each weekday is unique within a 7-pill strip).
    /// Avoids regenerating IDs on parent re-renders, which would defeat SwiftUI diffing.
    var id: Weekday { weekday }
    let weekday: Weekday
    /// SF Symbol names for the icon row. Single-session / rest / race days pass
    /// a single-element array; multi-session days pass one glyph per session in
    /// `orderInDay` order. Rendered side-by-side in an HStack.
    let glyphs: [String]
    let durationLabel: String?
    let state: PillState
    /// True iff the parent has marked this pill as the "previewed" day. Renders an
    /// accent-color outline on top of the state's normal background. Applies to
    /// every state including `.today` — today is the default selected pill, so
    /// the green border shows on today until the user taps a different day.
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

            // Sport / state glyph row. One Image per glyph so multi-session
            // days (e.g., swim + run) render two icons side-by-side. Single-
            // session / rest / race days pass a one-element array and look
            // identical to the pre-DRO-244 single-glyph layout.
            HStack(spacing: 4) {
                ForEach(Array(pill.glyphs.enumerated()), id: \.offset) { _, glyph in
                    Image(systemName: glyph)
                        .font(.caption.weight(.semibold))
                        .modifier(GlyphTextStyle(state: pill.state))
                }
            }

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
        // Selected pill: 2pt accent outline overlays the state background.
        // DRO-244: applies to every state — including `.today`, since today is
        // the default selected pill. The outline + the today solid background
        // together signal "this is today AND it's the previewed day"; tapping
        // a different pill moves the outline off today onto that day.
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    Color.accentColor,
                    lineWidth: pill.isSelected ? 2 : 0
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
        DayPill(weekday: .monday,    glyphs: ["figure.pool.swim"], durationLabel: "45m", state: .completed),
        DayPill(weekday: .tuesday,   glyphs: ["bicycle"],          durationLabel: "1h",  state: .completed),
        DayPill(weekday: .wednesday, glyphs: ["figure.run"],       durationLabel: "40m", state: .missed),
        DayPill(weekday: .thursday,  glyphs: ["bicycle"],          durationLabel: "1h",  state: .today),
        DayPill(weekday: .friday,    glyphs: ["bed.double.fill"],  durationLabel: nil,   state: .rest),
        DayPill(weekday: .saturday,  glyphs: ["figure.run"],       durationLabel: "1h30", state: .planned),
        DayPill(weekday: .sunday,    glyphs: ["bicycle"],          durationLabel: "2h",  state: .planned)
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
        DayPill(weekday: .monday,    glyphs: ["figure.pool.swim"], durationLabel: "45m", state: .completed),
        DayPill(weekday: .tuesday,   glyphs: ["bicycle"],          durationLabel: "1h",  state: .completed),
        DayPill(weekday: .wednesday, glyphs: ["figure.run"],       durationLabel: "40m", state: .missed),
        DayPill(weekday: .thursday,  glyphs: ["bicycle"],          durationLabel: "1h",  state: .today),
        DayPill(weekday: .friday,    glyphs: ["bed.double.fill"],  durationLabel: nil,   state: .rest),
        DayPill(weekday: .saturday,  glyphs: ["figure.run"],       durationLabel: "1h30", state: .planned, isSelected: true),
        DayPill(weekday: .sunday,    glyphs: ["bicycle"],          durationLabel: "2h",  state: .planned)
    ]

    return WeekDayStrip(days: days, onPillTap: { _ in })
        .padding()
        .background(Color.pageSurface)
}

#Preview("WeekDayStrip — today selected + multi-glyph day") {
    // DRO-244: today (Thursday) carries the accent outline by default while
    // also keeping its solid `.today` background. Thursday in this fixture is
    // a brick-style two-session day rendered with two glyphs side-by-side
    // (swim + run) to validate the multi-glyph icon row.
    let days: [DayPill] = [
        DayPill(weekday: .monday,    glyphs: ["figure.pool.swim"],                 durationLabel: "45m",  state: .completed),
        DayPill(weekday: .tuesday,   glyphs: ["bicycle"],                          durationLabel: "1h",   state: .completed),
        DayPill(weekday: .wednesday, glyphs: ["figure.run"],                       durationLabel: "40m",  state: .missed),
        DayPill(weekday: .thursday,  glyphs: ["figure.pool.swim", "figure.run"],   durationLabel: "1h30", state: .today, isSelected: true),
        DayPill(weekday: .friday,    glyphs: ["bed.double.fill"],                  durationLabel: nil,    state: .rest),
        DayPill(weekday: .saturday,  glyphs: ["figure.run"],                       durationLabel: "1h30", state: .planned),
        DayPill(weekday: .sunday,    glyphs: ["bicycle"],                          durationLabel: "2h",   state: .planned)
    ]

    return WeekDayStrip(days: days, onPillTap: { _ in })
        .padding()
        .background(Color.pageSurface)
}
