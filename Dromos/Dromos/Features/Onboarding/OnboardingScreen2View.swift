//
//  OnboardingScreen2View.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// Second onboarding screen collecting race goals.
/// Required: race objective, race date. Optional: time objective.
struct OnboardingScreen2View: View {
    @Binding var data: RaceGoalsData
    var onBack: () -> Void
    var onNext: () -> Void

    @State private var showErrors = false

    // Time objective as strings for TextField binding
    @State private var hoursText: String = ""
    @State private var minutesText: String = ""

    // MARK: - Validation

    /// Validates that race objective has been selected
    private var isRaceObjectiveValid: Bool {
        data.raceObjective != nil
    }

    /// Validates that race date is today or in the future
    private var isRaceDateValid: Bool {
        guard let raceDate = data.raceDate else { return false }
        return raceDate >= Calendar.current.startOfDay(for: Date())
    }

    /// Form is valid when all required fields are filled
    private var isFormValid: Bool {
        isRaceObjectiveValid && isRaceDateValid
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            // Progress indicator
            Text("2 of 3")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Title
            VStack(alignment: .leading, spacing: 8) {
                Text("Your race goal")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("What are you training for?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Form
            VStack(alignment: .leading, spacing: 20) {
                // Race objective
                VStack(alignment: .leading, spacing: 8) {
                    Text("Race Type")
                        .font(.headline)

                    Picker("Race Type", selection: Binding(
                        get: { data.raceObjective ?? .sprint },
                        set: { data.raceObjective = $0 }
                    )) {
                        ForEach(RaceObjective.allCases, id: \.self) { objective in
                            Text(objective.rawValue).tag(objective)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onAppear {
                        // Initialize to Sprint if not already set
                        // This ensures the visual selection matches the data state
                        if data.raceObjective == nil {
                            data.raceObjective = .sprint
                        }
                    }

                    if showErrors && !isRaceObjectiveValid {
                        Text("Please select a race type")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // Race date
                VStack(alignment: .leading, spacing: 8) {
                    Text("Race Date")
                        .font(.headline)

                    DatePicker(
                        "Race Date",
                        selection: Binding(
                            get: { data.raceDate ?? Date() },
                            set: { data.raceDate = $0 }
                        ),
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()

                    if showErrors && !isRaceDateValid {
                        Text("Race date cannot be in the past")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // Time objective (optional)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Time Objective (Optional)")
                        .font(.headline)

                    HStack(spacing: 12) {
                        VStack {
                            TextField("Hours", text: $hoursText)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)
                                .onChange(of: hoursText) { _, newValue in
                                    if let hours = Int(newValue) {
                                        data.timeObjectiveHours = hours
                                    }
                                    // Don't set to nil on invalid input - preserve previous valid value
                                }
                                .onAppear {
                                    if let hours = data.timeObjectiveHours {
                                        hoursText = String(hours)
                                    }
                                }
                            Text("Hours")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text(":")
                            .font(.title2)

                        VStack {
                            TextField("Minutes", text: $minutesText)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)
                                .onChange(of: minutesText) { _, newValue in
                                    if let minutes = Int(newValue) {
                                        data.timeObjectiveMinutes = minutes
                                    }
                                    // Don't set to nil on invalid input - preserve previous valid value
                                }
                                .onAppear {
                                    if let minutes = data.timeObjectiveMinutes {
                                        minutesText = String(minutes)
                                    }
                                }
                            Text("Minutes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text("You can skip this if you're not sure yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Navigation buttons
            HStack(spacing: 16) {
                Button(action: onBack) {
                    Text("Back")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }

                Button(action: {
                    showErrors = true
                    if isFormValid {
                        onNext()
                    }
                }) {
                    Text("Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
    }
}

#Preview {
    OnboardingScreen2View(
        data: .constant(RaceGoalsData()),
        onBack: { print("Back tapped") },
        onNext: { print("Next tapped") }
    )
}
