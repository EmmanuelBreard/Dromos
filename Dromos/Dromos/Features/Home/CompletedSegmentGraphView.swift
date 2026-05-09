//
//  CompletedSegmentGraphView.swift
//  Dromos
//
//  Strava-driven horizontal bar chart for completed-session cards (DRO-223 Phase 4).
//  One bar per Strava lap; width encodes lap distance share; height encodes sport-normalized
//  intensity from `LapIntensityCalculator`. Drag-and-hold tooltip surfaces per-lap detail.
//
//  Intentional divergences from `WorkoutGraphView`:
//  - X-axis = distance (not duration)
//  - Bars filtered to non-zero distance only
//  - Selected-state visual: dim siblings to 45% + 1.5pt outline on selected bar
//  - All-nil intensities (equal-value double-fallback per DRO-223 spec):
//    render every bar at 100% height with green/easy color via `Color.intensity(for: nil)`
//

import SwiftUI

// MARK: - CompletedSegmentGraphView

/// Strava-driven horizontal bar chart shown on completed-session cards.
///
/// One bar per Strava lap; width by lap distance share; height by sport-normalized
/// intensity from `LapIntensityCalculator`. Drag-and-hold tooltip shows per-lap detail.
struct CompletedSegmentGraphView: View {

    // MARK: Inputs

    let laps: [StravaLap]
    let sport: String
    let vma: Double?
    let ftp: Int?
    let css: Int?
    let maxHr: Int?

    // MARK: State

    /// Index into `validLaps` of the currently selected bar (nil = no selection).
    @State private var selectedLapIndex: Int?

    /// X position (within the GeometryReader) at which to center the tooltip bubble.
    @State private var tooltipXOffset: CGFloat = 0

    /// Captured graph width for tooltip x-clamping (updated via `.onAppear` + `.onChange`).
    @State private var graphWidth: CGFloat = 0

    // MARK: Constants

    /// Fixed height for the graph bar area in points.
    private let graphHeight: CGFloat = 80

    /// Approximate half-width of the tooltip bubble; used to clamp x so the bubble
    /// stays within the chart bounds on edge bars. Match `WorkoutGraphView`.
    private let tooltipHalfWidth: CGFloat = 110

    // MARK: Body

