//
//  TodayCompletedCard.swift
//  Dromos
//
//  Created by Emmanuel Breard on 26/04/2026.
//

import SwiftUI

/// Today tab — completed-session card.
///
/// Composes:
/// - `CompletedTag` (or `SessionSequenceBadge` in multi-session days) at the top.
/// - The session's display name in title case.
/// - `CoachFeedbackBlock` (handles all 3 states internally — filled / loading / missing).
/// - `ActualVsPlannedTable` showing what the athlete actually did vs. what was planned.
/// - Optional `StravaRouteMapView` when the activity has a `summaryPolyline` (outdoor runs / rides).
/// - A bottom disclosure button revealing the original planned workout (`WorkoutShape`
///   + `WorkoutStepList`) without the rationale paragraph.
///
/// The disclosure is the only interactive element on the card. The card itself is **not**
/// tappable — same rule as `TodayPlannedCard`.
struct TodayCompletedCard: View {
    let session: PlanSession
    let activity: StravaActivity
    let template: WorkoutTemplate?
    let ftp: Int?
    let vma: Double?
    let css: Int?
    let maxHr: Int?
    let sequenceContext: (index: Int, total: Int)?

    @State private var showPlannedWorkout = false

    private let workoutLibrary = WorkoutLibraryService.shared

    // MARK: - Derived data

    private var segments: [FlatSegment] {
        workoutLibrary.flattenedSegments(
            for: session, ftp: ftp, vma: vma, css: css, maxHr: maxHr
        )
    }

    /// Sum of `distanceMeters` across all flattened segments. Returns `nil` when zero so
    /// `ActualVsPlannedTable` falls back to `—` (e.g. duration-only run/bike sessions where
    /// no segment carries an explicit distance — the "2k @5:30/km" cue-text case is out of
    /// scope; see DRO-231 QA notes).
    private var plannedDistanceMeters: Int? {
        let total = segments.compactMap { $0.distanceMeters }.reduce(0, +)
        return total > 0 ? total : nil
    }

    private var steps: [StepSummary] {
        workoutLibrary.stepSummaries(
            for: session, ftp: ftp, vma: vma, css: css, maxHr: maxHr
        )
    }

    /// `H:MM` actual duration derived from Strava's `movingTime`. Tabular-nums + matches
    /// the apostrophe glyph used elsewhere in Phase 1.
    private var formattedActualDuration: String {
        ActualVsPlannedTable.formatDuration(seconds: activity.movingTime)
    }

