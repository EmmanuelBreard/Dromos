//
//  PaceMath.swift
//  Dromos
//
//  Pure math utilities for the pace calculator feature (DRO-262 / DRO-264).
//  Stateless functions — no services, no caching, trivially unit-testable.
//

import Foundation

// MARK: - Discipline

/// The three triathlon disciplines supported by the pace calculator.
enum Discipline: String, CaseIterable {
    case run
    case bike
    case swim
}

// MARK: - Distance Entry

/// A named race-distance entry used in the finish-times section.
struct DistanceEntry: Identifiable {
    /// Human-readable name (e.g. "Half marathon", "90 km · Half-Iron").
    let name: String
    /// Distance in kilometres used for time calculations.
    let km: Double

    // Synthesised `id` keeps SwiftUI ForEach happy without making the struct Hashable.
    var id: String { name }
}

// MARK: - DisciplineConfig

/// All per-sport UI and math constants for a single discipline.
struct DisciplineConfig {
    // MARK: Slider bounds

    /// Minimum slider integer value.
    let lowerBound: Int
    /// Maximum slider integer value.
    let upperBound: Int
    /// Slider step size.
    let step: Int
    /// Default slider value shown when no seed is provided.
    let defaultValue: Int

    // MARK: Label strings

    /// Short label above the major display value (e.g. "SPEED").
    let inputLabel: String
    /// Unit for the major display value (e.g. "km/h").
    let unit: String
    /// Short label above the secondary display value (e.g. "PACE").
    let secondaryLabel: String
    /// Unit for the secondary display value (e.g. "/ km").
    let secondaryUnit: String

    // MARK: Finish-time distances

    /// Ordered list of race distances shown in the finish-times section.
    let distances: [DistanceEntry]
}

// MARK: - Discipline.config

extension Discipline {
    /// Returns the full UI + math configuration for this discipline.
    var config: DisciplineConfig {
        switch self {
        case .run:
            return DisciplineConfig(
                lowerBound: 60,
                upperBound: 220,
                step: 1,
                defaultValue: 120,
                inputLabel: "SPEED",
                unit: "km/h",
                secondaryLabel: "PACE",
                secondaryUnit: "/ km",
                distances: [
                    DistanceEntry(name: "1 km",            km: 1.0),
                    DistanceEntry(name: "10 km",           km: 10.0),
                    DistanceEntry(name: "Half marathon",   km: 21.0975),
                    DistanceEntry(name: "Marathon",        km: 42.195),
                ]
            )

        case .bike:
            return DisciplineConfig(
                lowerBound: 150,
                upperBound: 500,
                step: 5,
                defaultValue: 320,
                inputLabel: "SPEED",
                unit: "km/h",
                secondaryLabel: "PACE",
                secondaryUnit: "/ km",
                distances: [
                    DistanceEntry(name: "1 km",              km: 1.0),
                    DistanceEntry(name: "40 km · Olympic",   km: 40.0),
                    DistanceEntry(name: "90 km · Half-Iron", km: 90.0),
                ]
            )

        case .swim:
            return DisciplineConfig(
                lowerBound: 60,
                upperBound: 180,
                step: 1,
                defaultValue: 110,
                inputLabel: "PACE",
                unit: "/ 100m",
                secondaryLabel: "SPEED",
                secondaryUnit: "km/h",
                distances: [
                    DistanceEntry(name: "1500 m · Olympic",   km: 1.5),
                    DistanceEntry(name: "1900 m · Half-Iron", km: 1.9),
                ]
            )
        }
    }

    /// Display name shown in the sheet title.
    var displayName: String {
        switch self {
        case .run:  return "Running"
        case .bike: return "Cycling"
        case .swim: return "Swimming"
        }
    }
}

// MARK: - PaceMath

/// Namespace for pure pace/speed conversion and formatting utilities.
enum PaceMath {

    /// Converts a slider integer value to a speed in km/h.
    ///
    /// - For `.run` and `.bike` the slider stores speed × 10 (e.g. 120 → 12.0 km/h).
    /// - For `.swim` the slider stores the CSS pace in seconds per 100 m; this is
    ///   converted to a speed using the formula: speed = 360 / pace_sec_per_100m.
    ///
    /// - Parameters:
    ///   - v: Integer slider value.
    ///   - discipline: The active discipline.
    /// - Returns: Speed in km/h.
    static func kmH(forSliderValue v: Int, discipline: Discipline) -> Double {
        switch discipline {
        case .run, .bike:
            return Double(v) / 10.0
        case .swim:
            guard v > 0 else { return 0 }
            return 360.0 / Double(v)
        }
    }

    /// Calculates the time in seconds required to cover a given distance at a given speed.
    ///
    /// - Parameters:
    ///   - km: Distance in kilometres.
    ///   - speedKmH: Speed in km/h. Must be > 0; passing 0 returns 0.
    /// - Returns: `TimeInterval` (seconds).
    static func secondsToCover(km: Double, atSpeedKmH speedKmH: Double) -> TimeInterval {
        guard speedKmH > 0 else { return 0 }
        return (km / speedKmH) * 3600.0
    }

    /// Formats a `TimeInterval` (seconds) as a human-readable finish time.
    ///
    /// - Returns `"H:MM:SS"` when the duration is 1 hour or longer.
    /// - Returns `"M:SS"` for durations under one hour.
    ///
    /// Seconds are rounded to the nearest integer before formatting.
    ///
    /// - Parameter seconds: Duration in seconds.
    /// - Returns: Formatted time string.
    static func formatTime(_ seconds: TimeInterval) -> String {
        let rounded = Int(seconds.rounded())
        let h = rounded / 3600
        let m = (rounded % 3600) / 60
        let s = rounded % 60

        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    /// Formats a pace expressed as seconds-per-kilometre into a readable `"M:SS"` string.
    ///
    /// The unit (`/ km`) is intentionally omitted — it is rendered separately
    /// as `config.secondaryUnit` in the view for uniform layout across disciplines.
    ///
    /// - Parameter secondsPerKm: Pace in seconds per kilometre.
    /// - Returns: Formatted pace string, e.g. `"5:00"`.
    static func formatPacePerKm(secondsPerKm: TimeInterval) -> String {
        let rounded = Int(secondsPerKm.rounded())
        let m = rounded / 60
        let s = rounded % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Formats a swim pace expressed as seconds per 100 m into a readable `"M:SS"` string.
    ///
    /// The unit (`/ 100m`) is intentionally omitted — it is rendered separately
    /// as `config.unit` in the view for uniform layout across disciplines.
    ///
    /// - Parameter secondsPer100m: Pace in seconds per 100 m.
    /// - Returns: Formatted pace string, e.g. `"1:50"`.
    static func formatPacePer100m(secondsPer100m: TimeInterval) -> String {
        let totalSec = Int(secondsPer100m.rounded())
        return String(format: "%d:%02d", totalSec / 60, totalSec % 60)
    }
}
