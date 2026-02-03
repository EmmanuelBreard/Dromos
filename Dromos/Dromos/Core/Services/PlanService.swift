//
//  PlanService.swift
//  Dromos
//
//  Created by Emmanuel Breard on 01/02/2026.
//

import Combine
import Foundation
import Supabase

/// Service for generating training plans via Edge Function.
/// Handles the long-running plan generation process (~140s) with progress tracking.
@MainActor
final class PlanService: ObservableObject {

    // MARK: - Published Properties

    /// Whether plan generation is currently in progress.
    @Published private(set) var isGenerating: Bool = false

    /// Last error message from plan generation, nil if no error.
    @Published var errorMessage: String?

    /// Current training plan, nil if not loaded.
    @Published private(set) var trainingPlan: TrainingPlan?

    /// Whether plan data is currently being fetched.
    @Published private(set) var isLoadingPlan: Bool = false

    // MARK: - Private Properties

    private let client = SupabaseClientProvider.client

    // MARK: - Public Methods

    /// Generate a training plan for the current user.
    /// Calls the `generate-plan` Edge Function which reads the user's profile server-side.
    /// The Bearer token is sent automatically by the SDK from the current session.
    /// - Throws: Error if generation fails
    func generatePlan() async throws {
        isGenerating = true
        errorMessage = nil

        defer { isGenerating = false }

        do {
            // Invoke the Edge Function (no body needed — Edge Function reads profile server-side)
            // The SDK automatically includes the Bearer token from the current session
            // Note: The SDK's FunctionsClient.requestIdleTimeout is hardcoded to 150s.
            // Edge Function takes ~140s, leaving only a 10s margin. If timeout issues occur,
            // we may need to configure URLSession timeout in SupabaseClientOptions.
            try await client.functions.invoke("generate-plan")

            // Success — plan generation completed
            // The plan is now in the database with status='active'
            // Edge Function returns 4xx/5xx on errors, which are handled in the catch block
        } catch {
            // Map various error types to user-friendly messages
            if let functionsError = error as? FunctionsError {
                switch functionsError {
                case .httpError(let code, let data):
                    // HTTP error from Edge Function
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMessage = json["error"] as? String {
                        self.errorMessage = errorMessage
                        throw PlanGenerationError.serverError(errorMessage)
                    } else {
                        let message = "Plan generation failed (HTTP \(code)). Please try again."
                        self.errorMessage = message
                        throw PlanGenerationError.serverError(message)
                    }
                case .relayError:
                    // Network/timeout error
                    let userMessage = "Unable to connect to the server. Please check your internet connection and try again."
                    self.errorMessage = userMessage
                    throw PlanGenerationError.networkError(userMessage)
                @unknown default:
                    let message = "An unexpected error occurred. Please try again."
                    self.errorMessage = message
                    throw PlanGenerationError.unknown(message)
                }
            } else if let planError = error as? PlanGenerationError {
                // Re-throw our custom errors (already have errorMessage set)
                throw planError
            } else {
                // Generic error
                let message = "Plan generation failed. Please try again."
                self.errorMessage = message
                throw PlanGenerationError.unknown(error.localizedDescription)
            }
        }
    }

    /// Fetch the full training plan for a user.
    /// Performs a nested query to fetch training_plans → plan_weeks → plan_sessions.
    /// - Parameter userId: The user's ID
    /// - Throws: Error if fetch fails
    func fetchFullPlan(userId: UUID) async throws {
        isLoadingPlan = true
        errorMessage = nil

        defer { isLoadingPlan = false }

        do {
            // Nested select: training_plans → plan_weeks → plan_sessions
            // PostgREST nested selects don't guarantee order, so we sort client-side
            let response: TrainingPlan = try await client
                .from("training_plans")
                .select("*, plan_weeks(*, plan_sessions(*))")
                .eq("user_id", value: userId.uuidString)
                .eq("status", value: "active")
                .single()
                .execute()
                .value

            // Sort planWeeks by weekNumber
            var sortedPlan = response
            sortedPlan.planWeeks.sort { $0.weekNumber < $1.weekNumber }

            let weekdayOrder: [String: Int] = [
                "Monday": 0,
                "Tuesday": 1,
                "Wednesday": 2,
                "Thursday": 3,
                "Friday": 4,
                "Saturday": 5,
                "Sunday": 6
            ]

            // Sort planSessions within each week by day order then orderInDay
            for weekIndex in sortedPlan.planWeeks.indices {
                sortedPlan.planWeeks[weekIndex].planSessions.sort { session1, session2 in
                    let dayOrder1 = weekdayOrder[session1.day] ?? 99
                    let dayOrder2 = weekdayOrder[session2.day] ?? 99
                    if dayOrder1 != dayOrder2 {
                        return dayOrder1 < dayOrder2
                    }
                    return session1.orderInDay < session2.orderInDay
                }
            }

            self.trainingPlan = sortedPlan
        } catch {
            errorMessage = "Failed to load training plan"
            throw error
        }
    }

    /// Clear the cached training plan (e.g., on sign out).
    func clearPlan() {
        trainingPlan = nil
        errorMessage = nil
    }
}

// MARK: - Error Types

/// Errors that can occur during plan generation.
enum PlanGenerationError: LocalizedError {
    case serverError(String)
    case networkError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .serverError(let message):
            return message
        case .networkError(let message):
            return message
        case .unknown(let message):
            return message
        }
    }
}

