//
//  WorkoutGraphView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 14/02/2026.
//

import SwiftUI

/// Displays a horizontal bar chart visualizing workout intensity over time.
/// Bar width = proportional to segment duration, bar height = normalized intensity.
/// Time axis labels shown below at ~15 min intervals.
/// Tap a bar to reveal a tooltip with segment details (sport-specific metrics).
struct WorkoutGraphView: View {
    let segments: [FlatSegment]
    let totalDurationMinutes: Double
    let sport: String
    let ftp: Int?
    let vma: Double?
    
    /// Selected segment index for tooltip display
    @State private var selectedSegmentIndex: Int?
    
    /// Fixed height for the graph area (bars)
    private let graphHeight: CGFloat = 60
    
    /// Fixed height for the time axis area
    private let axisHeight: CGFloat = 20
    
    var body: some View {
        // Guard against division by zero
        if totalDurationMinutes > 0 {
            VStack(alignment: .leading, spacing: 4) {
                // Graph bars with tap interaction
                GeometryReader { geometry in
                    // Account for HStack spacing in bar width calculations
                    let totalSpacing = CGFloat(max(0, segments.count - 1)) * 2
                    let usableWidth = max(0, geometry.size.width - totalSpacing)
                    
                    HStack(spacing: 2) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                            let barWidth = (segment.durationMinutes / totalDurationMinutes) * usableWidth
                            let effectivePct = effectiveIntensity(for: segment)
                            let barHeight = normalizedHeight(for: effectivePct)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.intensity(for: effectivePct, isRecovery: segment.isRecovery))
                                .frame(width: max(barWidth, 2), height: barHeight) // Minimum 2pt width for visibility
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .contentShape(Rectangle()) // Make entire bar tappable
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        // Toggle selection (tap same bar to dismiss)
                                        if selectedSegmentIndex == index {
                                            selectedSegmentIndex = nil
                                        } else {
                                            selectedSegmentIndex = index
                                        }
                                    }
                                }
                        }
                    }
                    .frame(height: graphHeight)
                    .background {
                        // Tap outside bars to dismiss tooltip
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedSegmentIndex = nil
                                }
                            }
                    }
                }
                .frame(height: graphHeight)
                
                // Time axis labels
                timeAxisView
                    .frame(height: axisHeight)
                
                // Tooltip row (only shown when a bar is selected)
                if let index = selectedSegmentIndex, index < segments.count {
                    segmentTooltipView(for: segments[index])
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .onDisappear {
                selectedSegmentIndex = nil
            }
        }
    }
    
    // MARK: - Tooltip View
    
    /// Creates a tooltip view for a segment with sport-specific metrics.
    /// - Parameter segment: The segment to display
    /// - Returns: A tooltip view with formatted text
    private func segmentTooltipView(for segment: FlatSegment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formatTooltipText(for: segment))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }
    
    /// Formats tooltip text with sport-specific metrics.
    /// - Parameter segment: The segment to format
    /// - Returns: Formatted text string
    private func formatTooltipText(for segment: FlatSegment) -> String {
        let duration = formatDuration(segment: segment)
        let label = segment.label
        let metric = formatMetric(segment: segment)
        
        if let metric = metric {
            return "\(duration) \(label) — \(metric)"
        } else {
            return "\(duration) \(label)"
        }
    }
    
    /// Formats the duration of a segment.
    /// - Parameter segment: The segment
    /// - Returns: Formatted duration string (e.g., "15 min", "300m")
    private func formatDuration(segment: FlatSegment) -> String {
        if let distance = segment.distanceMeters {
            return "\(distance)m"
        } else {
            let minutes = Int(round(segment.durationMinutes))
            return "\(minutes) min"
        }
    }
    
    /// Formats the sport-specific metric for a segment.
    /// - Parameter segment: The segment
    /// - Returns: Formatted metric string, or nil if not applicable
    private func formatMetric(segment: FlatSegment) -> String? {
        switch sport.lowercased() {
        case "bike":
            if let intensityPct = segment.intensityPct {
                if let ftp = ftp {
                    let watts = Int(round(Double(intensityPct) / 100.0 * Double(ftp)))
                    return "\(watts) W"
                } else {
                    return "\(intensityPct)% FTP"
                }
            }
            
        case "run":
            if let intensityPct = segment.intensityPct {
                if let vma = vma {
                    let speed = vma * Double(intensityPct) / 100.0
                    // Use shared speedToPace from WorkoutLibraryService
                    let pace = WorkoutLibraryService.shared.speedToPace(speed: speed)
                    return String(format: "%.1f km/h (%@)", speed, pace)
                } else {
                    return "\(intensityPct)% VMA"
                }
            }
            
        case "swim":
            // Note: Tooltip shows "pace" suffix for clarity ("hard pace" vs "hard")
            // WorkoutLibraryService.formatMetric uses label-only format for step summaries
            // This intentional difference makes tooltips more descriptive
            if let pace = segment.pace {
                return "\(pace) pace"
            }
            
        default:
            break
        }
        
        return nil
    }
    
    // MARK: - Time Axis
    
    /// Renders time axis labels at ~15 min intervals.
    /// For very long workouts (3h+), increases interval to prevent crowding.
    /// Adaptive time axis interval based on workout duration.
    private var timeInterval: Double {
        if totalDurationMinutes > 240 { return 60.0 }
        if totalDurationMinutes > 120 { return 30.0 }
        return 15.0
    }

    private var timeAxisView: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let interval = timeInterval
            let labelCount = Int(totalDurationMinutes / interval) + 1
            
            HStack(spacing: 0) {
                ForEach(0..<labelCount, id: \.self) { index in
                    let minutes = Double(index) * interval
                    
                    if minutes <= totalDurationMinutes {
                        Text("\(Int(minutes))'")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: index < labelCount - 1 ? interval / totalDurationMinutes * availableWidth : nil, alignment: .leading)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Derives an effective intensity for bar height calculation.
    /// For swim segments without intensityPct, maps pace label to approximate intensity.
    private func effectiveIntensity(for segment: FlatSegment) -> Int? {
        if let pct = segment.intensityPct { return pct }
        if let pace = segment.pace {
            switch pace.lowercased() {
            case "easy": return 55
            case "medium", "moderate": return 70
            case "hard", "fast": return 85
            case "sprint", "max": return 105
            default: return 65
            }
        }
        return nil
    }

    /// Calculates normalized bar height for an intensity percentage.
    /// Returns a value between 30% and 100% of graph height for visual clarity.
    /// - Parameter intensityPct: Intensity percentage (nil defaults to minimum height)
    /// - Returns: Bar height in points
    private func normalizedHeight(for intensityPct: Int?) -> CGFloat {
        guard let pct = intensityPct, pct > 0 else {
            return graphHeight * 0.3 // Minimum 30% height for low/nil intensity
        }
        
        // Clamp lower bound to prevent dropping below 30% floor
        // Map intensity to 30%-100% of graph height
        // pct = 50 → 30% height
        // pct = 100 → 100% height
        // pct = 120 → 100% height (capped)
        let normalized = max(0, min(Double(pct - 50) / 70.0, 1.0)) // 50-120 → 0-1, clamped
        let heightPct = 0.3 + (normalized * 0.7) // 0-1 → 0.3-1.0
        
        return graphHeight * heightPct
    }
}

// MARK: - Previews

#Preview("Bike Intervals - Tap Interaction") {
    let segments = [
        FlatSegment(label: "warmup", durationMinutes: 15, intensityPct: 50, distanceMeters: nil, pace: nil, isRecovery: false),
        FlatSegment(label: "work", durationMinutes: 6, intensityPct: 95, distanceMeters: nil, pace: nil, isRecovery: false),
        FlatSegment(label: "recovery", durationMinutes: 4, intensityPct: nil, distanceMeters: nil, pace: nil, isRecovery: true),
        FlatSegment(label: "work", durationMinutes: 6, intensityPct: 95, distanceMeters: nil, pace: nil, isRecovery: false),
        FlatSegment(label: "recovery", durationMinutes: 4, intensityPct: nil, distanceMeters: nil, pace: nil, isRecovery: false),
        FlatSegment(label: "work", durationMinutes: 6, intensityPct: 95, distanceMeters: nil, pace: nil, isRecovery: false),
        FlatSegment(label: "cooldown", durationMinutes: 10, intensityPct: 45, distanceMeters: nil, pace: nil, isRecovery: false)
    ]
    
    let totalDuration = segments.reduce(0) { $0 + $1.durationMinutes }
    
    return WorkoutGraphView(
        segments: segments,
        totalDurationMinutes: totalDuration,
        sport: "bike",
        ftp: 250,
        vma: nil
    )
    .padding()
    .background(Color(.systemBackground))
}

