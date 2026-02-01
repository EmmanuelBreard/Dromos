//
//  WeekHeaderView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 01/02/2026.
//

import SwiftUI

/// Header view for displaying week navigation, phase badge, and date range.
/// Matches the Stamina-style design with arrows, week number, phase, and dates.
struct WeekHeaderView: View {
    let weekNumber: Int
    let totalWeeks: Int
    let phase: String
    let weekStartDate: Date
    let onPrevious: () -> Void
    let onNext: () -> Void
    let canGoPrevious: Bool
    let canGoNext: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Row 1: Navigation arrows and week number
            HStack {
                // Previous arrow
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(canGoPrevious ? .primary : .gray.opacity(0.3))
                }
                .disabled(!canGoPrevious)

                Spacer()

                // Week number
                Text("Week \(weekNumber) / \(totalWeeks)")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                // Next arrow
                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .foregroundColor(canGoNext ? .primary : .gray.opacity(0.3))
                }
                .disabled(!canGoNext)
            }

            // Phase badge
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.phaseColor(for: phase))
                    .frame(width: 8, height: 8)
                Text("\(phase) phase")
                    .font(.subheadline)
                    .foregroundColor(Color.phaseColor(for: phase))
            }

            // Date range
            Text(dateRangeLabel)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Computed Properties

    /// Date range label (e.g., "FEB 2026" or "JAN / FEB" if week spans months).
    private var dateRangeLabel: String {
        let calendar = Calendar.current
        let endDate = calendar.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate

        let startMonth = calendar.component(.month, from: weekStartDate)
        let startYear = calendar.component(.year, from: weekStartDate)
        let endMonth = calendar.component(.month, from: endDate)
        let endYear = calendar.component(.year, from: endDate)

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"

        let startMonthName = monthFormatter.string(from: weekStartDate).uppercased()
        let endMonthName = monthFormatter.string(from: endDate).uppercased()

        if startMonth == endMonth && startYear == endYear {
            // Same month: "FEB 2026"
            let yearFormatter = DateFormatter()
            yearFormatter.dateFormat = "yyyy"
            return "\(startMonthName) \(yearFormatter.string(from: weekStartDate))"
        } else {
            // Different months: "JAN / FEB"
            return "\(startMonthName) / \(endMonthName)"
        }
    }
}

#Preview {
    VStack {
        WeekHeaderView(
            weekNumber: 2,
            totalWeeks: 16,
            phase: "Base",
            weekStartDate: Date(),
            onPrevious: {},
            onNext: {},
            canGoPrevious: true,
            canGoNext: true
        )
        Spacer()
    }
    .padding()
}

