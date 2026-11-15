//
//  OnboardingCards.swift
//  Dromos
//
//  The non-chat controls that sit in the onboarding thread: date, time,
//  sliders, the three sport weeks, and the day-length card.
//

import SwiftUI

struct OnboardingDateCard: View {
    let minimum: Date
    let onConfirm: (Date) -> Void
    @State private var date: Date

    init(minimum: Date, onConfirm: @escaping (Date) -> Void) {
        self.minimum = minimum
        self.onConfirm = onConfirm
        _date = State(initialValue: minimum)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker(
                "Race date",
                selection: $date,
                in: minimum...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            Button("Set this date") { onConfirm(date) }
                .buttonStyle(OnboardingPrimaryButton())
        }
        .onboardingCard()
    }
}

struct OnboardingTimeCard: View {
    let onConfirm: (Int) -> Void
    @State private var hours: Int
    @State private var minutes: Int

    init(defaultMinutes: Int, onConfirm: @escaping (Int) -> Void) {
        self.onConfirm = onConfirm
        _hours = State(initialValue: max(1, defaultMinutes / 60))
        _minutes = State(initialValue: defaultMinutes % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OnboardingCopy.formatClock(minutes: hours * 60 + minutes))
                .font(.title2.weight(.semibold))
            Stepper("\(hours) h", value: $hours, in: 1...18)
            Stepper("\(minutes) min", value: $minutes, in: 0...55, step: 5)
            Button("Set this time") { onConfirm(hours * 60 + minutes) }
                .buttonStyle(OnboardingPrimaryButton())
        }
        .onboardingCard()
    }
}

struct OnboardingHoursCard: View {
    let onConfirm: (Double) -> Void
    @State private var hours: Double

    init(initial: Double, onConfirm: @escaping (Double) -> Void) {
        self.onConfirm = onConfirm
        _hours = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OnboardingCopy.formatHours(hours))
                .font(.title2.weight(.semibold))
            Slider(value: $hours, in: 0...25, step: 0.5)
            Button("Use \(OnboardingCopy.formatHours(hours))") { onConfirm(hours) }
                .buttonStyle(OnboardingPrimaryButton())
        }
        .onboardingCard()
    }
}

struct OnboardingValueCard: View {
    let title: String
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    let onConfirm: (Double) -> Void
    @State private var value: Double

    init(
        title: String,
        initial: Double,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String,
        onConfirm: @escaping (Double) -> Void
    ) {
        self.title = title
        self.range = range
        self.step = step
        self.format = format
        self.onConfirm = onConfirm
        _value = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(format(value))
                .font(.title2.weight(.semibold))
            Slider(value: $value, in: range, step: step)
            Button("Use \(format(value))") { onConfirm(value) }
                .buttonStyle(OnboardingPrimaryButton())
        }
        .onboardingCard()
    }
}

struct OnboardingClockEntryCard: View {
    let title: String
    let minuteRange: ClosedRange<Int>
    let onConfirm: (Int) -> Void
    @State private var minutes: Int
    @State private var seconds: Int

    init(title: String, initialSeconds: Int, minuteRange: ClosedRange<Int>, onConfirm: @escaping (Int) -> Void) {
        self.title = title
        self.minuteRange = minuteRange
        self.onConfirm = onConfirm
        _minutes = State(initialValue: min(max(initialSeconds / 60, minuteRange.lowerBound), minuteRange.upperBound))
        _seconds = State(initialValue: initialSeconds % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(OnboardingCopy.formatRaceClock(minutes * 60 + seconds))
                .font(.title2.weight(.semibold))
            Stepper("\(minutes) min", value: $minutes, in: minuteRange)
            Stepper("\(seconds) sec", value: $seconds, in: 0...55, step: 5)
            Button("Use this time") { onConfirm(minutes * 60 + seconds) }
                .buttonStyle(OnboardingPrimaryButton())
        }
        .onboardingCard()
    }
}

struct OnboardingBirthYearCard: View {
    let onConfirm: (Int) -> Void
    @State private var year: Int

    init(onConfirm: @escaping (Int) -> Void) {
        self.onConfirm = onConfirm
        let current = Calendar.current.component(.year, from: Date())
        _year = State(initialValue: min(max(current - 30, 1920), 2030))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Year of birth")
                .font(.headline)
            Stepper(String(year), value: $year, in: 1920...2030)
            Button("Estimate max HR") { onConfirm(year) }
                .buttonStyle(OnboardingPrimaryButton())
        }
        .onboardingCard()
    }
}

struct OnboardingAvailabilityCard: View {
    let title: String
    let selected: [String]
    let hinted: [String]
    let onToggle: (String) -> Void
    let onAnyDay: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Weekday.ordered, id: \.self) { day in
                    let isOn = selected.contains(day)
                    Button(Weekday.short(day)) { onToggle(day) }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isOn ? Color.accentColor : Color(.systemGray6))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.accentColor.opacity(hinted.contains(day) && !isOn ? 0.7 : 0), lineWidth: 1.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel(day)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                }
                Button("Any day", action: onAnyDay)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .foregroundStyle(Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if selected.isEmpty {
                Text(OnboardingCopy.emptyDaysHint())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Done") { onDone() }
                .buttonStyle(OnboardingPrimaryButton())
                .disabled(selected.isEmpty)
        }
        .onboardingCard()
    }
}

struct OnboardingDurationCard: View {
    let days: [String]
    let values: [String: Int]
    let onChange: (String, Int) -> Void
    let onDone: () -> Void

    private let choices = Array(stride(from: 30, through: 420, by: 15))

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Time per day")
                .font(.headline)
            ForEach(days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Weekday.short(day)) · \(OnboardingCopy.formatDuration(values[day] ?? 60))")
                        .font(.subheadline.weight(.semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(choices, id: \.self) { minutes in
                                let on = values[day] == minutes
                                Button(OnboardingCopy.formatDuration(minutes)) {
                                    onChange(day, minutes)
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(on ? Color.accentColor : Color(.systemGray6))
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            Button("Done") { onDone() }
                .buttonStyle(OnboardingPrimaryButton())
                .disabled(days.contains { values[$0] == nil })
        }
        .onboardingCard()
    }
}

struct OnboardingRecapCard: View {
    let rows: [OnboardingCopy.RecapRow]
    let onEdit: (OnboardingStep) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                Button {
                    onEdit(row.step)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Text("Edit")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                if row.step != rows.last?.step {
                    Divider()
                }
            }
        }
        .onboardingCard()
    }
}

struct OnboardingPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

extension View {
    func onboardingCard() -> some View {
        padding(14)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
    }
}
