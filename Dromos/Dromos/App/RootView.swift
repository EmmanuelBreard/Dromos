//
//  RootView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// Root view that manages app navigation based on authentication and onboarding state.
///
/// Navigation Flow:
/// 1. Not authenticated → AuthView (login/signup)
/// 2. Authenticated but onboarding incomplete → OnboardingFlowView
/// 3. Authenticated and onboarding complete → MainTabView
struct RootView: View {
    @StateObject private var authService = AuthService()

    var body: some View {
        Group {
            if !authService.isAuthenticated {
                // Not signed in → show auth screens (login/signup)
                AuthView(authService: authService)
            } else if !authService.onboardingCompleted {
                // Signed in but onboarding incomplete → show onboarding flow
                OnboardingFlowView(authService: authService)
            } else {
                // Signed in and onboarded → show main app
                MainTabView(authService: authService)
            }
        }
        .animation(.default, value: authService.isAuthenticated)
        .animation(.default, value: authService.onboardingCompleted)
        .task {
            // Check onboarding status on app launch if user is already authenticated
            // This ensures onboardingCompleted is up-to-date with the database
            if authService.isAuthenticated {
                try? await authService.checkOnboardingStatus()
            }
        }
    }
}

#Preview("Logged Out") {
    RootView()
}
