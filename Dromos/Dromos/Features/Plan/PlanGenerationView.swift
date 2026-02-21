//
//  PlanGenerationView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 01/02/2026.
//

import SwiftUI
import OSLog
import Combine

/// View displayed when user has completed onboarding but doesn't have an active training plan.
/// Provides a CTA to generate their plan, shows progress during generation (~140s), and handles errors.
struct PlanGenerationView: View {
    @ObservedObject var authService: AuthService
    @StateObject private var planService = PlanService()

    @State private var generationStartTime: Date?
    @State private var elapsedSeconds: Double = 0
    @State private var generationCompleted: Bool = false
    @State private var timerCancellable: AnyCancellable?
    @State private var shimmerPhase: CGFloat = 0

    /// Logger for plan generation operations
    private let logger = Logger(subsystem: "com.getdromos.app", category: "PlanGeneration")

    /// Step thresholds for progress bar
    private let stepThresholds: [(threshold: Double, label: String, step: Int)] = [
        (0, "Periodizing your plan", 1),
        (20, "Structuring your weeks", 2),
        (40, "Selecting your workouts", 3)
    ]

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
                    startProgressTimer()
                } else {
                    stopProgressTimer()
                }
            }
            .onDisappear {
                stopProgressTimer()
            }
        }
    }

    // MARK: - Idle State View

    /// View shown when user hasn't started plan generation yet.
    private var idleView: some View {
        VStack(spacing: 24) {
            // Icon
            Image("DromosLogo")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 60)

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

    /// View shown during plan generation with stepped progress bar.
    private var generatingView: some View {
        VStack(spacing: 24) {
            // Custom progress bar with shimmer wave
            GeometryReader { geometry in
                let barWidth = geometry.size.width
                let filledWidth = barWidth * progress
                let shimmerWidth: CGFloat = 60

                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green.opacity(0.2))

                    // Filled portion with shimmer overlay
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                        .frame(width: max(0, filledWidth))
                        .overlay(
                            // Shimmer wave — lighter green sweep across filled area
                            LinearGradient(
                                colors: [
                                    .clear,
                                    Color.white.opacity(0.4),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: shimmerWidth)
                            .offset(x: -filledWidth / 2 - shimmerWidth / 2 + (filledWidth + shimmerWidth) * shimmerPhase)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .animation(.easeInOut(duration: 0.5), value: progress)
            }
            .frame(height: 8)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1.0
                }
            }

            // Step label
            Text("Step \(currentStep) of 3 — \(currentLabel)")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Computed Properties

    /// Current step based on elapsed time
    private var currentStep: Int {
        for i in stride(from: stepThresholds.count - 1, through: 0, by: -1) {
            if elapsedSeconds >= stepThresholds[i].threshold {
                return stepThresholds[i].step
            }
        }
        return stepThresholds[0].step
    }

    /// Current label based on elapsed time
    private var currentLabel: String {
        if elapsedSeconds > 65 && !generationCompleted {
            return "Finalizing..."
        }

        for i in stride(from: stepThresholds.count - 1, through: 0, by: -1) {
            if elapsedSeconds >= stepThresholds[i].threshold {
                return stepThresholds[i].label
            }
        }

        return stepThresholds[0].label
    }

    /// Progress value (0.0–1.0) based on elapsed time
    private var progress: Double {
        if generationCompleted {
            return 1.0
        }

        // 0-20s → 0.0-0.33
        if elapsedSeconds < 20 {
            return (elapsedSeconds / 20.0) * 0.33
        }
        // 20-40s → 0.33-0.66
        else if elapsedSeconds < 40 {
            return 0.33 + ((elapsedSeconds - 20) / 20.0) * 0.33
        }
        // 40-65s → 0.66-0.90
        else if elapsedSeconds < 65 {
            return 0.66 + ((elapsedSeconds - 40) / 25.0) * 0.24
        }
        // Cap at 0.90 if generation is taking longer than expected
        else {
            return 0.90
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

                // Mark generation as completed to snap progress bar to 100%
                generationCompleted = true

                // Brief delay to let user see the bar hit 100%
                try? await Task.sleep(for: .milliseconds(600))

                // Mark that user has a plan locally to trigger RootView transition
                // If status check fails, use fallback - we know generation succeeded
                do {
                    try await authService.checkPlanStatus()
                    logger.debug("Successfully updated auth service plan status")
                } catch {
                    // Fallback: Manually mark has plan locally since generation succeeded
                    // This prevents user from being stuck on plan generation screen
                    logger.warning("Failed to check plan status, using local fallback: \(error.localizedDescription, privacy: .public)")
                    // Already on MainActor, no need for MainActor.run
                    authService.markHasPlanLocally()
                }
            } catch {
                logger.error("Plan generation failed: \(error.localizedDescription, privacy: .public)")
                // Error is already set in planService.errorMessage
                // Timer cleanup handled by .onChange(of: planService.isGenerating)
            }
        }
    }

    // MARK: - Progress Timer

    /// Starts the progress timer that updates elapsed time every 0.5 seconds.
    private func startProgressTimer() {
        stopProgressTimer() // Ensure no existing timer

        // Reset state
        generationStartTime = Date()
        elapsedSeconds = 0
        generationCompleted = false
        shimmerPhase = 0

        // Create timer to update elapsed time every 0.5 seconds
        timerCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                guard let startTime = generationStartTime else { return }
                elapsedSeconds = Date().timeIntervalSince(startTime)
            }
    }

    /// Stops the progress timer.
    private func stopProgressTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        generationStartTime = nil
        elapsedSeconds = 0
        generationCompleted = false
    }
}

#Preview("Idle") {
    PlanGenerationView(authService: AuthService())
}

