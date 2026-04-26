//
//  WorkoutShape.swift
//  Dromos
//
//  Created by Emmanuel Breard on 26/04/2026.
//

import SwiftUI

/// Compact horizontal "shape" of a workout — a 56pt-tall stack of intensity-colored bars
/// flex-sized by segment duration (or distance for swim).
///
/// Used as the at-a-glance anchor inside `TodayPlannedCard` / `TodayCompletedCard`.
/// Visually equivalent to `WorkoutGraphView` minus the time axis and tap tooltip — this
/// component is non-interactive and chrome-free so it composes inside cards without
/// stealing focus from the title and step list.
///
/// Reuses `Color.intensity(for:isRecovery:)` so the gradient stays in lockstep with the
/// detailed graph rendered elsewhere.
struct WorkoutShape: View {
    let segments: [FlatSegment]

    /// Fixed outer height. Tuned to read as a "shape" (not a chart) at the card scale.
    private let outerHeight: CGFloat = 56

    /// Minimum bar width so a very short segment (e.g. 30s recovery) stays visible.
    private let minBarWidth: CGFloat = 2

    /// Per-bar corner radius — soft enough to feel like a shape, sharp enough to read as data.
    private let barCornerRadius: CGFloat = 3

    /// Inter-bar spacing. Mirrors `WorkoutGraphView` so widths reconcile when both render.
    private let interBarSpacing: CGFloat = 2

    /// Total weight used to flex bars. We prefer duration; fall back to distance for swim
    /// segments that carry only `distanceMeters`.
    private var totalWeight: Double {
        segments.reduce(0) { acc, seg in acc + weight(for: seg) }
    }

