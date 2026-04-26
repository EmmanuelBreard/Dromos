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
/// Provides access to Home (placeholder), Calendar (paged single-week plan view), and Profile sections.
/// Owns the PlanService, ProfileService, and StravaService, sharing them between tabs.
struct MainTabView: View {
    @ObservedObject var authService: AuthService

    /// Shared plan service for fetching and caching training plan data.
    /// Owned here so it survives tab switches; the Calendar tab is the only consumer of plan data.
    @StateObject private var planService = PlanService()

    /// Shared profile service for fetching and caching user profile data.
    /// Owned here so tabs can access athlete metrics (FTP, VMA, CSS).
    @StateObject private var profileService = ProfileService()

    /// Shared Strava service for OAuth, sync, and activity access.
    /// Owned here so it persists across tab switches and can auto-sync on launch.
    @StateObject private var stravaService = StravaService()


    /// Tracks the currently selected tab.
    @State private var selectedTab: AppTab = .home

    /// Toggled when the Calendar tab is re-selected. Triggers cache purge for the current week + snap to current week + Strava completion refetch in CalendarView.
    @State private var calendarReset: Bool = false

    /// Observed scene phase to trigger foreground-resume syncs.
    @Environment(\.scenePhase) private var scenePhase

    /// Custom binding that triggers view resets on tab navigation.
    /// Fires for both tab switches (Profile→Calendar) and same-tab re-taps (Calendar→Calendar).
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == .calendar { calendarReset.toggle() }
                selectedTab = newValue
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeView()
            }

            Tab("Calendar", systemImage: "calendar", value: .calendar) {
                CalendarView(
                    authService: authService,
                    planService: planService,
                    profileService: profileService,
                    stravaService: stravaService,
                    calendarReset: $calendarReset
                )
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
        .onChange(of: scenePhase) { _, newPhase in
            // Sync Strava activities whenever the app returns to the foreground.
            // Profile must already be loaded (isStravaConnected is non-nil) for sync to fire.
            // On cold launch this naturally no-ops because profileService.user is still nil
            // when scenePhase first fires .active — the .task {} path handles that case.
            if newPhase == .active, profileService.user?.isStravaConnected == true {
                Task { await stravaService.syncActivities() }
            }
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
