//
//  TodayMissedCard.swift
//  Dromos
//
//  Created by Emmanuel Breard on 26/04/2026.
//

import SwiftUI

/// Today tab — missed-session card.
///
/// Deliberately the smallest of the three Today variants:
/// - Smaller padding (12pt vs. 16pt) to reduce visual weight on a day already past.
/// - No rationale, no `WorkoutShape`, no `WorkoutStepList`, no CTA.
/// - Session name is rendered in `.headline` + `.secondary` (semantic dim, no opacity).
///
/// The single accent hit comes from the `MissedTag` (or numbered badge in multi-session
/// days) — nothing else on the card is colored. This keeps the missed state from
/// dominating the screen when the athlete opens Today after a missed day.
struct TodayMissedCard: View {
    let session: PlanSession
    let sequenceContext: (index: Int, total: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(spacing: 8) {
                Image(systemName: session.sportIcon)
                Text("\(session.displayName) - \(Self.formatTitleDuration(minutes: session.durationMinutes))")
            }
            .font(.headline)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.cardSurface)
        )
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            if let ctx = sequenceContext {
                SessionSequenceBadge(index: ctx.index)
                Text("\(session.sport.capitalized) · \(session.type.lowercased())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                MissedTag()
            }
            // Spacer kept so the badge / sport·type stays left-aligned with no
            // right-side caption (Phase 2 dropped the duration·sport caption — the
            // duration now lives in the title row inline next to the icon).
            Spacer(minLength: 8)
        }
    }

    /// Compact title-row duration. `60→"1h"`, `90→"1h30"`, `45→"45'"`, `120→"2h"`.
    /// Mirrors `HomeView.formatPillDuration` (DRO-242 Phase 1) so the inline duration
    /// next to the session icon matches the week-strip pills.
    private static func formatTitleDuration(minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m == 0 ? "\(h)h" : "\(h)h\(m)"
        }
        return "\(minutes)'"
    }
}

// MARK: - Previews

private let _missedRun = PlanSession(
    id: UUID(),
    weekId: UUID(),
    day: "Tuesday",
    sport: "run",
    type: "Easy",
    templateId: "RUN_Easy_01",
    durationMinutes: 45,
    isBrick: false,
    notes: nil,
    orderInDay: 0,
    feedback: nil,
    matchedActivityId: nil
)

private let _missedSwim = PlanSession(
    id: UUID(),
    weekId: UUID(),
    day: "Tuesday",
    sport: "swim",
    type: "Easy",
    templateId: "SWIM_Easy_01",
    durationMinutes: 40,
    isBrick: false,
    notes: nil,
    orderInDay: 1,
    feedback: nil,
    matchedActivityId: nil
)

#Preview("Single missed") {
    ScrollView {
        TodayMissedCard(session: _missedRun, sequenceContext: nil)
            .padding(16)
    }
    .background(Color.pageSurface)
}

#Preview("Multi-session missed (2 of 2)") {
    ScrollView {
        VStack(spacing: 12) {
            TodayMissedCard(session: _missedRun, sequenceContext: (index: 1, total: 2))
            TodayMissedCard(session: _missedSwim, sequenceContext: (index: 2, total: 2))
        }
        .padding(16)
    }
    .background(Color.pageSurface)
}

#Preview("Single missed bike — 1h30 title duration") {
    // Demonstrates the hour-and-minute formatter (`90 → "1h30"`) and the bike sport icon
    // in the Phase 2 inline title row, with the `.headline` / `.secondary` missed-card style.
    let bikeSession = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Wednesday",
        sport: "bike",
        type: "Tempo",
        templateId: "BIKE_TEMPO_3x12",
        durationMinutes: 90,
        isBrick: false,
        notes: nil,
        orderInDay: 0,
        feedback: nil,
        matchedActivityId: nil
    )
    return ScrollView {
        TodayMissedCard(session: bikeSession, sequenceContext: nil)
            .padding(16)
    }
    .background(Color.pageSurface)
}
