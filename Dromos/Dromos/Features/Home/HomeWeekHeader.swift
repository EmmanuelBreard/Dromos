//
//  HomeWeekHeader.swift
//  Dromos
//
//  Created by Emmanuel Breard on 26/04/2026.
//

import SwiftUI

// MARK: - HomeWeekHeader

/// Two-row header for the Home single-week paged view.
///
/// **Row 1:** chevron-left — Spacer — semantic title — Spacer — chevron-right
/// **Row 2:** phase dot + phase label — date range (caption, secondary)
///
/// Navigation callbacks (`onPrevious` / `onNext`) are owned by the parent.
/// Chevrons are visually dimmed and `.disabled` when `canGoPrevious` /
/// `canGoNext` is false.
struct HomeWeekHeader: View {

    // MARK: - TitleVariant

    /// Semantic label variant for the week header title.
    /// Drives the human-readable prefix shown alongside the week number.
    enum TitleVariant {
        /// The plan's current calendar week: "Current Week - 3/16"
        case currentWeek
        /// One week before the current week: "Last Week - 2/16"
        case lastWeek
        /// One week after the current week: "Next Week - 4/16"
        case nextWeek
        /// Any other week (non-adjacent to current): "Week 6 / 16"
        case other
    }

    // MARK: Props

    /// 1-indexed week number within the plan.
    let weekNumber: Int
    /// Total number of weeks in the plan.
    let totalWeeks: Int
    /// Phase name for this week (e.g. "Base", "Build", "Peak", "Taper", "Recovery").
    let phase: String
    /// Monday of this week (used to compute the date-range label).
    let weekStartDate: Date
    /// Controls which semantic prefix is shown in the title row.
    let titleVariant: TitleVariant
    /// Called when the user taps the left chevron.
    let onPrevious: () -> Void
    /// Called when the user taps the right chevron.
    let onNext: () -> Void
    /// Whether the left chevron is interactive (false = first week).
    let canGoPrevious: Bool
    /// Whether the right chevron is interactive (false = last week).
    let canGoNext: Bool

    // MARK: Body

    var body: some View {
        VStack(spacing: 8) {
            titleRow
            metaRow
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
    }

    // MARK: - Row 1: Title + Chevrons

    private var titleRow: some View {
        HStack {
            // Left chevron — dims and disables at week boundary
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(
                        canGoPrevious
                            ? Color.secondary.opacity(0.6)
                            : Color.secondary.opacity(0.25)
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!canGoPrevious)
            .accessibilityLabel("Previous week")

            Spacer()

            // Semantic title
            Text(titleText)
                .font(.title2)
                .fontWeight(.bold)

            Spacer()

            // Right chevron — dims and disables at week boundary
            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .foregroundColor(
                        canGoNext
                            ? Color.secondary.opacity(0.6)
                            : Color.secondary.opacity(0.25)
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!canGoNext)
            .accessibilityLabel("Next week")
        }
    }

    // MARK: - Row 2: Phase badge + Date range

    private var metaRow: some View {
        HStack(spacing: 12) {
            // Phase dot + label
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.phaseColor(for: phase))
                    .frame(width: 8, height: 8)
                Text("\(phase) phase")
                    .font(.subheadline)
                    .foregroundColor(Color.phaseColor(for: phase))
            }

            // Date range label (e.g. "Feb 10th - 16th")
            Text(Self.weekDateRange(start: weekStartDate))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    // MARK: - Computed: title text

    /// Formats the title based on the semantic variant.
    private var titleText: String {
        switch titleVariant {
        case .currentWeek: return "Current Week - \(weekNumber)/\(totalWeeks)"
        case .lastWeek:    return "Last Week - \(weekNumber)/\(totalWeeks)"
        case .nextWeek:    return "Next Week - \(weekNumber)/\(totalWeeks)"
        case .other:       return "Week \(weekNumber) / \(totalWeeks)"
        }
    }

    // MARK: - Static helpers (copied from HomeView, kept private here)

    /// Short-format month name (e.g. "Feb").
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Formats a week's date range with ordinal day suffixes.
    ///
    /// Same-month example: `"Feb 10th - 16th"`
    /// Cross-month example: `"Feb 28th - Mar 6th"`
    ///
    /// - Parameter start: The Monday (start) of the week.
    /// - Returns: A human-readable date range string.
    private static func weekDateRange(start: Date) -> String {
        let calendar = Calendar.current
        let endDate = calendar.date(byAdding: .day, value: 6, to: start) ?? start

        let startDay = calendar.component(.day, from: start)
        let endDay   = calendar.component(.day, from: endDate)

        let startMonth = monthFormatter.string(from: start)
        let endMonth   = monthFormatter.string(from: endDate)

        if startMonth == endMonth {
            return "\(startMonth) \(ordinal(startDay)) - \(ordinal(endDay))"
        } else {
            return "\(startMonth) \(ordinal(startDay)) - \(endMonth) \(ordinal(endDay))"
        }
    }

    /// Converts a day number into its ordinal string (1st, 2nd, 3rd, etc.).
    private static func ordinal(_ day: Int) -> String {
        let suffix: String
        // Days 11, 12, 13 correctly fall through to "th" via the default case (English-language rule).
        switch day {
        case 1, 21, 31: suffix = "st"
        case 2, 22:     suffix = "nd"
        case 3, 23:     suffix = "rd"
        default:        suffix = "th"
        }
        return "\(day)\(suffix)"
    }
}

// MARK: - Preview

#Preview("All TitleVariant cases") {
    // Feb 10 2026 (Monday) — week 3 of 16, Base phase
    var components = DateComponents()
    components.year = 2026
    components.month = 2
    components.day = 10
    let sampleStart = Calendar.current.date(from: components) ?? Date()

    return VStack(spacing: 0) {
        Divider()

        // .currentWeek — "Current Week - 3/16"
        HomeWeekHeader(
            weekNumber: 3,
            totalWeeks: 16,
            phase: "Base",
            weekStartDate: sampleStart,
            titleVariant: .currentWeek,
            onPrevious: {},
            onNext: {},
            canGoPrevious: true,
            canGoNext: true
        )

        Divider()

        // .lastWeek — "Last Week - 2/16"
        HomeWeekHeader(
            weekNumber: 2,
            totalWeeks: 16,
            phase: "Base",
            weekStartDate: sampleStart,
            titleVariant: .lastWeek,
            onPrevious: {},
            onNext: {},
            canGoPrevious: false,   // first week — left chevron disabled
            canGoNext: true
        )

        Divider()

        // .nextWeek — "Next Week - 4/16"
        HomeWeekHeader(
            weekNumber: 4,
            totalWeeks: 16,
            phase: "Base",
            weekStartDate: sampleStart,
            titleVariant: .nextWeek,
            onPrevious: {},
            onNext: {},
            canGoPrevious: true,
            canGoNext: true
        )

        Divider()

        // .other — "Week 6 / 16"
        HomeWeekHeader(
            weekNumber: 6,
            totalWeeks: 16,
            phase: "Build",
            weekStartDate: sampleStart,
            titleVariant: .other,
            onPrevious: {},
            onNext: {},
            canGoPrevious: true,
            canGoNext: false    // last week — right chevron disabled
        )

        Divider()

        Spacer()
    }
}
