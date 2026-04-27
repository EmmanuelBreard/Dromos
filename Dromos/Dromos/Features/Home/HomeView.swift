//
//  HomeView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//  DRO-237 — Phase 5 of DRO-231: full Today screen assembly + lifecycle.
//

import SwiftUI

/// Today screen ("Home" tab).
///
/// Top → bottom layout:
/// 1. `SportProgressStrip` — week-to-date completion vs. plan, by sport.
/// 2. `todayHero` — state-routed card(s) for today's session(s):
///    - Empty plan → `EmptyHomeHero`
///    - No sessions today → `RestDayCardView`
///    - Race day → `RaceDayCardView`
///    - 1 session → `TodayPlannedCard` / `TodayCompletedCard` / `TodayMissedCard`
///    - 2+ sessions → header + ordered stack (planned-on-top, then completed)
/// 3. `WeekDayStrip` — 7-pill weekly overview.
///
/// Lifecycle:
/// - `.task` → first load.
/// - `.onChange(stravaService.isSyncing)` → re-load completion + totals when a sync finishes.
/// - `.onChange(homeReset)` → tab re-tap forces a Strava sync + refetch + scroll-to-top.
/// - `.refreshable` → pull-to-refresh triggers `stravaService.syncActivities()`.
///
/// No `.toolbar` — Today is a "look at it, go do it" surface, not an editor.
struct HomeView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var planService: PlanService
    @ObservedObject var profileService: ProfileService
    @ObservedObject var stravaService: StravaService
    @Binding var homeReset: Bool

    /// Per-session completion status, keyed by `PlanSession.id`. Recomputed whenever
    /// activities or the visible week change. Empty until the first `.task` resolves.
    @State private var completionStatuses: [UUID: SessionCompletionStatus] = [:]

    /// Per-sport (done, total) minutes for the current week. Drives the top progress strip.
    @State private var sportTotals: [String: (done: Int, total: Int)] = [:]

    /// Cached fetch of this week's Strava activities. Kept in state so multi-card render
    /// passes don't re-hit Supabase between completion lookups.
    @State private var activities: [StravaActivity] = []

    private let workoutLibrary = WorkoutLibraryService.shared
    private let calendar = Calendar.current

    /// Current week, derived from `currentWeekIndex()` since `TrainingPlan` doesn't
    /// expose a direct `currentWeek()` accessor. Returns nil when no plan is loaded
    /// or the index is out of bounds (defensive — should not happen in practice).
    private var currentWeek: PlanWeek? {
        guard let plan = planService.trainingPlan else { return nil }
        let idx = plan.currentWeekIndex()
        guard plan.planWeeks.indices.contains(idx) else { return nil }
        return plan.planWeeks[idx]
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 24) {
                        if planService.trainingPlan == nil {
                            // Empty state takes the whole canvas — strip + week-strip are hidden
                            // because the user has no plan to derive them from.
                            EmptyHomeHero(onGeneratePlan: {
                                // TODO(DRO-237 follow-up): Wire to plan-generation flow.
                                // RootView routes to PlanGenerationView when `authService.hasPlan == false`,
                                // but there's no programmatic re-entry from inside MainTabView today.
                                // Leaving as a no-op so the QA pass / human reviewer can decide whether
                                // to surface a sheet, deep-link, or status mutation.
                            })
                        } else {
                            SportProgressStrip(totals: sportTotalsForStrip())
                            todayHero
                            WeekDayStrip(days: weekPills)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .id("top")
                }
                .background(Color.pageSurface)
                .refreshable {
                    await stravaService.syncActivities()
                }
                .task {
                    await loadCompletionAndTotals()
                }
                .onChange(of: stravaService.isSyncing) { _, isSyncing in
                    // When a sync finishes (isSyncing flips false), refetch the visible-week
                    // activities + recompute completion + totals. Avoids stale UI after pull-to-
                    // refresh, foreground-resume syncs, or homeReset re-taps.
                    if !isSyncing {
                        Task { await loadCompletionAndTotals() }
                    }
                }
                .onChange(of: homeReset) { _, _ in
                    // Tab re-tap: sync Strava, refetch, then scroll to top. Sync is awaited
                    // before the refetch so the new activities land in the same render pass.
                    Task {
                        await stravaService.syncActivities()
                        await loadCompletionAndTotals()
                        withAnimation { scrollProxy.scrollTo("top", anchor: .top) }
                    }
                }
                .onChange(of: planService.trainingPlan?.id) { _, _ in
                    // Plan swapped (e.g., regeneration) — invalidate completion cache and refetch.
                    Task { await loadCompletionAndTotals() }
                }
            }
            // No .toolbar — no edit mode on Home (deliberate; spec §10b).
        }
    }

    // MARK: - Today Hero State Router

    /// Routes the central "today" slot to the right card variant based on:
    /// - empty day → rest
    /// - race-day flag → race card
    /// - exactly 1 session → single planned/completed/missed card
    /// - 2+ sessions → multi-session stack with header + sorted cards
    @ViewBuilder
    private var todayHero: some View {
        let todayWeekday = todayWeekday()
        let todaysSessions = (currentWeek?.sessionsByDay[todayWeekday] ?? [])
            .sorted { $0.orderInDay < $1.orderInDay }

        if todaysSessions.isEmpty {
            // RestDayCardView already renders its own "TODAY · Rest day" header.
            // Notes intentionally nil — current schema has no per-day rest-day notes.
            RestDayCardView(notes: nil)
        } else if let race = todaysSessions.first(where: { $0.sport.lowercased() == "race" }) {
            // Race day card. Coexists with the strip + week-strip — does NOT take over
            // the canvas. raceObjective falls back to the session.type when no plan-level
            // objective is captured (matches CalendarView behavior).
            RaceDayCardView(
                raceObjective: race.type,
                template: workoutLibrary.template(for: race.templateId),
                notes: race.notes
            )
        } else if todaysSessions.count == 1 {
            cardForSession(todaysSessions[0], sequenceContext: nil)
        } else {
            multiSessionStack(sessions: todaysSessions)
        }
    }

    /// Multi-session day: caption header + sorted card list (planned-on-top, completed-below).
    @ViewBuilder
    private func multiSessionStack(sessions: [PlanSession]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TODAY · \(sessions.count) SESSIONS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(1)
                Spacer()
                Text("\(formatTotalDuration(sessions)) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Sort: planned/missed cards above completed cards. Within each bucket,
            // ascending order_in_day. Reads top-to-bottom as "what to do next, then
            // what you've already done".
            let sorted = sessions.sorted { a, b in
                let aCompleted = isCompleted(a)
                let bCompleted = isCompleted(b)
                if aCompleted != bCompleted { return !aCompleted }
                return a.orderInDay < b.orderInDay
            }
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, session in
                cardForSession(
                    session,
                    sequenceContext: (index: index + 1, total: sorted.count)
                )
            }
        }
    }

    /// Builds the right card variant for a session based on its completion status.
    /// Uses `AnyView` because the switch returns three different concrete view types —
    /// acceptable here since the call site has at most a few children per render.
    private func cardForSession(
        _ session: PlanSession,
        sequenceContext: (index: Int, total: Int)?
    ) -> some View {
        let template = workoutLibrary.template(for: session.templateId)
        let ftp = profileService.user?.ftp
        let vma = profileService.user?.vma
        let css = profileService.user?.cssSecondsPer100m
        let maxHr = profileService.user?.maxHr

        switch completionStatuses[session.id] ?? .planned {
        case .planned:
            return AnyView(
                TodayPlannedCard(
                    session: session,
                    template: template,
                    ftp: ftp, vma: vma, css: css, maxHr: maxHr,
                    sequenceContext: sequenceContext
                )
            )
        case .completed(let activity):
            return AnyView(
                TodayCompletedCard(
                    session: session,
                    activity: activity,
                    template: template,
                    ftp: ftp, vma: vma, css: css, maxHr: maxHr,
                    sequenceContext: sequenceContext
                )
            )
        case .missed:
            return AnyView(
                TodayMissedCard(session: session, sequenceContext: sequenceContext)
            )
        }
    }

    /// True iff the session's current completion status is `.completed`. Used by the
    /// multi-session sort to push completed cards below planned/missed ones.
    private func isCompleted(_ session: PlanSession) -> Bool {
        if case .completed = completionStatuses[session.id] ?? .planned { return true }
        return false
    }

    // MARK: - Data Loading

    /// Fetches this week's Strava activities, runs `SessionMatcher` to classify every
    /// session in the visible week, and recomputes per-sport totals. Safe to call
    /// repeatedly — it's a pure read + state mutation.
    ///
    /// Failure modes:
    /// - No current week → no-op (state unchanged).
    /// - Empty/failed Strava fetch → all sessions resolve to `.planned` or `.missed`
    ///   per `SessionMatcher`'s past/future cutoff.
    private func loadCompletionAndTotals() async {
        guard let week = currentWeek else { return }
        guard let weekStart = week.startDateAsDate else { return }
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart

        let fetched = await stravaService.fetchActivities(from: weekStart, to: weekEnd)
        activities = fetched

        // Build [(session, date)] tuples for the matcher — it needs each session's
        // calendar date, not just its weekday string, to group activities correctly.
        let allSessions = week.sessionsByDay.values.flatMap { $0 }
        let sessionsWithDates: [(session: PlanSession, date: Date)] = allSessions.compactMap { session in
            guard let weekday = Weekday(fullName: session.day) else { return nil }
            return (session, weekday.date(relativeTo: weekStart))
        }

        completionStatuses = SessionMatcher.match(sessions: sessionsWithDates, activities: fetched)
        sportTotals = planService.weeklySportTotals(for: week, with: fetched)
    }

    // MARK: - WeekDayStrip Data Prep

    /// 7 day-pills for the current week, in Mon→Sun order. Always returns exactly 7
    /// (WeekDayStrip asserts on count).
    private var weekPills: [DayPill] {
        let week = currentWeek
        let weekday = todayWeekday()
        let sessionsByDay = week?.sessionsByDay ?? [:]

        return Weekday.allCases.map { day in
            let sessions = (sessionsByDay[day] ?? []).sorted { $0.orderInDay < $1.orderInDay }
            return DayPill(
                weekday: day,
                glyph: glyph(for: day, sessions: sessions),
                durationLabel: durationLabel(for: sessions),
                state: pillState(for: day, today: weekday, sessions: sessions)
            )
        }
    }

    /// SF Symbol glyph for a day-pill. Rules per DRO-236 spec:
    /// - 0 sessions → bed icon ("Rest").
    /// - 1 race session → flag.
    /// - 1 brick session → link icon.
    /// - 1 session → sport icon.
    /// - 2+ sessions → "X+Y" abbreviation glyph picker (we just render the first
    ///   session's icon since SF Symbols can't render arbitrary combo glyphs).
    ///   The duration label below carries the multi-session signal.
    private func glyph(for day: Weekday, sessions: [PlanSession]) -> String {
        guard let first = sessions.first else { return "bed.double.fill" }
        if sessions.count == 1 {
            if first.sport.lowercased() == "race" { return "flag.checkered" }
            if first.isBrick { return "link" }
            return first.sportIcon
        }
        // Multi-session day — first session's icon is the visual anchor.
        return first.sportIcon
    }

    /// Total minutes for the day, formatted compactly. nil for rest days (no sessions)
    /// so the pill shows just the day label + glyph.
    private func durationLabel(for sessions: [PlanSession]) -> String? {
        guard !sessions.isEmpty else { return nil }
        let total = sessions.reduce(0) { $0 + $1.durationMinutes }
        return formatPillDuration(minutes: total)
    }

    /// Pill state derived from past/today/future + completion status.
    /// - today (regardless of count) → .today
    /// - past + all sessions completed → .completed
    /// - past + any session missed → .missed
    /// - past + no sessions → .rest
    /// - future + no sessions → .rest
    /// - future + sessions → .planned
    private func pillState(for day: Weekday, today: Weekday, sessions: [PlanSession]) -> PillState {
        if day == today { return .today }

        let dayIsPast = isPast(day: day, today: today)

        if sessions.isEmpty { return .rest }

        if dayIsPast {
            // Inspect each session's matched completion. Missing entries mean the
            // matcher hasn't run yet (first paint) — treat as planned to avoid a
            // false-red flash before the .task resolves.
            let statuses = sessions.map { completionStatuses[$0.id] ?? .planned }
            if statuses.contains(where: { if case .missed = $0 { return true } else { return false } }) {
                return .missed
            }
            if statuses.allSatisfy({ if case .completed = $0 { return true } else { return false } }) {
                return .completed
            }
            // Mixed past day with some unmatched sessions — treat as missed to surface
            // attention. (e.g., two-session day where one was logged and one was not.)
            return .missed
        }

        return .planned
    }

    /// True iff `day` falls before `today` within the current week (Mon-indexed).
    private func isPast(day: Weekday, today: Weekday) -> Bool {
        guard let dayIndex = Weekday.allCases.firstIndex(of: day),
              let todayIndex = Weekday.allCases.firstIndex(of: today) else {
            return false
        }
        return dayIndex < todayIndex
    }

    // MARK: - Adapters

    /// Adapts the (done, total) tuple from PlanService into the SportProgressStrip
    /// value type. Done in the view layer because the strip's value type is a UI
    /// concern; the service stays pure.
    private func sportTotalsForStrip() -> [String: SportProgressStrip.SportTotals] {
        sportTotals.mapValues {
            SportProgressStrip.SportTotals(doneMinutes: $0.done, totalMinutes: $0.total)
        }
    }

    // MARK: - Formatting Helpers

    /// "1h 30 min" / "45 min" — used in the multi-session header caption.
    private func formatTotalDuration(_ sessions: [PlanSession]) -> String {
        let total = sessions.reduce(0) { $0 + $1.durationMinutes }
        let hours = total / 60
        let minutes = total % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes) min" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes) min"
    }

    /// Compact pill duration: "2h", "1h30", "45'" — fits the narrow pill column.
    private func formatPillDuration(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h\(m)" }
        if h > 0 { return "\(h)h" }
        return "\(m)'"
    }

    /// Today's weekday derived from `Calendar.current`. `Weekday.from(date:)` does not
    /// exist in the model — we compute it here so HomeView is self-contained.
    private func todayWeekday() -> Weekday {
        let comp = calendar.component(.weekday, from: Date())
        // Calendar weekday: Sun=1 ... Sat=7. Map to our Mon-first enum.
        switch comp {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .monday
        }
    }
}

// MARK: - Previews

#Preview("HomeView — empty state") {
    // Empty preview — the real view requires live services; this just confirms the
    // empty hero renders without a plan.
    HomeView(
        authService: AuthService(),
        planService: PlanService(),
        profileService: ProfileService(),
        stravaService: StravaService(),
        homeReset: .constant(false)
    )
}
