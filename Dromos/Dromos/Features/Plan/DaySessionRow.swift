//
//  DaySessionRow.swift
//  Dromos
//
//  Created by Emmanuel Breard on 01/02/2026.
//

import SwiftUI

/// Row component for displaying a day's sessions or rest day.
/// Shows day header (abbreviation + date), session rows, or rest day indicator.
struct DaySessionRow: View {
    let weekday: Weekday
    let date: Date
    let sessions: [PlanSession]
    let isRestDay: Bool

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

    /// Session row with sport icon, name, duration, and brick indicator.
    private func sessionRow(session: PlanSession) -> some View {
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
        }
        .padding(.vertical, 4)
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
        orderInDay: 0
    )

    return DaySessionRow(
        weekday: .monday,
        date: Date(),
        sessions: [session],
        isRestDay: false
    )
    .padding()
}

#Preview("Rest Day") {
    DaySessionRow(
        weekday: .tuesday,
        date: Date(),
        sessions: [],
        isRestDay: true
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
        orderInDay: 0
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
        orderInDay: 1
    )

    return DaySessionRow(
        weekday: .friday,
        date: Date(),
        sessions: [session1, session2],
        isRestDay: false
    )
    .padding()
}

