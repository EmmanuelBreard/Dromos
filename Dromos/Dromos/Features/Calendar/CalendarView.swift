//
//  CalendarView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// Calendar view for training schedule.
/// Will display workouts by day/week/month with completion status.
struct CalendarView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Image(systemName: "calendar")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)
                Text("Training Calendar")
                    .font(.title)
                Text("Your workout schedule will appear here")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Calendar")
        }
    }
}

#Preview {
    CalendarView()
}
