//
//  User.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import Foundation

// MARK: - Race Objective Enum

/// Represents the triathlon race distance objective.
/// Maps directly to the CHECK constraint in the database.
enum RaceObjective: String, Codable, CaseIterable {
    case sprint = "Sprint"
    case olympic = "Olympic"
    case ironman703 = "Ironman 70.3"
    case ironman = "Ironman"
}

// MARK: - User Model

/// User profile model matching the public.users table in Supabase.
/// Includes onboarding fields for race goals, performance metrics, and availability.
struct User: Codable, Identifiable, Equatable {
    // MARK: - Core Properties

    let id: UUID
    let email: String
    var name: String?

    // MARK: - Onboarding: Race Goals (Screen 2)

    /// Target triathlon race distance
    var raceObjective: RaceObjective?

    /// Target race date
    var raceDate: Date?

    /// Target finish time in total minutes (consolidated from hours + minutes)
    var timeObjectiveMinutes: Int?

    // MARK: - Onboarding: Performance Metrics (Screen 3)

    /// VMA (Vitesse Maximale Aérobie) in km/h (valid range: 10-25)
    var vma: Double?

    /// CSS (Critical Swim Speed) in total seconds per 100m (consolidated from minutes + seconds, valid range: 25-300)
    var cssSecondsPer100m: Int?

    /// FTP (Functional Threshold Power) in watts (valid range: 50-500)
    var ftp: Int?

    /// Years of triathlon/endurance sport experience
    var experienceYears: Int?

    /// Average weekly training hours over the last 4 weeks (0-25)
    var currentWeeklyHours: Double?

    // MARK: - Onboarding: Weekly Availability (Screens 4, 5, 6)

    /// Days of the week user can train swimming (e.g., ["Monday", "Wednesday", "Friday"])
    var swimDays: [String]?

    /// Days of the week user can train cycling (e.g., ["Tuesday", "Thursday"])
    var bikeDays: [String]?

    /// Days of the week user can train running (e.g., ["Saturday", "Sunday"])
    var runDays: [String]?

    // MARK: - Onboarding: Daily Training Duration (Screen 7)

    /// Total training duration for Monday in minutes (30-420, nullable if day not available)
    var monDuration: Int?

    /// Total training duration for Tuesday in minutes (30-420, nullable if day not available)
    var tueDuration: Int?

    /// Total training duration for Wednesday in minutes (30-420, nullable if day not available)
    var wedDuration: Int?

    /// Total training duration for Thursday in minutes (30-420, nullable if day not available)
    var thuDuration: Int?

    /// Total training duration for Friday in minutes (30-420, nullable if day not available)
    var friDuration: Int?

    /// Total training duration for Saturday in minutes (30-420, nullable if day not available)
    var satDuration: Int?

    /// Total training duration for Sunday in minutes (30-420, nullable if day not available)
    var sunDuration: Int?

    // MARK: - Onboarding Status

    /// Indicates whether the user has completed the onboarding flow
    var onboardingCompleted: Bool

    // MARK: - Strava Integration

    /// Strava athlete ID, present when the user has connected their Strava account
    let stravaAthleteId: Int64?

    // MARK: - Timestamps

    let createdAt: Date
    let updatedAt: Date

    // MARK: - Computed Properties

    /// Whether the user has a connected Strava account
    var isStravaConnected: Bool { stravaAthleteId != nil }

    /// Formats the CSS pace as a string (e.g., "1:45" for 1 min 45 sec per 100m)
    /// Derives minutes:seconds from total seconds
    var formattedCSS: String? {
        guard let totalSeconds = cssSecondsPer100m else { return nil }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Formats the target time as a string (e.g., "5h 30min")
    /// Derives hours:minutes from total minutes
    var formattedTimeObjective: String? {
        guard let totalMinutes = timeObjectiveMinutes else { return nil }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(minutes)min"
    }
}

// MARK: - User Update Payload

/// Payload for updating user profile.
/// Only includes fields that can be updated by the user.
struct UserUpdate: Codable {
    var name: String?

    // Onboarding fields
    var raceObjective: RaceObjective?
    var raceDate: Date?
    var timeObjectiveMinutes: Int?
    var vma: Double?
    var cssSecondsPer100m: Int?
    var ftp: Int?
    var experienceYears: Int?
    var currentWeeklyHours: Double?
    var swimDays: [String]?
    var bikeDays: [String]?
    var runDays: [String]?
    var monDuration: Int?
    var tueDuration: Int?
    var wedDuration: Int?
    var thuDuration: Int?
    var friDuration: Int?
    var satDuration: Int?
    var sunDuration: Int?
    var onboardingCompleted: Bool?
}
