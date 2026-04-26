//
//  SessionCardView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 01/02/2026.
//

import SwiftUI

/// Rich session card for the Home tab.
/// Displays sport icon, workout name, duration, type tag, workout steps, and intensity graph.
/// Renders visual completion state via a colored left border and optional dimming.
struct SessionCardView: View {
    let session: PlanSession
    let swimDistance: Int?
    let template: WorkoutTemplate?
    let ftp: Int?
    let vma: Double?
    let css: Int?
    /// Max heart rate in bpm (for HR-zone targets). DRO-213 Phase 5.
    var maxHr: Int? = nil
    /// Completion status drives visual treatment: green border (completed), red border + dim (missed), no change (planned).
    var completionStatus: SessionCompletionStatus = .planned

    /// Controls visibility of the planned workout disclosure (completed cards only).
    @State private var showPlannedWorkout = false

    /// Controls whether coach feedback text is fully expanded (default: collapsed to 2 lines).
    @State private var showFeedback = false

    /// Shared workout library service for segment operations
    private let workoutLibrary = WorkoutLibraryService.shared

    // MARK: - Computed visual properties

    /// Left border color: green for completed, red for missed, nil for planned (no border).
    private var borderColor: Color? {
        switch completionStatus {
        case .completed: return .green
        case .missed: return .red
        case .planned: return nil
        }
    }

