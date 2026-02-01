//
//  OnboardingScreen3View.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// Third onboarding screen collecting performance metrics.
/// All fields are optional: VMA, CSS, FTP, experience years.
struct OnboardingScreen3View: View {
    @Binding var data: MetricsData
    var onBack: () -> Void
    var onNext: () -> Void

    @State private var showErrors = false

    // Text field bindings
    @State private var vmaText: String = ""
    @State private var cssMinutesText: String = ""
    @State private var cssSecondsText: String = ""
    @State private var ftpText: String = ""
    @State private var experienceYearsText: String = ""

    // MARK: - Validation (only for filled fields)

    /// Validates VMA is 10-25 km/h if filled
    private var isVmaValid: Bool {
        guard !vmaText.isEmpty, let vma = data.vma else { return true } // Empty is valid
        return vma >= 10 && vma <= 25
    }

    /// Validates CSS total seconds is 25-300 if filled
    private var isCssValid: Bool {
        // If either field is filled, validate total seconds
        guard !cssMinutesText.isEmpty || !cssSecondsText.isEmpty else { return true }
        guard let totalSeconds = data.cssSecondsPer100m else { return true }
        return totalSeconds >= 25 && totalSeconds <= 300
    }

    /// Validates FTP is 50-500 watts if filled
    private var isFtpValid: Bool {
        guard !ftpText.isEmpty, let ftp = data.ftp else { return true }
        return ftp >= 50 && ftp <= 500
    }

    /// Validates experience years is >= 0 if filled
    private var isExperienceYearsValid: Bool {
        guard !experienceYearsText.isEmpty, let years = data.experienceYears else { return true }
        return years >= 0
    }

    /// Form is valid when all filled fields meet validation criteria
    private var isFormValid: Bool {
        isVmaValid && isCssValid && isFtpValid && isExperienceYearsValid
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
                Text("Help us personalize your training (all optional)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // VMA
                    VStack(alignment: .leading, spacing: 8) {
                        Text("VMA (km/h)")
                            .font(.headline)

                        TextField("e.g., 18.5", text: $vmaText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: vmaText) { _, newValue in
                                if let vma = Double(newValue) {
                                    data.vma = vma
                                }
                                // Don't set to nil on invalid input - preserve previous valid value
                            }
                            .onAppear {
                                if let vma = data.vma {
                                    vmaText = String(format: "%.1f", vma)
                                }
                            }

                        if showErrors && !isVmaValid {
                            Text("VMA must be between 10 and 25 km/h")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Text("Your maximal aerobic speed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // CSS
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CSS (Critical Swim Speed)")
                            .font(.headline)

                        HStack(spacing: 12) {
                            VStack {
                                TextField("Min", text: $cssMinutesText)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.center)
                                .onChange(of: cssMinutesText) { _, newValue in
                                    // Convert min:sec UI to total seconds
                                    let minutes = Int(newValue) ?? 0
                                    let seconds = Int(cssSecondsText) ?? 0
                                    data.cssSecondsPer100m = minutes * 60 + seconds
                                }
                                .onAppear {
                                    // Decompose total seconds into min:sec for display
                                    if let totalSeconds = data.cssSecondsPer100m {
                                        let minutes = totalSeconds / 60
                                        cssMinutesText = String(minutes)
                                    }
                                }
                                Text("Minutes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Text(":")
                                .font(.title2)

                            VStack {
                                TextField("Sec", text: $cssSecondsText)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.center)
                                .onChange(of: cssSecondsText) { _, newValue in
                                    // Convert min:sec UI to total seconds
                                    let minutes = Int(cssMinutesText) ?? 0
                                    let seconds = Int(newValue) ?? 0
                                    data.cssSecondsPer100m = minutes * 60 + seconds
                                }
                                .onAppear {
                                    // Decompose total seconds into min:sec for display
                                    if let totalSeconds = data.cssSecondsPer100m {
                                        let seconds = totalSeconds % 60
                                        cssSecondsText = String(seconds)
                                    }
                                }
                                Text("Seconds")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if showErrors && !isCssValid {
                            Text("CSS must be between 0:25 and 5:00 per 100m")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Text("Pace per 100 meters")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // FTP
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FTP (Watts)")
                            .font(.headline)

                        TextField("e.g., 250", text: $ftpText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: ftpText) { _, newValue in
                                if let ftp = Int(newValue) {
                                    data.ftp = ftp
                                }
                                // Don't set to nil on invalid input - preserve previous valid value
                            }
                            .onAppear {
                                if let ftp = data.ftp {
                                    ftpText = String(ftp)
                                }
                            }

                        if showErrors && !isFtpValid {
                            Text("FTP must be between 50 and 500 watts")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Text("Your functional threshold power")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Experience years
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Triathlon Experience (years)")
                            .font(.headline)

                        TextField("e.g., 2", text: $experienceYearsText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: experienceYearsText) { _, newValue in
                                if let years = Int(newValue) {
                                    data.experienceYears = years
                                }
                                // Don't set to nil on invalid input - preserve previous valid value
                            }
                            .onAppear {
                                if let years = data.experienceYears {
                                    experienceYearsText = String(years)
                                }
                            }

                        if showErrors && !isExperienceYearsValid {
                            Text("Experience must be 0 or more years")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Text("How long have you been training?")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
    }
}

#Preview {
    OnboardingScreen3View(
        data: .constant(MetricsData()),
        onBack: { print("Back tapped") },
        onNext: { print("Next tapped") }
    )
}
