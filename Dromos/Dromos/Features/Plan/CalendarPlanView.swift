//
//  CalendarPlanView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 01/02/2026.
//

import SwiftUI
import OSLog

/// Main calendar view displaying week-by-week training plan overview.
/// Auto-opens to current week, allows navigation between weeks.
struct CalendarPlanView: View {
    @ObservedObject var authService: AuthService
    @StateObject private var planService = PlanService()

    @State private var currentWeekIndex: Int = 0

    /// Logger for calendar operations
    private let logger = Logger(subsystem: "com.dromos.app", category: "CalendarPlan")

    var body: some View {
        NavigationStack {
            Group {
                if planService.isLoadingPlan {
                    // Loading state
                    ProgressView()
                        .scaleEffect(1.5)
                } else if let errorMessage = planService.errorMessage {
                    // Error state
                    errorView(errorMessage: errorMessage)
                } else if let plan = planService.trainingPlan, !plan.planWeeks.isEmpty {
                    // Content state
                    contentView(plan: plan)
                } else {
                    // No plan state
                    emptyStateView
                }
            }
            .navigationTitle("Plan")
            .task {
                await loadPlan()
            }
        }
    }

    // MARK: - Content View

    /// Main content view with week navigation and day sessions.
    private func contentView(plan: TrainingPlan) -> some View {
        let currentWeek = plan.planWeeks[currentWeekIndex]

        return ScrollView {
            VStack(spacing: 0) {
                // Week header
                WeekHeaderView(
                    weekNumber: currentWeek.weekNumber,
                    totalWeeks: plan.totalWeeks,
                    phase: currentWeek.phase,
                    weekStartDate: currentWeek.startDateAsDate ?? Date(),
                    onPrevious: {
                        if currentWeekIndex > 0 {
                            currentWeekIndex -= 1
                        }
                    },
                    onNext: {
                        if currentWeekIndex < plan.planWeeks.count - 1 {
                            currentWeekIndex += 1
                        }
                    },
                    canGoPrevious: currentWeekIndex > 0,
                    canGoNext: currentWeekIndex < plan.planWeeks.count - 1
                )
                .padding(.horizontal)
                .padding(.top)

                // Days list
                LazyVStack(spacing: 0) {
                    ForEach(daysForWeek(currentWeek, plan: plan), id: \.weekday) { dayInfo in
                        DaySessionRow(
                            weekday: dayInfo.weekday,
                            date: dayInfo.date,
                            sessions: dayInfo.sessions,
                            isRestDay: dayInfo.isRestDay
                        )
                        .padding(.horizontal)
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    /// Empty state when no plan is available.
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            Text("No Training Plan")
                .font(.title2)
                .fontWeight(.bold)
            Text("Your training plan will appear here once generated.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Error View

    /// Error state with retry button.
    private func errorView(errorMessage: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.red)

            VStack(spacing: 8) {
                Text("Failed to Load Plan")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: {
                Task {
                    await loadPlan()
                }
            }) {
                Text("Retry")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
        }
        .padding()
    }

    // MARK: - Helper Methods

    /// Loads the training plan and calculates current week index.
    private func loadPlan() async {
        guard let userId = authService.currentUserId else {
            logger.error("Cannot load plan: No user ID available")
            return
        }

        do {
            try await planService.fetchFullPlan(userId: userId)
            logger.info("Successfully loaded training plan")

            // Calculate current week index
            if let plan = planService.trainingPlan {
                currentWeekIndex = calculateCurrentWeekIndex(plan: plan)
                logger.debug("Current week index: \(currentWeekIndex, privacy: .public)")
            }
        } catch {
            logger.error("Failed to load training plan: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Calculates which week contains today's date.
    /// Falls back to Week 1 if before plan start, last week if after plan end.
    private func calculateCurrentWeekIndex(plan: TrainingPlan) -> Int {
        let today = Date()
        let calendar = Calendar.current

        // If before plan start, return Week 1
        if let planStart = plan.startDateAsDate, today < planStart {
            return 0
        }

        // Find week containing today
        for (index, week) in plan.planWeeks.enumerated() {
            guard let weekStart = week.startDateAsDate else { continue }
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart

            if today >= weekStart && today <= weekEnd {
                return index
            }
        }

        // If after all weeks, return last week
        return max(0, plan.planWeeks.count - 1)
    }

    /// Returns day information for the current week, handling partial Week 1.
    private func daysForWeek(_ week: PlanWeek, plan: TrainingPlan) -> [DayInfo] {
        guard let weekStartDate = week.startDateAsDate else { return [] }

        let calendar = Calendar.current
        let sessionsByDay = week.sessionsByDay
        let restDaySet = week.restDaySet

        var days: [DayInfo] = []

        // Determine which weekdays to show
        let weekdaysToShow: [Weekday]
        if week.weekNumber == 1, let planStart = plan.startDateAsDate {
            // Partial Week 1: only show days from plan start to Sunday
            let weekdayComponent = calendar.component(.weekday, from: planStart)
            // Convert Calendar weekday (Sunday=1, Monday=2, ..., Saturday=7) to our Weekday enum
            let startWeekday: Weekday
            switch weekdayComponent {
            case 1: startWeekday = .sunday
            case 2: startWeekday = .monday
            case 3: startWeekday = .tuesday
            case 4: startWeekday = .wednesday
            case 5: startWeekday = .thursday
            case 6: startWeekday = .friday
            case 7: startWeekday = .saturday
            default: startWeekday = .monday
            }
            
            // Get all weekdays from start to Sunday
            if let startIndex = Weekday.allCases.firstIndex(of: startWeekday) {
                weekdaysToShow = Array(Weekday.allCases[startIndex...])
            } else {
                weekdaysToShow = Weekday.allCases
            }
        } else {
            // Full week: show all days Monday through Sunday
            weekdaysToShow = Weekday.allCases
        }

        // Create day info for each weekday
        for weekday in weekdaysToShow {
            let dayDate = weekday.date(relativeTo: weekStartDate)

            // Skip days before plan start for Week 1 (safety check)
            if week.weekNumber == 1,
               let planStart = plan.startDateAsDate,
               dayDate < planStart {
                continue
            }

            let sessions = sessionsByDay[weekday] ?? []
            let isRestDay = restDaySet.contains(weekday) && sessions.isEmpty

            days.append(DayInfo(
                weekday: weekday,
                date: dayDate,
                sessions: sessions,
                isRestDay: isRestDay
            ))
        }

        return days
    }
}

// MARK: - Day Info

/// Information about a single day in the week.
private struct DayInfo {
    let weekday: Weekday
    let date: Date
    let sessions: [PlanSession]
    let isRestDay: Bool
}

#Preview {
    CalendarPlanView(authService: AuthService())
}

