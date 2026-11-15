//
//  ProfileService.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import Combine
import Foundation
import Supabase

/// Service for fetching and updating user profile data.
@MainActor
final class ProfileService: ObservableObject {

    // MARK: - Published Properties

    /// Current user profile, nil if not loaded.
    @Published private(set) var user: User?

    /// Whether a profile operation is in progress.
    @Published private(set) var isLoading = false

    /// Last error message from a profile operation.
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let client = SupabaseClientProvider.client

    // MARK: - Public Methods

    /// Fetch the current user's profile.
    /// - Parameter userId: The user's ID (from auth session)
    /// - Returns: The user profile
    /// - Throws: Error if fetch fails
    @discardableResult
    func fetchProfile(userId: UUID) async throws -> User {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let user: User = try await client
                .from("users")
                .select()
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value

            self.user = user
            return user
        } catch {
            errorMessage = "Failed to load profile"
            throw error
        }
    }

    /// Update the current user's profile.
    /// - Parameters:
    ///   - userId: The user's ID
    ///   - name: New name value (optional)
    ///   - raceObjective: Target triathlon race distance (optional)
    ///   - raceDate: Target race date (optional)
    ///   - timeObjectiveMinutes: Target finish time in total minutes (optional)
    ///   - vma: VMA in km/h (optional)
    ///   - cssSecondsPer100m: CSS in total seconds per 100m (optional)
    ///   - ftp: FTP in watts (optional)
    ///   - experienceYears: Years of triathlon experience (optional)
    /// - Returns: The updated user profile
    /// - Throws: Error if update fails
    @discardableResult
    func updateProfile(
        userId: UUID,
        name: String? = nil,
        raceObjective: RaceObjective? = nil,
        raceDate: Date? = nil,
        timeObjectiveMinutes: Int? = nil,
        vma: Double? = nil,
        cssSecondsPer100m: Int? = nil,
        ftp: Int? = nil,
        experienceYears: Int? = nil,
        maxHr: Int? = nil,
        birthYear: Int? = nil
    ) async throws -> User {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let update = UserUpdate(
                name: name,
                raceObjective: raceObjective,
                raceDate: raceDate,
                timeObjectiveMinutes: timeObjectiveMinutes,
                vma: vma,
                cssSecondsPer100m: cssSecondsPer100m,
                ftp: ftp,
                experienceYears: experienceYears,
                onboardingCompleted: nil,
                maxHr: maxHr,
                birthYear: birthYear
            )

            let user: User = try await client
                .from("users")
                .update(update)
                .eq("id", value: userId.uuidString)
                .select()
                .single()
                .execute()
                .value

            self.user = user
            return user
        } catch {
            errorMessage = "Failed to update profile"
            throw error
        }
    }

    /// Save complete onboarding data for a user.
    /// - Parameters:
    ///   - userId: The user's ID
    ///   - data: Complete onboarding data from all screens
    /// - Throws: Error if save fails
    func saveOnboardingData(userId: UUID, data: CompleteOnboardingData) async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            // Create encodable update payload
            // Note: We convert RaceObjective enum to its raw string value
            // Availability arrays (swimDays, bikeDays, runDays) are encoded as JSONB arrays
            // Duration fields are nullable INT values (30-420 minutes)
            struct OnboardingUpdate: Encodable {
                let raceObjective: String?
                let raceDate: Date?
                let timeObjectiveMinutes: Int?
                let vma: Double?
                let cssSecondsPer100m: Int?
                let ftp: Int?
                let experienceYears: Int?
                let currentWeeklyHours: Double?
                let swimDays: [String]?
                let bikeDays: [String]?
                let runDays: [String]?
                let monDuration: Int?
                let tueDuration: Int?
                let wedDuration: Int?
                let thuDuration: Int?
                let friDuration: Int?
                let satDuration: Int?
                let sunDuration: Int?
                let maxHr: Int?
                let birthYear: Int?
            }

            let update = OnboardingUpdate(
                raceObjective: data.raceObjective?.rawValue,
                raceDate: data.raceDate,
                timeObjectiveMinutes: data.timeObjectiveMinutes,
                vma: data.vma,
                cssSecondsPer100m: data.cssSecondsPer100m,
                ftp: data.ftp,
                experienceYears: data.experienceYears,
                currentWeeklyHours: data.currentWeeklyHours,
                swimDays: data.swimDays,
                bikeDays: data.bikeDays,
                runDays: data.runDays,
                monDuration: data.monDuration,
                tueDuration: data.tueDuration,
                wedDuration: data.wedDuration,
                thuDuration: data.thuDuration,
                friDuration: data.friDuration,
                satDuration: data.satDuration,
                sunDuration: data.sunDuration,
                maxHr: data.maxHr,
                birthYear: data.birthYear
            )

            try await client
                .from("users")
                .update(update)
                .eq("id", value: userId.uuidString)
                .execute()

            // Refresh cached profile
            self.user = try await fetchProfile(userId: userId)
        } catch {
            errorMessage = "Failed to save onboarding data"
            throw error
        }
    }

    /// Writes only the columns in `patch`. Other profile fields stay as they are,
    /// so closing the app mid-chat can resume from what was already saved.
    func saveOnboardingPatch(_ patch: OnboardingPatch, userId: UUID) async throws {
        guard !patch.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await client
                .from("users")
                .update(OnboardingPatchPayload(patch: patch))
                .eq("id", value: userId.uuidString)
                .execute()
        } catch {
            errorMessage = "Failed to save onboarding data"
            throw error
        }
    }

    /// Mark onboarding as complete for a user.
    /// - Parameter userId: The user's ID
    /// - Throws: Error if update fails
    func markOnboardingComplete(userId: UUID) async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            struct OnboardingStatusUpdate: Encodable {
                let onboardingCompleted: Bool
            }

            let update = OnboardingStatusUpdate(onboardingCompleted: true)

            try await client
                .from("users")
                .update(update)
                .eq("id", value: userId.uuidString)
                .execute()

            // Refresh cached profile
            self.user = try await fetchProfile(userId: userId)
        } catch {
            errorMessage = "Failed to mark onboarding complete"
            throw error
        }
    }

    /// Clear the cached user profile (e.g., on sign out).
    func clearProfile() {
        user = nil
        errorMessage = nil
    }
}

