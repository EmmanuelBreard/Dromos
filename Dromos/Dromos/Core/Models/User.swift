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
/// Includes onboarding fields for demographics, race goals, and performance metrics.
struct User: Codable, Identifiable, Equatable {
    // MARK: - Core Properties

    let id: UUID
    let email: String
    var name: String?

    // MARK: - Onboarding: Basic Info (Screen 1)

    /// User's biological sex (e.g., "Male", "Female")
    var sex: String?

    /// User's date of birth for age calculation
    var birthDate: Date?

    /// User's weight in kilograms (valid range: 30-300 kg)
    var weightKg: Double?

    // MARK: - Onboarding: Race Goals (Screen 2)

    /// Target triathlon race distance
    var raceObjective: RaceObjective?

    /// Target race date
    var raceDate: Date?

    /// Target finish time - hours component
    var timeObjectiveHours: Int?

    /// Target finish time - minutes component
    var timeObjectiveMinutes: Int?

    // MARK: - Onboarding: Performance Metrics (Screen 3)

    /// VMA (Vitesse Maximale Aérobie) in km/h (valid range: 10-25)
    var vma: Double?

    /// CSS (Critical Swim Speed) - minutes component for 100m pace
    var cssMinutes: Int?

    /// CSS (Critical Swim Speed) - seconds component for 100m pace (valid range: 0-59)
    var cssSeconds: Int?

    /// FTP (Functional Threshold Power) in watts (valid range: 50-500)
    var ftp: Int?

    /// Years of triathlon/endurance sport experience
    var experienceYears: Int?

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

    // MARK: - Timestamps

    let createdAt: Date
    let updatedAt: Date

    // MARK: - Computed Properties

    /// Calculates user's age from birth date.
    /// Returns nil if birth date is not set.
    var age: Int? {
        guard let birthDate = birthDate else { return nil }
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: birthDate, to: Date())
        return ageComponents.year
    }

    /// Formats the CSS pace as a string (e.g., "1:45" for 1 min 45 sec per 100m)
    var formattedCSS: String? {
        guard let minutes = cssMinutes else { return nil }
        let seconds = cssSeconds ?? 0
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Formats the target time as a string (e.g., "5h 30min")
    var formattedTimeObjective: String? {
        guard let hours = timeObjectiveHours else { return nil }
        let minutes = timeObjectiveMinutes ?? 0
        return "\(hours)h \(minutes)min"
    }
}

// MARK: - CodingKeys

extension User {
    /// Maps Swift property names (camelCase) to database column names (snake_case)
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case sex
        case birthDate = "birth_date"
        case weightKg = "weight_kg"
        case raceObjective = "race_objective"
        case raceDate = "race_date"
        case timeObjectiveHours = "time_objective_hours"
        case timeObjectiveMinutes = "time_objective_minutes"
        case vma
        case cssMinutes = "css_minutes"
        case cssSeconds = "css_seconds"
        case ftp
        case experienceYears = "experience_years"
        case swimDays = "swim_days"
        case bikeDays = "bike_days"
        case runDays = "run_days"
        case monDuration = "mon_duration"
        case tueDuration = "tue_duration"
        case wedDuration = "wed_duration"
        case thuDuration = "thu_duration"
        case friDuration = "fri_duration"
        case satDuration = "sat_duration"
        case sunDuration = "sun_duration"
        case onboardingCompleted = "onboarding_completed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - User Update Payload

/// Payload for updating user profile.
/// Only includes fields that can be updated by the user.
struct UserUpdate: Codable {
    var name: String?

    // Onboarding fields
    var sex: String?
    var birthDate: Date?
    var weightKg: Double?
    var raceObjective: RaceObjective?
    var raceDate: Date?
    var timeObjectiveHours: Int?
    var timeObjectiveMinutes: Int?
    var vma: Double?
    var cssMinutes: Int?
    var cssSeconds: Int?
    var ftp: Int?
    var experienceYears: Int?
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

    enum CodingKeys: String, CodingKey {
        case name
        case sex
        case birthDate = "birth_date"
        case weightKg = "weight_kg"
        case raceObjective = "race_objective"
        case raceDate = "race_date"
        case timeObjectiveHours = "time_objective_hours"
        case timeObjectiveMinutes = "time_objective_minutes"
        case vma
        case cssMinutes = "css_minutes"
        case cssSeconds = "css_seconds"
        case ftp
        case experienceYears = "experience_years"
        case swimDays = "swim_days"
        case bikeDays = "bike_days"
        case runDays = "run_days"
        case monDuration = "mon_duration"
        case tueDuration = "tue_duration"
        case wedDuration = "wed_duration"
        case thuDuration = "thu_duration"
        case friDuration = "fri_duration"
        case satDuration = "sat_duration"
        case sunDuration = "sun_duration"
        case onboardingCompleted = "onboarding_completed"
    }
}
