//
//  OnboardingAvailabilityView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 26/01/2026.
//

import SwiftUI

/// A reusable onboarding screen to collect weekly training availability for a specific sport.
struct OnboardingAvailabilityView: View {
    /// The sport for which availability is being collected.
    enum Sport: String {
        case swim = "Swim"
        case bike = "Bike"
        case run = "Run"
        
        var title: String {
            "\(self.rawValue) Availability"
        }
        
        var icon: String {
            switch self {
            case .swim: return "figure.pool.swim"
            case .bike: return "figure.outdoor.cycle"
            case .run: return "figure.run"
            }
        }
        
        var color: Color {
            switch self {
            case .swim: return .blue
            case .bike: return .orange
            case .run: return .green
            }
        }
    }
    
    let sport: Sport
    let screenNumber: Int
    let totalScreens: Int
    @Binding var selectedDays: [String]
    var onNext: () -> Void
    var onBack: () -> Void
    
    @State private var showErrors = false
    
    private let allDays = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
    ]
    
    // MARK: - Validation
    
    /// Validates that at least one day is selected.
    private var isFormValid: Bool {
        !selectedDays.isEmpty
    }
    
    /// Checks if "Any day" (all days) are selected.
    private var isAnyDaySelected: Bool {
        selectedDays.count == allDays.count
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 24) {
            // Progress indicator
            Text("\(screenNumber) of \(totalScreens)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Title and Icon
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: sport.icon)
                        .font(.title)
                        .foregroundColor(sport.color)
                    Text(sport.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                Text("When can you train for your \(sport.rawValue.lowercased()) sessions?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Grid of days
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(allDays, id: \.self) { day in
                    DayButton(
                        day: day,
                        isSelected: selectedDays.contains(day),
                        color: sport.color
                    ) {
                        toggleDay(day)
                    }
                    .accessibilityLabel("\(day), \(selectedDays.contains(day) ? "selected" : "not selected")")
                    .accessibilityHint("Double tap to \(selectedDays.contains(day) ? "deselect" : "select") this day")
                }
            }
            .padding(.vertical)
            
            // "Any day" toggle
            Button(action: toggleAnyDay) {
                HStack {
                    Image(systemName: isAnyDaySelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isAnyDaySelected ? sport.color : .secondary)
                    Text("Any day")
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Any day, \(isAnyDaySelected ? "all days selected" : "not all days selected")")
            .accessibilityHint("Double tap to \(isAnyDaySelected ? "deselect all days" : "select all days")")
            
            if showErrors && !isFormValid {
                Text("Please select at least one day")
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
                    Text(screenNumber == totalScreens ? "Complete" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(sport.color)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Helper Methods
    
    private func toggleDay(_ day: String) {
        if let index = selectedDays.firstIndex(of: day) {
            selectedDays.remove(at: index)
        } else {
            selectedDays.append(day)
            // Sort days to maintain consistency
            selectedDays.sort {
                (allDays.firstIndex(of: $0) ?? 0) < (allDays.firstIndex(of: $1) ?? 0)
            }
        }
    }
    
    private func toggleAnyDay() {
        if isAnyDaySelected {
            selectedDays.removeAll()
        } else {
            selectedDays = allDays
        }
    }
}

// MARK: - DayButton Component

struct DayButton: View {
    let day: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(day)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(color)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? color.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color : Color.secondary.opacity(0.3), lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Swim Availability") {
    OnboardingAvailabilityView(
        sport: .swim,
        screenNumber: 4,
        totalScreens: 7,
        selectedDays: .constant(["Monday", "Wednesday"]),
        onNext: {},
        onBack: {}
    )
}

#Preview("Bike Availability") {
    OnboardingAvailabilityView(
        sport: .bike,
        screenNumber: 5,
        totalScreens: 7,
        selectedDays: .constant([]),
        onNext: {},
        onBack: {}
    )
}

