//
//  OnboardingScreen1View.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// First onboarding screen collecting basic user information.
/// All fields are required: sex, birth date, weight.
struct OnboardingScreen1View: View {
    @Binding var data: BasicInfoData
    var onNext: () -> Void

    @State private var showErrors = false

    // MARK: - Validation

    /// Validates that sex has been selected
    private var isSexValid: Bool {
        guard let sex = data.sex else { return false }
        return !sex.isEmpty
    }

    /// Validates that birth date results in age between 13-99 years
    private var isBirthDateValid: Bool {
        guard let birthDate = data.birthDate else { return false }
        let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
        return age >= 13 && age <= 99
    }

    /// Validates that weight has been selected (picker constrains to 30-150 kg range)
    private var isWeightValid: Bool {
        data.weightKg != nil
    }

    /// Form is valid when all fields meet validation criteria
    private var isFormValid: Bool {
        isSexValid && isBirthDateValid && isWeightValid
    }

    /// Date range for birth date picker (100 years ago to 13 years ago)
    private var dateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let now = Date()
        guard let minDate = calendar.date(byAdding: .year, value: -100, to: now),
              let maxDate = calendar.date(byAdding: .year, value: -13, to: now) else {
            // Fallback to reasonable defaults if calendar operations fail
            // Jan 1, 1926 to Jan 1, 2013 (approx 100 to 13 years ago from 2026)
            return Date(timeIntervalSince1970: -1388534400)...Date(timeIntervalSince1970: 1356998400)
        }
        return minDate...maxDate
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Progress indicator
                Text("1 of 6")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Let's get started")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Tell us a bit about yourself")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Form
                VStack(alignment: .leading, spacing: 20) {
                    // Sex selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sex")
                            .font(.headline)

                        HStack(spacing: 12) {
                            Button(action: { data.sex = "Male" }) {
                                Text("Male")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(data.sex == "Male" ? Color.blue : Color.gray.opacity(0.2))
                                    .foregroundColor(data.sex == "Male" ? .white : .primary)
                                    .cornerRadius(10)
                            }

                            Button(action: { data.sex = "Female" }) {
                                Text("Female")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(data.sex == "Female" ? Color.blue : Color.gray.opacity(0.2))
                                    .foregroundColor(data.sex == "Female" ? .white : .primary)
                                    .cornerRadius(10)
                            }
                        }

                        if showErrors && !isSexValid {
                            Text("Please select your sex")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    // Birth date
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Birth Date")
                            .font(.headline)

                        DatePicker(
                            "Birth Date",
                            selection: Binding(
                                get: { data.birthDate ?? Date() },
                                set: { data.birthDate = $0 }
                            ),
                            in: dateRange,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()

                        if showErrors && !isBirthDateValid {
                            Text("Age must be between 13 and 99 years")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    // Weight
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weight (kg)")
                            .font(.headline)

                        Picker("Weight", selection: Binding(
                            get: { data.weightKg ?? 70.0 },
                            set: { data.weightKg = $0 }
                        )) {
                            ForEach(Array(stride(from: 30.0, through: 150.0, by: 1.0)), id: \.self) { weight in
                                Text("\(Int(weight)) kg").tag(weight)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                        .labelsHidden()
                    }
                }

                Spacer()

                // Next button
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
            // Set default weight if not already set
            if data.weightKg == nil {
                data.weightKg = 70.0
            }
        }
    }
}

#Preview {
    OnboardingScreen1View(
        data: .constant(BasicInfoData()),
        onNext: { print("Next tapped") }
    )
}