#Preview("Run Tempo") {
    let segments = [
        FlatSegment(label: "warmup", durationMinutes: 10, intensityPct: 60, distanceMeters: nil, pace: nil, isRecovery: false),
        FlatSegment(label: "tempo", durationMinutes: 20, intensityPct: 85, distanceMeters: nil, pace: nil, isRecovery: false),
        FlatSegment(label: "cooldown", durationMinutes: 10, intensityPct: 55, distanceMeters: nil, pace: nil, isRecovery: false)
    ]
    
    let totalDuration = segments.reduce(0) { $0 + $1.durationMinutes }
    
    return WorkoutGraphView(
        segments: segments,
        totalDurationMinutes: totalDuration,
        sport: "run",
        ftp: nil,
        vma: 15.0
    )
    .padding()
    .background(Color(.systemBackground))
}

#Preview("Swim Intervals") {
    let segments = [
        FlatSegment(label: "warmup", durationMinutes: 5, intensityPct: nil, distanceMeters: 200, pace: "easy", isRecovery: false),
        FlatSegment(label: "work", durationMinutes: 1.5, intensityPct: nil, distanceMeters: 100, pace: "hard", isRecovery: false),
        FlatSegment(label: "recovery", durationMinutes: 0.5, intensityPct: nil, distanceMeters: 50, pace: "easy", isRecovery: true),
        FlatSegment(label: "work", durationMinutes: 1.5, intensityPct: nil, distanceMeters: 100, pace: "hard", isRecovery: false),
        FlatSegment(label: "recovery", durationMinutes: 0.5, intensityPct: nil, distanceMeters: 50, pace: "easy", isRecovery: true),
        FlatSegment(label: "work", durationMinutes: 1.5, intensityPct: nil, distanceMeters: 100, pace: "hard", isRecovery: false),
        FlatSegment(label: "cooldown", durationMinutes: 5, intensityPct: nil, distanceMeters: 200, pace: "easy", isRecovery: false)
    ]
    
    let totalDuration = segments.reduce(0) { $0 + $1.durationMinutes }
    
    return WorkoutGraphView(
        segments: segments,
        totalDurationMinutes: totalDuration,
        sport: "swim",
        ftp: nil,
        vma: nil
    )
    .padding()
    .background(Color(.systemBackground))
}

#Preview("Long Ride - 3h+") {
    let segments = [
        FlatSegment(label: "warmup", durationMinutes: 20, intensityPct: 50, distanceMeters: nil, pace: nil, isRecovery: false),
        FlatSegment(label: "steady", durationMinutes: 150, intensityPct: 70, distanceMeters: nil, pace: nil, isRecovery: false),
        FlatSegment(label: "cooldown", durationMinutes: 10, intensityPct: 45, distanceMeters: nil, pace: nil, isRecovery: false)
    ]
    
    let totalDuration = segments.reduce(0) { $0 + $1.durationMinutes }
    
    return WorkoutGraphView(
        segments: segments,
        totalDurationMinutes: totalDuration,
        sport: "bike",
        ftp: 250,
        vma: nil
    )
    .padding()
    .background(Color(.systemBackground))
}
