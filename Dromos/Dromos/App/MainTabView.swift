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
/// Owns the PlanService, ProfileService, and StravaService, sharing them between tabs.
struct MainTabView: View {
    @ObservedObject var authService: AuthService

    /// Shared plan service for fetching and caching training plan data.
    /// Owned here so both Home and Calendar tabs share the same data.
    @StateObject private var planService = PlanService()

    /// Shared profile service for fetching and caching user profile data.
    /// Owned here so tabs can access athlete metrics (FTP, VMA, CSS).
    @StateObject private var profileService = ProfileService()

    /// Shared Strava service for OAuth, sync, and activity access.
    /// Owned here so it persists across tab switches and can auto-sync on launch.
    @StateObject private var stravaService = StravaService()

    /// Tracks the currently selected tab for scroll-reset on Home re-selection.
    @State private var selectedTab: AppTab = .home

    /// Toggled each time the Home tab is re-selected; the toggle (not the value) drives
    /// scroll reset in HomeView via a @Binding that stays live even when the tab is inactive.
    @State private var homeScrollReset: Bool = false

    /// Toggled each time the Calendar tab is re-selected; the toggle (not the value) drives
    /// week reset in CalendarPlanView via a @Binding that stays live even when the tab is inactive.
    @State private var calendarReset: Bool = false

    /// Custom binding that triggers view resets on tab navigation.
    /// Fires for both tab switches (Calendar→Home) and same-tab re-taps (Home→Home).
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == .home { homeScrollReset.toggle() }
                if newValue == .calendar { calendarReset.toggle() }
                selectedTab = newValue
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeView(
                    authService: authService,
                    planService: planService,
                    profileService: profileService,
                    scrollReset: $homeScrollReset
                )
            }

            Tab("Calendar", systemImage: "calendar", value: .calendar) {
                CalendarPlanView(authService: authService, planService: planService, profileService: profileService, calendarReset: $calendarReset)
            }

            Tab("Profile", systemImage: "person", value: .profile) {
                ProfileView(
                    authService: authService,
                    profileService: profileService,
                    stravaService: stravaService
                )
            }
        }
        .task {
            await loadData()
        }
    }
    
    // MARK: - Private Methods
    
    /// Loads training plan, user profile, and triggers Strava auto-sync if connected.
    private func loadData() async {
        guard let userId = authService.currentUserId else { return }

        // Load plan and profile in parallel
        async let planLoad: () = loadPlan(userId: userId)
        async let profileLoad: () = loadProfile(userId: userId)

        _ = await (planLoad, profileLoad)

        // Auto-sync Strava activities on app open if the user has connected Strava.
        // Profile must be loaded first so isStravaConnected reflects the DB state.
        if profileService.user?.isStravaConnected == true {
            await stravaService.syncActivities()
        }
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

