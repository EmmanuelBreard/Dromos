//
//  TodayPlannedCard.swift
//  Dromos
//
//  Created by Emmanuel Breard on 26/04/2026.
//

import SwiftUI

/// Today tab — planned (not-yet-completed) session card.
///
/// Composes the Phase 1 visual primitives: `WorkoutShape` + `WorkoutStepList`. Used both
/// as the standalone single-session view and as one row inside a multi-session day stack
/// (driven by `sequenceContext`). Card is intentionally **not** tappable — Today is a
/// "look at it, go do it" surface, not a navigation hub.
struct TodayPlannedCard: View {
    let session: PlanSession
    let template: WorkoutTemplate?
    let ftp: Int?
    let vma: Double?
    let css: Int?
    let maxHr: Int?
    /// Multi-session context: 1-based `index` within the day, plus `total` count.
    /// `nil` means single-session day → header collapses to just the right-side caption.
    /// The day anchor (Today / Yesterday / April 29th) is rendered as an external
    /// section header above the card by `HomeView`, not inside the card.
    let sequenceContext: (index: Int, total: Int)?

    /// Cached library reference. Singleton — safe to capture as a stored property.
    private let workoutLibrary = WorkoutLibraryService.shared

    // MARK: - Derived data

    /// Resolved bar segments for `WorkoutShape`. Uses the dual-path entry so the card
    /// transparently supports both legacy templates and new `SessionStructure` payloads.
    private var segments: [FlatSegment] {
        workoutLibrary.flattenedSegments(
            for: session,
            ftp: ftp,
            vma: vma,
            css: css,
            maxHr: maxHr
        )
    }

    /// Resolved step rows for `WorkoutStepList`.
    private var steps: [StepSummary] {
        workoutLibrary.stepSummaries(
            for: session,
            ftp: ftp,
            vma: vma,
            css: css,
            maxHr: maxHr
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 8) {
                Image(systemName: session.sportIcon)
                Text("\(session.displayName) - \(Self.formatTitleDuration(minutes: session.durationMinutes))")
            }
            .font(.title2)
            .fontWeight(.bold)
            .kerning(-0.4)
            .foregroundColor(.primary)
            if let notes = session.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !segments.isEmpty {
                WorkoutShape(segments: segments)
            }
            if !steps.isEmpty {
                Divider()
                WorkoutStepList(steps: steps)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.cardSurface)
        )
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            if let ctx = sequenceContext {
                SessionSequenceBadge(index: ctx.index)
                Text("\(session.sport.capitalized) · \(session.type.lowercased())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            // Spacer kept so the badge / sport·type stays left-aligned with no
            // right-side caption (Phase 2 dropped the duration·sport caption — the
            // duration now lives in the title row inline next to the icon).
            Spacer(minLength: 8)
        }
    }

    /// Compact title-row duration. `60→"1h"`, `90→"1h30"`, `45→"45'"`, `120→"2h"`.
    /// Mirrors `HomeView.formatPillDuration` (DRO-242 Phase 1) so the inline duration
    /// next to the session icon matches the week-strip pills. Intentionally omits the
    /// apostrophe on the minutes part of an hour-and-minute combo (`1h30`, not
    /// `1h 30'`).
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

/// Canonical Tuesday VO2 5×3' session shared across DRO-231 prototypes.
private let _previewVO2Session = PlanSession(
    id: UUID(),
    weekId: UUID(),
    day: "Tuesday",
    sport: "run",
    type: "Intervals",
    templateId: "RUN_VO2_5x3",
    durationMinutes: 52,
    isBrick: false,
    notes: "VO2 max work — keep the recovery jogs honest. Cadence around 88 spm on the work intervals.",
    orderInDay: 0,
    feedback: nil,
    matchedActivityId: nil
)

private let _previewMorningSwim = PlanSession(
    id: UUID(),
    weekId: UUID(),
    day: "Tuesday",
    sport: "swim",
    type: "Easy",
    templateId: "SWIM_Easy_01",
    durationMinutes: 45,
    isBrick: false,
    notes: "Aerobic recovery swim. Smooth catch, long exhale.",
    orderInDay: 0,
    feedback: nil,
    matchedActivityId: nil
)

private let _previewEveningRun = PlanSession(
    id: UUID(),
    weekId: UUID(),
    day: "Tuesday",
    sport: "run",
    type: "Easy",
    templateId: "RUN_Easy_01",
    durationMinutes: 30,
    isBrick: false,
    notes: nil,
    orderInDay: 1,
    feedback: nil,
    matchedActivityId: nil
)

#Preview("Single planned (run intervals)") {
    // Mirrors HomeView's hero layout: external "Today" section header above the
    // card. Demonstrates that the in-card date caption is gone and the external
    // label carries the temporal anchor.
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.title3)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            TodayPlannedCard(
                session: _previewVO2Session,
                template: nil,
                ftp: nil,
                vma: 17.0,
                css: nil,
                maxHr: 188,
                sequenceContext: nil
            )
        }
        .padding(16)
    }
    .background(Color.pageSurface)
}

#Preview("Multi-session — 1 of 2 (swim)") {
    ScrollView {
        VStack(spacing: 12) {
            TodayPlannedCard(
                session: _previewMorningSwim,
                template: nil,
                ftp: nil,
                vma: nil,
                css: 95,
                maxHr: 188,
                sequenceContext: (index: 1, total: 2)
            )
            TodayPlannedCard(
                session: _previewEveningRun,
                template: nil,
                ftp: nil,
                vma: 17.0,
                css: nil,
                maxHr: 188,
                sequenceContext: (index: 2, total: 2)
            )
        }
        .padding(16)
    }
    .background(Color.pageSurface)
}

#Preview("Bike tempo — 1h30 title duration") {
    // Demonstrates the hour-and-minute formatter (`90 → "1h30"`) and the bike sport icon
    // in the Phase 2 inline title row.
    let bikeSession = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Wednesday",
        sport: "bike",
        type: "Tempo",
        templateId: "BIKE_TEMPO_3x12",
        durationMinutes: 90,
        isBrick: false,
        notes: "Tempo blocks at 88-92% FTP — steady cadence in the work intervals.",
        orderInDay: 0,
        feedback: nil,
        matchedActivityId: nil
    )
    return ScrollView {
        TodayPlannedCard(
            session: bikeSession,
            template: nil,
            ftp: 250,
            vma: nil,
            css: nil,
            maxHr: 188,
            sequenceContext: nil
        )
        .padding(16)
    }
    .background(Color.pageSurface)
}

#Preview("Simple swim — no template segments") {
    // A session whose templateId resolves to nothing in the library — confirms the card
    // gracefully omits both shape and step list without leaving a dangling Divider.
    let session = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Wednesday",
        sport: "swim",
        type: "Easy",
        templateId: "MISSING_TEMPLATE_ID",
        durationMinutes: 40,
        isBrick: false,
        notes: "Open water — focus on sighting every 6 strokes.",
        orderInDay: 0,
        feedback: nil,
        matchedActivityId: nil
    )
    return ScrollView {
        TodayPlannedCard(
            session: session,
            template: nil,
            ftp: nil,
            vma: nil,
            css: 95,
            maxHr: 188,
            sequenceContext: nil
        )
        .padding(16)
    }
    .background(Color.pageSurface)
}
