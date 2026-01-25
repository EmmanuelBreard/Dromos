//
//  RootView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// Root view that switches between auth and main app based on authentication state.
struct RootView: View {
    @StateObject private var authService = AuthService()

    var body: some View {
        Group {
            if authService.isAuthenticated {
                MainTabView(authService: authService)
            } else {
                AuthView(authService: authService)
            }
        }
        .animation(.default, value: authService.isAuthenticated)
    }
}

#Preview("Logged Out") {
    RootView()
}
