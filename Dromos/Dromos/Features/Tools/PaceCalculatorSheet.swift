//
//  PaceCalculatorSheet.swift
//  Dromos
//
//  Dark-gradient bottom drawer for the pace calculator (DRO-262 / DRO-264).
//  Presented via `.sheet(...).presentationDetents([.fraction(0.8)])`.
//  Accepts an optional `PaceSeed`; nil → neutral run defaults.
//

import SwiftUI

// MARK: - PaceCalculatorSheet

/// Self-contained bottom drawer view that drives the Dromos pace calculator.
///
/// Layout (top → bottom):
/// 1. Eyebrow + title header
/// 2. Chevron-down dismiss affordance
/// 3. Segmented discipline picker
/// 4. Two-column speed / pace display
/// 5. Slider with min/max captions
/// 6. Divider + "FINISH TIMES" section
struct PaceCalculatorSheet: View {

    // MARK: Input

    let seed: PaceSeed?

    // MARK: Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: State

    @State private var discipline: Discipline
    @State private var sliderValue: Int

    // MARK: Init

    init(seed: PaceSeed?) {
        self.seed = seed
        let d = seed?.discipline ?? .run
        let v = seed?.sliderValue ?? Discipline.run.config.defaultValue
        _discipline = State(initialValue: d)
        _sliderValue = State(initialValue: v)
        Self.configureSegmentedControlAppearance()
    }

