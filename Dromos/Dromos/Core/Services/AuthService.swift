//
//  AuthService.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import Combine
import Foundation
import Supabase

/// Authentication service handling user sign-up, sign-in, and session management.
/// Uses Supabase Auth under the hood.
@MainActor
final class AuthService: ObservableObject {

    // MARK: - Published Properties

    /// Current authentication session, nil if not logged in.
    @Published private(set) var session: Session?

    /// Whether an auth operation is in progress.
    @Published private(set) var isLoading = false

    /// Last error message from an auth operation.
    @Published var errorMessage: String?

    /// Whether the current user has completed onboarding.
    /// Updated automatically when auth state changes.
    @Published private(set) var onboardingCompleted: Bool = false

    // MARK: - Computed Properties

    /// Whether the user is currently authenticated.
    var isAuthenticated: Bool {
        session != nil
    }

    /// Current user ID, if authenticated.
    var currentUserId: UUID? {
        session?.user.id
    }

    /// Current user email, if authenticated.
    var currentUserEmail: String? {
        session?.user.email
    }

    // MARK: - Private Properties

    private let client = SupabaseClientProvider.client
    private var authStateTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        // Start observing auth state changes
        startObservingAuthState()

        // Check for existing session
        Task {
            await checkExistingSession()
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    // MARK: - Public Methods

    /// Sign up a new user with email and password.
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password (min 6 characters recommended)
    /// - Throws: AuthError if sign-up fails
    func signUp(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let response = try await client.auth.signUp(
                email: email,
                password: password
            )
            session = response.session
        } catch {
            errorMessage = mapAuthError(error)
            throw error
        }
    }

    /// Sign in an existing user with email and password.
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    /// - Throws: AuthError if sign-in fails
    func signIn(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let session = try await client.auth.signIn(
                email: email,
                password: password
            )
            self.session = session
        } catch {
            errorMessage = mapAuthError(error)
            throw error
        }
    }

    /// Sign out the current user.
    /// - Throws: AuthError if sign-out fails
    func signOut() async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            try await client.auth.signOut()
            session = nil
            onboardingCompleted = false
        } catch {
            errorMessage = mapAuthError(error)
            throw error
        }
    }

    /// Check the current user's onboarding completion status.
    /// Updates the `onboardingCompleted` published property.
    /// - Throws: Error if fetch fails
    func checkOnboardingStatus() async throws {
        guard let userId = currentUserId else {
            onboardingCompleted = false
            return
        }

        do {
            // Minimal struct for fetching only onboarding status
            struct OnboardingStatus: Codable {
                let onboardingCompleted: Bool
            }

            // Fetch only the onboarding_completed field
            let response: [OnboardingStatus] = try await client
                .from("users")
                .select("onboarding_completed")
                .eq("id", value: userId.uuidString)
                .execute()
                .value

            onboardingCompleted = response.first?.onboardingCompleted ?? false
        } catch {
            // On error, default to false to be safe
            onboardingCompleted = false
            throw error
        }
    }

    /// Manually mark onboarding as complete.
    /// Use this as a fallback when database update succeeded but status check failed.
    func markOnboardingCompleteLocally() {
        onboardingCompleted = true
    }

    // MARK: - Private Methods

    /// Check for an existing session on app launch.
    private func checkExistingSession() async {
        do {
            let existingSession = try await client.auth.session
            // Only use the session if it's not expired
            if !existingSession.isExpired {
                session = existingSession
                // Check onboarding status for existing session
                try? await checkOnboardingStatus()
            } else {
                session = nil
                onboardingCompleted = false
            }
        } catch {
            // No existing session, user needs to sign in
            session = nil
            onboardingCompleted = false
        }
    }

    /// Start observing auth state changes (sign in, sign out, token refresh).
    private func startObservingAuthState() {
        authStateTask = Task {
            for await (event, session) in client.auth.authStateChanges {
                switch event {
                case .initialSession:
                    // Only use initial session if not expired
                    if let session, !session.isExpired {
                        self.session = session
                        // Check onboarding status when session is restored
                        try? await checkOnboardingStatus()
                    } else {
                        self.session = nil
                        self.onboardingCompleted = false
                    }
                case .signedIn:
                    self.session = session
                    // Check onboarding status when user signs in
                    try? await checkOnboardingStatus()
                case .signedOut:
                    self.session = nil
                    self.onboardingCompleted = false
                case .tokenRefreshed:
                    self.session = session
                    // Token refresh doesn't require onboarding status check
                case .userUpdated:
                    self.session = session
                    // User update might include onboarding changes, so re-check
                    try? await checkOnboardingStatus()
                default:
                    break
                }
            }
        }
    }

    /// Map Supabase auth errors to user-friendly messages.
    private func mapAuthError(_ error: Error) -> String {
        if let authError = error as? AuthError {
            switch authError {
            case .api(let message, _, _, _):
                // Common Supabase error messages
                if message.contains("Invalid login credentials") {
                    return "Invalid email or password"
                }
                if message.contains("User already registered") {
                    return "An account with this email already exists"
                }
                if message.contains("Email not confirmed") {
                    return "Please check your email to confirm your account"
                }
                return message
            default:
                return "Authentication failed. Please try again."
            }
        }
        return error.localizedDescription
    }
}
