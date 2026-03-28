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
            if authService.isInitializing {
                VStack(spacing: 24) {
                    Image("DromosLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120)
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !authService.isAuthenticated {
                // Not signed in → show auth screens (login/signup)
                AuthView(authService: authService)
            } else if !authService.onboardingCompleted {
                // Signed in but onboarding incomplete → show onboarding flow
                OnboardingFlowView(authService: authService)
            } else if !authService.hasPlan {
                // Signed in and onboarded but no active plan → show plan generation
                PlanGenerationView(authService: authService)
            } else {
                // Signed in, onboarded, and has plan → show main app
                MainTabView(authService: authService)
            }
        }
        .animation(.default, value: authService.isAuthenticated)
        .animation(.default, value: authService.onboardingCompleted)
        .animation(.default, value: authService.hasPlan)
    }
}

#Preview("Logged Out") {
    RootView()
}
