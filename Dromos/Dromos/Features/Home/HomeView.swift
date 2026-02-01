//
//  HomeView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI
import OSLog

/// Home dashboard view displaying the current week's training sessions.
/// Shows day-by-day view with rich session cards, auto-scrolling to today.
/// Shares plan data with Calendar tab via the passed PlanService.
struct HomeView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var planService: PlanService
    
    /// Reference to the workout library for swim distance lookups.
    private let workoutLibrary = WorkoutLibraryService.shared
    
    /// Logger for home view operations.
    private let logger = Logger(subsystem: "com.dromos.app", category: "Home")
    
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
    
    /// Main content view with week header and day sections.
    private func contentView(plan: TrainingPlan) -> some View {
        let currentWeekIndex = calculateCurrentWeekIndex(plan: plan)
        let currentWeek = plan.planWeeks[currentWeekIndex]
        let days = daysForWeek(currentWeek, plan: plan)
        
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Week header (simplified, no navigation arrows)
                    weekHeader(week: currentWeek, plan: plan)
                        .padding(.horizontal)
                        .padding(.top)
                        .padding(.bottom, 8)
                    
                    // Day sections
                    LazyVStack(spacing: 16) {
                        ForEach(days, id: \.weekday) { dayInfo in
                            daySectionView(dayInfo: dayInfo, week: currentWeek)
                                .id(dayInfo.weekday)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .onAppear {
                // Auto-scroll to today
                scrollToToday(proxy: proxy, days: days)
            }
        }
    }
    
    // MARK: - Week Header
    
    /// Simplified week header showing "Week N — Phase" with phase badge.
    private func weekHeader(week: PlanWeek, plan: TrainingPlan) -> some View {
        VStack(spacing: 8) {
            // Week number and phase
            HStack(spacing: 12) {
                Text("Week \(week.weekNumber)")
                    .font(.title2)
                    .fontWeight(.bold)
                
                // Phase badge
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
    
    /// A day section with header and session cards.
    private func daySectionView(dayInfo: DayInfo, week: PlanWeek) -> some View {
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
        }
    }
    
    // MARK: - Empty State
    
    /// Empty state when no plan is available.
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run")
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
                    await retryLoadPlan()
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
    
    /// Retries loading the training plan.
    private func retryLoadPlan() async {
        guard let userId = authService.currentUserId else {
            logger.error("Cannot load plan: No user ID available")
            return
        }
        
        do {
            try await planService.fetchFullPlan(userId: userId)
            logger.info("Successfully loaded training plan on retry")
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
            
            if let startIndex = Weekday.allCases.firstIndex(of: startWeekday) {
                weekdaysToShow = Array(Weekday.allCases[startIndex...])
            } else {
                weekdaysToShow = Weekday.allCases
            }
        } else {
            weekdaysToShow = Weekday.allCases
        }
        
        // Create day info for each weekday
        for weekday in weekdaysToShow {
            let dayDate = weekday.date(relativeTo: weekStartDate)
            
            // Skip days before plan start for Week 1
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
    
    /// Creates the day header label with relative prefix (Today/Tomorrow) + full date.
    /// Examples: "Today Saturday 1 February", "Tomorrow Sunday 2 February", "Monday 3 February"
    private func dayHeaderLabel(for date: Date, weekday: Weekday) -> String {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMMM"
        let dateString = dateFormatter.string(from: date)
        
        if calendar.isDateInToday(date) {
            return "Today \(weekday.fullName) \(dateString)"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow \(weekday.fullName) \(dateString)"
        } else {
            return "\(weekday.fullName) \(dateString)"
        }
    }
    
    /// Scrolls to today's section if it exists.
    private func scrollToToday(proxy: ScrollViewProxy, days: [DayInfo]) {
        let calendar = Calendar.current
        
        // Find today's weekday in the current week
        if let todayInfo = days.first(where: { calendar.isDateInToday($0.date) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(todayInfo.weekday, anchor: .top)
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
