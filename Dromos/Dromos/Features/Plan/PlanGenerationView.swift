//
//  PlanGenerationView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 01/02/2026.
//

import SwiftUI
import OSLog

/// View displayed when user has completed onboarding but doesn't have an active training plan.
/// Provides a CTA to generate their plan, shows progress during generation (~140s), and handles errors.
struct PlanGenerationView: View {
    @ObservedObject var authService: AuthService
    @StateObject private var planService = PlanService()

    @State private var currentProgressPhraseIndex = 0
    @State private var progressPhraseTimer: Timer?

    /// Progress phrases that rotate every ~15 seconds during plan generation.
    private let progressPhrases = [
        "Analyzing your goals...",
        "Building weekly structure...",
        "Selecting workouts...",
        "Optimizing your schedule...",
        "Finalizing your plan..."
    ]

    /// Logger for plan generation operations
    private let logger = Logger(subsystem: "com.dromos.app", category: "PlanGeneration")

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Content based on state
                if planService.isGenerating {
                    // Generating state: show progress spinner and rotating phrases
                    generatingView
                } else if let errorMessage = planService.errorMessage {
                    // Error state: show error message and retry button
                    errorView(errorMessage: errorMessage)
                } else {
                    // Idle state: show CTA to generate plan
                    idleView
                }

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign Out") {
                        Task {
                            try? await authService.signOut()
                        }
                    }
                    .foregroundColor(.red)
                }
            }
            .onChange(of: planService.isGenerating) { _, isGenerating in
                if isGenerating {
                    startProgressPhraseRotation()
                } else {
                    stopProgressPhraseRotation()
                }
            }
            .onDisappear {
                stopProgressPhraseRotation()
            }
        }
    }

    // MARK: - Idle State View

    /// View shown when user hasn't started plan generation yet.
    private var idleView: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "figure.run.circle")
                .font(.system(size: 80))
                .foregroundStyle(.tint)

            // Headline
            VStack(spacing: 8) {
                Text("Your plan is ready to be built")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("We'll create a personalized training plan based on your goals and availability.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Generate button
            Button(action: {
                generatePlan()
            }) {
                Text("Generate My Plan")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
    }

    // MARK: - Generating State View

    /// View shown during plan generation with rotating progress phrases.
    private var generatingView: some View {
        VStack(spacing: 24) {
            // Progress spinner
            ProgressView()
                .scaleEffect(1.5)

            // Rotating progress phrase
            Text(progressPhrases[currentProgressPhraseIndex])
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .animation(.easeInOut, value: currentProgressPhraseIndex)

            Text("This may take a few minutes...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Error State View

    /// View shown when plan generation fails.
    private func errorView(errorMessage: String) -> some View {
        VStack(spacing: 24) {
            // Error icon
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.red)

            // Error message
            VStack(spacing: 8) {
                Text("Plan Generation Failed")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Retry button
            Button(action: {
                planService.errorMessage = nil
                generatePlan()
            }) {
                Text("Try Again")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
    }

    // MARK: - Actions

    /// Starts plan generation process.
    private func generatePlan() {
        logger.info("Starting plan generation")
        Task {
            do {
                try await planService.generatePlan()
                logger.info("Plan generation completed successfully")

                // Mark that user has a plan locally to trigger RootView transition
                // If status check fails, use fallback - we know generation succeeded
                do {
                    try await authService.checkPlanStatus()
                    logger.debug("Successfully updated auth service plan status")
                } catch {
                    // Fallback: Manually mark has plan locally since generation succeeded
                    // This prevents user from being stuck on plan generation screen
                    logger.warning("Failed to check plan status, using local fallback: \(error.localizedDescription, privacy: .public)")
                    await MainActor.run {
                        authService.markHasPlanLocally()
                    }
                }
            } catch {
                logger.error("Plan generation failed: \(error.localizedDescription, privacy: .public)")
                // Error is already set in planService.errorMessage
            }
        }
    }

    // MARK: - Progress Phrase Rotation

    /// Starts rotating progress phrases every ~15 seconds.
    private func startProgressPhraseRotation() {
        stopProgressPhraseRotation() // Ensure no existing timer

        // Set initial phrase
        currentProgressPhraseIndex = 0

        // Create timer to rotate phrases every 15 seconds
        progressPhraseTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { _ in
            Task { @MainActor in
                currentProgressPhraseIndex = (currentProgressPhraseIndex + 1) % progressPhrases.count
            }
        }
    }

    /// Stops rotating progress phrases.
    private func stopProgressPhraseRotation() {
        progressPhraseTimer?.invalidate()
        progressPhraseTimer = nil
        currentProgressPhraseIndex = 0
    }
}

#Preview("Idle") {
    PlanGenerationView(authService: AuthService())
}

#Preview("Generating") {
    let view = PlanGenerationView(authService: AuthService())
    view.planService.isGenerating = true
    return view
}

#Preview("Error") {
    let view = PlanGenerationView(authService: AuthService())
    view.planService.errorMessage = "Unable to connect to the server. Please check your internet connection and try again."
    return view
}

