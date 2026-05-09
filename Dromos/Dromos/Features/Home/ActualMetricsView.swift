//
//  ActualMetricsView.swift
//  Dromos
//
//  Created by Mamma Aiuto Gang on 22/02/2026.
//
//  DRO-268: adaptive grid, .title3 typography, ActivityFormatters delegation.
//

import SwiftUI

/// Compact adaptive metric grid showing actual Strava performance data for a completed session.
/// Displays sport-specific metrics (duration, distance, pace, power, HR) derived from the matched activity.
/// Nil metrics are omitted entirely — the grid collapses gracefully to avoid empty cells.
///
/// Layout: `GridItem(.adaptive(minimum: 90))` so the grid handles 4-cell (Run/Swim, Bike-no-power)
/// and 5-cell (Bike-with-power) cases without conditional layouts.
struct ActualMetricsView: View {

    let activity: StravaActivity

    // MARK: - Metric Cell Model

    /// A single labeled metric cell for the grid.
    private struct MetricCell: Identifiable {
        var id: String { label }
        let label: String
        let value: String
    }

    // MARK: - Computed Metrics

    /// Builds the ordered list of metric cells appropriate for this activity's sport.
    ///
    /// Ordering per spec:
    /// - Run / Swim: Duration → Distance → Avg Pace → Avg HR
    /// - Bike (with power): Duration → Distance → Avg Power → Avg HR → Avg Speed
    /// - Bike (no power):   Duration → Distance → Avg HR → Avg Speed
    ///
    /// Common metrics (duration, distance) always appear first, followed by sport-specific ones.
    /// All formatting is delegated to `ActivityFormatters`; callers nil-guard before appending.
    private var cells: [MetricCell] {
        var result: [MetricCell] = []

        // Duration — always present (movingTime is non-optional)
        result.append(MetricCell(
            label: "Duration",
            value: ActivityFormatters.formatDuration(seconds: activity.movingTime)
        ))

        // Distance — present when available
        if let distanceMeters = activity.distance {
            result.append(MetricCell(
                label: "Distance",
                value: ActivityFormatters.formatDistance(meters: distanceMeters)
            ))
        }

        // Sport-specific metrics
        switch activity.normalizedSport?.lowercased() {

        case "bike":
            // Average Power (W) — only when power data is present
            if let watts = activity.averageWatts {
                result.append(MetricCell(
                    label: "Avg Power",
                    value: ActivityFormatters.formatPower(watts: watts)
                ))
            }
            // Average Heart Rate (bpm)
            if let hr = activity.averageHeartrate {
                result.append(MetricCell(
                    label: "Avg HR",
                    value: ActivityFormatters.formatHR(bpm: hr)
                ))
            }
            // Average Speed (km/h) — converted from m/s
            if let speedMs = activity.averageSpeed, speedMs > 0 {
                result.append(MetricCell(
                    label: "Avg Speed",
                    value: ActivityFormatters.formatSpeedKmh(speedMps: speedMs)
                ))
            }

        case "run":
            // Average Pace (/km) — converted from m/s to min:sec per km
            if let speedMs = activity.averageSpeed, speedMs > 0 {
                result.append(MetricCell(
                    label: "Avg Pace",
                    value: ActivityFormatters.formatPaceRunPerKm(speedMps: speedMs)
                ))
            }
            // Average Heart Rate (bpm)
            if let hr = activity.averageHeartrate {
                result.append(MetricCell(
                    label: "Avg HR",
                    value: ActivityFormatters.formatHR(bpm: hr)
                ))
            }

        case "swim":
            // Average Pace (/100m) — converted from m/s to min:sec per 100m
            if let speedMs = activity.averageSpeed, speedMs > 0 {
                result.append(MetricCell(
                    label: "Avg Pace",
                    value: ActivityFormatters.formatPaceSwimPer100m(speedMps: speedMs)
                ))
            }
            // Average Heart Rate (bpm)
            if let hr = activity.averageHeartrate {
                result.append(MetricCell(
                    label: "Avg HR",
                    value: ActivityFormatters.formatHR(bpm: hr)
                ))
            }

        default:
            // Unknown sport: no sport-specific cells, only common metrics above
            break
        }

        return result
    }

    // MARK: - Body

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 90))],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(cells) { cell in
                VStack(alignment: .leading, spacing: 2) {
                    Text(cell.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(cell.value)
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
            }
        }
    }
}
