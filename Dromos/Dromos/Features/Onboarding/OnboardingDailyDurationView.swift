//
//  OnboardingDailyDurationView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 26/01/2026.
//

import SwiftUI

/// Screen 7 of onboarding: Collect daily training duration.
/// Only shows days that are available across any sport (union of swim/bike/run days).
/// Each day has a dropdown picker with 15-minute increments from 30min to 7hr.
struct OnboardingDailyDurationView: View {
    let screenNumber: Int
    let totalScreens: Int
    
    /// Union of all available days from swim/bike/run availability screens
    let availableDays: [String]
    
    @Binding var durationData: DailyDurationData
    var onNext: () -> Void
    var onBack: () -> Void
    
    @State private var showErrors = false
    
    /// All days of the week in order
    private let allDays = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
    ]
    
    /// Duration options in minutes (30min to 7hr in 15min increments)
    private let durationOptions: [Int] = {
        var options: [Int] = []
        for minutes in stride(from: 30, through: 420, by: 15) {
            options.append(minutes)
        }
        return options
    }()
    
    /// Default duration: 1 hour (60 minutes)
    private let defaultDuration = 60
    
    // MARK: - Validation
    
    /// Validates that all shown days have a duration selected.
    /// Since we pre-fill with defaults, this should always be valid unless somehow cleared.
    private var isFormValid: Bool {
        availableDays.allSatisfy { day in
            getDuration(for: day) != nil
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 24) {
            // Progress indicator
            Text("\(screenNumber) of \(totalScreens)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Title
            VStack(alignment: .leading, spacing: 8) {
                Text("Daily Training Duration")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("How long can you train each day?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Duration pickers for available days
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(availableDays, id: \.self) { day in
                        DurationRow(
                            day: day,
                            selectedDuration: Binding(
                                get: { getDuration(for: day) ?? defaultDuration },
                                set: { setDuration(for: day, minutes: $0) }
                            ),
                            durationOptions: durationOptions
                        )
                    }
                }
                .padding(.vertical)
            }
            
            if showErrors && !isFormValid {
                Text("Please select a duration for all days")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            Spacer()
            
            // Navigation buttons
            HStack(spacing: 16) {
                Button(action: onBack) {
                    Text("Back")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.secondary.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
                
                Button(action: {
                    showErrors = true
                    if isFormValid {
                        onNext()
                    }
                }) {
                    Text("Complete")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
        .onAppear {
            // Initialize default values for all available days if not already set
            for day in availableDays {
                if getDuration(for: day) == nil {
                    setDuration(for: day, minutes: defaultDuration)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Gets the duration in minutes for a given day.
    private func getDuration(for day: String) -> Int? {
        switch day {
        case "Monday": return durationData.monDuration
        case "Tuesday": return durationData.tueDuration
        case "Wednesday": return durationData.wedDuration
        case "Thursday": return durationData.thuDuration
        case "Friday": return durationData.friDuration
        case "Saturday": return durationData.satDuration
        case "Sunday": return durationData.sunDuration
        default: return nil
        }
    }
    
    /// Sets the duration in minutes for a given day.
    private func setDuration(for day: String, minutes: Int) {
        switch day {
        case "Monday": durationData.monDuration = minutes
        case "Tuesday": durationData.tueDuration = minutes
        case "Wednesday": durationData.wedDuration = minutes
        case "Thursday": durationData.thuDuration = minutes
        case "Friday": durationData.friDuration = minutes
        case "Saturday": durationData.satDuration = minutes
        case "Sunday": durationData.sunDuration = minutes
        default: break
        }
    }
    
    /// Formats duration in minutes as a human-readable string (e.g., "1hr 15min", "30min").
    static func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        
        if hours == 0 {
            return "\(mins)min"
        } else if mins == 0 {
            return "\(hours)hr"
        } else {
            return "\(hours)hr \(mins)min"
        }
    }
}

// MARK: - DurationRow Component

/// A row displaying a day label and duration picker.
struct DurationRow: View {
    let day: String
    @Binding var selectedDuration: Int
    let durationOptions: [Int]
    
    var body: some View {
        HStack {
            Text(day)
                .font(.body)
                .fontWeight(.medium)
            
            Spacer()
            
            Picker("Duration", selection: $selectedDuration) {
                ForEach(durationOptions, id: \.self) { minutes in
                    Text(OnboardingDailyDurationView.formatDuration(minutes))
                        .tag(minutes)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Previews

#Preview("Daily Duration") {
    OnboardingDailyDurationView(
        screenNumber: 7,
        totalScreens: 7,
        availableDays: ["Monday", "Wednesday", "Friday", "Saturday", "Sunday"],
        durationData: .constant(DailyDurationData()),
        onNext: {},
        onBack: {}
    )
}

