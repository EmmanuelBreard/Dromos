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

    /// Initializes from individual screen data objects.
    /// - Parameters:
    ///   - basicInfo: Data from Screen 1 (demographics)
    ///   - raceGoals: Data from Screen 2 (race objectives)
    ///   - metrics: Data from Screen 3 (performance metrics)
    init(basicInfo: BasicInfoData, raceGoals: RaceGoalsData, metrics: MetricsData) {
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
    }
}
