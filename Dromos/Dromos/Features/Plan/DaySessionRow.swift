//
//  DaySessionRow.swift
//  Dromos
//
//  Created by Emmanuel Breard on 01/02/2026.
//

import SwiftUI

/// Row component for displaying a day's sessions or rest day.
/// Shows day header (abbreviation + date), session rows, or rest day indicator.
/// Sessions are tappable to expand/collapse workout details (steps + intensity graph).
struct DaySessionRow: View {
    let weekday: Weekday
    let date: Date
    let sessions: [PlanSession]
    let isRestDay: Bool
    /// IDs of currently expanded sessions.
    let expandedSessionIDs: Set<UUID>
    /// Athlete metrics for workout detail display.
    var ftp: Int? = nil
    var vma: Double? = nil
    var css: Int? = nil
    /// Callback when a session is tapped to expand/collapse.
    let onToggleExpand: (UUID) -> Void

    /// Shared workout library for template lookups and segment operations.
    private let workoutLibrary = WorkoutLibraryService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Day header: abbreviation + calendar date
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(weekday.abbreviation)
                        .font(.headline)
                    Text(dayNumber)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 4)

            // Content: rest day or sessions
            if isRestDay && sessions.isEmpty {
                restDayRow
            } else {
                ForEach(sessions) { session in
                    sessionRow(session: session)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Day Header

    /// Day number extracted from date (e.g., "27").
    private var dayNumber: String {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        return String(day)
    }

    // MARK: - Rest Day Row

    /// Rest day row with bed icon and label.
    private var restDayRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "bed.double")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Rest day")
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Session Row

    /// Session row with sport icon, name, duration, and optional expanded details.
    private func sessionRow(session: PlanSession) -> some View {
        let isExpanded = expandedSessionIDs.contains(session.id)

        return VStack(alignment: .leading, spacing: 0) {
            // Compact row (always visible)
            HStack(spacing: 12) {
                // Sport icon
                Image(systemName: session.sportIcon)
                    .font(.title3)
                    .foregroundColor(session.sportColor)

                // Session name
                Text(session.displayName)
                    .font(.body)

                Spacer()

                // Brick indicator (if applicable)
                if session.isBrick {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Duration
                Text(session.formattedDuration)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Chevron indicator
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                onToggleExpand(session.id)
            }

            // Expanded details (workout steps + graph)
            if isExpanded {
                expandedContent(for: session)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Expanded Content

    /// Renders workout steps, intensity graph, or swim distance for an expanded session.
    @ViewBuilder
    private func expandedContent(for session: PlanSession) -> some View {
        let template = workoutLibrary.template(for: session.templateId)

        VStack(alignment: .leading, spacing: 12) {
            if let template = template {
                let showSteps = session.shouldShowWorkoutSteps(template: template)

                // Workout steps (skip for simple swims)
                if showSteps {
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

                    // Intensity graph (same guard as steps)
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
                } else if session.sport.lowercased() == "swim" {
                    // Simple swim — show distance only
                    if let distance = workoutLibrary.swimDistance(for: session.templateId) {
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
            }
        }
    }
}

#Preview("Session") {
    let session = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Monday",
        sport: "swim",
        type: "Easy",
        templateId: "template-1",
        durationMinutes: 60,
        isBrick: false,
        notes: nil,
        orderInDay: 0,
        feedback: nil,
        matchedActivityId: nil
    )

    DaySessionRow(
        weekday: .monday,
        date: Date(),
        sessions: [session],
        isRestDay: false,
        expandedSessionIDs: [],
        onToggleExpand: { _ in }
    )
    .padding()
}

#Preview("Rest Day") {
    DaySessionRow(
        weekday: .tuesday,
        date: Date(),
        sessions: [],
        isRestDay: true,
        expandedSessionIDs: [],
        onToggleExpand: { _ in }
    )
    .padding()
}

#Preview("Multiple Sessions") {
    let session1 = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Friday",
        sport: "bike",
        type: "Easy",
        templateId: "template-1",
        durationMinutes: 50,
        isBrick: false,
        notes: nil,
        orderInDay: 0,
        feedback: nil,
        matchedActivityId: nil
    )

    let session2 = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Friday",
        sport: "swim",
        type: "Tempo",
        templateId: "template-2",
        durationMinutes: 60,
        isBrick: true,
        notes: nil,
        orderInDay: 1,
        feedback: nil,
        matchedActivityId: nil
    )

    DaySessionRow(
        weekday: .friday,
        date: Date(),
        sessions: [session1, session2],
        isRestDay: false,
        expandedSessionIDs: [],
        onToggleExpand: { _ in }
    )
    .padding()
}

// MARK: - PlanSession Shared Helpers

extension PlanSession {
    /// Sport color for UI display.
    var sportColor: Color {
        switch sport.lowercased() {
        case "swim":
            return .cyan
        case "bike":
            return .green
        case "run":
            return .orange
        default:
            return .primary
        }
    }

    /// Returns false for simple swims (1 segment, no repeats) — show distance only.
    func shouldShowWorkoutSteps(template: WorkoutTemplate) -> Bool {
        if sport.lowercased() == "swim" {
            if template.segments.count == 1,
               template.segments.first?.repeats == nil {
                return false
            }
        }
        return true
    }

    /// Formats distance in meters to a readable string (e.g., "1.5 km", "800 m").
    static func formatDistance(_ meters: Int) -> String {
        if meters >= 1000 {
            let km = Double(meters) / 1000.0
            if km.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(km)) km"
            } else {
                return String(format: "%.1f km", km)
            }
        } else {
            return "\(meters) m"
        }
    }
}
