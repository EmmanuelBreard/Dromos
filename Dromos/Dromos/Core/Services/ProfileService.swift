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
    /// - Returns: The updated user profile
    /// - Throws: Error if update fails
    @discardableResult
    func updateProfile(userId: UUID, name: String?) async throws -> User {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let update = UserUpdate(name: name)

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

    /// Clear the cached user profile (e.g., on sign out).
    func clearProfile() {
        user = nil
        errorMessage = nil
    }
}
