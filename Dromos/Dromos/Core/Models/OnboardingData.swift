//
//  OnboardingData.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import Foundation

// MARK: - Screen 1: Race Goals

/// Data collected on the first onboarding screen.
/// Contains the user's race objectives and target times.
struct RaceGoalsData: Codable {
    /// Target triathlon race distance (Sprint, Olympic, 70.3, Ironman)
    var raceObjective: RaceObjective?

    /// Target race date
    var raceDate: Date?

    /// Target finish time in total minutes (consolidated from hours + minutes)
    var timeObjectiveMinutes: Int?
}

// MARK: - Screen 2: Performance Metrics

/// Data collected on the second onboarding screen.
/// Contains the user's current performance metrics for training personalization.
struct MetricsData: Codable {
    /// VMA (Vitesse Maximale Aérobie) in km/h - key running metric
    var vma: Double?

    /// CSS (Critical Swim Speed) in total seconds per 100m (consolidated from minutes + seconds)
    var cssSecondsPer100m: Int?

    /// FTP (Functional Threshold Power) in watts - key cycling metric
    var ftp: Int?

    /// Years of triathlon/endurance sport experience
    var experienceYears: Int?

    /// Average weekly training hours over the last 4 weeks (0-25, step 0.5)
    /// Defaults to 3.0 so the slider is pre-filled (required field).
    var currentWeeklyHours: Double? = 3.0

    /// Maximum heart rate in bpm (100-220, DRO-213 Phase 6)
    var maxHr: Int?

    /// Year of birth (1920-2020, DRO-213 Phase 6)
    var birthYear: Int?
}

// MARK: - Screens 3, 4, 5: Weekly Availability

/// Data collected on availability screens (3, 4, 5).
/// Contains the days of the week the user can train for each sport.
/// Day names are capitalized: ["Monday", "Wednesday", "Friday"]
struct AvailabilityData: Codable {
    /// Days of the week user can train swimming
    var swimDays: [String] = []

    /// Days of the week user can train cycling
    var bikeDays: [String] = []

    /// Days of the week user can train running
    var runDays: [String] = []
}

// MARK: - Screen 6: Daily Training Duration

/// Data collected on the sixth onboarding screen.
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
}

// MARK: - Complete Onboarding Payload

/// Aggregated onboarding data from all screens.
/// Used to submit the complete onboarding data to Supabase in a single update.
struct CompleteOnboardingData: Codable {
    // Race Goals (Screen 1)
    var raceObjective: RaceObjective?
    var raceDate: Date?
    var timeObjectiveMinutes: Int?

    // Performance Metrics (Screen 2)
    var vma: Double?
    var cssSecondsPer100m: Int?
    var ftp: Int?
    var experienceYears: Int?
    var currentWeeklyHours: Double?
    var maxHr: Int?
    var birthYear: Int?

    // Weekly Availability (Screens 3, 4, 5)
    var swimDays: [String]?
    var bikeDays: [String]?
    var runDays: [String]?

    // Daily Training Duration (Screen 6)
    var monDuration: Int?
    var tueDuration: Int?
    var wedDuration: Int?
    var thuDuration: Int?
    var friDuration: Int?
    var satDuration: Int?
    var sunDuration: Int?

    /// Initializes from individual screen data objects.
    /// - Parameters:
    ///   - raceGoals: Data from Screen 1 (race objectives)
    ///   - metrics: Data from Screen 2 (performance metrics)
    ///   - availability: Data from Screens 3, 4, 5 (weekly training availability)
    ///   - duration: Data from Screen 6 (daily training duration)
    init(raceGoals: RaceGoalsData, metrics: MetricsData, availability: AvailabilityData? = nil, duration: DailyDurationData? = nil) {
        self.raceObjective = raceGoals.raceObjective
        self.raceDate = raceGoals.raceDate
        self.timeObjectiveMinutes = raceGoals.timeObjectiveMinutes
        self.vma = metrics.vma
        self.cssSecondsPer100m = metrics.cssSecondsPer100m
        self.ftp = metrics.ftp
        self.experienceYears = metrics.experienceYears
        self.currentWeeklyHours = metrics.currentWeeklyHours
        self.maxHr = metrics.maxHr
        self.birthYear = metrics.birthYear
        self.swimDays = availability?.swimDays.isEmpty == false ? availability?.swimDays : nil
        self.bikeDays = availability?.bikeDays.isEmpty == false ? availability?.bikeDays : nil
        self.runDays = availability?.runDays.isEmpty == false ? availability?.runDays : nil
        
        // Calculate union of available days to determine which duration values to keep
        var availableDaysSet = Set<String>()
        if let swimDays = availability?.swimDays {
            availableDaysSet.formUnion(swimDays)
        }
        if let bikeDays = availability?.bikeDays {
            availableDaysSet.formUnion(bikeDays)
        }
        if let runDays = availability?.runDays {
            availableDaysSet.formUnion(runDays)
        }
        
        // Only keep duration values for days that are in the union of available days
        // Clear durations for days that are no longer available (prevents stale data)
        self.monDuration = availableDaysSet.contains("Monday") ? duration?.monDuration : nil
        self.tueDuration = availableDaysSet.contains("Tuesday") ? duration?.tueDuration : nil
        self.wedDuration = availableDaysSet.contains("Wednesday") ? duration?.wedDuration : nil
        self.thuDuration = availableDaysSet.contains("Thursday") ? duration?.thuDuration : nil
        self.friDuration = availableDaysSet.contains("Friday") ? duration?.friDuration : nil
        self.satDuration = availableDaysSet.contains("Saturday") ? duration?.satDuration : nil
        self.sunDuration = availableDaysSet.contains("Sunday") ? duration?.sunDuration : nil
    }
}
