//
//  ActualMetricsView.swift
//  Dromos
//
//  Created by Mamma Aiuto Gang on 22/02/2026.
//

import SwiftUI

/// Compact 2-column metric grid showing actual Strava performance data for a completed session.
/// Displays sport-specific metrics (duration, distance, pace, power, HR) derived from the matched activity.
/// Nil metrics are omitted entirely — the grid collapses gracefully to avoid empty cells.
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
    /// Common metrics (duration, distance) always appear first, followed by sport-specific ones.
    private var cells: [MetricCell] {
        var result: [MetricCell] = []

        // Duration — always present (movingTime is non-optional)
        result.append(MetricCell(label: "Duration", value: formatDuration(activity.movingTime)))

        // Distance — present when available
        if let distanceMeters = activity.distance {
            result.append(MetricCell(label: "Distance", value: formatDistance(distanceMeters)))
        }

        // Sport-specific metrics
        switch activity.normalizedSport?.lowercased() {

        case "bike":
            // Average Power (W)
            if let watts = activity.averageWatts {
                result.append(MetricCell(label: "Avg Power", value: "\(Int(watts)) W"))
            }
            // Average Heart Rate (bpm)
            if let hr = activity.averageHeartrate {
                result.append(MetricCell(label: "Avg HR", value: "\(Int(hr)) bpm"))
            }
            // Average Speed (km/h) — converted from m/s
            if let speedMs = activity.averageSpeed, speedMs > 0 {
                let kmh = speedMs * 3.6
                result.append(MetricCell(label: "Avg Speed", value: String(format: "%.1f km/h", kmh)))
            }

        case "run":
            // Average Pace (/km) — converted from m/s to min:sec per km
            if let speedMs = activity.averageSpeed, speedMs > 0 {
                result.append(MetricCell(label: "Avg Pace", value: formatRunPace(speedMs: speedMs)))
            }
            // Average Heart Rate (bpm)
            if let hr = activity.averageHeartrate {
                result.append(MetricCell(label: "Avg HR", value: "\(Int(hr)) bpm"))
            }

        case "swim":
            // Average Pace (/100m) — converted from m/s to min:sec per 100m
            if let speedMs = activity.averageSpeed, speedMs > 0 {
                result.append(MetricCell(label: "Avg Pace", value: formatSwimPace(speedMs: speedMs)))
            }
            // Average Heart Rate (bpm)
            if let hr = activity.averageHeartrate {
                result.append(MetricCell(label: "Avg HR", value: "\(Int(hr)) bpm"))
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
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(cells) { cell in
                VStack(alignment: .leading, spacing: 2) {
                    Text(cell.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(cell.value)
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
            }
        }
    }

    // MARK: - Formatting Helpers

    /// Formats a duration in seconds into a human-readable string.
    /// Examples: "<1 min", "45 min", "1h 30min", "2h 5min"
    private func formatDuration(_ seconds: Int) -> String {
        let totalMinutes = seconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)min" : "\(hours)h"
        } else if totalMinutes > 0 {
            return "\(totalMinutes) min"
        } else {
            return "<1 min"
        }
    }

    /// Formats a distance in meters.
    /// Uses km for distances >= 1000m, meters otherwise.
    /// Examples: "42.2 km", "800 m"
    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        } else {
            return "\(Int(meters)) m"
        }
    }

    /// Formats a speed in m/s as a running pace (min:sec per km).
    /// Example: 3.33 m/s → "5:00 /km"
    private func formatRunPace(speedMs: Double) -> String {
        let secondsPerKm = 1000.0 / speedMs
        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    /// Formats a speed in m/s as a swim pace (min:sec per 100m).
    /// Example: 1.5 m/s → "1:06 /100m"
    private func formatSwimPace(speedMs: Double) -> String {
        let secondsPer100m = 100.0 / speedMs
        let minutes = Int(secondsPer100m) / 60
        let seconds = Int(secondsPer100m) % 60
        return String(format: "%d:%02d /100m", minutes, seconds)
    }
}
