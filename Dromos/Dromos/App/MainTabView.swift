//
//  MainTabView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// Main tab navigation for authenticated users.
/// Provides access to Home, Calendar, and Profile sections.
struct MainTabView: View {
    @ObservedObject var authService: AuthService

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeView()
            }

            Tab("Calendar", systemImage: "calendar") {
                CalendarPlanView(authService: authService)
            }

            Tab("Profile", systemImage: "person") {
                ProfileView(authService: authService)
            }
        }
    }
}

#Preview {
    MainTabView(authService: AuthService())
}
