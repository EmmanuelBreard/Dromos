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
/// 2. Authenticated but onboarding incomplete → coach chat (OnboardingFlowView)
/// 3. Authenticated and onboarding complete → MainTabView
struct RootView: View {
    @StateObject private var authService = AuthService()
    /// Set when the coach chat finishes, so the waiting screen starts generation
    /// instead of waiting for another tap.
    @State private var autoStartPlan = false

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
                .background(Color(.systemBackground))
            } else if !authService.isAuthenticated {
                // Not signed in → show auth screens (login/signup)
                AuthView(authService: authService)
            } else if !authService.onboardingCompleted {
                // Signed in but onboarding incomplete → coach chat
                OnboardingFlowView(authService: authService, autoStartPlan: $autoStartPlan)
            } else if !authService.hasPlan {
                // Signed in and onboarded but no active plan → show plan generation
                PlanGenerationView(authService: authService, autoStart: autoStartPlan)
            } else {
                // Signed in, onboarded, and has plan → show main app
                MainTabView(authService: authService)
            }
        }
        .animation(.none, value: authService.isInitializing)
        .animation(.default, value: authService.isAuthenticated)
        .animation(.default, value: authService.onboardingCompleted)
        .animation(.default, value: authService.hasPlan)
    }
}

#Preview("Logged Out") {
    RootView()
}
