//
//  OnboardingFlowView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI
import OSLog

/// Container view orchestrating the 6-screen onboarding flow.
/// Manages navigation between screens and handles data persistence to Supabase.
/// Screens 1-3: Basic info, race goals, performance metrics
/// Screens 4-6: Weekly training availability (swim, bike, run)
struct OnboardingFlowView: View {
    @ObservedObject var authService: AuthService
    @StateObject private var profileService = ProfileService()

    @State private var currentScreen: Int = 1
    @State private var transitionDirection: TransitionDirection = .forward
    @State private var basicInfo = BasicInfoData()
    @State private var raceGoals = RaceGoalsData()
    @State private var metrics = MetricsData()
    @State private var availability = AvailabilityData()

    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    /// Logger for onboarding flow operations
    private let logger = Logger(subsystem: "com.dromos.app", category: "OnboardingFlow")

    /// Navigation direction for transitions
    enum TransitionDirection {
        case forward
        case backward

        var transition: AnyTransition {
            switch self {
            case .forward:
                // Going forward: new screen slides in from right, old exits to left
                return .asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                )
            case .backward:
                // Going backward: new screen slides in from left, old exits to right
                return .asymmetric(
                    insertion: .move(edge: .leading),
                    removal: .move(edge: .trailing)
                )
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Screen navigation
                Group {
                    switch currentScreen {
                    case 1:
                        OnboardingScreen1View(
                            data: $basicInfo,
                            onNext: {
                                transitionDirection = .forward
                                currentScreen = 2
                            }
                        )
                        .transition(transitionDirection.transition)

                    case 2:
                        OnboardingScreen2View(
                            data: $raceGoals,
                            onBack: {
                                transitionDirection = .backward
                                currentScreen = 1
                            },
                            onNext: {
                                transitionDirection = .forward
                                currentScreen = 3
                            }
                        )
                        .transition(transitionDirection.transition)

                    case 3:
                        OnboardingScreen3View(
                            data: $metrics,
                            onBack: {
                                transitionDirection = .backward
                                currentScreen = 2
                            },
                            onNext: {
                                transitionDirection = .forward
                                currentScreen = 4
                            }
                        )
                        .transition(transitionDirection.transition)

                    case 4:
                        OnboardingAvailabilityView(
                            sport: .swim,
                            screenNumber: 4,
                            totalScreens: 6,
                            selectedDays: $availability.swimDays,
                            onNext: {
                                transitionDirection = .forward
                                currentScreen = 5
                            },
                            onBack: {
                                transitionDirection = .backward
                                currentScreen = 3
                            }
                        )
                        .transition(transitionDirection.transition)

                    case 5:
                        OnboardingAvailabilityView(
                            sport: .bike,
                            screenNumber: 5,
                            totalScreens: 6,
                            selectedDays: $availability.bikeDays,
                            onNext: {
                                transitionDirection = .forward
                                currentScreen = 6
                            },
                            onBack: {
                                transitionDirection = .backward
                                currentScreen = 4
                            }
                        )
                        .transition(transitionDirection.transition)

                    case 6:
                        OnboardingAvailabilityView(
                            sport: .run,
                            screenNumber: 6,
                            totalScreens: 6,
                            selectedDays: $availability.runDays,
                            onNext: { saveOnboardingData() },
                            onBack: {
                                transitionDirection = .backward
                                currentScreen = 5
                            }
                        )
                        .transition(transitionDirection.transition)

                    default:
                        EmptyView()
                    }
                }
                .animation(.easeInOut, value: currentScreen)

                // Loading overlay
                if isSaving {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()

                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Saving your profile...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(32)
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                    }
                }
            }
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
        }
        .alert("Error Saving Profile", isPresented: $showError) {
            Button("Retry") {
                saveOnboardingData()
            }
            Button("Cancel", role: .cancel) {
                isSaving = false
            }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Save Data

    /// Saves all onboarding data to Supabase and marks onboarding as complete.
    /// Updates AuthService state on success to trigger navigation to MainTabView.
    private func saveOnboardingData() {
        guard let userId = authService.currentUserId else {
            logger.error("Save failed: No user ID available")
            errorMessage = "Unable to identify user. Please sign in again."
            showError = true
            return
        }

        logger.info("Starting onboarding data save for user \(userId.uuidString, privacy: .public)")
        isSaving = true

        Task {
            do {
                // Combine all data from 6 screens (basic info, race goals, metrics, availability)
                let completeData = CompleteOnboardingData(
                    basicInfo: basicInfo,
                    raceGoals: raceGoals,
                    metrics: metrics,
                    availability: availability
                )

                logger.debug("Saving onboarding data: raceObjective=\(String(describing: completeData.raceObjective?.rawValue ?? "nil"), privacy: .public), hasAvailability=\(completeData.swimDays != nil || completeData.bikeDays != nil || completeData.runDays != nil, privacy: .public)")

                // Save to database
                try await profileService.saveOnboardingData(userId: userId, data: completeData)
                logger.info("Successfully saved onboarding data for user \(userId.uuidString, privacy: .public)")

                // Mark onboarding as complete
                try await profileService.markOnboardingComplete(userId: userId)
                logger.info("Successfully marked onboarding as complete for user \(userId.uuidString, privacy: .public)")

                // Update auth service state (triggers navigation to MainTabView)
                // If this fails, use fallback - we know save/markComplete succeeded
                do {
                    try await authService.checkOnboardingStatus()
                    logger.debug("Successfully updated auth service state")
                } catch {
                    // Fallback: Manually mark complete locally since database update succeeded
                    // This prevents user from being stuck on onboarding screen
                    logger.warning("Failed to check onboarding status, using local fallback: \(error.localizedDescription, privacy: .public)")
                    await MainActor.run {
                        authService.markOnboardingCompleteLocally()
                    }
                }

                await MainActor.run {
                    isSaving = false
                }
                logger.info("Onboarding save completed successfully for user \(userId.uuidString, privacy: .public)")

            } catch {
                logger.error("Failed to save onboarding data: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    isSaving = false
                    errorMessage = mapSaveError(error)
                    showError = true
                }
            }
        }
    }

    // MARK: - Error Handling

    /// Maps database and network errors to user-friendly messages.
    private func mapSaveError(_ error: Error) -> String {
        let errorString = error.localizedDescription.lowercased()

        // Database constraint violations
        if errorString.contains("check") || errorString.contains("constraint") {
            return "Some values are outside the valid range. Please check your entries and try again."
        }

        // Network errors
        if errorString.contains("network") || errorString.contains("connection") {
            return "Unable to connect. Please check your internet connection and try again."
        }

        // Generic fallback
        return "Unable to save your profile. Please try again."
    }
}

#Preview {
    OnboardingFlowView(authService: AuthService())
}