    /// Heuristic that tells `CoachFeedbackBlock` whether to render the silent skeleton.
    /// True iff: feedback is still nil AND the matcher has linked this activity to the
    /// session (so the edge function has been kicked off and a row is in flight).
    private var shouldExpectFeedback: Bool {
        session.feedback == nil && session.matchedActivityId == activity.id
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(spacing: 8) {
                Image(systemName: session.sportIcon)
                Text("\(session.displayName) - \(Self.formatTitleDuration(minutes: session.durationMinutes))")
            }
            .font(.title2)
            .fontWeight(.bold)
            .kerning(-0.4)
            .foregroundColor(.primary)

            CoachFeedbackBlock(
                feedback: session.feedback,
                isLoading: shouldExpectFeedback
            )

            ActualVsPlannedTable(
                session: session,
                activity: activity,
                plannedDistanceMeters: plannedDistanceMeters
            )

            if let polyline = activity.summaryPolyline, !polyline.isEmpty {
                mapBlock(polyline: polyline)
            }

            disclosureButton

            // TODO: WorkoutLibraryService.flattenedSegments/stepSummaries are not memoized.
            // For ≤30-segment workouts this is sub-ms; revisit if profiling shows render cost on disclosure toggle.
            if showPlannedWorkout {
                if !segments.isEmpty {
                    WorkoutShape(segments: segments)
                }
                if !steps.isEmpty {
                    Divider()
                    WorkoutStepList(steps: steps)
                }
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
            } else {
                CompletedTag()
            }
            // Spacer kept so the badge / sport·type stays left-aligned with no
            // right-side caption (Phase 2 dropped the actual-duration·sport caption —
            // the planned duration now lives in the title row inline next to the icon;
            // actual duration stays in `ActualVsPlannedTable`).
            Spacer(minLength: 8)
        }
    }

    /// Compact title-row duration. `60→"1h"`, `90→"1h30"`, `45→"45'"`, `120→"2h"`.
    /// Mirrors `HomeView.formatPillDuration` (DRO-242 Phase 1) so the inline duration
    /// next to the session icon matches the week-strip pills. Uses **planned**
    /// `session.durationMinutes` — the actual Strava duration stays in
    /// `ActualVsPlannedTable`.
    private static func formatTitleDuration(minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m == 0 ? "\(h)h" : "\(h)h\(m)"
        }
        return "\(minutes)'"
    }

    // MARK: - Map block

    /// Renders the route map with a small pill overlay (lower-left) summarising distance
    /// + total elevation gain. The overlay sits inside the rounded corners of the map so
    /// it reads as part of the same surface, not a banner above it.
    private func mapBlock(polyline: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            StravaRouteMapView(encodedPolyline: polyline)
            mapOverlay
                .padding(8)
        }
    }

    @ViewBuilder
    private var mapOverlay: some View {
        let distance = ActualVsPlannedTable.formatDistance(meters: activity.distance)
        let elevationText: String? = {
            guard let elev = activity.totalElevationGain, elev > 0 else { return nil }
            return "+\(Int(elev.rounded()))m"
        }()
        let parts = [distance, elevationText].compactMap { $0 }.filter { $0 != "—" }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        }
    }

    // MARK: - Disclosure

    private var disclosureButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showPlannedWorkout.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Text("View planned workout")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(showPlannedWorkout ? 90 : 0))
            }
            .foregroundColor(.accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showPlannedWorkout ? "Hide planned workout" : "View planned workout")
    }
}

// MARK: - Previews

private let _sampleSession = PlanSession(
    id: UUID(),
    weekId: UUID(),
    day: "Tuesday",
    sport: "run",
    type: "Intervals",
    templateId: "RUN_VO2_5x3",
    durationMinutes: 52,
    isBrick: false,
    notes: "VO2 max — keep recovery jogs honest.",
    orderInDay: 0,
    feedback: "Nailed the final two intervals — they were the same pace as the first. That's the fingerprint of a good VO2 day. Recovery jogs stayed honest. Easy spin tomorrow.",
    matchedActivityId: UUID()
)

/// A canonical Strava polyline — short loop around a city block, decodes cleanly.
/// Source: Google's documented sample at maps.googleapis.com.
private let _samplePolyline = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"

private func makeActivity(
    matchedTo session: PlanSession,
    polyline: String?,
    averageWatts: Double? = nil,
    distance: Double? = 10500,
    elevationGain: Double? = 80
) -> StravaActivity {
    StravaActivity(
        id: session.matchedActivityId ?? UUID(),
        userId: UUID(),
        stravaActivityId: 12345,
        sportType: session.sport.capitalized,
        normalizedSport: session.sport.lowercased(),
        name: "Morning session",
        startDate: Date(),
        startDateLocal: Date(),
        elapsedTime: 3120,
        movingTime: 3120,
        distance: distance,
        totalElevationGain: elevationGain,
        averageSpeed: 3.36,
        averageHeartrate: 162,
        averageWatts: averageWatts,
        isManual: false,
        summaryPolyline: polyline,
        createdAt: Date()
    )
}

#Preview("Completed — with map") {
    ScrollView {
        TodayCompletedCard(
            session: _sampleSession,
            activity: makeActivity(matchedTo: _sampleSession, polyline: _samplePolyline),
            template: nil,
            ftp: nil, vma: 17.0, css: nil, maxHr: 188,
            sequenceContext: nil
        )
        .padding(16)
    }
    .background(Color.pageSurface)
}

