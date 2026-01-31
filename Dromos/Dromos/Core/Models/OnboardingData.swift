//
//  OnboardingData.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import Foundation

// MARK: - Screen 1: Basic Info

/// Data collected on the first onboarding screen.
/// Contains demographic information about the user.
struct BasicInfoData: Codable {
    /// User's biological sex (e.g., "Male", "Female")
    var sex: String?

    /// User's date of birth
    var birthDate: Date?

    /// User's weight in kilograms
    var weightKg: Double?

    enum CodingKeys: String, CodingKey {
        case sex
        case birthDate = "birth_date"
        case weightKg = "weight_kg"
    }
}

// MARK: - Screen 2: Race Goals

/// Data collected on the second onboarding screen.
/// Contains the user's race objectives and target times.
struct RaceGoalsData: Codable {
    /// Target triathlon race distance (Sprint, Olympic, 70.3, Ironman)
    var raceObjective: RaceObjective?

    /// Target race date
    var raceDate: Date?

    /// Target finish time - hours component
    var timeObjectiveHours: Int?

    /// Target finish time - minutes component
    var timeObjectiveMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case raceObjective = "race_objective"
        case raceDate = "race_date"
        case timeObjectiveHours = "time_objective_hours"
        case timeObjectiveMinutes = "time_objective_minutes"
    }
}

// MARK: - Screen 3: Performance Metrics

/// Data collected on the third onboarding screen.
/// Contains the user's current performance metrics for training personalization.
struct MetricsData: Codable {
    /// VMA (Vitesse Maximale Aérobie) in km/h - key running metric
    var vma: Double?

    /// CSS (Critical Swim Speed) - minutes component for 100m pace
    var cssMinutes: Int?

    /// CSS (Critical Swim Speed) - seconds component for 100m pace
    var cssSeconds: Int?

    /// FTP (Functional Threshold Power) in watts - key cycling metric
    var ftp: Int?

    /// Years of triathlon/endurance sport experience
    var experienceYears: Int?

    enum CodingKeys: String, CodingKey {
        case vma
        case cssMinutes = "css_minutes"
        case cssSeconds = "css_seconds"
        case ftp
        case experienceYears = "experience_years"
    }
}

// MARK: - Screens 4, 5, 6: Weekly Availability

/// Data collected on availability screens (4, 5, 6).
/// Contains the days of the week the user can train for each sport.
/// Day names are capitalized: ["Monday", "Wednesday", "Friday"]
struct AvailabilityData: Codable {
    /// Days of the week user can train swimming
    var swimDays: [String] = []

    /// Days of the week user can train cycling
    var bikeDays: [String] = []

    /// Days of the week user can train running
    var runDays: [String] = []

    enum CodingKeys: String, CodingKey {
        case swimDays = "swim_days"
        case bikeDays = "bike_days"
        case runDays = "run_days"
    }
}

// MARK: - Screen 7: Daily Training Duration

/// Data collected on the seventh onboarding screen.
/// Contains total training duration per day of the week (in minutes).
/// Only days marked as available (union of swim/bike/run days) are included.
struct DailyDurationData: Codable {
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

    enum CodingKeys: String, CodingKey {
        case monDuration = "mon_duration"
        case tueDuration = "tue_duration"
        case wedDuration = "wed_duration"
        case thuDuration = "thu_duration"
        case friDuration = "fri_duration"
        case satDuration = "sat_duration"
        case sunDuration = "sun_duration"
    }
}

// MARK: - Complete Onboarding Payload

/// Aggregated onboarding data from all screens.
/// Used to submit the complete onboarding data to Supabase in a single update.
struct CompleteOnboardingData: Codable {
    // Basic Info (Screen 1)
    var sex: String?
    var birthDate: Date?
    var weightKg: Double?

    // Race Goals (Screen 2)
    var raceObjective: RaceObjective?
    var raceDate: Date?
    var timeObjectiveHours: Int?
    var timeObjectiveMinutes: Int?

    // Performance Metrics (Screen 3)
    var vma: Double?
    var cssMinutes: Int?
    var cssSeconds: Int?
    var ftp: Int?
    var experienceYears: Int?

    // Weekly Availability (Screens 4, 5, 6)
    var swimDays: [String]?
    var bikeDays: [String]?
    var runDays: [String]?

    // Daily Training Duration (Screen 7)
    var monDuration: Int?
    var tueDuration: Int?
    var wedDuration: Int?
    var thuDuration: Int?
    var friDuration: Int?
    var satDuration: Int?
    var sunDuration: Int?

    /// Initializes from individual screen data objects.
    /// - Parameters:
    ///   - basicInfo: Data from Screen 1 (demographics)
    ///   - raceGoals: Data from Screen 2 (race objectives)
    ///   - metrics: Data from Screen 3 (performance metrics)
    ///   - availability: Data from Screens 4, 5, 6 (weekly training availability)
    ///   - duration: Data from Screen 7 (daily training duration)
    init(basicInfo: BasicInfoData, raceGoals: RaceGoalsData, metrics: MetricsData, availability: AvailabilityData? = nil, duration: DailyDurationData? = nil) {
        self.sex = basicInfo.sex
        self.birthDate = basicInfo.birthDate
        self.weightKg = basicInfo.weightKg
        self.raceObjective = raceGoals.raceObjective
        self.raceDate = raceGoals.raceDate
        self.timeObjectiveHours = raceGoals.timeObjectiveHours
        self.timeObjectiveMinutes = raceGoals.timeObjectiveMinutes
        self.vma = metrics.vma
        self.cssMinutes = metrics.cssMinutes
        self.cssSeconds = metrics.cssSeconds
        self.ftp = metrics.ftp
        self.experienceYears = metrics.experienceYears
        self.swimDays = availability?.swimDays.isEmpty == false ? availability?.swimDays : nil
        self.bikeDays = availability?.bikeDays.isEmpty == false ? availability?.bikeDays : nil
        self.runDays = availability?.runDays.isEmpty == false ? availability?.runDays : nil
        self.monDuration = duration?.monDuration
        self.tueDuration = duration?.tueDuration
        self.wedDuration = duration?.wedDuration
        self.thuDuration = duration?.thuDuration
        self.friDuration = duration?.friDuration
        self.satDuration = duration?.satDuration
        self.sunDuration = duration?.sunDuration
    }

    enum CodingKeys: String, CodingKey {
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
    }
}
