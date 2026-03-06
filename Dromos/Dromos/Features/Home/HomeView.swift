//
//  HomeView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// Home dashboard view displaying the current week's training sessions.
/// Shows day-by-day view with rich session cards, auto-scrolling to today.
/// Shares plan data with Calendar tab via the passed PlanService.
/// Receives stravaService to fetch activities and compute per-session completion status.
struct HomeView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var planService: PlanService
    /// Shared profile service — provides athlete metrics (FTP, VMA, CSS) for session card details.
    @ObservedObject var profileService: ProfileService
    /// Strava service used to fetch activities for the visible date range and compute completion status.
    @ObservedObject var stravaService: StravaService
    /// Toggled by MainTabView each time the Home tab is re-selected.
    /// Using @Binding ensures the change propagates via Combine even when the tab is inactive.
    @Binding var scrollReset: Bool

    /// Reference to the workout library for swim distance lookups.
    private let workoutLibrary = WorkoutLibraryService.shared

    /// Cached calendar instance to avoid repeated allocations.
    private let calendar = Calendar.current

    /// Reusable date formatter for day headers (e.g., "1 February").
    private static let dayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMMM"
        return f
    }()

    /// Reusable date formatter for month abbreviations (e.g., "Feb").
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    /// Last visible week index (controls progressive disclosure).
    @State private var lastVisibleWeekIndex: Int = 0

    /// Whether edit mode is active (shows move arrows on session cards).
    @State private var isEditMode: Bool = false

    /// Maps each session UUID to its computed completion status (planned/completed/missed).
    /// Populated by `loadCompletionStatuses(plan:)` after fetching Strava activities.
    @State private var completionStatuses: [UUID: SessionCompletionStatus] = [:]

    var body: some View {
        NavigationStack {
            Group {
                if planService.isLoadingPlan {
                    loadingView
                } else if let errorMessage = planService.errorMessage {
                    errorView(errorMessage: errorMessage)
                } else if let plan = planService.trainingPlan, !plan.planWeeks.isEmpty {
                    contentView(plan: plan)
                } else {
                    emptyStateView
                }
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if planService.trainingPlan != nil {
                        Button(isEditMode ? "Done" : "Edit") {
                            withAnimation(.easeInOut(duration: 0.25)) { isEditMode.toggle() }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Loading View

    /// Loading state with progress indicator.
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading your training plan...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Content View

    /// Main content view with multi-week scrollable sections.
    private func contentView(plan: TrainingPlan) -> some View {
        let currentWeekIndex = plan.currentWeekIndex()
        let safeLastVisible = max(currentWeekIndex, lastVisibleWeekIndex)
        let endIndex = min(safeLastVisible, plan.planWeeks.count - 1)
        let visibleWeeks = Array(plan.planWeeks[currentWeekIndex...endIndex])

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Multi-week sections (current week through lastVisibleWeekIndex)
                    ForEach(Array(visibleWeeks.enumerated()), id: \.element.id) { offset, week in
                        let weekIndex = currentWeekIndex + offset

                        // Week section header
                        weekSectionHeader(week: week, currentWeekIndex: currentWeekIndex, weekIndex: weekIndex)
                            .padding(.horizontal)
                            .padding(.top, offset == 0 ? 0 : 16)
                            .padding(.bottom, 8)
                            .id("week-\(week.weekNumber)")

                        // Day sections for this week
                        let days = plan.daysForWeek(week)
                        LazyVStack(spacing: 16) {
                            ForEach(days, id: \.weekday) { dayInfo in
                                daySectionView(dayInfo: dayInfo, plan: plan, weekId: week.id, weekNumber: week.weekNumber)
                                    .id("\(week.weekNumber)-\(dayInfo.weekday)")
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }

                    // "Show next week" CTA (only if more weeks remain)
                    if endIndex < plan.planWeeks.count - 1 {
                        showNextWeekButton
                    }
                }
            }
            .background(Color.pageSurface)
            .task {
                lastVisibleWeekIndex = min(currentWeekIndex + 1, plan.planWeeks.count - 1)
                scrollToToday(proxy: proxy, plan: plan, currentWeekIndex: currentWeekIndex)
                await loadCompletionStatuses(plan: plan)
                await generatePendingFeedback(plan: plan)
            }
            .onChange(of: scrollReset) { _, _ in
                // Tab re-selection: reset weeks and scroll to today (matching first-load behavior).
                // Task inside .onChange is acceptable — triggered by user action, not view lifecycle.
                lastVisibleWeekIndex = min(currentWeekIndex + 1, plan.planWeeks.count - 1)
                scrollToToday(proxy: proxy, plan: plan, currentWeekIndex: currentWeekIndex)
                Task { await loadCompletionStatuses(plan: plan) }
            }
            .onChange(of: lastVisibleWeekIndex) { _, _ in
                Task { await loadCompletionStatuses(plan: plan) }
            }
            .onChange(of: stravaService.isSyncing) { oldValue, newValue in
                // Re-run matching after a Strava sync completes so newly synced activities are reflected.
                if oldValue && !newValue {
                    Task {
                        await loadCompletionStatuses(plan: plan)
                        await generatePendingFeedback(plan: plan)
                    }
                }
            }
        }
    }

    // MARK: - Week Section Header

    /// Week section header with title, date range, and phase badge.
    /// Shows "Current Week" / "Next Week" for the first two weeks, then date range only.
    private func weekSectionHeader(week: PlanWeek, currentWeekIndex: Int, weekIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    // Title: "Current Week", "Next Week", or date range
                    if weekIndex == currentWeekIndex {
                        Text("Current Week")
                            .font(.title2)
                            .fontWeight(.bold)
                    } else if weekIndex == currentWeekIndex + 1 {
                        Text("Next Week")
                            .font(.title2)
                            .fontWeight(.bold)
                    }

                    // Date range subtitle (always shown)
                    Text(weekDateRange(week: week))
                        .font(weekIndex <= currentWeekIndex + 1 ? .subheadline : .title3)
                        .fontWeight(weekIndex <= currentWeekIndex + 1 ? .regular : .semibold)
                        .foregroundColor(weekIndex <= currentWeekIndex + 1 ? .secondary : .primary)
                }

                // Phase badge (always shown)
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.phaseColor(for: week.phase))
                        .frame(width: 8, height: 8)
                    Text(week.phase)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(Color.phaseColor(for: week.phase))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.phaseColor(for: week.phase).opacity(0.15))
                .clipShape(Capsule())

                Spacer()
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Day Section

    /// A day section with header, session cards, and optional race day indicator.
    /// In edit mode, each session card shows up/down arrows to move between days.
    private func daySectionView(dayInfo: DayInfo, plan: TrainingPlan, weekId: UUID, weekNumber: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Day header with relative label + full date
            Text(dayHeaderLabel(for: dayInfo.date, weekday: dayInfo.weekday))
                .font(.headline)
                .foregroundColor(.primary)

            // Content: session cards or rest day
            if dayInfo.isRestDay && dayInfo.sessions.isEmpty {
                RestDayCardView()
            } else {
                let days = plan.daysForWeek(plan.planWeeks.first(where: { $0.id == weekId })!)
                let dayIndex = days.firstIndex(where: { $0.weekday == dayInfo.weekday }) ?? 0

                ForEach(Array(dayInfo.sessions.enumerated()), id: \.element.id) { sessionIndex, session in
                    let status = completionStatuses[session.id] ?? .planned
                    HStack(spacing: 8) {
                        SessionCardView(
                            session: session,
                            swimDistance: swimDistance(for: session),
                            template: workoutLibrary.template(for: session.templateId),
                            ftp: profileService.user?.ftp,
                            vma: profileService.user?.vma,
                            css: profileService.user?.cssSecondsPer100m,
                            completionStatus: status
                        )

                        // Edit mode: hide move arrows for completed sessions (they cannot be rescheduled).
                        if isEditMode && !isCompleted(session.id) {
                            VStack(spacing: 12) {
                                // Up: reorder within day first, then cross to previous day
                                Button {
                                    moveSessionUp(
                                        session: session, sessionIndex: sessionIndex,
                                        weekId: weekId, dayInfo: dayInfo,
                                        days: days, dayIndex: dayIndex
                                    )
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .fontWeight(.semibold)
                                }
                                .disabled(dayIndex == 0 && sessionIndex == 0)

                                // Down: reorder within day first, then cross to next day
                                Button {
                                    moveSessionDown(
                                        session: session, sessionIndex: sessionIndex,
                                        weekId: weekId, dayInfo: dayInfo,
                                        days: days, dayIndex: dayIndex
                                    )
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .fontWeight(.semibold)
                                }
                                .disabled(dayIndex == days.count - 1 && sessionIndex == dayInfo.sessions.count - 1)
                            }
                            .font(.title3)
                            .foregroundColor(.blue)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
            }

            // Race Day card (if this day is the race date)
            if let raceDate = plan.raceDateAsDate,
               calendar.isDate(dayInfo.date, inSameDayAs: raceDate) {
                RaceDayCardView(raceObjective: plan.raceObjective)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }

    // MARK: - Empty State

    /// Empty state when no plan is available.
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image("DromosLogo")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 48)
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

    // MARK: - "Show Next Week" CTA

    /// Button to progressively reveal more weeks.
    /// Content appears below without scrolling — user scrolls down naturally.
    private var showNextWeekButton: some View {
        Button {
            lastVisibleWeekIndex += 1
        } label: {
            HStack(spacing: 6) {
                Text("Show next week")
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.blue)
        }
        .padding(.vertical, 24)
    }

    // MARK: - Helper Methods

    /// Creates the day header label: "Today", "Tomorrow", or full date for other days.
    /// Examples: "Today", "Tomorrow", "Monday 3 February"
    private func dayHeaderLabel(for date: Date, weekday: Weekday) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let dateString = Self.dayDateFormatter.string(from: date)
            return "\(weekday.fullName) \(dateString)"
        }
    }

    /// Formats a week's date range with ordinal suffixes.
    /// Examples: "Feb 10th - 16th", "Feb 28th - Mar 6th"
    private func weekDateRange(week: PlanWeek) -> String {
        guard let startDate = week.startDateAsDate else { return "Week \(week.weekNumber)" }
        let endDate = calendar.date(byAdding: .day, value: 6, to: startDate) ?? startDate

        let startDay = calendar.component(.day, from: startDate)
        let endDay = calendar.component(.day, from: endDate)

        let startMonth = Self.monthFormatter.string(from: startDate)
        let endMonth = Self.monthFormatter.string(from: endDate)

        if startMonth == endMonth {
            return "\(startMonth) \(ordinal(startDay)) - \(ordinal(endDay))"
        } else {
            return "\(startMonth) \(ordinal(startDay)) - \(endMonth) \(ordinal(endDay))"
        }
    }

    /// Converts a day number to its ordinal form (1st, 2nd, 3rd, etc.).
    private func ordinal(_ day: Int) -> String {
        let suffix: String
        switch day {
        case 1, 21, 31: suffix = "st"
        case 2, 22: suffix = "nd"
        case 3, 23: suffix = "rd"
        default: suffix = "th"
        }
        return "\(day)\(suffix)"
    }

    /// Scrolls to today's section if it exists (using composite week-day IDs).
    private func scrollToToday(proxy: ScrollViewProxy, plan: TrainingPlan, currentWeekIndex: Int) {
        guard currentWeekIndex < plan.planWeeks.count else { return }
        let currentWeek = plan.planWeeks[currentWeekIndex]
        let days = plan.daysForWeek(currentWeek)

        // Find today's weekday in the current week.
        // Delay allows view to re-render after lastVisibleWeekIndex reset.
        if let todayInfo = days.first(where: { calendar.isDateInToday($0.date) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("\(currentWeek.weekNumber)-\(todayInfo.weekday)", anchor: .top)
                }
            }
        }
    }

    /// Gets swim distance for a session from the workout library.
    /// Returns nil for non-swim sessions.
    private func swimDistance(for session: PlanSession) -> Int? {
        guard session.sport.lowercased() == "swim" else { return nil }
        return workoutLibrary.swimDistance(for: session.templateId)
    }

    // MARK: - Completion Status

    /// Returns true when the session has a confirmed Strava match.
    /// Used to suppress edit-mode move arrows on completed sessions.
    private func isCompleted(_ sessionId: UUID) -> Bool {
        if case .completed? = completionStatuses[sessionId] { return true }
        return false
    }

    /// Fetches Strava activities for the visible date range and builds the completion status map.
    ///
    /// Early-exits if the user has not connected Strava — all sessions remain `.planned`.
    /// Covers the full range of currently visible weeks so completion state is always accurate.
    /// Existing statuses remain visible during fetch; overwritten on completion.
    private func loadCompletionStatuses(plan: TrainingPlan) async {
        // Only compute when Strava is connected — avoids unnecessary network calls.
        guard profileService.user?.isStravaConnected == true else { return }

        let currentWeekIndex = plan.currentWeekIndex()
        let safeLastVisible = max(currentWeekIndex, lastVisibleWeekIndex)
        let endIndex = min(safeLastVisible, plan.planWeeks.count - 1)
        // Start from week 0 so past weeks also get completion statuses (completed/missed).
        let visibleWeeks = Array(plan.planWeeks[0...endIndex])

        let allDates = visibleWeeks.flatMap { plan.daysForWeek($0) }.map(\.date)
        guard let fromDate = allDates.min(), let toDate = allDates.max() else { return }

        // Pad ±1 day to handle UTC vs local timezone edge cases at date boundaries.
        let paddedFrom = calendar.date(byAdding: .day, value: -1, to: fromDate)!
        let paddedTo = calendar.date(byAdding: .day, value: 1, to: toDate)!

        // Fetch activities covering the padded visible range.
        let activities = await stravaService.fetchActivities(from: paddedFrom, to: paddedTo)

        // Build (session, resolvedDate) tuples for all visible sessions.
        var sessionTuples: [(session: PlanSession, date: Date)] = []
        for week in visibleWeeks {
            guard let weekStartDate = week.startDateAsDate else { continue }
            let days = plan.daysForWeek(week)
            for dayInfo in days {
                for session in dayInfo.sessions {
                    let resolvedDate = Weekday(fullName: session.day)
                        .map { $0.date(relativeTo: weekStartDate) }
                        ?? dayInfo.date
                    sessionTuples.append((session: session, date: resolvedDate))
                }
            }
        }

        // Run the matching engine and publish results.
        completionStatuses = SessionMatcher.match(sessions: sessionTuples, activities: activities)
    }

    // MARK: - Session Feedback

    /// For each newly completed session that lacks feedback, trigger AI feedback generation.
    /// Fires sequentially to avoid rate limits. Silently skips failures.
    private func generatePendingFeedback(plan: TrainingPlan) async {
        guard profileService.user?.isStravaConnected == true else { return }

        var didGenerate = false

        // Order is non-deterministic but acceptable — each call is idempotent
        for (sessionId, status) in completionStatuses {
            guard case .completed(let activity) = status else { continue }

            // Find the PlanSession to check if feedback already exists
            let session = plan.planWeeks
                .flatMap(\.planSessions)
                .first { $0.id == sessionId }
            guard let session, session.feedback == nil else { continue }

            // Fire Edge Function — result is written to DB
            let feedback = await stravaService.generateSessionFeedback(
                sessionId: sessionId,
                activityId: activity.id
            )

            if feedback != nil {
                didGenerate = true
            }
        }

        // Refresh plan once at the end to pick up all new feedback without showing a spinner
        if didGenerate {
            await planService.refreshPlan(userId: plan.userId)
        }
    }

    // MARK: - Edit Mode Actions

    /// Moves a session up: reorders within the same day first, then crosses to the previous day.
    private func moveSessionUp(session: PlanSession, sessionIndex: Int, weekId: UUID, dayInfo: DayInfo, days: [DayInfo], dayIndex: Int) {
        if sessionIndex > 0 {
            // Reorder within same day — move up one position
            Task {
                await planService.moveSession(
                    sessionId: session.id,
                    toDay: dayInfo.weekday,
                    toWeekId: weekId,
                    atIndex: sessionIndex - 1
                )
            }
        } else if dayIndex > 0 {
            // Already at top of day — move to previous day (append at end,
            // visually close to where it came from).
            let targetDay = days[dayIndex - 1]
            Task {
                await planService.moveSession(
                    sessionId: session.id,
                    toDay: targetDay.weekday,
                    toWeekId: weekId,
                    atIndex: targetDay.sessions.count
                )
            }
        }
    }

    /// Moves a session down: reorders within the same day first, then crosses to the next day.
    private func moveSessionDown(session: PlanSession, sessionIndex: Int, weekId: UUID, dayInfo: DayInfo, days: [DayInfo], dayIndex: Int) {
        if sessionIndex < dayInfo.sessions.count - 1 {
            // Reorder within same day — move down one position
            Task {
                await planService.moveSession(
                    sessionId: session.id,
                    toDay: dayInfo.weekday,
                    toWeekId: weekId,
                    atIndex: sessionIndex + 1
                )
            }
        } else if dayIndex < days.count - 1 {
            // Already at bottom of day — move to next day (insert at start,
            // visually close to where it came from).
            let targetDay = days[dayIndex + 1]
            Task {
                await planService.moveSession(
                    sessionId: session.id,
                    toDay: targetDay.weekday,
                    toWeekId: weekId,
                    atIndex: 0
                )
            }
        }
    }
}

#Preview("Home - Content") {
    HomeView(
        authService: AuthService(),
        planService: PlanService(),
        profileService: ProfileService(),
        stravaService: StravaService(),
        scrollReset: .constant(false)
    )
}
