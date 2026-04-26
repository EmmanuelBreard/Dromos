//
//  HomeView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// Home dashboard view displaying a single week's training sessions.
/// Navigation between weeks via chevron buttons or horizontal swipe (paged TabView).
/// Shares plan data with Calendar tab via the passed PlanService.
/// Receives stravaService to fetch activities and compute per-session completion status.
struct HomeView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var planService: PlanService
    /// Shared profile service — provides athlete metrics (FTP, VMA, CSS) for session card details.
    @ObservedObject var profileService: ProfileService
    /// Strava service used to fetch activities for the displayed week and compute completion status.
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

    // MARK: - State

    /// Index of the currently displayed week in plan.planWeeks.
    @State private var currentWeekIndex: Int = 0

    /// Whether edit mode is active (shows move arrows on session cards).
    @State private var isEditMode: Bool = false

    /// Per-week completion status cache. Key = week index, value = session-UUID → status map.
    /// Populated by `loadIfNeeded(weekIndex:plan:)`. Purged on Strava sync completion.
    @State private var completionCacheByWeek: [Int: [UUID: SessionCompletionStatus]] = [:]

    /// Set of week indices whose Strava fetch is currently in flight (drives skeleton).
    @State private var loadingWeeks: Set<Int> = []

    /// Guards the one-time initialisation of `currentWeekIndex` to avoid re-running on every appear.
    @State private var didInitializeWeekIndex: Bool = false

    // MARK: - Body

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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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

    /// Main content view: HomeWeekHeader + paged TabView (one page per plan week).
    private func contentView(plan: TrainingPlan) -> some View {
        VStack(spacing: 0) {
            HomeWeekHeader(
                weekNumber: plan.planWeeks[currentWeekIndex].weekNumber,
                totalWeeks: plan.planWeeks.count,
                phase: plan.planWeeks[currentWeekIndex].phase,
                weekStartDate: plan.planWeeks[currentWeekIndex].startDateAsDate ?? Date(),
                titleVariant: titleVariant(for: currentWeekIndex, plan: plan),
                onPrevious: { goToWeek(currentWeekIndex - 1, plan: plan) },
                onNext:     { goToWeek(currentWeekIndex + 1, plan: plan) },
                canGoPrevious: currentWeekIndex > 0,
                canGoNext: currentWeekIndex < plan.planWeeks.count - 1
            )

            TabView(selection: $currentWeekIndex) {
                ForEach(plan.planWeeks.indices, id: \.self) { idx in
                    weekContent(weekIndex: idx, plan: plan)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: currentWeekIndex)
        }
        .background(Color.pageSurface)
        .task {
            if !didInitializeWeekIndex {
                currentWeekIndex = plan.currentWeekIndex()
                didInitializeWeekIndex = true
            }
            await loadIfNeeded(weekIndex: currentWeekIndex, plan: plan)
        }
        .onChange(of: currentWeekIndex) { _, newIdx in
            Task {
                await loadIfNeeded(weekIndex: newIdx, plan: plan)
                await generatePendingFeedback(plan: plan, weekIndex: newIdx)
            }
        }
        .onChange(of: scrollReset) { _, _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                currentWeekIndex = plan.currentWeekIndex()
            }
        }
        .onChange(of: stravaService.isSyncing) { oldValue, newValue in
            // Re-run matching after a Strava sync completes so newly synced activities are reflected.
            if oldValue && !newValue {
                completionCacheByWeek.removeAll()
                Task {
                    await loadIfNeeded(weekIndex: currentWeekIndex, plan: plan)
                    await generatePendingFeedback(plan: plan, weekIndex: currentWeekIndex)
                }
            }
        }
    }

    // MARK: - Week Content

    /// Scrollable day list for a single week page inside the TabView.
    private func weekContent(weekIndex: Int, plan: TrainingPlan) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                let week = plan.planWeeks[weekIndex]
                let days = plan.daysForWeek(week)
                ForEach(days, id: \.weekday) { dayInfo in
                    daySectionView(
                        dayInfo: dayInfo,
                        plan: plan,
                        weekId: week.id,
                        weekNumber: week.weekNumber,
                        weekIndex: weekIndex
                    )
                    .id("\(week.weekNumber)-\(dayInfo.weekday)")
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Day Section

    /// A day section with header, session cards, and optional race day indicator.
    /// In edit mode, each session card shows up/down arrows to move between days.
    /// SessionCardView is skeleton-redacted while the week's Strava fetch is in flight.
    private func daySectionView(dayInfo: DayInfo, plan: TrainingPlan, weekId: UUID, weekNumber: Int, weekIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Day header with relative label + full date (never redacted)
            Text(dayHeaderLabel(for: dayInfo.date, weekday: dayInfo.weekday))
                .font(.headline)
                .foregroundColor(.primary)

            // Content: session cards or rest day
            if dayInfo.sessions.isEmpty {
                RestDayCardView()
            } else {
                let days = plan.daysForWeek(plan.planWeeks.first(where: { $0.id == weekId })!)
                let dayIndex = days.firstIndex(where: { $0.weekday == dayInfo.weekday }) ?? 0

                ForEach(Array(dayInfo.sessions.enumerated()), id: \.element.id) { sessionIndex, session in
                    let status = (completionCacheByWeek[weekIndex] ?? [:])[session.id] ?? .planned

                    if session.sport.lowercased() == "race" {
                        // Race sessions render as a rich RaceDayCardView — never redacted.
                        RaceDayCardView(
                            raceObjective: plan.raceObjective,
                            template: workoutLibrary.template(for: session.templateId),
                            notes: session.notes
                        )
                    } else {
                        HStack(spacing: 8) {
                            SessionCardView(
                                session: session,
                                swimDistance: swimDistance(for: session),
                                template: workoutLibrary.template(for: session.templateId),
                                ftp: profileService.user?.ftp,
                                vma: profileService.user?.vma,
                                css: profileService.user?.cssSecondsPer100m,
                                maxHr: profileService.user?.maxHr,
                                completionStatus: status
                            )
                            // Skeleton while Strava fetch is in flight (Strava-connected users only).
                            .redacted(reason: loadingWeeks.contains(weekIndex) ? .placeholder : [])

                            // Edit mode: hide move arrows for completed sessions (cannot be rescheduled).
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
            }

            // Race Day card (static fallback): shown only when the day is the race date
            // AND no seeded race session already exists — avoids duplicate race cards.
            if let raceDate = plan.raceDateAsDate,
               calendar.isDate(dayInfo.date, inSameDayAs: raceDate),
               !dayInfo.sessions.contains(where: { $0.sport.lowercased() == "race" }) {
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

    // MARK: - Navigation Helpers

    /// Returns the semantic title variant for a given week index.
    private func titleVariant(for index: Int, plan: TrainingPlan) -> HomeWeekHeader.TitleVariant {
        let current = plan.currentWeekIndex()
        switch index {
        case current:      return .currentWeek
        case current - 1:  return .lastWeek
        case current + 1:  return .nextWeek
        default:           return .other
        }
    }

    /// Navigates to a week by index (bounds-checked), with animation.
    private func goToWeek(_ idx: Int, plan: TrainingPlan) {
        guard idx >= 0, idx < plan.planWeeks.count else { return }
        withAnimation(.easeInOut(duration: 0.25)) { currentWeekIndex = idx }
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

    /// Gets swim distance for a session from the workout library.
    /// Returns nil for non-swim sessions.
    private func swimDistance(for session: PlanSession) -> Int? {
        guard session.sport.lowercased() == "swim" else { return nil }
        return workoutLibrary.swimDistance(for: session.templateId)
    }

    // MARK: - Completion Status

    /// Returns true when the session has a confirmed Strava match.
    /// Reads from the currently displayed week's cache.
    /// Used to suppress edit-mode move arrows on completed sessions.
    private func isCompleted(_ sessionId: UUID) -> Bool {
        if case .completed? = (completionCacheByWeek[currentWeekIndex] ?? [:])[sessionId] { return true }
        return false
    }

    /// Fetches Strava activities for the given week and populates the per-week cache.
    ///
    /// - Skips if Strava is not connected (user remains on `.planned`).
    /// - Skips if the cache already has an entry for this week (instant backtrack).
    /// - Skips if a fetch for this week is already in flight.
    private func loadIfNeeded(weekIndex: Int, plan: TrainingPlan) async {
        guard profileService.user?.isStravaConnected == true else { return }
        guard completionCacheByWeek[weekIndex] == nil else { return }
        guard !loadingWeeks.contains(weekIndex) else { return }

        loadingWeeks.insert(weekIndex)
        defer { loadingWeeks.remove(weekIndex) }

        let week = plan.planWeeks[weekIndex]
        let days = plan.daysForWeek(week)
        let dates = days.map(\.date)
        guard let from = dates.min(), let to = dates.max() else { return }

        // Pad ±1 day to handle UTC vs local timezone edge cases at date boundaries.
        let paddedFrom = calendar.date(byAdding: .day, value: -1, to: from)!
        let paddedTo   = calendar.date(byAdding: .day, value:  1, to: to)!
        let activities = await stravaService.fetchActivities(from: paddedFrom, to: paddedTo)

        // Build (session, resolvedDate) tuples for this week's sessions only.
        var sessionTuples: [(session: PlanSession, date: Date)] = []
        guard let weekStartDate = week.startDateAsDate else { return }
        for dayInfo in days {
            for session in dayInfo.sessions {
                let resolved = Weekday(fullName: session.day)
                    .map { $0.date(relativeTo: weekStartDate) } ?? dayInfo.date
                sessionTuples.append((session, resolved))
            }
        }

        completionCacheByWeek[weekIndex] = SessionMatcher.match(
            sessions: sessionTuples,
            activities: activities
        )
    }

    // MARK: - Session Feedback

    /// For each completed session in the displayed week that lacks feedback,
    /// triggers AI feedback generation. Fires sequentially to avoid rate limits.
    /// Scoped to the displayed week only — avoids silent fan-out as user paginates.
    private func generatePendingFeedback(plan: TrainingPlan, weekIndex: Int) async {
        guard profileService.user?.isStravaConnected == true else { return }
        guard let statuses = completionCacheByWeek[weekIndex] else { return }

        let weekSessionIds = Set(plan.planWeeks[weekIndex].planSessions.map(\.id))
        var didGenerate = false

        for (sessionId, status) in statuses {
            guard weekSessionIds.contains(sessionId) else { continue }
            guard case .completed(let activity) = status else { continue }
            let session = plan.planWeeks[weekIndex].planSessions.first { $0.id == sessionId }
            guard let session, session.feedback == nil else { continue }

            let feedback = await stravaService.generateSessionFeedback(
                sessionId: sessionId,
                activityId: activity.id
            )
            if feedback != nil { didGenerate = true }
        }

        // Refresh plan once at the end to pick up all new feedback without showing a spinner.
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