#Preview("Completed — no map (manual)") {
    ScrollView {
        TodayCompletedCard(
            session: _sampleSession,
            activity: makeActivity(matchedTo: _sampleSession, polyline: nil),
            template: nil,
            ftp: nil, vma: 17.0, css: nil, maxHr: 188,
            sequenceContext: nil
        )
        .padding(16)
    }
    .background(Color.pageSurface)
}

#Preview("Completed — feedback loading") {
    let loadingSession = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Tuesday",
        sport: "run",
        type: "Intervals",
        templateId: "RUN_VO2_5x3",
        durationMinutes: 52,
        isBrick: false,
        notes: nil,
        orderInDay: 0,
        feedback: nil,
        matchedActivityId: UUID()
    )
    return ScrollView {
        TodayCompletedCard(
            session: loadingSession,
            activity: makeActivity(matchedTo: loadingSession, polyline: _samplePolyline),
            template: nil,
            ftp: nil, vma: 17.0, css: nil, maxHr: 188,
            sequenceContext: nil
        )
        .padding(16)
    }
    .background(Color.pageSurface)
}

#Preview("Completed — feedback missing (skipped)") {
    // No matched activity → block returns EmptyView so the section silently disappears.
    let unmatched = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Tuesday",
        sport: "run",
        type: "Easy",
        templateId: "RUN_Easy_01",
        durationMinutes: 30,
        isBrick: false,
        notes: nil,
        orderInDay: 0,
        feedback: nil,
        matchedActivityId: nil
    )
    return ScrollView {
        TodayCompletedCard(
            session: unmatched,
            activity: makeActivity(matchedTo: unmatched, polyline: nil),
            template: nil,
            ftp: nil, vma: 17.0, css: nil, maxHr: 188,
            sequenceContext: nil
        )
        .padding(16)
    }
    .background(Color.pageSurface)
}

#Preview("Completed — swim (45' title duration)") {
    // Demonstrates the sub-60-minute formatter (`45 → "45'"`) and the swim sport icon
    // in the Phase 2 inline title row.
    let swimSession = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Tuesday",
        sport: "swim",
        type: "Easy",
        templateId: "SWIM_Easy_01",
        durationMinutes: 45,
        isBrick: false,
        notes: "Aerobic recovery swim — smooth catch.",
        orderInDay: 0,
        feedback: "Stroke rate held steady. Sighting drills paid off — heading was clean across the bay.",
        matchedActivityId: UUID()
    )
    return ScrollView {
        TodayCompletedCard(
            session: swimSession,
            activity: makeActivity(
                matchedTo: swimSession,
                polyline: nil,
                averageWatts: nil,
                distance: 2000,
                elevationGain: 0
            ),
            template: nil,
            ftp: nil, vma: nil, css: 95, maxHr: 188,
            sequenceContext: nil
        )
        .padding(16)
    }
    .background(Color.pageSurface)
}

#Preview("Completed — bike, no power data") {
    let bikeSession = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Sunday",
        sport: "bike",
        type: "Endurance",
        templateId: "BIKE_E_180",
        durationMinutes: 180,
        isBrick: false,
        notes: "Long Z2 — keep HR drift under 5%.",
        orderInDay: 0,
        feedback: "Solid endurance. HR was steady through hour 2 then crept up — fueling is the next lever. Try a gel every 45'.",
        matchedActivityId: UUID()
    )
    return ScrollView {
        TodayCompletedCard(
            session: bikeSession,
            activity: makeActivity(
                matchedTo: bikeSession,
                polyline: _samplePolyline,
                averageWatts: nil,
                distance: 75000,
                elevationGain: 850
            ),
            template: nil,
            ftp: 250, vma: nil, css: nil, maxHr: 188,
            sequenceContext: nil
        )
        .padding(16)
    }
    .background(Color.pageSurface)
}
