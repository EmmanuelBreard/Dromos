//
//  SessionCardView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 01/02/2026.
//

import SwiftUI

/// Rich session card for the Home tab.
/// Displays sport icon, workout name, duration, type tag, and swim distance (if applicable).
struct SessionCardView: View {
    let session: PlanSession
    let swimDistance: Int?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: Sport icon + duration + display name
            HStack(spacing: 12) {
                // Sport icon with colored background
                Image(systemName: session.sportIcon)
                    .font(.title2)
                    .foregroundColor(session.sportColor)
                    .frame(width: 40, height: 40)
                    .background(session.sportColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                VStack(alignment: .leading, spacing: 2) {
                    // Workout name
                    Text(session.displayName)
                        .font(.headline)
                    
                    // Duration
                    Text(session.formattedDuration)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Brick indicator (if applicable)
                if session.isBrick {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption)
                        Text("BRICK")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
            
            // Row 2: Type tag chip
            HStack {
                Text(session.type.uppercased())
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(session.sportColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(session.sportColor.opacity(0.15))
                    .clipShape(Capsule())
                
                Spacer()
            }
            
            // Row 3: Swim distance (only for swim sessions)
            if let distance = swimDistance {
                HStack(spacing: 6) {
                    Image(systemName: "ruler")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Est. Distance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(formatDistance(distance))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Helper Methods
    
    /// Formats distance in meters to a readable string.
    /// Uses "km" for distances >= 1000m, otherwise "m".
    private func formatDistance(_ meters: Int) -> String {
        if meters >= 1000 {
            let km = Double(meters) / 1000.0
            // Format with one decimal if not a whole number
            if km.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(km)) km"
            } else {
                return String(format: "%.1f km", km)
            }
        } else {
            return "\(meters) m"
        }
    }
}

// MARK: - Rest Day Card

/// Simple card for rest days.
/// Shows bed icon with "Rest Day" label.
struct RestDayCardView: View {
    var body: some View {
        HStack(spacing: 12) {
            // Bed icon
            Image(systemName: "bed.double.fill")
                .font(.title2)
                .foregroundColor(.secondary)
                .frame(width: 40, height: 40)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            
            Text("Rest Day")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Race Day Card

/// Celebratory card for race days.
/// Shows trophy icon with "Race Day" label and optional race objective (e.g., "Olympic", "Ironman 70.3").
struct RaceDayCardView: View {
    let raceObjective: String?

    var body: some View {
        HStack(spacing: 12) {
            // Trophy icon
            Image(systemName: "trophy.fill")
                .font(.title2)
                .foregroundColor(.orange)
                .frame(width: 40, height: 40)
                .background(Color.orange.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text("Race Day")
                    .font(.headline)
                    .foregroundColor(.orange)

                // Optional race objective subtitle
                if let objective = raceObjective {
                    Text(objective)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Previews

#Preview("Session Card - Swim") {
    let session = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Monday",
        sport: "swim",
        type: "Easy",
        templateId: "SWIM_Easy_01",
        durationMinutes: 45,
        isBrick: false,
        notes: nil,
        orderInDay: 0
    )
    
    return SessionCardView(session: session, swimDistance: 550)
        .padding()
}

#Preview("Session Card - Bike with Brick") {
    let session = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Saturday",
        sport: "bike",
        type: "Tempo",
        templateId: "BIKE_Tempo_01",
        durationMinutes: 90,
        isBrick: true,
        notes: nil,
        orderInDay: 0
    )
    
    return SessionCardView(session: session, swimDistance: nil)
        .padding()
}

#Preview("Session Card - Run") {
    let session = PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Tuesday",
        sport: "run",
        type: "Intervals",
        templateId: "RUN_Intervals_01",
        durationMinutes: 60,
        isBrick: false,
        notes: nil,
        orderInDay: 0
    )
    
    return SessionCardView(session: session, swimDistance: nil)
        .padding()
}

#Preview("Rest Day Card") {
    RestDayCardView()
        .padding()
}

#Preview("Race Day Card - With Objective") {
    RaceDayCardView(raceObjective: "Ironman 70.3")
        .padding()
}

#Preview("Race Day Card - No Objective") {
    RaceDayCardView(raceObjective: nil)
        .padding()
}

