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
/// Owns the PlanService and shares it between Home and Calendar tabs.
struct MainTabView: View {
    @ObservedObject var authService: AuthService

    /// Shared plan service for fetching and caching training plan data.
    /// Owned here so both Home and Calendar tabs share the same data.
    @StateObject private var planService = PlanService()

    /// Tracks the currently selected tab for scroll-reset on Home re-selection.
    @State private var selectedTab: AppTab = .home

    /// Toggled each time the Home tab is re-selected; the toggle (not the value) drives
    /// scroll reset in HomeView via a @Binding that stays live even when the tab is inactive.
    @State private var homeScrollReset: Bool = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeView(authService: authService, planService: planService, scrollReset: $homeScrollReset)
            }

            Tab("Calendar", systemImage: "calendar", value: .calendar) {
                CalendarPlanView(authService: authService, planService: planService)
            }

            Tab("Profile", systemImage: "person", value: .profile) {
                ProfileView(authService: authService)
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .home {
                homeScrollReset.toggle()
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