/// Encodes one onboarding answer. Omitted keys are not updated. Duration saves
/// write null for days that are no longer available.
private struct OnboardingPatchPayload: Encodable {
    let patch: OnboardingPatch

    enum CodingKeys: String, CodingKey {
        case raceObjective, raceDate, timeObjectiveMinutes, experienceYears, currentWeeklyHours
        case vma, cssSecondsPer100m, ftp, maxHr, birthYear, metricsSource
        case swimDays, bikeDays, runDays
        case monDuration, tueDuration, wedDuration, thuDuration, friDuration, satDuration, sunDuration
        case limiters
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let race = patch.raceObjective {
            try container.encode(race.rawValue, forKey: .raceObjective)
        }
        if let date = patch.raceDate {
            try container.encode(PlanHorizon.isoString(date), forKey: .raceDate)
        }
        if patch.clearTimeObjective {
            try container.encodeNil(forKey: .timeObjectiveMinutes)
        } else {
            try container.encodeIfPresent(patch.timeObjectiveMinutes, forKey: .timeObjectiveMinutes)
        }
        try container.encodeIfPresent(patch.experienceYears, forKey: .experienceYears)
        try container.encodeIfPresent(patch.currentWeeklyHours, forKey: .currentWeeklyHours)
        try container.encodeIfPresent(patch.vma, forKey: .vma)
        try container.encodeIfPresent(patch.cssSecondsPer100m, forKey: .cssSecondsPer100m)
        try container.encodeIfPresent(patch.ftp, forKey: .ftp)
        try container.encodeIfPresent(patch.maxHr, forKey: .maxHr)
        try container.encodeIfPresent(patch.birthYear, forKey: .birthYear)
        try container.encodeIfPresent(patch.metrics, forKey: .metricsSource)
        try container.encodeIfPresent(patch.swimDays, forKey: .swimDays)
        try container.encodeIfPresent(patch.bikeDays, forKey: .bikeDays)
        try container.encodeIfPresent(patch.runDays, forKey: .runDays)
        if patch.replaceDurations {
            try encodeDuration(patch.monDuration, forKey: .monDuration, in: &container)
            try encodeDuration(patch.tueDuration, forKey: .tueDuration, in: &container)
            try encodeDuration(patch.wedDuration, forKey: .wedDuration, in: &container)
            try encodeDuration(patch.thuDuration, forKey: .thuDuration, in: &container)
            try encodeDuration(patch.friDuration, forKey: .friDuration, in: &container)
            try encodeDuration(patch.satDuration, forKey: .satDuration, in: &container)
            try encodeDuration(patch.sunDuration, forKey: .sunDuration, in: &container)
        }
        try container.encodeIfPresent(patch.limiters, forKey: .limiters)
    }

    private func encodeDuration(
        _ minutes: Int?,
        forKey key: CodingKeys,
        in container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let minutes {
            try container.encode(minutes, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }
}
