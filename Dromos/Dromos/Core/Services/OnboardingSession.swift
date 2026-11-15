//
//  OnboardingSession.swift
//  Dromos
//
//  Runs the scripted onboarding chat: save each answer, ask the coach to
//  react or parse free text, and fall back to a written line if that call fails.
//

import Combine
import Foundation
import Supabase

struct OnboardingLine: Identifiable, Equatable {
    let id: UUID
    var text: String
    var role: Role

    enum Role: Equatable {
        case coach
        case athlete
        case summary(OnboardingStep)
    }

    static func coach(_ text: String) -> OnboardingLine {
        OnboardingLine(id: UUID(), text: text, role: .coach)
    }

    static func athlete(_ text: String) -> OnboardingLine {
        OnboardingLine(id: UUID(), text: text, role: .athlete)
    }

    static func summary(_ step: OnboardingStep, _ text: String) -> OnboardingLine {
        OnboardingLine(id: UUID(), text: text, role: .summary(step))
    }
}

@MainActor
final class OnboardingSession: ObservableObject {

    @Published private(set) var lines: [OnboardingLine] = []
    @Published private(set) var state = OnboardingState.fresh()
    @Published private(set) var isThinking = false
    @Published private(set) var isSaving = false
    @Published private(set) var isLoading = true
    @Published private(set) var loadFailed = false
    @Published var errorMessage: String?
    @Published var draft = ""
    @Published var dayDraft: [String] = []
    @Published var durationDraft: [String: Int] = [:]

    private var didLoad = false
    private var userId: UUID?
    private var profile: ProfileService?
    private var auth: AuthService?
    private var onFinish: (() -> Void)?
    private var parkedDays: [String] = []
    private var parkedStep: OnboardingStep?
    private var parkedMode: OnboardingMode?
    private let client = SupabaseClientProvider.client

    var isBusy: Bool { isThinking || isSaving }

    var replies: [QuickReply] {
        OnboardingCopy.replies(for: state)
    }

    func bind(auth: AuthService, profile: ProfileService, onFinish: @escaping () -> Void) {
        self.auth = auth
        self.profile = profile
        self.onFinish = onFinish
    }

    func load() async {
        guard !didLoad, let userId = auth?.currentUserId, let profile else { return }
        didLoad = true
        self.userId = userId
        isLoading = true
        loadFailed = false
        do {
            let user = try await profile.fetchProfile(userId: userId)
            let answers = OnboardingState.answers(from: user)
            state = OnboardingState.resume(from: answers, now: Date())
            lines = openingLines(for: state)
            syncDrafts()
        } catch {
            didLoad = false
            loadFailed = true
        }
        isLoading = false
    }

    func tap(_ id: QuickReplyID) async {
        guard !isBusy else { return }
        switch id {
        case .weekdays:
            dayDraft = Weekday.weekdays
        case .weekends:
            dayDraft = Weekday.weekend
        case .anyDay:
            dayDraft = Weekday.ordered
        case .keepDurations:
            await perform(.confirmDurations(durationDraft))
        default:
            await perform(.reply(id))
        }
    }

