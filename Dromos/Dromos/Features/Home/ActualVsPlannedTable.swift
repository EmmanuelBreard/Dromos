//
//  ActualVsPlannedTable.swift
//  Dromos
//
//  Created by Emmanuel Breard on 26/04/2026.
//

import SwiftUI

/// 3-column table (Metric / Actual / Planned) shown inside `TodayCompletedCard`.
///
/// Sport-aware: the rows surfaced depend on `session.sport` so we don't show meaningless
/// rows (e.g. "avg power" for a run, "avg pace" for a strength). Bike's `Avg power` row
/// is omitted entirely when the activity has no power data — common for outdoor rides on a
/// non-power-meter bike.
///
/// Visual: borderless 3-column grid using SwiftUI `Grid` (iOS 16+). A header row + data
/// rows separated by 0.5pt hairlines (`Divider()`). All numbers use tabular monospaced
/// digits so rows align cleanly even on narrow widths.
struct ActualVsPlannedTable: View {
    let session: PlanSession
    let activity: StravaActivity
    /// Total planned distance (meters), summed by the caller from the workout's flattened
    /// segments. `nil` (or `0`) → render `—` in the Planned column. Non-nil and > 0 →
    /// formatted via `formatDistance(meters:)` for visual parity with the Actual column.
    /// Lifted to the call site (rather than recomputing here) so this view stays a pure
    /// renderer with no dependency on `WorkoutLibraryService`.
    var plannedDistanceMeters: Int? = nil

    // MARK: - Body

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            // Header
            GridRow {
                headerCell("METRIC")
                headerCell("ACTUAL", alignment: .trailing)
                headerCell("PLANNED", alignment: .trailing)
            }

