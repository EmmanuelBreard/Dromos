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
struct HomeView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var planService: PlanService

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

                        // Day sections for this week
                        let days = plan.daysForWeek(week)
                        LazyVStack(spacing: 16) {
                            ForEach(days, id: \.weekday) { dayInfo in
                                daySectionView(dayInfo: dayInfo, plan: plan)
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
            .onAppear {
                // Reset to current + next week (fresh view on each tab switch)
                lastVisibleWeekIndex = min(currentWeekIndex + 1, plan.planWeeks.count - 1)
                // Auto-scroll to today
                scrollToToday(proxy: proxy, plan: plan, currentWeekIndex: currentWeekIndex)
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
    private func daySectionView(dayInfo: DayInfo, plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Day header with relative label + full date
            Text(dayHeaderLabel(for: dayInfo.date, weekday: dayInfo.weekday))
                .font(.headline)
                .foregroundColor(.primary)

            // Content: session cards or rest day
            if dayInfo.isRestDay && dayInfo.sessions.isEmpty {
                RestDayCardView()
            } else {
                ForEach(dayInfo.sessions) { session in
                    SessionCardView(
                        session: session,
                        swimDistance: swimDistance(for: session)
                    )
                }
            }

            // Race Day card (if this day is the race date)
            if let raceDate = plan.raceDateAsDate,
               calendar.isDate(dayInfo.date, inSameDayAs: raceDate) {
                RaceDayCardView(raceObjective: plan.raceObjective)
            }
        }
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
    private var showNextWeekButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                lastVisibleWeekIndex += 1
            }
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

    /// Creates the day header label with relative prefix (Today/Tomorrow) + full date.
    /// Examples: "Today Saturday 1 February", "Tomorrow Sunday 2 February", "Monday 3 February"
    private func dayHeaderLabel(for date: Date, weekday: Weekday) -> String {
        let dateString = Self.dayDateFormatter.string(from: date)

        if calendar.isDateInToday(date) {
            return "Today \(weekday.fullName) \(dateString)"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow \(weekday.fullName) \(dateString)"
        } else {
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

        // Find today's weekday in the current week
        if let todayInfo = days.first(where: { calendar.isDateInToday($0.date) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
}

#Preview("Home - Content") {
    HomeView(authService: AuthService(), planService: PlanService())
}
