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
    ///   - sex: User's biological sex (optional)
    ///   - birthDate: User's date of birth (optional)
    ///   - weightKg: User's weight in kg (optional)
    ///   - raceObjective: Target triathlon race distance (optional)
    ///   - raceDate: Target race date (optional)
    ///   - timeObjectiveHours: Target finish time hours component (optional)
    ///   - timeObjectiveMinutes: Target finish time minutes component (optional)
    ///   - vma: VMA in km/h (optional)
    ///   - cssMinutes: CSS minutes component (optional)
    ///   - cssSeconds: CSS seconds component (optional)
    ///   - ftp: FTP in watts (optional)
    ///   - experienceYears: Years of triathlon experience (optional)
    /// - Returns: The updated user profile
    /// - Throws: Error if update fails
    @discardableResult
    func updateProfile(
        userId: UUID,
        name: String? = nil,
        sex: String? = nil,
        birthDate: Date? = nil,
        weightKg: Double? = nil,
        raceObjective: RaceObjective? = nil,
        raceDate: Date? = nil,
        timeObjectiveHours: Int? = nil,
        timeObjectiveMinutes: Int? = nil,
        vma: Double? = nil,
        cssMinutes: Int? = nil,
        cssSeconds: Int? = nil,
        ftp: Int? = nil,
        experienceYears: Int? = nil
    ) async throws -> User {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let update = UserUpdate(
                name: name,
                sex: sex,
                birthDate: birthDate,
                weightKg: weightKg,
                raceObjective: raceObjective,
                raceDate: raceDate,
                timeObjectiveHours: timeObjectiveHours,
                timeObjectiveMinutes: timeObjectiveMinutes,
                vma: vma,
                cssMinutes: cssMinutes,
                cssSeconds: cssSeconds,
                ftp: ftp,
                experienceYears: experienceYears,
                onboardingCompleted: nil
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
                let sex: String?
                let birthDate: Date?
                let weightKg: Double?
                let raceObjective: String?
                let raceDate: Date?
                let timeObjectiveHours: Int?
                let timeObjectiveMinutes: Int?
                let vma: Double?
                let cssMinutes: Int?
                let cssSeconds: Int?
                let ftp: Int?
                let experienceYears: Int?
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

            let update = OnboardingUpdate(
                sex: data.sex,
                birthDate: data.birthDate,
                weightKg: data.weightKg,
                raceObjective: data.raceObjective?.rawValue,
                raceDate: data.raceDate,
                timeObjectiveHours: data.timeObjectiveHours,
                timeObjectiveMinutes: data.timeObjectiveMinutes,
                vma: data.vma,
                cssMinutes: data.cssMinutes,
                cssSeconds: data.cssSeconds,
                ftp: data.ftp,
                experienceYears: data.experienceYears,
                swimDays: data.swimDays,
                bikeDays: data.bikeDays,
                runDays: data.runDays,
                monDuration: data.monDuration,
                tueDuration: data.tueDuration,
                wedDuration: data.wedDuration,
                thuDuration: data.thuDuration,
                friDuration: data.friDuration,
                satDuration: data.satDuration,
                sunDuration: data.sunDuration
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

                enum CodingKeys: String, CodingKey {
                    case onboardingCompleted = "onboarding_completed"
                }
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