    func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        draft = ""
        let result = OnboardingReducer.apply(.typed(text), to: state, now: Date())
        if result.consultCoach {
            if let echo = result.athleteEcho {
                lines.append(.athlete(echo))
            }
            await consult(text)
            return
        }
        await commit(result)
    }

    func confirmDate(_ date: Date) async {
        await perform(.confirmDate(date))
    }

    func confirmMinutes(_ minutes: Int) async {
        await perform(.confirmMinutes(minutes))
    }

    func confirmHours(_ hours: Double) async {
        await perform(.confirmHours(hours))
    }

    func confirmVma(_ value: Double) async {
        await perform(.confirmVma(value))
    }

    func confirmRunTime(_ distance: RunDistance, seconds: Int) async {
        await perform(.confirmRunTime(distance, seconds))
    }

    func confirmCss(_ seconds: Int) async {
        await perform(.confirmCss(seconds))
    }

    func confirmSwimTime(_ distance: SwimDistance, seconds: Int) async {
        await perform(.confirmSwimTime(distance, seconds))
    }

    func confirmFtp(_ watts: Int) async {
        await perform(.confirmFtp(watts))
    }

    func confirmTwenty(_ watts: Int) async {
        await perform(.confirmTwenty(watts))
    }

    func confirmMaxHr(_ bpm: Int) async {
        await perform(.confirmMaxHr(bpm))
    }

    func confirmBirthYear(_ year: Int) async {
        await perform(.confirmBirthYear(year))
    }

    func confirmDays() async {
        guard let sport = OnboardingSport.from(step: state.activeStep) else { return }
        await perform(.confirmDays(sport, dayDraft))
    }

    func toggleDay(_ day: String) {
        if let index = dayDraft.firstIndex(of: day) {
            dayDraft.remove(at: index)
        } else {
            dayDraft.append(day)
            dayDraft = Weekday.sorted(dayDraft)
        }
    }

    func setDuration(_ minutes: Int, for day: String) {
        durationDraft[day] = minutes
    }

    func edit(_ step: OnboardingStep) {
        guard !isBusy else { return }
        if state.editing == nil, state.step != .recap {
            parkedDays = dayDraft
            parkedStep = state.step
            parkedMode = state.mode
        }
        let result = OnboardingReducer.apply(.edit(step), to: state, now: Date())
        state = result.state
        syncDrafts()
        for line in result.coachLines where !line.isEmpty {
            lines.append(.coach(line))
        }
    }

    // MARK: - Private

    private func perform(_ event: OnboardingEvent) async {
        guard !isBusy else { return }
        let result = OnboardingReducer.apply(event, to: state, now: Date())
        await commit(result)
    }

    private func commit(_ result: OnboardingStepResult) async {
        if let patch = result.patch, !patch.isEmpty {
            guard let userId, let profile else { return }
            isSaving = true
            do {
                try await profile.saveOnboardingPatch(patch, userId: userId)
            } catch {
                isSaving = false
                errorMessage = "I couldn't save that. Check your connection and try again."
                return
            }
            isSaving = false
        }
        errorMessage = nil
        if let echo = result.athleteEcho, !echo.isEmpty {
            if let summary = result.summary {
                upsertSummary(summary, text: echo, replace: result.replacesSummary)
            } else {
                lines.append(.athlete(echo))
            }
        }
        let echo = result.athleteEcho
        let stepBefore = state.step
        state = result.state
        if stepBefore == state.step, let parkedMode {
            state.mode = parkedMode
            self.parkedMode = nil
        }
        restoreOrSyncDrafts()
        if let follow = result.followUp, !follow.isEmpty {
            lines.append(.coach(follow))
            return
        }
        if result.wantsReaction, let echo, !echo.isEmpty {
            isThinking = true
            let reaction = await react(to: echo) ?? result.fallbackReaction
            isThinking = false
            if let reaction, !reaction.isEmpty {
                lines.append(.coach(reaction))
            }
        }
        for line in result.coachLines where !line.isEmpty {
            lines.append(.coach(line))
        }
        if result.finish {
            await finishOnboarding()
        }
    }

    private func consult(_ text: String) async {
        isThinking = true
        let outcome = await parse(text)
        isThinking = false
        switch outcome {
        case .facts(let facts):
            var resolved = OnboardingReducer.apply(.resolved(facts), to: state, now: Date())
            resolved.athleteEcho = nil
            await commit(resolved)
        case .followUp(let message):
            lines.append(.coach(message))
        case .unavailable:
            let offered = OnboardingReducer.apply(.offerSaveNote(text), to: state, now: Date())
            if offered.state.mode == .confirmLimitersNote {
                state = offered.state
                if let follow = offered.followUp {
                    lines.append(.coach(follow))
                }
            } else {
                lines.append(.coach(OnboardingCopy.coachUnavailableFollowUp()))
            }
        }
    }

    private func finishOnboarding() async {
        guard let userId, let profile, let auth else { return }
        isSaving = true
        do {
            try await profile.markOnboardingComplete(userId: userId)
            onFinish?()
            do {
                try await auth.checkOnboardingStatus()
            } catch {
                auth.markOnboardingCompleteLocally()
            }
        } catch {
            errorMessage = "I couldn't start your plan. Tap Get my plan to try again."
        }
        isSaving = false
    }

    private func openingLines(for state: OnboardingState) -> [OnboardingLine] {
        let texts = OnboardingCopy.openingLines(for: state, now: Date())
        var rows: [OnboardingLine] = []
        if let first = texts.first {
            rows.append(.coach(first))
        }
        for (step, text) in OnboardingCopy.completedSummaries(in: state.answers, before: state.step) {
            rows.append(.summary(step, text))
        }
        for text in texts.dropFirst() where !text.isEmpty {
            rows.append(.coach(text))
        }
        return rows
    }

    private func upsertSummary(_ step: OnboardingStep, text: String, replace: Bool) {
        if replace, let index = lines.lastIndex(where: { $0.role == .summary(step) }) {
            lines[index].text = text
            return
        }
        lines.append(.summary(step, text))
    }

    private func syncDrafts() {
        let step = state.activeStep
        if let sport = OnboardingSport.from(step: step) {
            dayDraft = state.answers.days(for: sport)
        }
        if step == .dailyDuration {
            let proposed = MetricEstimates.defaultDurations(
                days: state.answers.trainingDays,
                weeklyHours: state.answers.currentWeeklyHours ?? 3
            )
            var draft: [String: Int] = [:]
            for day in state.answers.trainingDays {
                draft[day] = state.answers.duration(for: day) ?? proposed[day] ?? 60
            }
            durationDraft = draft
        }
    }

    private func restoreOrSyncDrafts() {
        if state.editing == nil, let parkedStep, state.step == parkedStep {
            dayDraft = parkedDays
            self.parkedStep = nil
            return
        }
        syncDrafts()
    }

    private func react(to message: String) async -> String? {
        do {
            let response = try await callCoach(purpose: "react", message: message)
            let reply = response.reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reply.isEmpty, reply.count <= 400 else { return nil }
            return reply
        } catch {
            return nil
        }
    }

    private func parse(_ message: String) async -> CoachParseOutcome {
        do {
            let response = try await callCoach(purpose: "parse", message: message)
            if response.followUp {
                let reply = response.reply.trimmingCharacters(in: .whitespacesAndNewlines)
                return .followUp(reply.isEmpty ? OnboardingCopy.gentleRedirect() : reply)
            }
            guard let parsed = response.parsed else {
                let reply = response.reply.trimmingCharacters(in: .whitespacesAndNewlines)
                return .followUp(reply.isEmpty ? OnboardingCopy.gentleRedirect() : reply)
            }
            return .facts(parsed.facts())
        } catch {
            return .unavailable
        }
    }

    private func callCoach(purpose: String, message: String) async throws -> CoachWireResponse {
        let request = CoachWireRequest(
            step: wireStep(state.activeStep),
            mode: wireMode(state.mode),
            purpose: purpose,
            message: String(message.prefix(1000)),
            answers: CoachWireAnswers(answers: state.answers)
        )
        // Stay on the main actor. A detached task group would have to send the
        // Supabase client across isolation, which this target rejects.
        let invoke = Task { () -> CoachWireResponse in
            try await client.functions.invoke(
                "onboarding-coach",
                options: FunctionInvokeOptions(body: request)
            )
        }
        let timeout = Task {
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            invoke.cancel()
        }
        do {
            let response = try await invoke.value
            timeout.cancel()
            return response
        } catch is CancellationError {
            timeout.cancel()
            throw CoachCallError.timedOut
        } catch {
            timeout.cancel()
            throw error
        }
    }

    private func wireStep(_ step: OnboardingStep) -> String {
        switch step {
        case .raceType: return "race_type"
        case .raceDate: return "race_date"
        case .targetTime: return "target_time"
        case .experience: return "experience"
        case .weeklyHours: return "weekly_hours"
        case .run: return "run"
        case .swim: return "swim"
        case .bike: return "bike"
        case .maxHeartRate: return "max_hr"
        case .swimDays: return "swim_days"
        case .bikeDays: return "bike_days"
        case .runDays: return "run_days"
        case .dailyDuration: return "daily_duration"
        case .limiters: return "limiters"
        case .recap: return "recap"
        }
    }

    private func wireMode(_ mode: OnboardingMode) -> String {
        switch mode {
        case .ask: return "ask"
        case .pickTime: return "pick_time"
        case .enterVma: return "enter_vma"
        case .pickRunDistance: return "pick_run_distance"
        case .enterRunTime: return "enter_run_time"
        case .enterCss: return "enter_css"
        case .pickSwimDistance: return "pick_swim_distance"
        case .enterSwimTime: return "enter_swim_time"
        case .enterTypicalPace: return "enter_typical_pace"
        case .enterFtp: return "enter_ftp"
        case .enterTwenty: return "enter_twenty"
        case .enterMaxHr: return "enter_max_hr"
        case .enterBirthYear: return "enter_birth_year"
        case .confirmSuggestion: return "confirm_suggestion"
        case .confirmLimitersNote: return "confirm_note"
        }
    }
}

