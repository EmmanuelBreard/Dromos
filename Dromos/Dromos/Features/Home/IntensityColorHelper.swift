//
//  IntensityColorHelper.swift
//  Dromos
//
//  Created by Emmanuel Breard on 14/02/2026.
//

import SwiftUI

// FIX #6: Refactor to Color extension per codebase convention
extension Color {
    /// Shared intensity color function for workout step dots and graph bars.
    /// Maps intensity percentage to a color gradient from green (easy) to red (max effort).
    ///
    /// Color mapping:
    /// - Green (hue ~0.33): warmup/cooldown/easy ≤65%
    /// - Yellow-green (hue ~0.22): moderate ~70-80%
    /// - Orange (hue ~0.08): tempo/threshold ~85-95%
    /// - Red (hue ~0.0): max effort ≥100%
    /// - Recovery segments: always green regardless of intensity
    /// - nil intensity: default to green
    ///
    /// - Parameters:
    ///   - pct: Intensity percentage (e.g., FTP% for bike, MAS% for run)
    ///   - isRecovery: Force green color for recovery segments
    /// - Returns: A Color representing the intensity level
    static func intensity(for pct: Int?, isRecovery: Bool = false) -> Color {
        // Recovery segments always get green
        guard !isRecovery else {
            return Color(hue: 0.33, saturation: 0.65, brightness: 0.85)
        }

        // Default to green for nil intensity
        guard let pct = pct else {
            return Color(hue: 0.33, saturation: 0.65, brightness: 0.85)
        }

        // HSL gradient: hue = max(0, (120 - ((pct - 50) / 70 * 120))) / 360
        // Bright, colorful tones (saturation 0.65, brightness 0.85)
        let hue = max(0, (120.0 - ((Double(pct) - 50.0) / 70.0 * 120.0))) / 360.0

        return Color(hue: hue, saturation: 0.65, brightness: 0.85)
    }

    /// Phase color for training plan phases.
    /// Used by CalendarWeekHeader to color the phase badge dot and label.
    /// - Parameter phase: Phase name string (e.g. "Base", "Build", "Peak", "Taper", "Recovery")
    /// - Returns: A Color associated with the given phase.
    static func phaseColor(for phase: String) -> Color {
        switch phase {
        case "Base":     return .blue
        case "Build":    return .orange
        case "Peak":     return .red
        case "Taper":    return .purple
        case "Recovery": return .green
        // Unknown phase strings render as `.primary` so the badge remains visible
        // (e.g., during plan-generation race conditions or future phase additions).
        default:         return .primary
        }
    }

    // MARK: - HR-based intensity color (DRO-297)

    /// HR-based intensity color for segments whose target is `hr_pct_max` or `hr_zone`.
    ///
    /// Maps a heart-rate percentage of max HR (0–100) to the same green→yellow→orange→red
    /// gradient used by `Color.intensity(for:isRecovery:)`. Anchors:
    /// - ≤65% → green (warm-up / Z1)
    /// - 65–80% → green fading to yellow (Z2–Z3)
    /// - 80–90% → yellow fading to orange (Z3–Z4)
    /// - ≥90% → orange fading to red (Z4–Z5)
    /// - Recovery → always green regardless of percentage.
    ///
    /// - Parameters:
    ///   - pct: Heart-rate percentage of max HR (e.g., 88.0 for 88%).
    ///   - isRecovery: Force green for recovery segments.
    /// - Returns: A Color in the green→red gradient.
    static func intensity(forHRPctMax pct: Double, isRecovery: Bool = false) -> Color {
        guard !isRecovery else {
            return Color(hue: 0.33, saturation: 0.65, brightness: 0.85)
        }
        // Map the physiologically relevant HR range (60–95%) linearly onto the
        // same 120°→0° hue sweep used by the FTP/VMA percentage path.
        // Below 60% → full green; above 95% → full red.
        let clamped = max(60.0, min(95.0, pct))
        let hue = max(0.0, (120.0 - ((clamped - 60.0) / 35.0 * 120.0))) / 360.0
        return Color(hue: hue, saturation: 0.65, brightness: 0.85)
    }

    // MARK: - Asset-backed color tokens
    //
    // `Color.errorStrong` is generated automatically by Xcode from the `ErrorStrong`
    // colorset in `Assets.xcassets` — see `GeneratedAssetSymbols.swift`. We do **not**
    // declare a manual extension here because that would collide with the synthesized
    // symbol. Light `#FF3B30` / dark `#FF453A` per DESIGN.md §1. Used by `MissedTag`
    // and any other "not completed / failure" affordance.
    //
    // If you add another asset-backed color and want the same generated treatment,
    // just add the colorset — no Swift extension needed.
}