            ForEach(rows) { row in
                Divider().gridCellColumns(3)
                GridRow {
                    Text(row.metric)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(row.actual)
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(row.planned)
                        .font(.body)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Header cell

    private func headerCell(_ text: String, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .tracking(1)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    // MARK: - Row construction

    /// A single rendered row in the table.
    /// `id` derives from `metric` (unique within each sport branch's row set) so SwiftUI's `ForEach`
    /// sees stable identities across re-renders — `rows` is a computed property invoked per body eval,
    /// so a `UUID()` here would regenerate every render and break diffing.
    private struct Row: Identifiable {
        var id: String { metric }
        let metric: String
        let actual: String
        let planned: String
    }

    /// Renders the Planned column for the Distance row.
    /// Mirrors the Actual column's `formatDistance` so a 2400m planned swim and a 2400m
    /// completed swim render identically (`2.4 km`). Falls back to `—` when no planned
    /// distance is available (e.g. duration-only run/bike workouts).
    private var plannedDistanceCell: String {
        guard let meters = plannedDistanceMeters, meters > 0 else { return "—" }
        return Self.formatDistance(meters: Double(meters))
    }

    /// Sport-aware row builders. Each branch decides which rows to surface and in what
    /// order. Bike skips the `Avg power` row when `averageWatts` is nil (no power meter).
    private var rows: [Row] {
        switch session.sport.lowercased() {
        case "run":
            return [
                Row(
                    metric: "Duration",
                    actual: Self.formatDuration(seconds: activity.movingTime),
                    planned: Self.formatPlannedDuration(minutes: session.durationMinutes)
                ),
                Row(
                    metric: "Distance",
                    actual: Self.formatDistance(meters: activity.distance),
                    planned: plannedDistanceCell
                ),
                Row(
                    metric: "Avg pace",
                    actual: Self.formatPacePerKm(speedMps: activity.averageSpeed),
                    planned: "—"
                ),
                Row(
                    metric: "HR avg",
                    actual: Self.formatHR(activity.averageHeartrate),
                    planned: "—"
                )
            ]
        case "bike":
            var out: [Row] = [
                Row(
                    metric: "Duration",
                    actual: Self.formatDuration(seconds: activity.movingTime),
                    planned: Self.formatPlannedDuration(minutes: session.durationMinutes)
                )
            ]
            if let watts = activity.averageWatts {
                out.append(Row(
                    metric: "Avg power",
                    actual: "\(Int(watts.rounded())) W",
                    planned: "—"
                ))
            }
            out.append(Row(
                metric: "Distance",
                actual: Self.formatDistance(meters: activity.distance),
                planned: plannedDistanceCell
            ))
            out.append(Row(
                metric: "HR avg",
                actual: Self.formatHR(activity.averageHeartrate),
                planned: "—"
            ))
            return out
        case "swim":
            return [
                Row(
                    metric: "Duration",
                    actual: Self.formatDuration(seconds: activity.movingTime),
                    planned: Self.formatPlannedDuration(minutes: session.durationMinutes)
                ),
                Row(
                    metric: "Distance",
                    actual: Self.formatDistance(meters: activity.distance),
                    planned: plannedDistanceCell
                ),
                Row(
                    metric: "Avg pace",
                    actual: Self.formatPacePer100m(speedMps: activity.averageSpeed),
                    planned: "—"
                ),
                Row(
                    metric: "Avg HR",
                    actual: Self.formatHR(activity.averageHeartrate),
                    planned: "—"
                )
            ]
        default:
            return [
                Row(
                    metric: "Duration",
                    actual: Self.formatDuration(seconds: activity.movingTime),
                    planned: Self.formatPlannedDuration(minutes: session.durationMinutes)
                )
            ]
        }
    }

    // MARK: - Format helpers
    // Static so they're easy to unit-test if we ever pull them out — they have no
    // dependency on view state.
    //
    // TODO(DRO-240): Consolidate with ActualMetricsView formatters into Core/Formatting/ActivityFormatters.swift.
    // Two surfaces currently maintain near-identical helpers with subtly different output strings.

    /// Formats moving time as `Hh MM'` when ≥ 1 hour, `MM'` otherwise. Always uses
    /// the apostrophe time-glyph for consistency with the Phase 1 step list.
    static func formatDuration(seconds: Int) -> String {
        let totalMinutes = seconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return String(format: "%dh %02d'", hours, minutes)
        }
        return "\(minutes)'"
    }

    /// Formats the planned duration (already in minutes) using the same glyph rules.
    static func formatPlannedDuration(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return String(format: "%dh %02d'", hours, mins)
        }
        return "\(mins)'"
    }

    /// Formats distance in meters as `X.X km` (1 decimal) or `X km` for clean integers.
    /// Returns `"—"` when nil (e.g. manual activities with no distance).
    static func formatDistance(meters: Double?) -> String {
        guard let meters = meters, meters > 0 else { return "—" }
        let km = meters / 1000.0
        if km.truncatingRemainder(dividingBy: 1) < 0.05 || km.truncatingRemainder(dividingBy: 1) > 0.95 {
            return "\(Int(km.rounded())) km"
        }
        return String(format: "%.1f km", km)
    }

    /// Converts an average speed in m/s into a `M:SS/km` pace string for run.
    /// Rounds total seconds first, then decomposes — avoids the boundary bug where
    /// truncated minutes + rounded seconds produce e.g. `5:00/km` for 359.7 s.
    static func formatPacePerKm(speedMps: Double?) -> String {
        guard let mps = speedMps, mps > 0 else { return "—" }
        let secondsPerKm = 1000.0 / mps
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d/km", total / 60, total % 60)
    }

    /// Converts an average speed in m/s into a `M:SS/100m` pace string for swim.
    /// Rounds total seconds first, then decomposes — avoids the boundary bug where
    /// truncated minutes + rounded seconds produce e.g. `5:00/100m` for 359.7 s.
    static func formatPacePer100m(speedMps: Double?) -> String {
        guard let mps = speedMps, mps > 0 else { return "—" }
        let secondsPer100 = 100.0 / mps
        let total = Int(secondsPer100.rounded())
        return String(format: "%d:%02d/100m", total / 60, total % 60)
    }

    /// Formats average heart rate. Returns `"—"` when nil (manual entry, no HR strap).
    static func formatHR(_ hr: Double?) -> String {
        guard let hr = hr, hr > 0 else { return "—" }
        return "\(Int(hr.rounded())) bpm"
    }
}

// MARK: - Previews

private let _runSession = PlanSession(
    id: UUID(), weekId: UUID(), day: "Tuesday",
    sport: "run", type: "Intervals",
    templateId: "RUN_VO2_5x3", durationMinutes: 52,
    isBrick: false, notes: nil, orderInDay: 0,
    feedback: nil, matchedActivityId: nil
)

private let _runActivity = StravaActivity(
    id: UUID(), userId: UUID(), stravaActivityId: 1,
    sportType: "Run", normalizedSport: "run",
    name: "Morning run", startDate: Date(), startDateLocal: Date(),
    elapsedTime: 3120, movingTime: 3120,
    distance: 10500, totalElevationGain: 80,
    averageSpeed: 3.36, averageHeartrate: 162,
    averageWatts: nil, isManual: false,
    summaryPolyline: nil, createdAt: Date()
)

private let _bikeSession = PlanSession(
    id: UUID(), weekId: UUID(), day: "Sunday",
    sport: "bike", type: "Endurance",
    templateId: "BIKE_E_180", durationMinutes: 180,
    isBrick: false, notes: nil, orderInDay: 0,
    feedback: nil, matchedActivityId: nil
)

private let _bikeActivityWithPower = StravaActivity(
    id: UUID(), userId: UUID(), stravaActivityId: 2,
    sportType: "Ride", normalizedSport: "bike",
    name: "Long ride", startDate: Date(), startDateLocal: Date(),
    elapsedTime: 11400, movingTime: 11000,
    distance: 75000, totalElevationGain: 850,
    averageSpeed: 6.8, averageHeartrate: 138,
    averageWatts: 196, isManual: false,
    summaryPolyline: nil, createdAt: Date()
)

private let _bikeActivityNoPower = StravaActivity(
    id: UUID(), userId: UUID(), stravaActivityId: 3,
    sportType: "Ride", normalizedSport: "bike",
    name: "Casual ride", startDate: Date(), startDateLocal: Date(),
    elapsedTime: 4200, movingTime: 4100,
    distance: 28000, totalElevationGain: 200,
    averageSpeed: 6.8, averageHeartrate: 132,
    averageWatts: nil, isManual: false,
    summaryPolyline: nil, createdAt: Date()
)

private let _swimSession = PlanSession(
    id: UUID(), weekId: UUID(), day: "Wednesday",
    sport: "swim", type: "Easy",
    templateId: "SWIM_Easy_01", durationMinutes: 45,
    isBrick: false, notes: nil, orderInDay: 0,
    feedback: nil, matchedActivityId: nil
)

private let _swimActivity = StravaActivity(
    id: UUID(), userId: UUID(), stravaActivityId: 4,
    sportType: "Swim", normalizedSport: "swim",
    name: "Pool swim", startDate: Date(), startDateLocal: Date(),
    elapsedTime: 2700, movingTime: 2400,
    distance: 2000, totalElevationGain: nil,
    averageSpeed: 0.83, averageHeartrate: 130,
    averageWatts: nil, isManual: false,
    summaryPolyline: nil, createdAt: Date()
)

#Preview("Run") {
    ActualVsPlannedTable(session: _runSession, activity: _runActivity)
        .padding(16)
        .background(Color.cardSurface)
        .padding()
        .background(Color.pageSurface)
}

#Preview("Bike — with power") {
    ActualVsPlannedTable(session: _bikeSession, activity: _bikeActivityWithPower)
        .padding(16)
        .background(Color.cardSurface)
        .padding()
        .background(Color.pageSurface)
}

#Preview("Bike — no power data") {
    ActualVsPlannedTable(session: _bikeSession, activity: _bikeActivityNoPower)
        .padding(16)
        .background(Color.cardSurface)
        .padding()
        .background(Color.pageSurface)
}

#Preview("Swim — with planned distance") {
    // 2400m = 400 WU + 8×100 + 4×200 + 400 CD (Monday tempo swim from QA bug repro).
    ActualVsPlannedTable(
        session: _swimSession,
        activity: _swimActivity,
        plannedDistanceMeters: 2400
    )
    .padding(16)
    .background(Color.cardSurface)
    .padding()
    .background(Color.pageSurface)
}

#Preview("Swim — no planned distance (fallback)") {
    ActualVsPlannedTable(session: _swimSession, activity: _swimActivity)
        .padding(16)
        .background(Color.cardSurface)
        .padding()
        .background(Color.pageSurface)
}
