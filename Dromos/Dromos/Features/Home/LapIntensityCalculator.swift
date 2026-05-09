//
//  LapIntensityCalculator.swift
//  Dromos
//
//  Sport-aware lap intensity normalization for the completed-session segments graph (DRO-223).
//
//  Design decisions:
//  - Pure functions, no SwiftUI / UIKit imports. Independently testable.
//  - Bike fallback is per-activity: if any lap lacks valid watts, the whole activity uses HR.
//  - Equal-value double-fallback: when every non-nil lap reports the same metric value AND
//    no reference (VMA/FTP/CSS) is set, all bars return 100. Rationale: we have no basis to
//    differentiate effort; 100 with default green color communicates "uniform session" without
//    a blank chart. See tech spec resolved decisions (DRO-223).
//

import Foundation

// MARK: - LapIntensityCalculator

/// Computes a normalized intensity percentage (0–100) for each lap, sport-aware.
///
/// **Default path** uses the athlete's reference value (VMA for run / FTP for bike power /
/// CSS for swim). The returned percentage may exceed 100 when the athlete goes above their
/// reference (e.g., sprinting above VMA). Callers that clamp to 100 for visual purposes
/// should do so at the rendering layer — the raw value is meaningful for diagnostics.
///
/// **Fallback path** triggers when the relevant reference is nil: intensities are normalized
/// against the session's own min and max (`sessionMin … sessionMax → 0 … 100`).
///
/// **Bike-specific rule**: power vs HR detection is per-activity, not per-lap. If even one
/// lap has `averageWatts == nil || averageWatts == 0`, the entire activity falls back to HR.
enum LapIntensityCalculator {

    // MARK: - Public Entry Point

    /// Computes a normalized intensity percentage (0–100) for each lap, sport-aware.
    ///
    /// - Parameters:
    ///   - laps: Ordered array of `StravaLap` instances for a single activity.
    ///   - sport: Sport string (e.g., `"run"`, `"bike"`, `"swim"`). Case-insensitive.
    ///   - vma: Athlete's VMA (km/h). Used for run reference normalization.
    ///   - ftp: Athlete's FTP (W). Used for bike-power reference normalization.
    ///   - css: Athlete's CSS (seconds/100 m). Used for swim reference normalization.
    ///   - maxHr: Athlete's max heart rate (bpm). Used for bike-HR reference normalization.
    /// - Returns: One element per input lap, same order. `nil` for a lap that cannot be
    ///   normalized (missing the metric required by its sport, e.g., a swim lap with no speed).
    static func intensities(
        for laps: [StravaLap],
        sport: String,
        vma: Double?,
        ftp: Int?,
        css: Int?,
        maxHr: Int?
    ) -> [Int?] {
        guard !laps.isEmpty else { return [] }

        switch sport.lowercased() {
        case "run":
            return runIntensities(laps: laps, vma: vma)
        case "bike":
            return bikeIntensities(laps: laps, ftp: ftp, maxHr: maxHr)
        case "swim":
            return swimIntensities(laps: laps, css: css)
        default:
            // Unknown sport: session-normalize on averageSpeed. Laps with nil speed → nil.
            return sessionNormalized(values: laps.map { $0.averageSpeed })
        }
    }

    // MARK: - Sport Routing

    /// Run: intensity based on speed relative to VMA (km/h).
    /// If VMA is not set, falls back to session-normalized speed.
    private static func runIntensities(laps: [StravaLap], vma: Double?) -> [Int?] {
        let speedsKmh: [Double?] = laps.map { lap in
            guard let speed = lap.averageSpeed else { return nil }
            return speed * 3.6
        }

        if let vma = vma {
            // Reference path: intensity % = (speed_kmh / VMA) * 100
            return speedsKmh.map { kmh in
                guard let kmh = kmh else { return nil }
                return Int((kmh / vma * 100.0).rounded())
            }
        } else {
            // Fallback: session-normalize on averageSpeed (m/s); kmh is monotone so either works.
            return sessionNormalized(values: laps.map { $0.averageSpeed })
        }
    }

