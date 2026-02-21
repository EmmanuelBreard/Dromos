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
/// Receives planService and profileService from parent (MainTabView) for shared data access.
struct CalendarPlanView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var planService: PlanService
    /// Shared profile service — provides athlete metrics (FTP, VMA, CSS) for expanded session details.
    @ObservedObject var profileService: ProfileService
    /// Toggled by MainTabView each time the Calendar tab is re-selected.
    /// Using @Binding ensures the change propagates even when the tab is inactive.
    @Binding var calendarReset: Bool

    @State private var currentWeekIndex: Int = 0
    /// Tracks which sessions are currently expanded. Resets on tab re-selection.
    @State private var expandedSessionIDs: Set<UUID> = []

    /// Logger for calendar operations
    private let logger = Logger(subsystem: "com.getdromos.app", category: "CalendarPlan")

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
            .onChange(of: planService.trainingPlan?.id) { _, _ in
                // Recalculate current week when plan data changes
                if let plan = planService.trainingPlan {
                    currentWeekIndex = plan.currentWeekIndex()
                    logger.debug("Current week index recalculated: \(currentWeekIndex, privacy: .public)")
                }
            }
            .onChange(of: calendarReset) { _, _ in
                // Tab re-selection: reset to current week and collapse all sessions
                if let plan = planService.trainingPlan {
                    currentWeekIndex = plan.currentWeekIndex()
                }
                expandedSessionIDs.removeAll()
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
                    ForEach(plan.daysForWeek(currentWeek), id: \.weekday) { dayInfo in
                        DaySessionRow(
                            weekday: dayInfo.weekday,
                            date: dayInfo.date,
                            sessions: dayInfo.sessions,
                            isRestDay: dayInfo.isRestDay,
                            expandedSessionIDs: expandedSessionIDs,
                            ftp: profileService.user?.ftp,
                            vma: profileService.user?.vma,
                            css: profileService.user?.cssSecondsPer100m,
                            onToggleExpand: { sessionID in
                                withAnimation {
                                    if expandedSessionIDs.contains(sessionID) {
                                        expandedSessionIDs.remove(sessionID)
                                    } else {
                                        expandedSessionIDs.insert(sessionID)
                                    }
                                }
                            }
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
                    if let userId = authService.currentUserId {
                        try? await planService.fetchFullPlan(userId: userId)
                    }
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
}

#Preview {
    CalendarPlanView(authService: AuthService(), planService: PlanService(), profileService: ProfileService(), calendarReset: .constant(false))
}
