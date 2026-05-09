//
//  ActivityFormatters.swift
//  Dromos
//
//  Reusable formatting utilities for activity metrics (DRO-267 / DRO-263).
//  Stateless pure functions — no services, no caching, trivially unit-testable.
//
//  Mirrors the PaceMath.swift pattern. All formatters take non-optional values;
//  callers are responsible for nil-guarding (and zero-guarding for speed inputs)
//  before calling in. Pace formatters additionally self-guard `speedMps > 0` as a
//  safety net to prevent a division-by-zero crash on contract violation — the
//  call-site guard remains the canonical UX rule ("hide cells for invalid data"),
//  while the in-formatter guard is a defensive backstop, not a UX decision.
//
//  Output conventions:
//  - Duration:  `Hh MM'` when ≥ 1 h, `MM'` otherwise (apostrophe glyph, not "min")
//  - Distance:  `X.X km` (1 decimal) or `X km` (integer) near whole-km boundaries
//  - Run pace:  `M:SS/km`
//  - Swim pace: `M:SS/100m`
//  - Bike speed:`X.X km/h`
//  - Power:     `N W` (integer)
//  - Heart rate:`N bpm` (integer)
//

import Foundation

// MARK: - ActivityFormatters

/// Namespace for pure activity-metric formatting utilities.
///
/// All functions are stateless and have no side effects — they are safe to call
/// from any thread. No UIKit or SwiftUI dependency; usable in unit tests without
/// a simulator.
enum ActivityFormatters {

    // MARK: Duration

    /// Formats a moving-time duration in seconds as a compact time string.
    ///
    /// - Returns `"Hh MM'"` (e.g. `"1h 30'"`) when the duration is 1 hour or longer.
    /// - Returns `"MM'"` (e.g. `"52'"`) for durations under one hour.
    ///
    /// Sub-minute durations round down to `"0'"`. Seconds are intentionally discarded
    /// (whole-minute granularity is appropriate for training summaries).
    ///
    /// - Parameter seconds: Duration in seconds (non-negative integer).
    /// - Returns: Compact time string using the apostrophe glyph for minutes.
    static func formatDuration(seconds: Int) -> String {
        let totalMinutes = seconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return String(format: "%dh %02d'", hours, minutes)
        }
        return "\(minutes)'"
    }

    // MARK: Distance

    /// Formats a distance in meters as a human-readable kilometre string.
    ///
    /// Uses 1 decimal place by default. Near integer-km boundaries (fractional part
    /// < 0.05 or > 0.95) the value is rounded to the nearest integer and rendered
    /// without a decimal — so `970 m` becomes `"1 km"` and `1 050 m` becomes `"1 km"`.
    ///
    /// - Parameter meters: Distance in metres. Pass non-negative; behaviour for
    ///   negatives is undefined (Strava activities cannot have negative distance).
    ///   A `0` input returns `"0 km"` — callers should guard before calling if they
    ///   want the cell hidden entirely.
    /// - Returns: Formatted distance string, e.g. `"10.5 km"` or `"42 km"`.
    static func formatDistance(meters: Double) -> String {
        let km = meters / 1000.0
        let fractional = km.truncatingRemainder(dividingBy: 1)
        if fractional < 0.05 || fractional > 0.95 {
            return "\(Int(km.rounded())) km"
        }
        return String(format: "%.1f km", km)
    }

    // MARK: Distance — Compact

    /// Formats a distance in meters with a compact unit choice — meters under 1 km, km otherwise.
    ///
    /// Used by tooltips on per-lap displays where short segments (e.g., a 870m interval rep)
    /// read more naturally as `"870 m"` than `"0.9 km"`. For values >= 1000 m the formatter
    /// delegates to `formatDistance(meters:)` so the existing rounding rule applies unchanged.
    ///
    /// - Parameter meters: Distance in metres (non-negative).
    /// - Returns: e.g. `"0 m"`, `"870 m"`, `"999 m"`, `"1.7 km"`, `"11 km"`.
    static func formatDistanceCompact(meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        return formatDistance(meters: meters)
    }

    // MARK: Pace — Run

    /// Converts an average speed in m/s into a running pace string (`M:SS/km`).
    ///
    /// Rounds the total seconds-per-kilometre **before** decomposing into minutes and
    /// seconds. This avoids a truncation bug where `359.7 s/km` (≈ 6.0 m/s pace zone)
    /// would otherwise produce `"5:59/km"` → `"5:60/km"` or an incorrect `"6:00/km"`.
    ///
    /// - Parameter speedMps: Average speed in metres per second. Must be > 0;
    ///   passing `0` or negative returns `"0:00/km"` (callers should guard).
    /// - Returns: Pace string, e.g. `"5:00/km"` or `"4:30/km"`.
    static func formatPaceRunPerKm(speedMps: Double) -> String {
        guard speedMps > 0 else { return "0:00/km" }
        let secondsPerKm = 1000.0 / speedMps
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d/km", total / 60, total % 60)
    }

    // MARK: Pace — Swim

    /// Converts an average speed in m/s into a swim pace string (`M:SS/100m`).
    ///
    /// Applies the same round-then-decompose strategy as `formatPaceRunPerKm` to
    /// avoid boundary bugs at minute crossovers.
    ///
    /// - Parameter speedMps: Average speed in metres per second. Must be > 0;
    ///   passing `0` or negative returns `"0:00/100m"` (callers should guard).
    /// - Returns: Pace string, e.g. `"1:40/100m"`.
    static func formatPaceSwimPer100m(speedMps: Double) -> String {
        guard speedMps > 0 else { return "0:00/100m" }
        let secondsPer100m = 100.0 / speedMps
        let total = Int(secondsPer100m.rounded())
        return String(format: "%d:%02d/100m", total / 60, total % 60)
    }

    // MARK: Speed — Bike

    /// Converts an average speed in m/s into a km/h display string (`X.X km/h`).
    ///
    /// Always renders one decimal place for visual consistency in the metrics row.
    ///
    /// - Parameter speedMps: Average speed in metres per second.
    /// - Returns: Speed string, e.g. `"32.4 km/h"`.
    static func formatSpeedKmh(speedMps: Double) -> String {
        let kmh = speedMps * 3.6
        return String(format: "%.1f km/h", kmh)
    }

    // MARK: Power

    /// Formats an average power value as an integer-rounded wattage string.
    ///
    /// - Parameter watts: Power in watts.
    /// - Returns: Power string, e.g. `"215 W"`.
    static func formatPower(watts: Double) -> String {
        return String(format: "%d W", Int(watts.rounded()))
    }

    // MARK: Heart Rate

    /// Formats an average heart rate as an integer-rounded bpm string.
    ///
    /// - Parameter bpm: Heart rate in beats per minute.
    /// - Returns: HR string, e.g. `"152 bpm"`.
    static func formatHR(bpm: Double) -> String {
        return String(format: "%d bpm", Int(bpm.rounded()))
    }
}
