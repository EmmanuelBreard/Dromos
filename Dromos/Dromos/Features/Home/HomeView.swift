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
/// 2. `WeekDayStrip` — 7-pill weekly overview (drives `selectedDay`).
/// 3. External day label — `Today` / `Tomorrow` / `Yesterday` / `April 29th`.
///    Section header above the hero card; replaces the in-card date captions.
/// 4. `todayHero` — state-routed card(s) for the previewed day's session(s):
///    - Empty plan → `EmptyHomeHero`
///    - No sessions → `RestDayCardView`
///    - Race day → `RaceDayCardView`
///    - 1 session → `TodayPlannedCard` / `TodayCompletedCard` / `TodayMissedCard`
///    - 2+ sessions → header + ordered stack (planned-on-top, then completed)
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

    /// Drives the sheet presentation of `PlanGenerationView` from `EmptyHomeHero`'s CTA.
    /// PlanGenerationView owns its own services and dismisses itself on success — when
    /// generation completes, `planService.trainingPlan` flips to non-nil and the empty
    /// branch naturally retreats.
    @State private var showPlanGeneration = false

    /// Day currently previewed in the today-hero slot via the WeekDayStrip pills.
    /// `nil` is the default and means "today is selected" — the hero behaves as before.
    /// Set non-nil when the user taps a non-today pill; the hero swaps to that day's
    /// session(s) using the existing card components driven off `effectiveSelectedDay`.
    /// Preserved across pull-to-refresh and Strava-sync events; reset to nil only by
    /// tab re-tap (`homeReset`) or by tapping today / re-tapping the selected pill.
    @State private var selectedDay: Weekday? = nil

    private let workoutLibrary = WorkoutLibraryService.shared
    private let calendar = Calendar.current

    /// Cached formatter for the external day label's full-date variant ("April 29").
    /// The ordinal suffix ("th") is appended separately by `dayLabel(for:)`; this
    /// formatter only emits `MMMM d` so the ordinal logic stays in Swift rather than
    /// being baked into a locale-specific `DateFormatter` setting.
    /// Hoisted to a static `let` so it's allocated once per process — `DateFormatter`
    /// init is expensive and was previously rebuilt on every body render. Locale is
    /// pinned to `en_US_POSIX` so the format stays stable in English regardless of
    /// the device locale (matches the rest of the app's English copy).
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM d"
        return f
    }()

    /// Current week, derived from `currentWeekIndex()` since `TrainingPlan` doesn't
    /// expose a direct `currentWeek()` accessor. Returns nil when no plan is loaded
    /// or the index is out of bounds (defensive — should not happen in practice).
    // TODO(DRO-241): cache this — body eval calls it multiple times per render and each
    // call is O(N) over plan weeks. Pass as a parameter or memoize on plan.id change.
    private var currentWeek: PlanWeek? {
        guard let plan = planService.trainingPlan else { return nil }
        let idx = plan.currentWeekIndex()
        guard plan.planWeeks.indices.contains(idx) else { return nil }
        return plan.planWeeks[idx]
    }

    /// The weekday whose session(s) the today-hero should render. Falls back to
    /// the live "today" when no pill is explicitly selected — keeps the default
    /// behavior identical to pre-DRO-231-week-strip-tap.
    private var effectiveSelectedDay: Weekday {
        selectedDay ?? todayWeekday()
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 24) {
                        if let _ = planService.trainingPlan {
                            SportProgressStrip(totals: sportTotalsForStrip())
                            WeekDayStrip(
                                days: weekPills(selected: selectedDay),
                                onPillTap: handlePillTap
                            )
                            // External day-anchor section header. Sits between the
                            // week strip and the hero so the user always has a clear
                            // textual cue about which day they're previewing.
                            Text(dayLabel(for: effectiveSelectedDay))
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityAddTraits(.isHeader)
                            todayHero
                        } else if planService.isLoadingPlan {
                            // Cold-launch guard: while the plan fetch is in flight, show a
                            // centered spinner instead of flashing EmptyHomeHero. Without this
                            // the empty hero appears for ~1 frame then swaps to the today screen.
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 200)
                        } else {
                            // Empty state takes the whole canvas — strip + week-strip are hidden
                            // because the user has no plan to derive them from.
                            EmptyHomeHero(onGeneratePlan: { showPlanGeneration = true })
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
                .sheet(isPresented: $showPlanGeneration) {
                    // PlanGenerationView owns its own PlanService/ProfileService/StravaService
                    // (@StateObject inside). On successful generation, `authService.hasPlan` flips
                    // and `planService.trainingPlan` becomes non-nil — at which point the empty
                    // branch retreats. The view dismisses itself on success.
                    PlanGenerationView(authService: authService)
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
                    // Tab re-tap: clear any previewed day (back to "today"), sync Strava,
                    // refetch, then scroll to top. Sync is awaited before the refetch so
                    // the new activities land in the same render pass. selectedDay reset
                    // happens synchronously so the visual snaps back before the network
                    // round-trip completes — feels like a true "back to today" gesture.
                    selectedDay = nil
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

    /// Routes the central hero slot to the right card variant based on the
    /// `effectiveSelectedDay` (today by default; any other weekday when the user
    /// has tapped a pill in the WeekDayStrip):
    /// - empty day → rest
    /// - race-day flag → race card
    /// - exactly 1 session → single planned/completed/missed card
    /// - 2+ sessions → multi-session stack with header + sorted cards
    @ViewBuilder
    private var todayHero: some View {
        let day = effectiveSelectedDay
        let daysSessions = (currentWeek?.sessionsByDay[day] ?? [])
            .sorted { $0.orderInDay < $1.orderInDay }

        if daysSessions.isEmpty {
            // Rest day. The day anchor is rendered by the external day label above
            // the card, so the rest-day card itself no longer carries a header row.
            RestDayCardView(notes: nil)
        } else if let race = daysSessions.first(where: { $0.sport.lowercased() == "race" }) {
            // Race day card. Coexists with the strip + week-strip — does NOT take over
            // the canvas. raceObjective falls back to the session.type when no plan-level
            // objective is captured (matches CalendarView behavior).
            //
            // Race-day takeover: when the day contains a race session, render the race
            // card alone. Any co-occurring sessions (e.g., shake-out runs) are
            // intentionally hidden. Revisit if athletes report missing race-day shake-outs.
            RaceDayCardView(
                raceObjective: race.type,
                template: workoutLibrary.template(for: race.templateId),
                notes: race.notes
            )
        } else if daysSessions.count == 1 {
            cardForSession(daysSessions[0], sequenceContext: nil)
        } else {
            multiSessionStack(sessions: daysSessions)
        }
    }

    /// Multi-session day: caption header + sorted card list (planned-on-top, completed-below).
    @ViewBuilder
    private func multiSessionStack(sessions: [PlanSession]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Day prefix dropped — the external day label above the hero already
                // carries the temporal anchor (Today / Yesterday / April 29th).
                Text("\(sessions.count) SESSIONS")
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
            // Badge index reflects PRESENTATION order (planned-on-top), not session.orderInDay.
            // See DRO-237 spec: planned/missed cards above completed cards within the day.
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, session in
                cardForSession(
                    session,
                    sequenceContext: (index: index + 1, total: sorted.count)
                )
            }
        }
    }

    /// Builds the right card variant for a session based on its completion status.
    /// `@ViewBuilder` lets SwiftUI see all three concrete view types in the result builder
    /// (wrapped in an internal `_ConditionalContent`), preserving view diffing across
    /// status transitions without the type-erasure cost of `AnyView`.
    ///
    /// The day anchor (Today / Yesterday / April 29th) is rendered by the external day
    /// label above the hero, so cards no longer carry a date caption inside their header.
    @ViewBuilder
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
            TodayPlannedCard(
                session: session,
                template: template,
                ftp: ftp, vma: vma, css: css, maxHr: maxHr,
                sequenceContext: sequenceContext
            )
        case .completed(let activity):
            TodayCompletedCard(
                session: session,
                activity: activity,
                template: template,
                ftp: ftp, vma: vma, css: css, maxHr: maxHr,
                sequenceContext: sequenceContext
            )
        case .missed:
            TodayMissedCard(
                session: session,
                sequenceContext: sequenceContext
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
    // TODO(DRO-241): de-dup the cold-launch double-fetch. HomeView.task fires this once,
    // then MainTabView's loadData() triggers Strava sync → onChange(isSyncing) fires this
    // again. Acceptable trade-off today (second pass returns post-sync data) but worth a
    // dedupe gate (e.g., in-flight request token).
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
    ///
    /// `selected` is the user's currently-previewed day. DRO-244: today is the
    /// default selected pill — when `selected == nil` the today-pill carries
    /// `isSelected = true` so the green accent border renders on today by
    /// default. When `selected` is non-nil, the matching pill is marked
    /// `isSelected = true` instead and the border moves there. The today pill
    /// keeps its solid background regardless; the outline overlays it.
    private func weekPills(selected: Weekday?) -> [DayPill] {
        let week = currentWeek
        let today = todayWeekday()
        let sessionsByDay = week?.sessionsByDay ?? [:]

        return Weekday.allCases.map { day in
            let sessions = (sessionsByDay[day] ?? []).sorted { $0.orderInDay < $1.orderInDay }
            // DRO-244: nil selection means "today is the previewed day" — today
            // pill gets the accent outline by default. Any non-nil selection
            // moves the outline onto that day.
            let isSelected = (selected == nil) ? (day == today) : (selected == day)
            return DayPill(
                weekday: day,
                glyphs: glyphs(for: day, sessions: sessions),
                durationLabel: durationLabel(for: sessions),
                state: pillState(for: day, today: today, sessions: sessions),
                isSelected: isSelected
            )
        }
    }

    /// SF Symbol glyphs for a day-pill icon row. Returns one element for single-
    /// session / rest / race / brick days and one element per session for any
    /// other multi-session day. WeekDayStrip renders these side-by-side in an
    /// HStack so two-session days (e.g., swim + run) show two icons inline.
    ///
    /// Rules:
    /// - 0 sessions → `["bed.double.fill"]` (rest).
    /// - any race session → `["flag.checkered"]` (race takeover; matches the
    ///   race-day card behaviour in `todayHero`).
    /// - otherwise → `sessions.map(\.sportIcon)` (one glyph per session in
    ///   `orderInDay` order).
    private func glyphs(for day: Weekday, sessions: [PlanSession]) -> [String] {
        if sessions.isEmpty { return ["bed.double.fill"] }
        if sessions.contains(where: { $0.sport.lowercased() == "race" }) {
            return ["flag.checkered"]
        }
        return sessions.map(\.sportIcon)
    }

    /// Total minutes for the day, formatted compactly. nil for rest days (no sessions)
    /// so the pill shows just the day label + glyph.
    private func durationLabel(for sessions: [PlanSession]) -> String? {
        guard !sessions.isEmpty else { return nil }
        let total = sessions.reduce(0) { $0 + $1.durationMinutes }
        return PlanSession.formatCompactDuration(minutes: total)
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

    // MARK: - Pill Tap Handling

    /// Handles a tap on a WeekDayStrip pill. The behavior matches the QA-confirmed
    /// spec for DRO-231-week-strip-tap:
    /// - Tap **today** (regardless of `selectedDay`) → clear selection, return to today.
    /// - Tap the **already-selected** non-today pill → clear selection, return to today.
    /// - Tap any **other** pill → mark it selected so the hero previews that day.
    private func handlePillTap(_ tappedWeekday: Weekday) {
        let today = todayWeekday()
        if tappedWeekday == today {
            selectedDay = nil
        } else if selectedDay == tappedWeekday {
            selectedDay = nil
        } else {
            selectedDay = tappedWeekday
        }
    }

    // MARK: - Day Label Helpers

    /// External section header above the hero card. Returns one of:
    /// - `"Today"` when the previewed day equals today.
    /// - `"Tomorrow"` / `"Yesterday"` when adjacent to today within the current week.
    /// - `"April 29th"` (full month name + ordinal day) for any other day.
    ///
    /// "Adjacent" is computed as today's index ± 1 within the Mon-first `Weekday`
    /// enum, scoped to the current week — the WeekDayStrip never previews a day
    /// outside the current week, so we don't need cross-week edges.
    /// Defensive fallback: if `currentWeek` lacks a `startDate`, we drop back to
    /// the weekday's full name (e.g. `"Wednesday"`) so the label is never empty.
    private func dayLabel(for weekday: Weekday) -> String {
        let today = todayWeekday()
        if weekday == today { return "Today" }

        if let dayIdx = Weekday.allCases.firstIndex(of: weekday),
           let todayIdx = Weekday.allCases.firstIndex(of: today) {
            if dayIdx == todayIdx + 1 { return "Tomorrow" }
            if dayIdx == todayIdx - 1 { return "Yesterday" }
        }

        guard let week = currentWeek,
              let weekStart = week.startDateAsDate else {
            return weekday.fullName
        }
        let date = weekday.date(relativeTo: weekStart)
        let monthDay = Self.monthDayFormatter.string(from: date)
        let dayOfMonth = calendar.component(.day, from: date)
        return "\(monthDay)\(Self.ordinalSuffix(for: dayOfMonth))"
    }

    /// English ordinal suffix for a day-of-month integer.
    /// 1→st, 2→nd, 3→rd, 4–20→th, 21→st, 22→nd, 23→rd, 24–30→th, 31→st.
    /// Pure function, kept private to HomeView since the day label is the only
    /// surface that needs it; promote to a util only when a second caller appears.
    private static func ordinalSuffix(for day: Int) -> String {
        let mod100 = day % 100
        if (11...13).contains(mod100) { return "th" }
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
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

    /// Today's weekday derived from `Calendar.current`. `Weekday.from(date:)` does not
    /// exist in the model — we compute it here so HomeView is self-contained.
    // TODO(DRO-241): move into `Weekday` as `static func today(calendar:)` for reuse.
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
        default:
            // Calendar.weekday is contractually 1...7 — getting here means Apple changed
            // the API or the calendar was misconfigured. Crash in debug to catch it; in
            // release fall through to Monday as a safe default rather than abort.
            assertionFailure("Unexpected Calendar weekday component: \(comp)")
            return .monday
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
