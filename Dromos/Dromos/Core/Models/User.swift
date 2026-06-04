//
//  User.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import Foundation

// MARK: - Race Objective Enum

/// Represents the triathlon race distance objective. Currently supports Olympic and Ironman 70.3.
/// Maps directly to the CHECK constraint in the database.
enum RaceObjective: String, Codable, CaseIterable {
    case olympic = "Olympic"
    case ironman703 = "Ironman 70.3"
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

    // MARK: - Performance Metrics: HR (DRO-213)

    /// Maximum heart rate in bpm (used for HR-zone and hr_pct_max target resolution)
    var maxHr: Int?

    /// Year of birth (used for the 220−age formula affordance in onboarding)
    var birthYear: Int?

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

// MARK: - Codable (lossy raceObjective)

extension User {
    /// Coding keys declared explicitly so the custom decoder below can reference them.
    /// Raw values stay camelCase; the global `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`
    /// (see `SupabaseClient.swift`) handles the snake_case → camelCase conversion on the wire.
    private enum CodingKeys: String, CodingKey {
        case id, email, name, raceObjective, raceDate, timeObjectiveMinutes,
             vma, cssSecondsPer100m, ftp, experienceYears, currentWeeklyHours,
             swimDays, bikeDays, runDays, monDuration, tueDuration, wedDuration,
             thuDuration, friDuration, satDuration, sunDuration, maxHr, birthYear,
             onboardingCompleted, stravaAthleteId, createdAt, updatedAt
    }

    /// Custom decoder so legacy `race_objective` raw values in the DB (e.g. "Sprint", "Ironman")
    /// degrade to `nil` instead of throwing `DecodingError.dataCorrupted` and locking the user
    /// out of the app. Declared in an extension to preserve the synthesized memberwise init
    /// used by tests.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.email = try c.decode(String.self, forKey: .email)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.raceObjective = (try c.decodeIfPresent(String.self, forKey: .raceObjective))
            .flatMap { RaceObjective(rawValue: $0) }
        self.raceDate = try c.decodeIfPresent(Date.self, forKey: .raceDate)
        self.timeObjectiveMinutes = try c.decodeIfPresent(Int.self, forKey: .timeObjectiveMinutes)
        self.vma = try c.decodeIfPresent(Double.self, forKey: .vma)
        self.cssSecondsPer100m = try c.decodeIfPresent(Int.self, forKey: .cssSecondsPer100m)
        self.ftp = try c.decodeIfPresent(Int.self, forKey: .ftp)
        self.experienceYears = try c.decodeIfPresent(Int.self, forKey: .experienceYears)
        self.currentWeeklyHours = try c.decodeIfPresent(Double.self, forKey: .currentWeeklyHours)
        self.swimDays = try c.decodeIfPresent([String].self, forKey: .swimDays)
        self.bikeDays = try c.decodeIfPresent([String].self, forKey: .bikeDays)
        self.runDays = try c.decodeIfPresent([String].self, forKey: .runDays)
        self.monDuration = try c.decodeIfPresent(Int.self, forKey: .monDuration)
        self.tueDuration = try c.decodeIfPresent(Int.self, forKey: .tueDuration)
        self.wedDuration = try c.decodeIfPresent(Int.self, forKey: .wedDuration)
        self.thuDuration = try c.decodeIfPresent(Int.self, forKey: .thuDuration)
        self.friDuration = try c.decodeIfPresent(Int.self, forKey: .friDuration)
        self.satDuration = try c.decodeIfPresent(Int.self, forKey: .satDuration)
        self.sunDuration = try c.decodeIfPresent(Int.self, forKey: .sunDuration)
        self.maxHr = try c.decodeIfPresent(Int.self, forKey: .maxHr)
        self.birthYear = try c.decodeIfPresent(Int.self, forKey: .birthYear)
        self.onboardingCompleted = try c.decode(Bool.self, forKey: .onboardingCompleted)
        self.stravaAthleteId = try c.decodeIfPresent(Int64.self, forKey: .stravaAthleteId)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
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
    var maxHr: Int?
    var birthYear: Int?
}