    var body: some View {
        if segments.isEmpty || totalWeight <= 0 {
            EmptyView()
        } else {
            // GeometryReader is needed because SwiftUI's HStack cannot flex children by an
            // arbitrary numeric weight — we have to translate "this segment is X% of the total
            // duration" into a pixel width ourselves. Same approach as `WorkoutGraphView`.
            GeometryReader { geo in
                let totalSpacing = CGFloat(max(0, segments.count - 1)) * interBarSpacing
                let usableWidth = max(0, geo.size.width - totalSpacing)

                HStack(alignment: .bottom, spacing: interBarSpacing) {
                    ForEach(segments) { segment in
                        let effectivePct = effectiveIntensity(for: segment)
                        let barWidth = max(
                            CGFloat(weight(for: segment) / totalWeight) * usableWidth,
                            minBarWidth
                        )
                        let barHeight = heightFraction(for: effectivePct) * outerHeight

                        RoundedRectangle(cornerRadius: barCornerRadius)
                            .fill(Color.intensity(for: effectivePct, isRecovery: segment.isRecovery))
                            .frame(width: barWidth, height: barHeight)
                            // Push every bar to share the same baseline regardless of height.
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            .frame(height: outerHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    // MARK: - Sizing

    /// Weight used for horizontal flex. Duration when present, otherwise distance.
    /// (Swim segments often carry distance only — the shape still wants them sized proportionally.)
    private func weight(for segment: FlatSegment) -> Double {
        if segment.durationMinutes > 0 { return segment.durationMinutes }
        if let distance = segment.distanceMeters, distance > 0 { return Double(distance) }
        return 0
    }

    /// Maps intensity percentage to a height fraction of `outerHeight`.
    /// Buckets per the DRO-231 spec — gives clear visual contrast between recovery and VO2 work.
    /// - Recovery / very easy (≤55%) → 25-35%
    /// - Moderate (~60-75%)         → 50-60%
    /// - Tempo (~80-85%)            → 70-80%
    /// - Threshold (~90-95%)        → 85-90%
    /// - VO2 / max (≥100%)          → 95-100%
    private func heightFraction(for intensityPct: Int?) -> CGFloat {
        guard let pct = intensityPct, pct > 0 else { return 0.30 }
        switch pct {
        case ..<60:    return 0.30
        case 60..<80:  return 0.55
        case 80..<88:  return 0.75
        case 88..<95:  return 0.88
        default:       return 1.00
        }
    }

    /// Same heuristic `WorkoutGraphView` uses for swim/strength: derive an effective intensity
    /// from a pace label when `intensityPct` is missing. Keeps the shape's height contrast
    /// usable for the bundled swim templates.
    private func effectiveIntensity(for segment: FlatSegment) -> Int? {
        if let pct = segment.intensityPct { return pct }
        if let pace = segment.pace {
            switch pace.lowercased() {
            case "easy":              return 55
            case "medium", "moderate": return 70
            case "hard", "fast":       return 85
            case "sprint", "max":      return 105
            default:                   return 65
            }
        }
        return nil
    }

    // MARK: - Accessibility

    /// Single-sentence summary for VoiceOver — the visual shape is decorative beside the
    /// step list, so we describe shape rather than enumerate every bar.
    private var accessibilityLabel: String {
        let mins = Int(round(segments.reduce(0) { $0 + $1.durationMinutes }))
        return "Workout intensity profile, \(mins) minutes total."
    }
}

// MARK: - Previews

/// Tuesday VO2 5×3' canonical structure shared across DRO-231 prototypes.
/// 11' warmup → 5×(3' work @ VMA 95% + 3' recovery jog) → 11' cooldown.
private let tuesdayVO2Segments: [FlatSegment] = {
    var segs: [FlatSegment] = [
        FlatSegment(label: "warmup", durationMinutes: 11, intensityPct: 50, distanceMeters: nil, pace: nil, isRecovery: false)
    ]
    for _ in 0..<5 {
        segs.append(FlatSegment(label: "work", durationMinutes: 3, intensityPct: 95, distanceMeters: nil, pace: nil, isRecovery: false))
        segs.append(FlatSegment(label: "recovery", durationMinutes: 3, intensityPct: nil, distanceMeters: nil, pace: nil, isRecovery: true))
    }
    segs.append(FlatSegment(label: "cooldown", durationMinutes: 11, intensityPct: 50, distanceMeters: nil, pace: nil, isRecovery: false))
    return segs
}()

#Preview("Tuesday VO2 5×3' (canonical)") {
    VStack(alignment: .leading, spacing: 12) {
        Text("VO2 intervals 5×3'")
            .font(.title2.bold())
        WorkoutShape(segments: tuesdayVO2Segments)
    }
    .padding(16)
    .background(Color("CardSurface"))
    .padding()
    .background(Color("PageSurface"))
}

#Preview("Long ride — steady block") {
    let segments: [FlatSegment] = [
        FlatSegment(label: "warmup", durationMinutes: 20, intensityPct: 50, distanceMeters: nil, pace: nil, isRecovery: false),
        FlatSegment(label: "steady", durationMinutes: 150, intensityPct: 70, distanceMeters: nil, pace: nil, isRecovery: false),
        FlatSegment(label: "cooldown", durationMinutes: 10, intensityPct: 45, distanceMeters: nil, pace: nil, isRecovery: false)
    ]
    return WorkoutShape(segments: segments)
        .padding(16)
        .background(Color("CardSurface"))
        .padding()
}

#Preview("Swim — distance-driven") {
    let segments: [FlatSegment] = [
        FlatSegment(label: "warmup", durationMinutes: 5, intensityPct: nil, distanceMeters: 200, pace: "easy", isRecovery: false),
        FlatSegment(label: "work", durationMinutes: 1.5, intensityPct: nil, distanceMeters: 100, pace: "hard", isRecovery: false),
        FlatSegment(label: "recovery", durationMinutes: 0.5, intensityPct: nil, distanceMeters: 50, pace: "easy", isRecovery: true),
        FlatSegment(label: "work", durationMinutes: 1.5, intensityPct: nil, distanceMeters: 100, pace: "hard", isRecovery: false),
        FlatSegment(label: "recovery", durationMinutes: 0.5, intensityPct: nil, distanceMeters: 50, pace: "easy", isRecovery: true),
        FlatSegment(label: "cooldown", durationMinutes: 5, intensityPct: nil, distanceMeters: 200, pace: "easy", isRecovery: false)
    ]
    return WorkoutShape(segments: segments)
        .padding(16)
        .background(Color("CardSurface"))
        .padding()
}
