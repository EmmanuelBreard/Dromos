//
//  MainTabView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// Main tab navigation for authenticated users.
/// Provides access to Home, Calendar, and Profile sections.
/// Owns the PlanService and shares it between Home and Calendar tabs.
struct MainTabView: View {
    @ObservedObject var authService: AuthService
    
    /// Shared plan service for fetching and caching training plan data.
    /// Owned here so both Home and Calendar tabs share the same data.
    @StateObject private var planService = PlanService()

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeView(authService: authService, planService: planService)
            }

            Tab("Calendar", systemImage: "calendar") {
                CalendarPlanView(authService: authService, planService: planService)
            }

            Tab("Profile", systemImage: "person") {
                ProfileView(authService: authService)
            }
        }
        .task {
            await loadPlan()
        }
    }
    
    // MARK: - Private Methods
    
    /// Loads the training plan if user is authenticated.
    private func loadPlan() async {
        guard let userId = authService.currentUserId else { return }
        
        do {
            try await planService.fetchFullPlan(userId: userId)
        } catch {
            // Error is already captured in planService.errorMessage
        }
    }
}

#Preview {
    MainTabView(authService: AuthService())
}