    /// Content opacity: 0.5 for missed sessions to visually de-emphasize them.
    private var contentOpacity: Double {
        if case .missed = completionStatus { return 0.5 }
        return 1.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: Sport icon + name + duration + type badge
            HStack(spacing: 12) {
                // Sport emoji with colored background
                Text(session.sportEmoji)
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .background(session.sportColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    // Workout name
                    Text(session.displayName)
                        .font(.headline)

                    // Duration (+ swim distance when available)
                    if session.sport.lowercased() == "swim", let distance = swimDistance, distance > 0 {
                        Text("\(session.formattedDuration) · \(PlanSession.formatDistance(distance))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text(session.formattedDuration)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Type tag chip (moved to top-right)
                Text(session.type.uppercased())
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(session.typeColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(session.typeColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Row 2: Brick indicator (if applicable)
            if session.isBrick {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption)
                    Text("BRICK")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
            }
            
            if case .completed(let activity) = completionStatus {
                // COMPLETED LAYOUT: actual Strava data is primary content, planned workout is collapsible.

                Divider()

                // Actual metrics always visible for completed sessions
                ActualMetricsView(activity: activity)

                // GPS map when a non-empty encoded polyline is available
                if let polyline = activity.summaryPolyline, !polyline.isEmpty {
                    StravaRouteMapView(encodedPolyline: polyline)
                }

                // Coach feedback — always visible when present, truncated to 2 lines by default
                if let feedback = session.feedback {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "message.fill")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Coach feedback")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Text(feedback)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(showFeedback ? nil : 2)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showFeedback.toggle()
                            }
                        } label: {
                            Text(showFeedback ? "Show less" : "Show more")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // "Planned workout" disclosure — only when a template exists
                if template != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showPlannedWorkout.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.clipboard")
                                .font(.caption)
                            Text("Planned workout")
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .rotationEffect(.degrees(showPlannedWorkout ? 90 : 0))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    if showPlannedWorkout {
                        plannedWorkoutContent
                    }
                }

            } else {
                // PLANNED / MISSED LAYOUT: workout detail is always visible (no disclosure).
                plannedWorkoutContent
            }
        }
        .padding(16)
        // NB: opacity before background intentionally dims content only, not the card fill.
        .opacity(contentOpacity)
        .background(Color.cardSurface)
        // Left border overlay: a 4pt colored rectangle anchored to the leading edge.
        // clipShape applied AFTER overlay so the border inherits the card's rounded corners.
        .overlay(alignment: .leading) {
            if let color = borderColor {
                Rectangle()
                    .fill(color)
                    .frame(width: 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Planned Workout Content

    /// Shared planned workout rendering used by both the completed-card disclosure and
    /// the always-visible planned/missed layout. Contains coaching notes, workout steps,
    /// intensity graph, and swim distance (swim-only, simple sessions).
    @ViewBuilder
    private var plannedWorkoutContent: some View {
        // Coaching notes from plan (displayed above workout steps when present).
        // These come from plan_sessions.notes and carry pre-session coaching guidance.
        if let notes = session.notes, !notes.isEmpty {
            Text(notes)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)
        }

        // DRO-213 Phase 5: dual-path renderer reads session.structure first; falls back to template lookup.
        // Steps + graph share the same `shouldShow` predicate so simple swims hide both consistently
        // (resolves the prior inconsistency where SessionCardView showed graph but DaySessionRow hid it).
        let canRender = session.structure != nil || template != nil
        if canRender, workoutLibrary.shouldShowWorkoutSteps(for: session) {
            let steps = workoutLibrary.stepSummaries(
                for: session,
                ftp: ftp, vma: vma, css: css, maxHr: maxHr
            )
            if !steps.isEmpty {
                WorkoutStepsView(steps: steps)
            }

            let segments = workoutLibrary.flattenedSegments(
                for: session,
                ftp: ftp, vma: vma, css: css, maxHr: maxHr
            )
            if !segments.isEmpty {
                let totalDuration = segments.reduce(0) { $0 + $1.durationMinutes }
                WorkoutGraphView(
                    segments: segments,
                    totalDurationMinutes: totalDuration,
                    sport: session.sport,
                    ftp: ftp,
                    vma: vma,
                    css: css,
                    maxHr: maxHr
                )
            }
        }
    }

}

// MARK: - Rest Day Card

/// Simple card for rest days.
/// Shows bed icon with "Rest Day" label.
struct RestDayCardView: View {
    var body: some View {
        HStack(spacing: 12) {
            // Bed icon
            Image(systemName: "bed.double.fill")
                .font(.title2)
                .foregroundColor(.secondary)
                .frame(width: 40, height: 40)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            
            Text("Rest Day")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(16)
        .background(Color.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Race Day Card

/// Celebratory card for race days.
/// When a race template is provided, renders individual race legs (swim/T1/bike/T2/run)
/// with their cues and durations. Falls back to a simple header-only display otherwise.
struct RaceDayCardView: View {
    let raceObjective: String?
    /// Optional workout template carrying race leg segments (from WorkoutLibrary race array).
    var template: WorkoutTemplate? = nil
    /// Optional coaching/strategy notes for race day (from plan_sessions.notes).
    var notes: String? = nil

    private let workoutLibrary = WorkoutLibraryService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: trophy icon + race day title + objective subtitle
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                    .frame(width: 40, height: 40)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Race Day")
                        .font(.headline)
                        .foregroundColor(.orange)

                    if let objective = raceObjective {
                        Text(objective)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            // Race legs breakdown (only when a template with segments is available)
            if let template = template {
                Divider()
                raceLegsList(template: template)
            }

            // Session notes: race strategy, target times, pacing guidance
            if let notes = notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Race Legs List

    /// Renders each race segment (swim, T1, bike, T2, run) as a labelled row
    /// with a sport-appropriate icon, human-readable name, duration, and cue text.
    @ViewBuilder
    private func raceLegsList(template: WorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(template.segments.enumerated()), id: \.offset) { _, segment in
                HStack(spacing: 12) {
                    // Sport icon inferred from segment label / cue
                    legIcon(for: segment)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(legName(for: segment))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Spacer()

                            if let duration = segment.durationMinutes {
                                Text(formatLegDuration(duration))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Cue carries pacing / strategy notes for this leg
                        if let cue = segment.cue, !cue.isEmpty {
                            Text(cue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// Returns an SF Symbol image appropriate for the race leg based on its label and cue.
    private func legIcon(for segment: WorkoutSegment) -> Image {
        let cue = (segment.cue ?? "").lowercased()
        let label = segment.label.lowercased()

        // Transition segments
        if label == "recovery" || cue.contains("t1") || cue.contains("t2") {
            return Image(systemName: "arrow.triangle.2.circlepath")
        }
        // Discipline-specific icons
        if cue.contains("swim") { return Image(systemName: "figure.pool.swim") }
        if cue.contains("bike") { return Image(systemName: "bicycle") }
        if cue.contains("run") || cue.contains("marathon") { return Image(systemName: "figure.run") }

        // Distance-based fallback: <5 km → swim, >40 km → marathon run, >20 km → bike
        if let dist = segment.distanceMeters {
            if dist < 5000  { return Image(systemName: "figure.pool.swim") }
            if dist > 40000 { return Image(systemName: "figure.run") }
            if dist > 20000 { return Image(systemName: "bicycle") }
            return Image(systemName: "figure.run")
        }

        return Image(systemName: "flag.checkered")
    }

    /// Derives a human-readable leg name from the segment's cue or label.
    private func legName(for segment: WorkoutSegment) -> String {
        let cue = (segment.cue ?? "").lowercased()

        if cue.contains("t1")       { return "T1" }
        if cue.contains("t2")       { return "T2" }
        if cue.contains("swim")     { return "Swim" }
        if cue.contains("bike")     { return "Bike" }
        if cue.contains("marathon") { return "Marathon" }
        if cue.contains("run")      { return "Run" }

        return segment.label.capitalized
    }

    /// Converts a minute value to a compact human-readable string (e.g., "1h30", "45 min").
    private func formatLegDuration(_ minutes: Int) -> String {
        let totalMinutes = minutes
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins  = totalMinutes % 60
            if mins == 0 { return "\(hours)h" }
            return "\(hours)h\(String(format: "%02d", mins))"
        }
        return "\(totalMinutes) min"
    }
}

// MARK: - Previews

#Preview("Session Card - Bike Intervals") {
    let session = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Wednesday",
        sport: "bike",
        type: "Intervals",
        templateId: "BIKE_Intervals_01",
        durationMinutes: 60,
        isBrick: false,
        notes: nil,
        orderInDay: 0,
        feedback: nil,
        matchedActivityId: nil
    )
    
    // Mock template using convenience initializer
    let workSegment = WorkoutSegment(
        label: "work",
        durationMinutes: 6,
        ftpPct: 95
    )
    
    let warmupSegment = WorkoutSegment(
        label: "warmup",
        durationMinutes: 15,
        ftpPct: 50
    )
    
    let cooldownSegment = WorkoutSegment(
        label: "cooldown",
        durationMinutes: 10,
        ftpPct: 45
    )
    
    let template = WorkoutTemplate(
        templateId: "BIKE_Intervals_01",
        segments: [warmupSegment, workSegment, cooldownSegment]
    )
    
    SessionCardView(
        session: session,
        swimDistance: nil,
        template: template,
        ftp: 250,
        vma: nil,
        css: nil
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Session Card - Run Tempo") {
    let session = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Tuesday",
        sport: "run",
        type: "Tempo",
        templateId: "RUN_Tempo_01",
        durationMinutes: 40,
        isBrick: false,
        notes: nil,
        orderInDay: 0,
        feedback: nil,
        matchedActivityId: nil
    )
    
    // Mock template using convenience initializer
    let warmupSegment = WorkoutSegment(
        label: "warmup",
        durationMinutes: 10,
        masPct: 60
    )
    
    let tempoSegment = WorkoutSegment(
        label: "tempo",
        durationMinutes: 20,
        masPct: 85
    )
    
    let cooldownSegment = WorkoutSegment(
        label: "cooldown",
        durationMinutes: 10,
        masPct: 55
    )
    
    let template = WorkoutTemplate(
        templateId: "RUN_Tempo_01",
        segments: [warmupSegment, tempoSegment, cooldownSegment]
    )
    
    SessionCardView(
        session: session,
        swimDistance: nil,
        template: template,
        ftp: nil,
        vma: 15.0,
        css: nil
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Session Card - Swim Intervals") {
    let session = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Monday",
        sport: "swim",
        type: "Intervals",
        templateId: "SWIM_Intervals_01",
        durationMinutes: 45,
        isBrick: false,
        notes: nil,
        orderInDay: 0,
        feedback: nil,
        matchedActivityId: nil
    )
    
    // Mock complex swim template (intervals with different paces)
    let warmupSegment = WorkoutSegment(
        label: "warmup",
        durationMinutes: nil,
        distanceMeters: 200,
        pace: "easy"
    )
    
    let workSegment = WorkoutSegment(
        label: "work",
        durationMinutes: nil,
        distanceMeters: 100,
        pace: "hard"
    )
    
    let recoverySegment = WorkoutSegment(
        label: "recovery",
        durationMinutes: nil,
        distanceMeters: 50,
        pace: "easy"
    )
    
    let repeatBlock = WorkoutSegment(
        label: "main set",
        repeats: 4,
        segments: [workSegment],
        recovery: recoverySegment
    )
    
    let cooldownSegment = WorkoutSegment(
        label: "cooldown",
        durationMinutes: nil,
        distanceMeters: 200,
        pace: "easy"
    )
    
    let template = WorkoutTemplate(
        templateId: "SWIM_Intervals_01",
        segments: [warmupSegment, repeatBlock, cooldownSegment]
    )
    
    SessionCardView(
        session: session,
        swimDistance: 1000,
        template: template,
        ftp: nil,
        vma: nil,
        css: 105
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Session Card - Swim (Simple)") {
    let session = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Monday",
        sport: "swim",
        type: "Easy",
        templateId: "SWIM_Easy_01",
        durationMinutes: 45,
        isBrick: false,
        notes: nil,
        orderInDay: 0,
        feedback: nil,
        matchedActivityId: nil
    )
    
    // Mock simple swim template (1 segment) using convenience initializer
    let swimSegment = WorkoutSegment(
        label: "continuous",
        durationMinutes: 45,
        distanceMeters: 1800
    )
    
    let template = WorkoutTemplate(
        templateId: "SWIM_Easy_01",
        segments: [swimSegment]
    )
    
    SessionCardView(
        session: session,
        swimDistance: 1800,
        template: template,
        ftp: nil,
        vma: nil,
        css: 105
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Session Card - Long Ride (3h+)") {
    let session = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Saturday",
        sport: "bike",
        type: "Easy",
        templateId: "BIKE_LongRide_01",
        durationMinutes: 180,
        isBrick: false,
        notes: nil,
        orderInDay: 0,
        feedback: nil,
        matchedActivityId: nil
    )
    
    // Mock long ride template
    let warmupSegment = WorkoutSegment(
        label: "warmup",
        durationMinutes: 20,
        ftpPct: 50
    )
    
    let steadySegment = WorkoutSegment(
        label: "steady",
        durationMinutes: 150,
        ftpPct: 70
    )
    
    let cooldownSegment = WorkoutSegment(
        label: "cooldown",
        durationMinutes: 10,
        ftpPct: 45
    )
    
    let template = WorkoutTemplate(
        templateId: "BIKE_LongRide_01",
        segments: [warmupSegment, steadySegment, cooldownSegment]
    )
    
    SessionCardView(
        session: session,
        swimDistance: nil,
        template: template,
        ftp: 250,
        vma: nil,
        css: nil
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Session Card - No FTP/VMA (Percentages)") {
    let session = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Wednesday",
        sport: "bike",
        type: "Intervals",
        templateId: "BIKE_Intervals_01",
        durationMinutes: 60,
        isBrick: false,
        notes: nil,
        orderInDay: 0,
        feedback: nil,
        matchedActivityId: nil
    )
    
    // Mock template using convenience initializer
    let workSegment = WorkoutSegment(
        label: "work",
        durationMinutes: 6,
        ftpPct: 95
    )
    
    let warmupSegment = WorkoutSegment(
        label: "warmup",
        durationMinutes: 15,
        ftpPct: 50
    )
    
    let cooldownSegment = WorkoutSegment(
        label: "cooldown",
        durationMinutes: 10,
        ftpPct: 45
    )
    
    let template = WorkoutTemplate(
        templateId: "BIKE_Intervals_01",
        segments: [warmupSegment, workSegment, cooldownSegment]
    )
    
    SessionCardView(
        session: session,
        swimDistance: nil,
        template: template,
        ftp: nil, // No FTP set
        vma: nil,
        css: nil
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
