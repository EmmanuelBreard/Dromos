//
//  TrainingPlan.swift
//  Dromos
//
//  Created by Emmanuel Breard on 01/02/2026.
//

import Foundation
import SwiftUI

// MARK: - Weekday Enum

/// Represents a day of the week, ordered Monday through Sunday.
/// Handles normalization between abbreviated names ("Mon") and full names ("Monday").
enum Weekday: String, CaseIterable, Codable, Hashable {
    case monday = "Monday"
    case tuesday = "Tuesday"
    case wednesday = "Wednesday"
    case thursday = "Thursday"
    case friday = "Friday"
    case saturday = "Saturday"
    case sunday = "Sunday"

    /// All weekdays ordered Monday through Sunday.
    static var allCases: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }

    /// Full name of the weekday (e.g., "Monday").
    var fullName: String {
        rawValue
    }

    /// Abbreviated name of the weekday (e.g., "Mon").
    var abbreviation: String {
        switch self {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }

    /// Initialize from abbreviated name (e.g., "Mon" → .monday).
    init?(abbreviation: String) {
        let normalized = abbreviation.prefix(3).capitalized
        switch normalized {
        case "Mon": self = .monday
        case "Tue": self = .tuesday
        case "Wed": self = .wednesday
        case "Thu": self = .thursday
        case "Fri": self = .friday
        case "Sat": self = .saturday
        case "Sun": self = .sunday
        default: return nil
        }
    }

    /// Initialize from full name (e.g., "Monday" → .monday).
    init?(fullName: String) {
        self.init(rawValue: fullName)
    }

    /// Computes the calendar date for this weekday relative to a week's start date.
    /// - Parameter weekStartDate: The start date of the week (may be any day of the week)
    /// - Returns: The date for this weekday within that week
    func date(relativeTo weekStartDate: Date) -> Date {
        let calendar = Calendar.current
        let weekdayComponent = calendar.component(.weekday, from: weekStartDate)
        
        // Convert Calendar's weekday (Sunday=1, Monday=2, ..., Saturday=7) to our offset (Monday=0, ..., Sunday=6)
        let startOffset: Int
        switch weekdayComponent {
        case 1: startOffset = 6 // Sunday → offset 6
        case 2: startOffset = 0 // Monday → offset 0
        case 3: startOffset = 1 // Tuesday → offset 1
        case 4: startOffset = 2 // Wednesday → offset 2
        case 5: startOffset = 3 // Thursday → offset 3
        case 6: startOffset = 4 // Friday → offset 4
        case 7: startOffset = 5 // Saturday → offset 5
        default: startOffset = 0
        }
        
        // Calculate target weekday offset (Monday=0, Tuesday=1, ..., Sunday=6)
        let targetOffset: Int
        switch self {
        case .monday: targetOffset = 0
        case .tuesday: targetOffset = 1
        case .wednesday: targetOffset = 2
        case .thursday: targetOffset = 3
        case .friday: targetOffset = 4
        case .saturday: targetOffset = 5
        case .sunday: targetOffset = 6
        }
        
        // Calculate days to add (can be negative if target is before start)
        let daysToAdd = targetOffset - startOffset
        return calendar.date(byAdding: .day, value: daysToAdd, to: weekStartDate) ?? weekStartDate
    }
}

// MARK: - Plan Session Model

/// Individual training session within a week.
/// Represents a single workout (swim, bike, or run) scheduled for a specific day.
struct PlanSession: Codable, Identifiable {
    let id: UUID
    var weekId: UUID
    var day: String // Full name: "Monday", "Tuesday", etc.
    let sport: String // "swim", "bike", "run"
    let type: String // "Easy", "Tempo", "Intervals"
    let templateId: String
    let durationMinutes: Int
    let isBrick: Bool
    let notes: String?
    var orderInDay: Int
    let feedback: String?
    let matchedActivityId: UUID?

    // MARK: - Computed Properties

    /// Display name derived from type + sport (e.g., "Easy Swim", "Tempo Run").
    var displayName: String {
        "\(type) \(sport.capitalized)"
    }

    /// SF Symbol name for the sport icon.
    var sportIcon: String {
        switch sport.lowercased() {
        case "swim":
            return "figure.pool.swim"
        case "bike":
            return "bicycle"
        case "run":
            return "figure.run"
        default:
            return "figure.run"
        }
    }

    /// Color based on workout type (Easy=green, Tempo=orange, Intervals=red).
    var typeColor: Color {
        switch type.lowercased() {
        case "easy": return .green
        case "tempo": return .orange
        case "intervals": return .red
        default: return .gray
        }
    }

    /// Emoji for the sport.
    var sportEmoji: String {
        switch sport.lowercased() {
        case "swim": return "🏊‍♂️"
        case "bike": return "🚴‍♂️"
        case "run": return "🏃‍♂️"
        default: return "🏃‍♂️"
        }
    }

    /// Formatted duration string (e.g., "60 min", "1h 30 min").
    var formattedDuration: String {
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes) min"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes) min"
        }
    }
}

// MARK: - Plan Week Model

