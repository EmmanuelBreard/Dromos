//
//  MainTabView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// Tabs available in the main navigation.
enum AppTab: Hashable {
    case home, calendar, profile
}

/// Main tab navigation for authenticated users.
/// Provides access to Home, Calendar, and Profile sections.
/// Owns the PlanService and ProfileService, sharing them between tabs.
struct MainTabView: View {
    @ObservedObject var authService: AuthService

    /// Shared plan service for fetching and caching training plan data.
    /// Owned here so both Home and Calendar tabs share the same data.
    @StateObject private var planService = PlanService()
    
    /// Shared profile service for fetching and caching user profile data.
    /// Owned here so tabs can access athlete metrics (FTP, VMA, CSS).
    @StateObject private var profileService = ProfileService()

    /// Tracks the currently selected tab for scroll-reset on Home re-selection.
    @State private var selectedTab: AppTab = .home

    /// Toggled each time the Home tab is re-selected; the toggle (not the value) drives
    /// scroll reset in HomeView via a @Binding that stays live even when the tab is inactive.
    @State private var homeScrollReset: Bool = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeView(
                    authService: authService,
                    planService: planService,
                    profileService: profileService,
                    scrollReset: $homeScrollReset
                )
            }

            Tab("Calendar", systemImage: "calendar", value: .calendar) {
                CalendarPlanView(authService: authService, planService: planService)
            }

            Tab("Profile", systemImage: "person", value: .profile) {
                // FIX #6: Pass shared profileService to ProfileView
                ProfileView(authService: authService, profileService: profileService)
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .home {
                homeScrollReset.toggle()
            }
        }
        .task {
            await loadData()
        }
    }
    
    // MARK: - Private Methods
    
    /// Loads both training plan and user profile if user is authenticated.
    private func loadData() async {
        guard let userId = authService.currentUserId else { return }
        
        // Load plan and profile in parallel
        async let planLoad: () = loadPlan(userId: userId)
        async let profileLoad: () = loadProfile(userId: userId)
        
        _ = await (planLoad, profileLoad)
    }
    
    /// Loads the training plan.
    private func loadPlan(userId: UUID) async {
        do {
            try await planService.fetchFullPlan(userId: userId)
        } catch {
            // Error is already captured in planService.errorMessage
        }
    }
    
    /// Loads the user profile.
    private func loadProfile(userId: UUID) async {
        do {
            try await profileService.fetchProfile(userId: userId)
        } catch {
            // Error is already captured in profileService.errorMessage
        }
    }
}

#Preview {
    MainTabView(authService: AuthService())
}
