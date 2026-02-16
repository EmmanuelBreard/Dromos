//
//  OnboardingScreen3View.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// Third onboarding screen collecting performance metrics.
/// All fields are required: current weekly hours, VMA, CSS, FTP, experience years.
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

    // Static VMA values array (computed once)
    private static let vmaValues: [Double] = stride(from: 13.0, through: 25.0, by: 0.1)
        .map { Double(round($0 * 10)) / 10 }

    // MARK: - Validation

    /// Current weekly hours must be set (required field)
    private var isCurrentWeeklyHoursValid: Bool {
        data.currentWeeklyHours != nil
    }

    /// Form is valid when required field is set (all picker fields have defaults)
    private var isFormValid: Bool {
        isCurrentWeeklyHoursValid
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            // Progress indicator
            Text("3 of 6")
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

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Current Weekly Hours (required)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Training Volume")
                            .font(.headline)

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
                        } else {
                            Text("In the last 4 weeks, how many hours per week did you train?")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    // VMA
                    VStack(alignment: .leading, spacing: 8) {
                        Text("VMA (km/h)")
                            .font(.headline)

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

                        Text("Your maximal aerobic speed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // CSS
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CSS (Critical Swim Speed)")
                            .font(.headline)

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

                        Text("Pace per 100 meters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // FTP
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FTP (Watts)")
                            .font(.headline)

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

                        Text("Your functional threshold power")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Experience years
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Triathlon Experience")
                            .font(.headline)

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

                        Text("How long have you been training?")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