    @ViewBuilder
    var body: some View {
        // Filter out laps with zero or nil distance — they produce zero-width bars
        // and cannot be normalized meaningfully.
        let validLaps = laps.filter { ($0.distance ?? 0) > 0 }

        // Defensive early exit — parent should guard laps.count < 2 before rendering,
        // but we protect here as well. Implicit empty branch renders nothing.
        if validLaps.count >= 2 {

        // Compute intensities exactly once for this render pass.
        let intensities = LapIntensityCalculator.intensities(
            for: validLaps,
            sport: sport,
            vma: vma,
            ftp: ftp,
            css: css,
            maxHr: maxHr
        )

        // Detect the equal-value double-fallback: calculator returns all-nil when it has
        // no basis to differentiate effort. In that case every bar renders at 100% / green.
        let isAllNil = intensities.allSatisfy { $0 == nil }

        // Total distance across valid laps — denominator for width fractions.
        let totalDistance = validLaps.reduce(0.0) { $0 + ($1.distance ?? 0) }

        VStack(alignment: .leading, spacing: 8) {

                // Section header
                Text("Segments")
                    .font(.headline)
                    .foregroundColor(.primary)

                // Graph area
                GeometryReader { geometry in
                    // Subtract HStack spacing from usable width for accurate bar fractions.
                    let totalSpacing = CGFloat(max(0, validLaps.count - 1)) * 2
                    let usableWidth = max(0, geometry.size.width - totalSpacing)

                    // Precompute bar center x-positions in O(n) via a single forward scan.
                    // X-axis is distance-based (divergence from WorkoutGraphView which uses duration).
                    // The for-loop lives in a helper to avoid a @ViewBuilder control-flow conflict.
                    let barCenterXs: [CGFloat] = barCenters(for: validLaps, totalDistance: totalDistance, usableWidth: usableWidth)

                    HStack(spacing: 2) {
                        ForEach(Array(validLaps.enumerated()), id: \.element.id) { idx, lap in
                            let distanceFrac = (lap.distance ?? 0) / totalDistance
                            let barWidth = max(distanceFrac * usableWidth, 2)

                            // Equal-value double-fallback: when all intensities are nil,
                            // override to nil (→ green) and full height.
                            let intensityForRender: Int? = isAllNil ? nil : intensities[idx]
                            let heightFrac: CGFloat = isAllNil ? 1.0 : heightFractionFor(pct: intensities[idx])
                            let barHeight = max(heightFrac * graphHeight, 4)

                            ZStack {
                                // Bar fill
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.intensity(for: intensityForRender, isRecovery: false))
                                    .frame(width: barWidth, height: barHeight)

                                // Selected-bar outline (divergence from WorkoutGraphView)
                                if idx == selectedLapIndex {
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color.primary, lineWidth: 1.5)
                                        .frame(width: barWidth, height: barHeight)
                                }
                            }
                            .frame(width: barWidth, height: graphHeight, alignment: .bottom)
                            // Dim all other bars when a selection is active
                            .opacity(selectedLapIndex.map { $0 == idx ? 1.0 : 0.45 } ?? 1.0)
                        }
                    }
                    .frame(height: graphHeight)
                    // Drag gesture — mirrors WorkoutGraphView.swift pattern (lines 77-110).
                    // Nearest-bar lookup uses precomputed barCenterXs (no O(n) in handler).
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x
                                if let index = barCenterXs.indices.min(by: {
                                    abs(barCenterXs[$0] - x) < abs(barCenterXs[$1] - x)
                                }) {
                                    withAnimation(.easeInOut(duration: 0.1)) {
                                        tooltipXOffset = barCenterXs[index]
                                        selectedLapIndex = index
                                    }
                                }
                            }
                            .onEnded { _ in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedLapIndex = nil
                                    tooltipXOffset = 0
                                }
                            }
                    )

                    // Capture geometry width so the VStack-level overlay can clamp the tooltip.
                    Color.clear
                        .frame(width: 0, height: 0)
                        .onAppear { graphWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, newValue in graphWidth = newValue }
                }
                .frame(height: graphHeight)
                // Floating tooltip overlay at VStack level — not clipped by graph frame.
                // `.overlay(alignment: .topLeading)` so `.position(x:y:)` is relative to this view.
                .overlay(alignment: .topLeading) {
                    if let index = selectedLapIndex, index < validLaps.count {
                        lapTooltipView(
                            for: validLaps[index],
                            lapNumber: index + 1,
                            intensity: isAllNil ? nil : intensities[index]
                        )
                        .fixedSize()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        // Center on the selected bar, clamp x to keep bubble inside graph bounds.
                        // y: -60 places the bottom edge of the 4-line bubble (~80–100pt tall) ~10pt
                        // above the chart top — avoids the overlap that y: -28 caused.
                        .position(
                            x: min(max(tooltipXOffset, tooltipHalfWidth), graphWidth - tooltipHalfWidth),
                            y: -60
                        )
                    }
                }
                .onDisappear {
                    selectedLapIndex = nil
                    tooltipXOffset = 0
                }

                // X-axis distance labels: 0%, 25%, 50%, 75%, 100% of total distance.
                // Uses formatDistance (km) per spec — not compact.
                distanceAxisView(totalDistance: totalDistance)
            }
        } // end if validLaps.count >= 2
    }

    // MARK: - Tooltip

    /// Floating tooltip bubble showing per-lap detail.
    ///
    /// Layout (top to bottom):
    /// - "LAP N" — uppercase caption, secondary color
    /// - Primary metric (sport-specific, large semibold tabular)
    /// - Duration · distance compact
    /// - Avg HR (omitted if nil)
    private func lapTooltipView(
        for lap: StravaLap,
        lapNumber: Int,
        intensity: Int?
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {

            // Line 1: lap label
            Text("LAP \(lapNumber)")
                .font(.caption)
                .foregroundColor(.secondary)

            // Line 2: primary metric — sport-specific, large semibold tabular-numeric
            // Bike: speed if available, watts if not, omit if neither.
            if let metric = primaryMetric(for: lap) {
                Text(metric)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }

            // Line 3: duration · distance
            Text("\(ActivityFormatters.formatDuration(seconds: lap.elapsedTime)) · \(ActivityFormatters.formatDistanceCompact(meters: lap.distance ?? 0))")
                .font(.caption)
                .foregroundColor(.secondary)

            // Line 4: avg HR — omit entirely when nil
            if let hr = lap.averageHeartrate {
                Text("\(Int(hr)) bpm avg")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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

    /// Returns the sport-specific primary metric string for the tooltip, or nil to omit the line.
    ///
    /// Sport routing:
    /// - Run: running pace `/km`
    /// - Bike: avg speed (km/h) if available; avg watts if speed unavailable and watts > 0; omit otherwise
    /// - Swim: swim pace `/100m`
    /// - Default: running pace (safe fallback for unknown sports)
    private func primaryMetric(for lap: StravaLap) -> String? {
        switch sport.lowercased() {
        case "run":
            guard let speed = lap.averageSpeed, speed > 0 else { return "—" }
            return ActivityFormatters.formatPaceRunPerKm(speedMps: speed)

        case "bike":
            if let speed = lap.averageSpeed {
                return ActivityFormatters.formatSpeedKmh(speedMps: speed)
            } else if let watts = lap.averageWatts, watts > 0 {
                return ActivityFormatters.formatPower(watts: watts)
            } else {
                return nil // omit line 2 entirely
            }

        case "swim":
            guard let speed = lap.averageSpeed, speed > 0 else { return "—" }
            return ActivityFormatters.formatPaceSwimPer100m(speedMps: speed)

        default:
            // Unknown sport — fall back to run pace as the most universally readable metric.
            guard let speed = lap.averageSpeed, speed > 0 else { return "—" }
            return ActivityFormatters.formatPaceRunPerKm(speedMps: speed)
        }
    }

    // MARK: - X-Axis

    /// Renders 5 distance labels along the axis: 0%, 25%, 50%, 75%, 100% of total distance.
    /// Uses `formatDistance(meters:)` (km, not compact) per spec.
    /// ZStack + .position(x:) mirrors `WorkoutGraphView.timeAxisView` to anchor each label's
    /// center at its true axis x-position, preventing drift with variable-width labels.
    private func distanceAxisView(totalDistance: Double) -> some View {
        let fractions: [Double] = [0.0, 0.25, 0.50, 0.75, 1.0]
        let labels: [String] = fractions.map { ActivityFormatters.formatDistance(meters: totalDistance * $0) }
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                ForEach(labels.indices, id: \.self) { i in
                    let frac = fractions[i]
                    Text(labels[i])
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize()
                        .position(
                            x: CGFloat(frac) * geo.size.width,
                            y: axisHeight / 2
                        )
                }
            }
        }
        .frame(height: axisHeight)
    }

    /// Fixed height for the distance-axis label row.
    private let axisHeight: CGFloat = 20

    // MARK: - Bar Center Helper

    /// Computes bar center x-positions in O(n) via a single forward scan.
    ///
    /// Extracted from the GeometryReader closure so the imperative for-loop doesn't
    /// conflict with the surrounding @ViewBuilder result builder.
    private func barCenters(for laps: [StravaLap], totalDistance: Double, usableWidth: CGFloat) -> [CGFloat] {
        let barWidths: [CGFloat] = laps.map { lap in
            max(CGFloat((lap.distance ?? 0) / totalDistance) * usableWidth, 2)
        }
        var centers: [CGFloat] = []
        var cursor: CGFloat = 0
        for (i, w) in barWidths.enumerated() {
            centers.append(cursor + w / 2)
            cursor += w
            if i < barWidths.count - 1 { cursor += 2 } // inter-bar spacing
        }
        return centers
    }

    // MARK: - Height Bucket Helper

    /// Maps intensity percentage to a height fraction of `graphHeight`.
    ///
    /// Continuous linear mapping (NOT the bucket scheme used by `WorkoutShape`):
    /// the completed graph shows actual execution where small lap-to-lap deltas
    /// are the signal. Buckets clustered the entire 60–80% range to one height,
    /// flattening visible variation (e.g. a steady-state run with all laps in
    /// that band rendered as identical bars). Linear preserves differentiation.
    ///
    /// - 30% → 0.20 (floor)
    /// - 110% → 1.00 (ceiling)
    /// - Linear interpolation between, clamped to [0.20, 1.00].
    /// - nil or 0 intensity → 30% floor (visible but clearly low).
    ///
    /// `WorkoutShape` keeps the bucket scheme since the planned graph encodes
    /// prescribed training zones — different visual language by design.
    private func heightFractionFor(pct: Int?) -> CGFloat {
        guard let pct = pct, pct > 0 else { return 0.30 }
        let normalized = (Double(pct) - 30.0) / 80.0
        let clamped = min(max(normalized, 0.0), 1.0)
        return CGFloat(0.20 + clamped * 0.80)
    }
}

