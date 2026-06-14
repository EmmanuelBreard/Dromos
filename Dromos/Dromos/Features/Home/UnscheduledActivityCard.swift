//
//  UnscheduledActivityCard.swift
//  Dromos
//
//  Created by Mamma Aiuto Gang on 14/06/2026.
//  DRO-307: card for Strava activities with no backing PlanSession.
//

import SwiftUI

/// Today tab — card for a completed Strava activity that has no matching `PlanSession`.
///
/// Composes:
/// - `UnscheduledTag` (or `SessionSequenceBadge` on multi-session days) at the top.
/// - A title row: sport icon + `activity.displayName` + compact moving-time duration.
/// - `ActualMetricsView` — sport-adaptive metric grid, hides nil cells.
/// - Optional `CompletedSegmentGraphView` when ≥ 2 laps are available (fetched asynchronously).
/// - Optional `StravaRouteMapView` with a distance/elevation overlay when `summaryPolyline != nil`.
///
/// No `CoachFeedbackBlock`, no planned-workout disclosure, no `PlanSession` references.
/// Degrades gracefully for manual entries (no polyline, no laps) — tag + title + metrics only.
struct UnscheduledActivityCard: View {
    let activity: StravaActivity
    let ftp: Int?
    let vma: Double?
    let css: Int?
    let maxHr: Int?
    /// When non-nil the `SessionSequenceBadge` replaces `UnscheduledTag` to signal
    /// position within a multi-activity day (mirrors `TodayCompletedCard` behavior).
    let sequenceContext: (index: Int, total: Int)?

    /// Strava lap data for the activity, fetched asynchronously via `.task(id: activity.id)`.
    /// Empty until the fetch resolves; empty on error — StravaService swallows errors defensively.
    @State private var laps: [StravaLap] = []

    /// Owned by this view — `fetchLaps` is a stateless read query; no shared ownership needed.
    @StateObject private var stravaService = StravaService()

    // MARK: - Derived

    /// Whether to render the segment graph after `ActualMetricsView`.
    /// Hidden when fewer than 2 laps — guards against single-lap / not-yet-fetched state.
    private var shouldShowSegmentGraph: Bool {
        laps.count >= 2
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(spacing: 8) {
                Image(systemName: activity.sportIcon)
                Text("\(activity.displayName) - \(ActivityFormatters.formatDuration(seconds: activity.movingTime))")
            }
            .font(.title2)
            .fontWeight(.bold)
            .kerning(-0.4)
            .foregroundColor(.primary)

            ActualMetricsView(activity: activity)

            // Segment graph — rendered only when ≥ 2 laps are available.
            // Laps arrive asynchronously; the graph is simply absent while the array is empty.
            if shouldShowSegmentGraph {
                CompletedSegmentGraphView(
                    laps: laps,
                    sport: activity.normalizedSport ?? "run",
                    vma: vma,
                    ftp: ftp,
                    css: css,
                    maxHr: maxHr
                )
            }

            if let polyline = activity.summaryPolyline, !polyline.isEmpty {
                mapBlock(polyline: polyline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.cardSurface)
        )
        // Re-fires whenever the activity changes (e.g. day swipe updates the card).
        // fetchLaps returns [] on error — no error UI needed at this layer per DRO-275 spec.
        .task(id: activity.id) {
            laps = await stravaService.fetchLaps(activityId: activity.id)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            if let ctx = sequenceContext {
                SessionSequenceBadge(index: ctx.index)
                Text("Unscheduled · \(activity.normalizedSport?.capitalized ?? "Activity")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                UnscheduledTag()
            }
            Spacer(minLength: 8)
        }
    }

    // MARK: - Map block

    /// Renders the route map with a small pill overlay (lower-left) summarising distance
    /// + total elevation gain. Mirrors the layout used by `TodayCompletedCard.mapBlock`.
    private func mapBlock(polyline: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            StravaRouteMapView(encodedPolyline: polyline)
            mapOverlay
                .padding(8)
        }
    }

    @ViewBuilder
    private var mapOverlay: some View {
        let distance = activity.distance.map { ActivityFormatters.formatDistance(meters: $0) } ?? "—"
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
}

// MARK: - Previews

/// Canonical encoded polyline — a short city-block loop, decodes cleanly.
private let _previewPolyline = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"

private func makeUnscheduledActivity(
    sport: String,
    polyline: String? = nil,
    distance: Double? = 10_500,
    elevationGain: Double? = 80,
    averageSpeed: Double? = 3.36,
    averageHeartrate: Double? = 162,
    isManual: Bool = false
) -> StravaActivity {
    StravaActivity(
        id: UUID(),
        userId: UUID(),
        stravaActivityId: 99001,
        sportType: sport.capitalized,
        normalizedSport: sport.lowercased(),
        name: isManual ? nil : "Morning \(sport.capitalized)",
        startDate: Date(),
        startDateLocal: Date(),
        elapsedTime: 3600,
        movingTime: 3240,
        distance: distance,
        totalElevationGain: elevationGain,
        averageSpeed: averageSpeed,
        averageHeartrate: averageHeartrate,
        averageWatts: nil,
        isManual: isManual,
        summaryPolyline: polyline,
        createdAt: Date()
    )
}

/// (a) GPS outdoor run — full card: UnscheduledTag + title + metrics + segment graph + map.
/// Laps are stubbed externally; in real use they arrive asynchronously from StravaService.
#Preview("Unscheduled — GPS run (full card)") {
    ScrollView {
        UnscheduledActivityCard(
            activity: makeUnscheduledActivity(
                sport: "run",
                polyline: _previewPolyline,
                distance: 12_300,
                elevationGain: 95,
                averageSpeed: 3.5
            ),
            ftp: nil,
            vma: 17.0,
            css: nil,
            maxHr: 188,
            sequenceContext: nil
        )
        .padding(16)
    }
    .background(Color.pageSurface)
}

/// (b) Manual entry — degrades to tag + title + metrics only (no polyline, no laps).
#Preview("Unscheduled — manual run (degraded)") {
    ScrollView {
        UnscheduledActivityCard(
            activity: makeUnscheduledActivity(
                sport: "run",
                polyline: nil,
                distance: 8_000,
                elevationGain: nil,
                averageSpeed: 3.2,
                averageHeartrate: 155,
                isManual: true
            ),
            ftp: nil,
            vma: 17.0,
            css: nil,
            maxHr: 188,
            sequenceContext: nil
        )
        .padding(16)
    }
    .background(Color.pageSurface)
}

/// (c) Swim — no polyline (pool sessions are always indoor), metrics use /100m pace.
#Preview("Unscheduled — swim") {
    ScrollView {
        UnscheduledActivityCard(
            activity: makeUnscheduledActivity(
                sport: "swim",
                polyline: nil,
                distance: 2_500,
                elevationGain: nil,
                averageSpeed: 100.0 / 95.0,   // ≈ 1:35/100m
                averageHeartrate: 148
            ),
            ftp: nil,
            vma: nil,
            css: 90,
            maxHr: 188,
            sequenceContext: nil
        )
        .padding(16)
    }
    .background(Color.pageSurface)
}