private enum CoachParseOutcome {
    case facts(CoachFacts)
    case followUp(String)
    case unavailable
}

private enum CoachCallError: Error {
    case timedOut
}

private struct CoachWireRequest: Encodable, Sendable {
    let step: String
    let mode: String
    let purpose: String
    let message: String
    let answers: CoachWireAnswers
}

private struct CoachWireAnswers: Encodable, Sendable {
    var raceObjective: String?
    var raceDate: String?
    var timeObjectiveMinutes: Int?
    var experienceYears: Int?
    var currentWeeklyHours: Double?
    var vma: Double?
    var cssSecondsPer100m: Int?
    var ftp: Int?
    var maxHr: Int?
    var birthYear: Int?
    var swimDays: [String]
    var bikeDays: [String]
    var runDays: [String]
    var limiters: String?

    init(answers: OnboardingAnswers) {
        raceObjective = answers.raceObjective?.rawValue
        raceDate = answers.raceDate.map(PlanHorizon.isoString)
        timeObjectiveMinutes = answers.timeObjectiveMinutes
        experienceYears = answers.experienceYears
        currentWeeklyHours = answers.currentWeeklyHours
        vma = answers.vma
        cssSecondsPer100m = answers.cssSecondsPer100m
        ftp = answers.ftp
        maxHr = answers.maxHr
        birthYear = answers.birthYear
        swimDays = answers.swimDays
        bikeDays = answers.bikeDays
        runDays = answers.runDays
        limiters = answers.limiters
    }

