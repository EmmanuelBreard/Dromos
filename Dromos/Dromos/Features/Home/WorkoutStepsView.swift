//
//  WorkoutStepsView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 14/02/2026.
//

import SwiftUI

/// Displays workout steps as a compact vertical list with intensity-colored dots.
/// Each step shows: colored circle (intensity dot) + formatted text with sport-specific metrics.
struct WorkoutStepsView: View {
    let steps: [StepSummary]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(steps) { step in
                HStack(spacing: 10) {
                    // Intensity dot
                    // FIX #9: isRecovery is false because StepSummary collapses recovery into repeat blocks,
                    // so standalone recovery steps don't appear in the step list.
                    Circle()
                        .fill(Color.intensity(for: step.intensityPct, isRecovery: false))
                        .frame(width: 8, height: 8)
                    
                    // Step text
                    // FIX #11: Subtle visual differentiation for repeat blocks
                    Text(step.text)
                        .font(.subheadline)
                        .fontWeight(step.isRepeatBlock ? .medium : .regular)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Bike Intervals") {
    let steps = [
        StepSummary(text: "15' warmup - 120 W", intensityPct: 50, isRepeatBlock: false),
        StepSummary(text: "3× (6' work - 260 W + 4' recovery)", intensityPct: 95, isRepeatBlock: true),
        StepSummary(text: "10' cooldown - 100 W", intensityPct: 45, isRepeatBlock: false)
    ]
    
    return WorkoutStepsView(steps: steps)
        .padding()
        .background(Color(.systemBackground))
}

#Preview("Run Tempo") {
    let steps = [
        StepSummary(text: "10' warmup - 9.0 km/h (6:40/km)", intensityPct: 60, isRepeatBlock: false),
        StepSummary(text: "20' tempo - 12.0 km/h (5:00/km)", intensityPct: 85, isRepeatBlock: false),
        StepSummary(text: "10' cooldown - 8.0 km/h (7:30/km)", intensityPct: 55, isRepeatBlock: false)
    ]
    
    return WorkoutStepsView(steps: steps)
        .padding()
        .background(Color(.systemBackground))
}

#Preview("Swim Intervals") {
    let steps = [
        StepSummary(text: "300m warmup", intensityPct: nil, isRepeatBlock: false),
        StepSummary(text: "4×100m medium", intensityPct: 75, isRepeatBlock: true),
        StepSummary(text: "200m cooldown", intensityPct: nil, isRepeatBlock: false)
    ]
    
    return WorkoutStepsView(steps: steps)
        .padding()
        .background(Color(.systemBackground))
}
