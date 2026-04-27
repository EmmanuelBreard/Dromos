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
            Text(session.displayName)
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
            Spacer(minLength: 8)
            Text("\(Self.formatDurationApostrophe(minutes: session.durationMinutes)) · \(session.sport.lowercased())")
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
    }

    /// Mirrors the apostrophe glyph format used by `TodayCompletedCard` (and the Phase 1
    /// step list) so the right-side caption reads identically across the three card
    /// variants. Intentionally local — `session.formattedDuration` is still consumed
    /// elsewhere with the verbose `"60 min"` style.
    private static func formatDurationApostrophe(minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)'"
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
