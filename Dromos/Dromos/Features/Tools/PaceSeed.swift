//
//  PaceSeed.swift
//  Dromos
//
//  Pre-seed factory for the pace calculator (DRO-262 / DRO-264).
//  Maps a PlanSession + optional User profile to an initial discipline + slider value.
//

import Foundation

// MARK: - PaceSeed

/// Carries the initial state used to pre-fill the pace calculator drawer.
///
/// Both entry points (Profile row and SessionCard chip) produce a `PaceSeed?`
/// which is handed to `PaceCalculatorSheet(seed:)`.  A `nil` seed means
/// "open with neutral run defaults".
struct PaceSeed {
    /// The discipline to pre-select in the segmented control.
    let discipline: Discipline
    /// The initial integer slider value (already clamped to `discipline.config.[min, max]`).
    let sliderValue: Int
}

// MARK: - Factory

extension PaceSeed {
    /// Derives a `PaceSeed` from a planned session and an optional athlete profile.
    ///
    /// Mapping rules:
    /// - `.run`  → `sliderValue` = `Int((vma × 10).rounded())` if VMA is set, else default.
    /// - `.bike` → always default 320 (= 32.0 km/h) in V0 — no FTP→speed derivation.
    /// - `.swim` → `sliderValue` = `cssSecondsPer100m` if CSS is set, else default.
    /// - Unknown sport → returns `nil` (chip is hidden for non-triathlon sessions).
    ///
    /// The `sliderValue` is always clamped to `[config.min, config.max]` before returning.
    ///
    /// - Parameters:
    ///   - session: The training session providing the sport string.
    ///   - profile: The athlete profile providing VMA / CSS; may be `nil`.
    /// - Returns: A `PaceSeed`, or `nil` if the sport is not recognised.
    static func from(session: PlanSession, profile: User?) -> PaceSeed? {
        let discipline: Discipline

        switch session.sport.lowercased() {
        case "run":  discipline = .run
        case "bike": discipline = .bike
        case "swim": discipline = .swim
        default:     return nil
        }

        let config = discipline.config
        var raw: Int

        switch discipline {
        case .run:
            if let vma = profile?.vma {
                raw = Int((vma * 10).rounded())
            } else {
                raw = config.defaultValue
            }

        case .bike:
            // V0: always use the default speed (32.0 km/h).
            raw = config.defaultValue

        case .swim:
            if let css = profile?.cssSecondsPer100m {
                raw = css
            } else {
                raw = config.defaultValue
            }
        }

        // Clamp to the valid slider range.
        let clamped = max(config.min, min(config.max, raw))
        return PaceSeed(discipline: discipline, sliderValue: clamped)
    }
}
