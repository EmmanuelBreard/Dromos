//
//  TodayMissedCard.swift
//  Dromos
//
//  Created by Emmanuel Breard on 26/04/2026.
//

import SwiftUI

/// Today tab — missed-session card.
///
/// A missed session still shows the **scheduled workout** — title + notes + `WorkoutShape`
/// + `WorkoutStepList`, identical content to `TodayPlannedCard` — so the athlete can see
/// what was planned even though they didn't complete it.
///
/// The missed state is conveyed exactly like the Calendar tab's session cards: a red
/// leading border plus dimmed (0.5 opacity) content. No `MissedTag` pill — the border +
/// dim carry the signal, matching CalendarView for a consistent cross-tab treatment.
struct TodayMissedCard: View {
    let session: PlanSession
    let ftp: Int?
    let vma: Double?
    let css: Int?
    let maxHr: Int?
    let sequenceContext: (index: Int, total: Int)?

    /// Cached library reference. Singleton — safe to capture as a stored property.
    private let workoutLibrary = WorkoutLibraryService.shared

    /// Resolved bar segments for `WorkoutShape` (same dual-path entry as `TodayPlannedCard`).
    private var segments: [FlatSegment] {
        workoutLibrary.flattenedSegments(for: session, ftp: ftp, vma: vma, css: css, maxHr: maxHr)
    }

    /// Resolved step rows for `WorkoutStepList`.
    private var steps: [StepSummary] {
        workoutLibrary.stepSummaries(for: session, ftp: ftp, vma: vma, css: css, maxHr: maxHr)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 8) {
                Image(systemName: session.sportIcon)
                Text("\(session.displayName) - \(PlanSession.formatCompactDuration(minutes: session.durationMinutes))")
            }
            .font(.title2)
            .fontWeight(.bold)
            .kerning(-0.4)
            .foregroundColor(.primary)

            // Notes are always shown when present, regardless of sport (mirrors TodayPlannedCard).
            if let notes = session.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Strength sessions: notes only. Everything else shows the planned shape + steps.
            if session.sport.lowercased() != "strength" {
                if !segments.isEmpty {
                    WorkoutShape(segments: segments)
                }
                if !steps.isEmpty {
                    Divider()
                    WorkoutStepList(steps: steps)
                }
            }
        }
        // Dim the CONTENT (not the card fill) to de-emphasize a missed day — mirrors
        // CalendarView's `contentOpacity`. Applied before `.background` so only the
        // workout content fades, not the card surface.
        .opacity(0.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.cardSurface)
        )
        // Red leading border — the same "missed" signal CalendarView's session cards use.
        // clipShape applied AFTER the overlay so the border inherits the rounded corners.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.red)
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            if let ctx = sequenceContext {
                SessionSequenceBadge(index: ctx.index)
                Text("\(session.sport.capitalized) · \(session.type.lowercased())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
        }
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
        TodayMissedCard(session: _missedRun, ftp: nil, vma: nil, css: nil, maxHr: nil, sequenceContext: nil)
            .padding(16)
    }
    .background(Color.pageSurface)
}

#Preview("Multi-session missed (2 of 2)") {
    ScrollView {
        VStack(spacing: 12) {
            TodayMissedCard(session: _missedRun, ftp: nil, vma: nil, css: nil, maxHr: nil, sequenceContext: (index: 1, total: 2))
            TodayMissedCard(session: _missedSwim, ftp: nil, vma: nil, css: nil, maxHr: nil, sequenceContext: (index: 2, total: 2))
        }
        .padding(16)
    }
    .background(Color.pageSurface)
}

#Preview("Single missed bike — 1h30 title duration") {
    // Demonstrates the hour-and-minute formatter (`90 → "1h30"`) and the bike sport icon
    // in the inline title row, plus the missed treatment (red leading border + dimmed content).
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
        TodayMissedCard(session: bikeSession, ftp: nil, vma: nil, css: nil, maxHr: nil, sequenceContext: nil)
            .padding(16)
    }
    .background(Color.pageSurface)
}