/// Weekly plan information within a training plan.
/// Contains sessions and metadata for a single week.
struct PlanWeek: Codable, Identifiable {
    let id: UUID
    let planId: UUID
    let weekNumber: Int
    let phase: String // "Base", "Build", "Peak", "Taper", "Recovery"
    let isRecovery: Bool
    let restDays: [String] // Abbreviated names: ["Mon", "Fri"] or full names: ["Monday", "Friday"]
    let notes: String?
    let startDate: String // ISO date string (YYYY-MM-DD)
    var planSessions: [PlanSession]

    // MARK: - Computed Properties

    /// Total training minutes for this week (sum of all session durations).
    var totalMinutes: Int {
        planSessions.reduce(0) { $0 + $1.durationMinutes }
    }

    /// Parsed start date as Date object.
    var startDateAsDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: startDate)
    }

    /// Sessions grouped by weekday, sorted by orderInDay.
    var sessionsByDay: [Weekday: [PlanSession]] {
        var grouped: [Weekday: [PlanSession]] = [:]

        for session in planSessions {
            guard let weekday = Weekday(fullName: session.day) else { continue }
            if grouped[weekday] == nil {
                grouped[weekday] = []
            }
            grouped[weekday]?.append(session)
        }

        // Sort sessions within each day by orderInDay
        for (weekday, sessions) in grouped {
            grouped[weekday] = sessions.sorted { $0.orderInDay < $1.orderInDay }
        }

        return grouped
    }

    /// Set of rest days normalized from abbreviated or full names.
    var restDaySet: Set<Weekday> {
        var restDaysSet = Set<Weekday>()
        for restDay in restDays {
            // Try full name first, then abbreviation
            if let weekday = Weekday(fullName: restDay) {
                restDaysSet.insert(weekday)
            } else if let weekday = Weekday(abbreviation: restDay) {
                restDaysSet.insert(weekday)
            }
        }
        return restDaysSet
    }
}

// MARK: - Training Plan Model

/// Top-level training plan for a user.
/// Contains all weeks and sessions for the entire plan.
struct TrainingPlan: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let status: String // "generating" or "active"
    let raceDate: String? // ISO date string (YYYY-MM-DD)
    let raceObjective: String?
    let totalWeeks: Int
    let startDate: String // ISO date string (YYYY-MM-DD)
    var planWeeks: [PlanWeek]

    // MARK: - Computed Properties

    /// Parsed start date as Date object.
    var startDateAsDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: startDate)
    }

    /// Parsed race date as Date object.
    var raceDateAsDate: Date? {
        guard let raceDate = raceDate else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: raceDate)
    }

    // MARK: - Navigation Helpers

    /// Calculates which week index contains today's date.
    /// Falls back to Week 1 (index 0) if before plan start, last week if after plan end.
    func currentWeekIndex() -> Int {
        let today = Date()
        let calendar = Calendar.current

        // If before plan start, return Week 1
        if let planStart = startDateAsDate, today < planStart {
            return 0
        }

        // Find week containing today
        for (index, week) in planWeeks.enumerated() {
            guard let weekStart = week.startDateAsDate else { continue }
            let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart

            if today >= weekStart && today < nextWeekStart {
                return index
            }
        }

        // If after all weeks, return last week
        return max(0, planWeeks.count - 1)
    }

    /// Returns day information for a given week, handling partial Week 1.
    /// - Parameter week: The week to get days for
    /// - Returns: Array of DayInfo for each day in the week
    func daysForWeek(_ week: PlanWeek) -> [DayInfo] {
        guard let weekStartDate = week.startDateAsDate else { return [] }

        let calendar = Calendar.current
        let sessionsByDay = week.sessionsByDay
        let restDaySet = week.restDaySet

        var days: [DayInfo] = []

        // Determine which weekdays to show
        let weekdaysToShow: [Weekday]
        if week.weekNumber == 1, let planStart = startDateAsDate {
            // Partial Week 1: only show days from plan start to Sunday
            let weekdayComponent = calendar.component(.weekday, from: planStart)
            let startWeekday: Weekday
            switch weekdayComponent {
            case 1: startWeekday = .sunday
            case 2: startWeekday = .monday
            case 3: startWeekday = .tuesday
            case 4: startWeekday = .wednesday
            case 5: startWeekday = .thursday
            case 6: startWeekday = .friday
            case 7: startWeekday = .saturday
            default: startWeekday = .monday
            }

            if let startIndex = Weekday.allCases.firstIndex(of: startWeekday) {
                weekdaysToShow = Array(Weekday.allCases[startIndex...])
            } else {
                weekdaysToShow = Weekday.allCases
            }
        } else {
            weekdaysToShow = Weekday.allCases
        }

        // Create day info for each weekday
        for weekday in weekdaysToShow {
            let dayDate = weekday.date(relativeTo: weekStartDate)

            // Skip days before plan start for Week 1
            if week.weekNumber == 1,
               let planStart = startDateAsDate,
               dayDate < planStart {
                continue
            }

            let sessions = sessionsByDay[weekday] ?? []
            let isRestDay = restDaySet.contains(weekday) && sessions.isEmpty

            days.append(DayInfo(
                weekday: weekday,
                date: dayDate,
                sessions: sessions,
                isRestDay: isRestDay
            ))
        }

        return days
    }
}

// MARK: - Day Info

/// Information about a single day in a week.
/// Used by both HomeView and CalendarPlanView to display day sections.
struct DayInfo {
    let weekday: Weekday
    let date: Date
    let sessions: [PlanSession]
    let isRestDay: Bool
}