    private static func configureSegmentedControlAppearance() {
        let appearance = UISegmentedControl.appearance()
        appearance.selectedSegmentTintColor = UIColor(Color.accentColor)
        appearance.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        appearance.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.7)], for: .normal)
        appearance.backgroundColor = UIColor.white.withAlphaComponent(0.08)
    }

    // MARK: Colours

    /// Top colour of the dark gradient (#0a1612 ≈ rgb(10, 22, 18)).
    private let gradientTop    = Color(red: 10/255, green: 22/255,  blue: 18/255)
    /// Bottom colour of the dark gradient (#021510 ≈ rgb(2, 21, 16)).
    private let gradientBottom = Color(red: 2/255,  green: 21/255,  blue: 16/255)

    // MARK: Computed helpers

    /// Current speed in km/h derived from the slider value.
    private var speedKmH: Double {
        PaceMath.kmH(forSliderValue: sliderValue, discipline: discipline)
    }

    /// Seconds per kilometre at the current speed.
    private var secPerKm: TimeInterval {
        guard speedKmH > 0 else { return 0 }
        return 3600.0 / speedKmH
    }

    private var config: DisciplineConfig { discipline.config }

    // MARK: View

    var body: some View {
        ZStack {
            // Full-bleed dark gradient background.
            LinearGradient(
                colors: [gradientTop, gradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    headerSection
                    dismissButton
                    pickerSection
                    metricsRow
                    sliderSection
                    finishTimesSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        // Per V0 spec: switching disciplines resets the slider to that discipline's
        // default. A seeded value (e.g. user's CSS for swim) is lost if the user
        // navigates away and back. Acceptable trade-off for V0 — revisit if users
        // complain. See DRO-262 Open Question #4 (persistence).
        .onChange(of: discipline) { _, newDiscipline in
            sliderValue = newDiscipline.config.defaultValue
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            // Eyebrow
            Text("DROMOS · PACE CARD")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .tracking(2)
                .foregroundColor(.accentColor)
                .padding(.top, 24)

            // Dynamic discipline title
            Text(discipline.displayName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
    }

    // MARK: - Dismiss button

    private var dismissButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
        .padding(.bottom, 20)
    }

    // MARK: - Discipline picker

    private var pickerSection: some View {
        Picker("Discipline", selection: $discipline) {
            ForEach(Discipline.allCases, id: \.self) { d in
                Text(d.displayName).tag(d)
            }
        }
        .pickerStyle(.segmented)
        .padding(.bottom, 24)
    }

    // MARK: - Two-column metrics row

    private var metricsRow: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left: major value
            majorValueColumn

            Spacer()

            // Right: secondary value
            secondaryValueColumn
        }
        .padding(.bottom, 20)
    }

    /// Left column: either speed (run / bike) or pace per 100 m (swim).
    private var majorValueColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(config.inputLabel)
                .font(.caption2.weight(.semibold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.5))

            if discipline == .swim {
                // Swim major = pace per 100m (M:SS format).
                Text(PaceMath.formatPacePer100m(secondsPer100m: TimeInterval(sliderValue)))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            } else {
                // Run / bike major = speed in km/h.
                Text(String(format: "%.1f", speedKmH))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Text(config.unit)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    /// Right column: either pace per km (run / bike) or speed in km/h (swim).
    private var secondaryValueColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(config.secondaryLabel)
                .font(.caption2.weight(.semibold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.5))

            if discipline == .swim {
                // Swim secondary = speed in km/h derived from CSS pace.
                Text(String(format: "%.2f", speedKmH))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            } else {
                // Run / bike secondary = pace per km.
                Text(PaceMath.formatPacePerKm(secondsPerKm: secPerKm))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Text(config.secondaryUnit)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Slider

    /// Text shown in the major value display — used for accessibility.
    private var majorValueText: String {
        discipline == .swim
            ? PaceMath.formatPacePer100m(secondsPer100m: TimeInterval(sliderValue))
            : String(format: "%.1f", speedKmH)
    }

    private var sliderSection: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { Double(sliderValue) },
                    set: { sliderValue = Int($0.rounded()) }
                ),
                in: Double(config.lowerBound)...Double(config.upperBound),
                step: Double(config.step)
            )
            .tint(.accentColor)
            .accessibilityValue("\(majorValueText) \(config.unit)")

            // Min / max captions
            HStack {
                Text(minCaption)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text(maxCaption)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.bottom, 24)
    }

    /// Human-readable label for the slider's minimum bound.
    private var minCaption: String {
        switch discipline {
        case .run, .bike:
            return String(format: "%.1f km/h", Double(config.lowerBound) / 10.0)
        case .swim:
            return "\(config.lowerBound) s / 100m"
        }
    }

    /// Human-readable label for the slider's maximum bound.
    private var maxCaption: String {
        switch discipline {
        case .run, .bike:
            return String(format: "%.1f km/h", Double(config.upperBound) / 10.0)
        case .swim:
            return "\(config.upperBound) s / 100m"
        }
    }

    // MARK: - Finish times

    private var finishTimesSection: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("FINISH TIMES")
                    .font(.caption2.weight(.semibold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
            .padding(.bottom, 10)

            Divider()
                .background(Color.white.opacity(0.12))

            LazyVStack(spacing: 0) {
                ForEach(Array(config.distances.enumerated()), id: \.element.id) { index, entry in
                    finishTimeRow(entry: entry)
                    if index < config.distances.count - 1 {
                        Divider()
                            .background(Color.white.opacity(0.08))
                    }
                }
            }
        }
    }

    /// One distance-name + computed time row.
    private func finishTimeRow(entry: DistanceEntry) -> some View {
        let elapsed = PaceMath.secondsToCover(km: entry.km, atSpeedKmH: speedKmH)
        return HStack {
            Text(entry.name)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            Text(PaceMath.formatTime(elapsed))
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundColor(.white)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Preview

#Preview("No seed — neutral defaults") {
    PaceCalculatorSheet(seed: nil)
        .presentationDetents([.fraction(0.8)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
}

#Preview("Run seed — VMA 13.8 km/h") {
    PaceCalculatorSheet(seed: PaceSeed(discipline: .run, sliderValue: 138))
        .presentationDetents([.fraction(0.8)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
}

#Preview("Swim seed — CSS 110 s/100m") {
    PaceCalculatorSheet(seed: PaceSeed(discipline: .swim, sliderValue: 110))
        .presentationDetents([.fraction(0.8)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
}
