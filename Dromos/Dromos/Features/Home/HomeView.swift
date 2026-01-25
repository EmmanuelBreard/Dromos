//
//  HomeView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// Home dashboard view - entry point after authentication.
/// Will display training overview, upcoming workouts, and quick actions.
struct HomeView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Image(systemName: "figure.run")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)
                Text("Welcome to Dromos")
                    .font(.title)
                Text("Your triathlon training starts here")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Home")
        }
    }
}

#Preview {
    HomeView()
}
