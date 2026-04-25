//
//  OnboardingScreen3View.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// Third onboarding screen collecting performance metrics.
/// All fields are required: current weekly hours, VMA, CSS, FTP, experience years.
/// Also collects birth year and max HR (optional, DRO-213 Phase 6).
struct OnboardingScreen3View: View {
    @Binding var data: MetricsData
    var onBack: () -> Void
    var onNext: () -> Void

    @State private var showErrors = false

    // Picker selection values
    @State private var selectedVma: Double = 18.0
    @State private var selectedCssMin: Int = 2
    @State private var selectedCssSec: Int = 0
    @State private var selectedFtp: Int = 200
    @State private var selectedExperience: Int = 2
    @State private var selectedBirthYear: Int = 1996
    @State private var selectedMaxHr: Int = 190

    // Static VMA values array (computed once)
    private static let vmaValues: [Double] = stride(from: 13.0, through: 25.0, by: 0.1)
        .map { Double(round($0 * 10)) / 10 }

    // Birth year range: 1920–2020
    private static let birthYearValues: [Int] = Array(1920...2020).reversed()

    // Max HR range: 100–220
    private static let maxHrValues: [Int] = Array(100...220)

    // MARK: - Validation

    /// Current weekly hours must be set (required field)
    private var isCurrentWeeklyHoursValid: Bool {
        data.currentWeeklyHours != nil
    }

    /// Form is valid when required field is set (all picker fields have defaults)
    private var isFormValid: Bool {
        isCurrentWeeklyHoursValid
    }

    // MARK: - Formula

    /// The current calendar year, derived at runtime (not hardcoded).
    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    /// Computes max HR from birth year using the 220 − age formula.
    private func applyMaxHrFormula() {
        let age = currentYear - selectedBirthYear
        let computed = 220 - age
        let clamped = min(220, max(100, computed))
        selectedMaxHr = clamped
        data.maxHr = clamped
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Progress indicator
                Text("2 of 6")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Performance Metrics")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Help us personalize your training")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 20) {
                    // Current Weekly Hours (required)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Training Volume")
                            .font(.headline)
                        Text("In the last 4 weeks, how many hours per week did you train?")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        VStack(spacing: 4) {
                            Text(data.currentWeeklyHours.map { "\(String(format: "%.1f", $0))h / week" } ?? "Select your volume")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(data.currentWeeklyHours != nil ? .primary : .secondary)
                                .frame(maxWidth: .infinity)

                            Slider(
                                value: Binding(
                                    get: { data.currentWeeklyHours ?? 3.0 },
                                    set: { data.currentWeeklyHours = $0 }
                                ),
                                in: 0...25,
                                step: 0.5
                            )
                        }

                        if showErrors && !isCurrentWeeklyHoursValid {
                            Text("Please set your current training volume")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    Divider()

                    // VMA
                    VStack(alignment: .leading, spacing: 8) {
                        Text("VMA (km/h)")
                            .font(.headline)
                        Text("Your maximal aerobic speed")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("VMA", selection: $selectedVma) {
                            ForEach(Self.vmaValues, id: \.self) { value in
                                Text(String(format: "%.1f km/h", value))
                                    .tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                        .onChange(of: selectedVma) { _, newValue in
                            data.vma = newValue
                        }
                    }

                    // CSS
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CSS (Critical Swim Speed)")
                            .font(.headline)
                        Text("Pace per 100 meters")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Picker("Minutes", selection: $selectedCssMin) {
                                ForEach(0...5, id: \.self) { value in
                                    Text("\(value) min")
                                        .tag(value)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 120)
                            .onChange(of: selectedCssMin) { _, _ in
                                data.cssSecondsPer100m = selectedCssMin * 60 + selectedCssSec
                            }

                            Picker("Seconds", selection: $selectedCssSec) {
                                ForEach(0...59, id: \.self) { value in
                                    Text(String(format: "%02d sec", value))
                                        .tag(value)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 120)
                            .onChange(of: selectedCssSec) { _, _ in
                                data.cssSecondsPer100m = selectedCssMin * 60 + selectedCssSec
                            }
                        }
                    }

                    // FTP
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FTP (Watts)")
                            .font(.headline)
                        Text("Your functional threshold power")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("FTP", selection: $selectedFtp) {
                            ForEach(Array(stride(from: 50, through: 500, by: 5)), id: \.self) { value in
                                Text("\(value) W")
                                    .tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                        .onChange(of: selectedFtp) { _, newValue in
                            data.ftp = newValue
                        }
                    }

                    // Experience years
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Triathlon Experience")
                            .font(.headline)
                        Text("How long have you been training?")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Experience", selection: $selectedExperience) {
                            ForEach(0...30, id: \.self) { value in
                                Text(value == 1 ? "1 year" : "\(value) years")
                                    .tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                        .onChange(of: selectedExperience) { _, newValue in
                            data.experienceYears = newValue
                        }
                    }

                    Divider()

                    // Birth Year
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Year of Birth")
                            .font(.headline)
                        Text("Used to estimate your max heart rate")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Birth Year", selection: $selectedBirthYear) {
                            ForEach(Self.birthYearValues, id: \.self) { year in
                                Text(String(year))
                                    .tag(year)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                        .onChange(of: selectedBirthYear) { _, newValue in
                            data.birthYear = newValue
                        }
                    }

                    // Max HR
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Max Heart Rate (bpm)")
                            .font(.headline)
                        Text("Your maximum heart rate — used for HR zone targets")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Max HR", selection: $selectedMaxHr) {
                            ForEach(Self.maxHrValues, id: \.self) { value in
                                Text("\(value) bpm")
                                    .tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                        .onChange(of: selectedMaxHr) { _, newValue in
                            data.maxHr = newValue
                        }

                        Button(action: applyMaxHrFormula) {
                            Label("Use formula (220 − age)", systemImage: "function")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                        }
                        .accessibilityLabel("Use formula 220 minus age to calculate max heart rate")
                    }
                }

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
        }
        .padding()
        .onAppear {
            // Restore picker values from data, or set defaults
            if let vma = data.vma {
                selectedVma = Double(round(vma * 10)) / 10
            } else {
                data.vma = selectedVma
            }
            if let css = data.cssSecondsPer100m {
                selectedCssMin = css / 60
                selectedCssSec = css % 60
            } else {
                data.cssSecondsPer100m = selectedCssMin * 60 + selectedCssSec
            }
            if let ftp = data.ftp {
                selectedFtp = ftp
            } else {
                data.ftp = selectedFtp
            }
            if let years = data.experienceYears {
                selectedExperience = years
            } else {
                data.experienceYears = selectedExperience
            }
            if let birthYear = data.birthYear {
                selectedBirthYear = birthYear
            } else {
                data.birthYear = selectedBirthYear
            }
            if let maxHr = data.maxHr {
                selectedMaxHr = maxHr
            } else {
                data.maxHr = selectedMaxHr
            }
        }
    }
}

#Preview {
    OnboardingScreen3View(
        data: .constant(MetricsData()),
        onBack: { print("Back tapped") },
        onNext: { print("Next tapped") }
    )
}
