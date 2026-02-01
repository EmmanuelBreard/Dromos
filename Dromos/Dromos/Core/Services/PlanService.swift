//
//  PlanService.swift
//  Dromos
//
//  Created by Emmanuel Breard on 01/02/2026.
//

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
            try await client.functions.invoke(
                "generate-plan",
                options: FunctionInvokeOptions(body: nil, headers: [:])
            )

            // Success — plan generation completed
            // The plan is now in the database with status='active'
            // Edge Function returns 4xx/5xx on errors, which are handled in the catch block
        } catch {
            // Map various error types to user-friendly messages
            if let functionsError = error as? FunctionsError {
                switch functionsError {
                case .httpError(let code, let data):
                    // HTTP error from Edge Function
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMessage = json["error"] as? String {
                        self.errorMessage = errorMessage
                        throw PlanGenerationError.serverError(errorMessage)
                    } else {
                        let message = "Plan generation failed (HTTP \(code)). Please try again."
                        self.errorMessage = message
                        throw PlanGenerationError.serverError(message)
                    }
                case .relayError(let message):
                    // Network/timeout error
                    let userMessage = "Unable to connect to the server. Please check your internet connection and try again."
                    self.errorMessage = userMessage
                    throw PlanGenerationError.networkError(message)
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