    enum CodingKeys: String, CodingKey {
        case raceObjective = "race_objective"
        case raceDate = "race_date"
        case timeObjectiveMinutes = "time_objective_minutes"
        case experienceYears = "experience_years"
        case currentWeeklyHours = "current_weekly_hours"
        case vma
        case cssSecondsPer100m = "css_seconds_per100m"
        case ftp
        case maxHr = "max_hr"
        case birthYear = "birth_year"
        case swimDays = "swim_days"
        case bikeDays = "bike_days"
        case runDays = "run_days"
        case limiters
    }
}

private struct CoachWireResponse: Decodable, Sendable {
    let reply: String
    let followUp: Bool
    let parsed: CoachWireParsed?

    enum CodingKeys: String, CodingKey {
        case reply
        case followUp = "follow_up"
        case parsed
    }
}

private struct CoachWireParsed: Decodable, Sendable {
    var raceObjective: String?
    var raceDate: String?
    var justFinish: Bool?
    var timeObjectiveMinutes: Int?
    var experienceYears: Int?
    var currentWeeklyHours: Double?
    var vma: Double?
    var runDistance: String?
    var runTimeSeconds: Int?
    var cssSecondsPer100m: Int?
    var swimDistance: String?
    var swimTimeSeconds: Int?
    var typicalPaceSeconds: Int?
    var ftp: Int?
    var twentyMinWatts: Int?
    var noPowerMeter: Bool?
    var maxHr: Int?
    var birthYear: Int?
    var limiters: String?
    var unknownMetric: Bool?
    var swimDays: [String]?
    var bikeDays: [String]?
    var runDays: [String]?

    enum CodingKeys: String, CodingKey {
        case raceObjective = "race_objective"
        case raceDate = "race_date"
        case justFinish = "just_finish"
        case timeObjectiveMinutes = "time_objective_minutes"
        case experienceYears = "experience_years"
        case currentWeeklyHours = "current_weekly_hours"
        case vma
        case runDistance = "run_distance"
        case runTimeSeconds = "run_time_seconds"
        case cssSecondsPer100m = "css_seconds_per100m"
        case swimDistance = "swim_distance"
        case swimTimeSeconds = "swim_time_seconds"
        case typicalPaceSeconds = "typical_pace_seconds"
        case ftp
        case twentyMinWatts = "twenty_min_watts"
        case noPowerMeter = "no_power_meter"
        case maxHr = "max_hr"
        case birthYear = "birth_year"
        case limiters
        case unknownMetric = "unknown_metric"
        case swimDays = "swim_days"
        case bikeDays = "bike_days"
        case runDays = "run_days"
    }

    func facts() -> CoachFacts {
        var facts = CoachFacts()
        if raceObjective == "Olympic" { facts.raceObjective = .olympic }
        if raceObjective == "Ironman 70.3" { facts.raceObjective = .ironman703 }
        if raceObjective == "Sprint" || raceObjective == "Ironman" { facts.unsupportedRace = true }
        if let raceDate {
            facts.raceDate = CoachWireParsed.utcDate(raceDate)
        }
        facts.justFinish = justFinish ?? false
        facts.timeMinutes = timeObjectiveMinutes
        facts.experienceYears = experienceYears
        facts.weeklyHours = currentWeeklyHours
        facts.vma = vma
        facts.runDistance = runDistance == "10k" ? .tenK : (runDistance == "5k" ? .fiveK : nil)
        facts.runSeconds = runTimeSeconds
        facts.cssSeconds = cssSecondsPer100m
        facts.swimDistance = swimDistance == "1500" ? .fifteenHundred : (swimDistance == "400" ? .fourHundred : nil)
        facts.swimSeconds = swimTimeSeconds
        facts.typicalPaceSeconds = typicalPaceSeconds
        facts.ftp = ftp
        facts.twentyMinWatts = twentyMinWatts
        facts.noPowerMeter = noPowerMeter ?? false
        facts.maxHr = maxHr
        facts.birthYear = birthYear
        facts.limiters = limiters
        facts.unknownMetric = unknownMetric ?? false
        facts.swimDays = swimDays
        facts.bikeDays = bikeDays
        facts.runDays = runDays
        return facts
    }

    private static func utcDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withFullDate]
        if let date = formatter.date(from: String(string.prefix(10))) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