// MARK: - Previews

/// 1. Run with VMA set — canonical VO2 5×3' workout.
///    Warm-up at 4:30/km, 5 reps at 3:30/km, recoveries at 5:30/km, cool-down at 5:00/km.
///    Expected: alternating tall-red (VO2 reps) and short-green (recoveries) bars.
#Preview("Run — VMA set (VO2 5×3')") {
    // Speed in m/s: 4:30/km ≈ 3.70, 3:30/km ≈ 4.76, 5:30/km ≈ 3.03, 5:00/km ≈ 3.33
    let vma = 18.5 // km/h = 5.14 m/s
    let lapData: [(speed: Double, dist: Double, elapsed: Int, hr: Double)] = [
        (speed: 3.70, dist: 1000, elapsed: 270, hr: 140),  // warm-up 4:30/km
        (speed: 4.76, dist: 700,  elapsed: 180, hr: 175),  // rep 1 3:30/km
        (speed: 3.03, dist: 450,  elapsed: 180, hr: 148),  // recovery 5:30/km
        (speed: 4.76, dist: 700,  elapsed: 180, hr: 177),  // rep 2
        (speed: 3.03, dist: 450,  elapsed: 180, hr: 149),  // recovery
        (speed: 4.76, dist: 700,  elapsed: 180, hr: 178),  // rep 3
        (speed: 3.03, dist: 450,  elapsed: 180, hr: 151),  // recovery
        (speed: 4.76, dist: 700,  elapsed: 180, hr: 179),  // rep 4
        (speed: 3.03, dist: 450,  elapsed: 180, hr: 152),  // recovery
        (speed: 4.76, dist: 700,  elapsed: 180, hr: 180),  // rep 5
        (speed: 3.03, dist: 450,  elapsed: 180, hr: 155),  // recovery
        (speed: 3.33, dist: 800,  elapsed: 240, hr: 135),  // cool-down 5:00/km
    ]
    let laps = lapData.enumerated().map { i, d in
        StravaLap(
            id: UUID(),
            activityId: UUID(),
            lapIndex: i,
            elapsedTime: d.elapsed,
            movingTime: d.elapsed,
            distance: d.dist,
            averageSpeed: d.speed,
            averageCadence: nil,
            averageWatts: nil,
            averageHeartrate: d.hr,
            maxHeartrate: d.hr + 10,
            startIndex: nil,
            endIndex: nil
        )
    }
    return CompletedSegmentGraphView(
        laps: laps, sport: "run",
        vma: vma, ftp: nil, css: nil, maxHr: nil
    )
    .padding()
    .background(
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    )
    .padding()
}