    /// Bike: prefer power-based normalization when all laps have valid watts.
    /// Per-activity rule: if any lap is missing watts or has watts == 0, the whole
    /// activity falls back to HR-based normalization.
    private static func bikeIntensities(laps: [StravaLap], ftp: Int?, maxHr: Int?) -> [Int?] {
        let usePower = laps.allSatisfy { ($0.averageWatts ?? 0) > 0 }

        if usePower {
            let wattsValues = laps.map { $0.averageWatts }

            if let ftp = ftp {
                // Power reference path: intensity % = (watts / FTP) * 100
                return wattsValues.map { watts in
                    guard let watts = watts else { return nil }
                    return Int((watts / Double(ftp) * 100.0).rounded())
                }
            } else {
                // Power fallback: session-normalize on watts
                return sessionNormalized(values: wattsValues)
            }
        } else {
            // HR fallback path (per-activity: entire activity switches to HR)
            let hrValues = laps.map { $0.averageHeartrate }

            if let maxHr = maxHr {
                // HR reference path: intensity % = (bpm / maxHr) * 100
                return hrValues.map { hr in
                    guard let hr = hr else { return nil }
                    return Int((hr / Double(maxHr) * 100.0).rounded())
                }
            } else {
                // HR session-normalize fallback
                return sessionNormalized(values: hrValues)
            }
        }
    }

    /// Swim: intensity based on seconds per 100 m relative to CSS.
    /// Faster speed (fewer seconds/100 m) = higher intensity.
    /// Laps with `averageSpeed == nil || averageSpeed <= 0` → nil.
    private static func swimIntensities(laps: [StravaLap], css: Int?) -> [Int?] {
        if let css = css {
            // CSS reference path: intensity % = (CSS / secondsPer100m) * 100
            // When secondsPer100m < CSS (swimmer is faster than CSS), result > 100 — intentional.
            return laps.map { lap in
                guard let speed = lap.averageSpeed, speed > 0 else { return nil }
                let secondsPer100m = 100.0 / speed
                return Int((Double(css) / secondsPer100m * 100.0).rounded())
            }
        } else {
            // Fallback: session-normalize on averageSpeed (faster speed = higher intensity).
            // Laps with nil / non-positive speed are nil'd out before normalization.
            let speeds: [Double?] = laps.map { lap in
                guard let speed = lap.averageSpeed, speed > 0 else { return nil }
                return speed
            }
            return sessionNormalized(values: speeds)
        }
    }

    // MARK: - Session-Normalize Helper

    /// Normalizes an array of optional Double values to the range 0–100 using
    /// min-max scaling: `pct = ((value - min) / (max - min)) * 100`.
    ///
    /// **Equal-value double-fallback** (tech spec DRO-223 resolved decisions):
    /// When `min == max` for all non-nil values — meaning every lap reports the same metric
    /// AND the caller already determined no reference (VMA/FTP/CSS) is available — return 100
    /// for every non-nil entry. This communicates "uniform session with no reference" without
    /// producing a blank chart. Color rendering via `Color.intensity(for: 100)` produces the
    /// orange/tempo tone, but callers may override via `Color.intensity(for: nil)` for a
    /// greener "easy" default if product decides to differentiate in Phase 4.
    ///
    /// - Parameter values: Parallel array of optional metric values. Nil entries remain nil.
    /// - Returns: Normalized intensities (Int), same length and order. Nil for nil inputs.
    private static func sessionNormalized(values: [Double?]) -> [Int?] {
        let nonNilValues = values.compactMap { $0 }
        guard !nonNilValues.isEmpty else {
            // All laps missing the required metric — nothing to normalize.
            return values.map { _ in nil }
        }

        let sessionMin = nonNilValues.min()!
        let sessionMax = nonNilValues.max()!

        // Equal-value double-fallback: all non-nil values are identical AND no reference is set
        // (this function is only called when the reference is absent). Return 100 for all.
        // See: tech-specs/DRO-223-completed-segments-graph.md → "Resolved Decisions".
        if sessionMin == sessionMax {
            return values.map { $0 == nil ? nil : 100 }
        }

        let range = sessionMax - sessionMin
        return values.map { value in
            guard let value = value else { return nil }
            return Int(((value - sessionMin) / range * 100.0).rounded())
        }
    }
}
