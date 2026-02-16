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

    // Time objective toggle and picker state
    @State private var showTimeObjective: Bool = false
    @State private var selectedHours: Int = 2
    @State private var selectedMinutes: Int = 0

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
            Text("2 of 6")
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
                    Toggle("I have a time goal", isOn: $showTimeObjective)
                        .font(.headline)
                        .onChange(of: showTimeObjective) { _, isOn in
                            if isOn {
                                data.timeObjectiveMinutes = selectedHours * 60 + selectedMinutes
                            } else {
                                data.timeObjectiveMinutes = nil
                            }
                        }

                    if showTimeObjective {
                        HStack(spacing: 16) {
                            Picker("Hours", selection: $selectedHours) {
                                ForEach(0...23, id: \.self) { hour in
                                    Text("\(hour) h").tag(hour)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 120)
                            .onChange(of: selectedHours) { _, _ in
                                data.timeObjectiveMinutes = selectedHours * 60 + selectedMinutes
                            }

                            Picker("Minutes", selection: $selectedMinutes) {
                                ForEach(0...59, id: \.self) { minute in
                                    Text("\(minute) min").tag(minute)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 120)
                            .onChange(of: selectedMinutes) { _, _ in
                                data.timeObjectiveMinutes = selectedHours * 60 + selectedMinutes
                            }
                        }
                    }
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
        .onAppear {
            if let totalMinutes = data.timeObjectiveMinutes {
                showTimeObjective = true
                selectedHours = totalMinutes / 60
                selectedMinutes = totalMinutes % 60
            }
        }
    }
}

#Preview {
    OnboardingScreen2View(
        data: .constant(RaceGoalsData()),
        onBack: { print("Back tapped") },
        onNext: { print("Next tapped") }
    )
}