/// 2. Bike — no power, no FTP. Session-normalized HR.
///    Expected: bars with varying mid-tone heights, height driven by HR spread.
#Preview("Bike — no power, no FTP (HR-normalized)") {
    let laps = [
        StravaLap(id: UUID(), activityId: UUID(), lapIndex: 0, elapsedTime: 600, movingTime: 590,
                  distance: 4500, averageSpeed: 7.5, averageCadence: 85, averageWatts: 0,
                  averageHeartrate: 130, maxHeartrate: 145, startIndex: nil, endIndex: nil),
        StravaLap(id: UUID(), activityId: UUID(), lapIndex: 1, elapsedTime: 580, movingTime: 570,
                  distance: 4600, averageSpeed: 7.9, averageCadence: 88, averageWatts: nil,
                  averageHeartrate: 145, maxHeartrate: 158, startIndex: nil, endIndex: nil),
        StravaLap(id: UUID(), activityId: UUID(), lapIndex: 2, elapsedTime: 560, movingTime: 550,
                  distance: 4700, averageSpeed: 8.4, averageCadence: 90, averageWatts: nil,
                  averageHeartrate: 160, maxHeartrate: 170, startIndex: nil, endIndex: nil),
        StravaLap(id: UUID(), activityId: UUID(), lapIndex: 3, elapsedTime: 590, movingTime: 580,
                  distance: 4550, averageSpeed: 7.7, averageCadence: 87, averageWatts: nil,
                  averageHeartrate: 150, maxHeartrate: 162, startIndex: nil, endIndex: nil),
    ]
    return CompletedSegmentGraphView(
        laps: laps, sport: "bike",
        vma: nil, ftp: nil, css: nil, maxHr: 190
    )
    .padding()
    .background(
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    )
    .padding()
}

