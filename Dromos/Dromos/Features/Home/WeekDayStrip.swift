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
    let id = UUID()
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
        HStack(spacing: 8) {
            ForEach(days) { pill in
                pillView(for: pill)
            }
        }
    }

    // MARK: - Pill Rendering

    @ViewBuilder
    private func pillView(for pill: DayPill) -> some View {
        VStack(spacing: 2) {
            Text(pill.weekday.abbreviation)
                .font(.caption2)
                .foregroundColor(textColor(for: pill.state, role: .secondary))
                .textCase(.uppercase)
                .tracking(0.8)

            Image(systemName: pill.glyph)
                .font(.caption.weight(.semibold))
                .foregroundColor(textColor(for: pill.state, role: .primary))

            if let durationLabel = pill.durationLabel {
                Text(durationLabel)
                    .font(.caption2)
                    .foregroundColor(textColor(for: pill.state, role: .tertiary))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 60)
        .padding(.vertical, 6)
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

    /// Text role within a pill — used to map secondary/tertiary text to the right color
    /// while overriding everything to `cardSurface` when the pill is "today".
    private enum TextRole { case primary, secondary, tertiary }

    private func textColor(for state: PillState, role: TextRole) -> Color {
        if state == .today {
            // White-on-dark — use cardSurface so it adapts in light/dark.
            return .cardSurface
        }
        if state == .rest {
            // Rest day uses muted text across all roles.
            return .secondary
        }
        switch role {
        case .primary:   return .primary
        case .secondary: return .secondary
        case .tertiary:  return .secondary.opacity(0.7)
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
