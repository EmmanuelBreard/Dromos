//
//  HomeView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// Lightweight placeholder for the Home tab.
/// The full paged training-plan view lives in CalendarView (Calendar tab).
struct HomeView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image("DromosLogo")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 48)
            Text("Coming soon")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pageSurface)
    }
}

#Preview {
    HomeView()
}