/// 3. Swim with CSS set — 6 × 100m laps at varying speeds.
///    CSS = 90 s/100m ≈ 1.11 m/s.
///    Expected: bars with CSS-relative heights; faster laps taller and more orange/red.
#Preview("Swim — CSS set (6 × 100 m)") {
    let cssSeconds = 90 // 90 s/100m CSS
    // Speeds in m/s: 100m / seconds
    let lapData: [(speed: Double, hr: Double)] = [
        (speed: 100.0/110, hr: 130), // warm-up, slower than CSS
        (speed: 100.0/95,  hr: 148), // moderate
        (speed: 100.0/88,  hr: 162), // above CSS — harder
        (speed: 100.0/85,  hr: 170), // harder
        (speed: 100.0/92,  hr: 155), // moderate
        (speed: 100.0/108, hr: 132), // cool-down
    ]
    let laps = lapData.enumerated().map { i, d in
        StravaLap(
            id: UUID(),
            activityId: UUID(),
            lapIndex: i,
            elapsedTime: Int(100.0 / d.speed),
            movingTime: Int(100.0 / d.speed),
            distance: 100,
            averageSpeed: d.speed,
            averageCadence: nil,
            averageWatts: nil,
            averageHeartrate: d.hr,
            maxHeartrate: d.hr + 8,
            startIndex: nil,
            endIndex: nil
        )
    }
    return CompletedSegmentGraphView(
        laps: laps, sport: "swim",
        vma: nil, ftp: nil, css: cssSeconds, maxHr: nil
    )
    .padding()
    .background(
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    )
    .padding()
}

/// 4. All-nil edge case — equal-value double-fallback.
///    5 run laps all at the same speed (4.0 m/s), vma = nil.
///    Calculator returns all-nil → renderer must show 5 equal-tall GREEN bars at 100% height.
///    This is the visual proof of the calculator/renderer contract.
#Preview("Run — All-nil fallback (uniform speed, no VMA)") {
    let laps = (0..<5).map { i in
        StravaLap(
            id: UUID(),
            activityId: UUID(),
            lapIndex: i,
            elapsedTime: 300,
            movingTime: 295,
            distance: 1200,
            averageSpeed: 4.0, // all identical → equal-value → all-nil from calculator
            averageCadence: nil,
            averageWatts: nil,
            averageHeartrate: 155,
            maxHeartrate: 165,
            startIndex: nil,
            endIndex: nil
        )
    }
    return CompletedSegmentGraphView(
        laps: laps, sport: "run",
        vma: nil, ftp: nil, css: nil, maxHr: nil
    )
    .padding()
    .background(
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    )
    .padding()
}
