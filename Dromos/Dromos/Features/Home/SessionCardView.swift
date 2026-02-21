//
//  SessionCardView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 01/02/2026.
//

import SwiftUI

/// Rich session card for the Home tab.
/// Displays sport icon, workout name, duration, type tag, workout steps, and intensity graph.
struct SessionCardView: View {
    let session: PlanSession
    let swimDistance: Int?
    let template: WorkoutTemplate?
    let ftp: Int?
    let vma: Double?
    let css: Int?
    
    /// Shared workout library service for segment operations
    private let workoutLibrary = WorkoutLibraryService.shared
    
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
                    
                    // Duration
                    Text(session.formattedDuration)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
            
            // Row 3: Workout steps (only if template has >1 segment or has repeats)
            if let template = template, session.shouldShowWorkoutSteps(template: template) {
                let steps = workoutLibrary.stepSummaries(
                    for: session.templateId,
                    sport: session.sport,
                    ftp: ftp,
                    vma: vma,
                    css: css
                )
                
                if !steps.isEmpty {
                    WorkoutStepsView(steps: steps)
                }
            }
            
            // Row 4: Intensity graph (for all sessions with a template)
            if template != nil {
                let segments = workoutLibrary.flattenedSegments(for: session.templateId)
                
                if !segments.isEmpty {
                    let totalDuration = segments.reduce(0) { $0 + $1.durationMinutes }
                    WorkoutGraphView(
                        segments: segments,
                        totalDurationMinutes: totalDuration,
                        sport: session.sport,
                        ftp: ftp,
                        vma: vma
                    )
                }
            }
            
            // Row 5: Swim distance (only for simple swims without steps/graph)
            if session.sport.lowercased() == "swim",
               let distance = swimDistance,
               template.map({ session.shouldShowWorkoutSteps(template: $0) }) != true {
                HStack(spacing: 6) {
                    Image(systemName: "ruler")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Est. Distance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(PlanSession.formatDistance(distance))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Race Day Card

/// Celebratory card for race days.
/// Shows trophy icon with "Race Day" label and optional race objective (e.g., "Olympic", "Ironman 70.3").
struct RaceDayCardView: View {
    let raceObjective: String?

    var body: some View {
        HStack(spacing: 12) {
            // Trophy icon
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
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
        orderInDay: 0
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
    
    return SessionCardView(
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
        orderInDay: 0
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
    
    return SessionCardView(
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
        orderInDay: 0
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
    
    return SessionCardView(
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
        orderInDay: 0
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
    
    return SessionCardView(
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
        orderInDay: 0
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
    
    return SessionCardView(
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
        orderInDay: 0
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
    
    return SessionCardView(
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
