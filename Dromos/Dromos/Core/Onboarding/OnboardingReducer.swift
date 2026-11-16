//
//  OnboardingReducer.swift
//  Dromos
//
//  Pure step transitions. A tap or a parsed message either stores a checked
//  value and moves on, or asks again and stores nothing.
//

import Foundation

enum OnboardingReducer {

    static func apply(
        _ event: OnboardingEvent,
        to state: OnboardingState,
        now: Date,
        calendar: Calendar = .current
    ) -> OnboardingStepResult {
        switch event {
        case .reply(let id):
            return applyReply(id, state: state, now: now, calendar: calendar)
        case .typed(let text):
            return applyTyped(text, state: state, now: now, calendar: calendar)
        case .confirmDate(let date):
            return storeDate(date, alreadyUTC: false, echo: OnboardingCopy.displayDate(PlanHorizon.utcMidnight(localDay: date, calendar: calendar)), state: state, now: now, calendar: calendar)
        case .confirmMinutes(let minutes):
            return storeFinishTime(minutes, echo: OnboardingCopy.formatClock(minutes: minutes), state: state, now: now)
        case .confirmHours(let hours):
            return storeHours(hours, echo: OnboardingCopy.formatHours(hours), state: state, now: now)
        case .confirmVma(let value):
            return storeEnteredVma(value, echo: "VMA \(OnboardingCopy.formatVma(value))", state: state, now: now)
        case .confirmRunTime(let distance, let seconds):
            return storeRunTime(distance, seconds: seconds, echo: "\(distance.title) \(OnboardingCopy.formatRaceClock(seconds))", state: state, now: now)
        case .confirmCss(let seconds):
            return storeEnteredCss(seconds, echo: "CSS \(OnboardingCopy.formatPace(seconds))", state: state, now: now)
        case .confirmSwimTime(let distance, let seconds):
            return storeSwimTime(distance, seconds: seconds, echo: "\(distance.title) \(OnboardingCopy.formatRaceClock(seconds))", state: state, now: now)
        case .confirmFtp(let watts):
            return storeEnteredFtp(watts, echo: "FTP \(watts) W", state: state, now: now)
        case .confirmTwenty(let watts):
            return storeTwentyMinute(watts, echo: "\(watts) W for 20 min", state: state, now: now)
        case .confirmMaxHr(let bpm):
            return storeEnteredMaxHr(bpm, echo: "\(bpm) bpm", state: state, now: now)
        case .confirmBirthYear(let year):
            return storeBirthYear(year, echo: "Born \(year)", state: state, now: now, calendar: calendar)
        case .confirmDays(let sport, let days):
            return storeDays(sport, days: days, state: state, now: now)
        case .confirmDurations(let map):
            return storeDurations(map, state: state, now: now)
        case .edit(let step):
            return beginEdit(step, state: state, now: now)
        case .resolved(let facts):
            return applyFacts(facts, state: state, now: now, calendar: calendar)
        case .savePendingNote:
            return saveNote(state: state, now: now)
        case .offerSaveNote(let text):
            return offerSaveNote(text, state: state)
        }
    }

    // MARK: - Replies

    private static func applyReply(
        _ id: QuickReplyID,
        state: OnboardingState,
        now: Date,
        calendar: Calendar
    ) -> OnboardingStepResult {
        switch id {
        case .olympic:
            return storeRace(.olympic, echo: "Olympic", state: state, now: now)
        case .ironman703:
            return storeRace(.ironman703, echo: "Ironman 70.3", state: state, now: now)
        case .weeks8:
            return storeOffset(weeks: 8, months: nil, echo: "In 8 weeks", state: state, now: now, calendar: calendar)
        case .weeks16:
            return storeOffset(weeks: 16, months: nil, echo: "In 16 weeks", state: state, now: now, calendar: calendar)
        case .months6:
            return storeOffset(weeks: nil, months: 6, echo: "In 6 months", state: state, now: now, calendar: calendar)
        case .justFinish:
            return storeJustFinish(echo: "Just finish", state: state, now: now)
        case .haveTime:
            return changeMode(.pickTime, echo: "I have a time", state: state, now: now)
        case .expStarting:
            return storeExperience(0, echo: "Just starting", state: state, now: now)
        case .expOne:
            return storeExperience(1, echo: "1 year", state: state, now: now)
        case .expMid:
            return storeExperience(3, echo: "2–4 years", state: state, now: now)
        case .expVeteran:
            return storeExperience(5, echo: "5+ years", state: state, now: now)
        case .hours2:
            return storeHours(2, echo: "Under 3h", state: state, now: now)
        case .hours4:
            return storeHours(4, echo: "3–5h", state: state, now: now)
        case .hours6_5:
            return storeHours(6.5, echo: "5–8h", state: state, now: now)
        case .hours10:
            return storeHours(10, echo: "8–12h", state: state, now: now)
        case .hours14:
            return storeHours(14, echo: "12h+", state: state, now: now)
        case .knowVma:
            return changeMode(.enterVma, echo: "I know my VMA", state: state, now: now)
        case .haveRunRace:
            return changeMode(.pickRunDistance, echo: "I have a race time", state: state, now: now)
        case .noRunIdea:
            return storeEstimatedVma(echo: "No idea", state: state, now: now)
        case .run5k:
            return changeMode(.enterRunTime(.fiveK), echo: "5K", state: state, now: now)
        case .run10k:
            return changeMode(.enterRunTime(.tenK), echo: "10K", state: state, now: now)
        case .knowCss:
            return changeMode(.enterCss, echo: "I know my CSS", state: state, now: now)
        case .swim400:
            return changeMode(.enterSwimTime(.fourHundred), echo: "400m time", state: state, now: now)
        case .swim1500:
            return changeMode(.enterSwimTime(.fifteenHundred), echo: "1500m time", state: state, now: now)
        case .typicalPace:
            return changeMode(.enterTypicalPace, echo: "Typical pace", state: state, now: now)
        case .noSwimIdea:
            return storeEstimatedCss(echo: "No idea", state: state, now: now)
        case .knowFtp:
            return changeMode(.enterFtp, echo: "I know my FTP", state: state, now: now)
        case .twentyMin:
            return changeMode(.enterTwenty, echo: "20-min power", state: state, now: now)
        case .noPower, .noBikeIdea:
            return storeEstimatedFtp(echo: id == .noPower ? "I don't use a power meter" : "No idea", state: state, now: now)
        case .knowMaxHr:
            return changeMode(.enterMaxHr, echo: "I know my max HR", state: state, now: now)
        case .knowBirthYear:
            return changeMode(.enterBirthYear, echo: "Use my year of birth", state: state, now: now)
        case .noLimiters:
            return storeLimiters("none", echo: "None", state: state, now: now)
        case .saveNote:
            return saveNote(state: state, now: now)
        case .yesSuggestion:
            return acceptSuggestion(state: state, now: now)
        case .noSuggestion:
            return rejectSuggestion(state: state)
        case .getPlan:
            return finish(state: state, now: now)
        case .weekdays, .weekends, .anyDay, .keepDurations:
            return .unchanged(state)
        }
    }

    // MARK: - Stores

    private static func storeRace(
        _ objective: RaceObjective,
        echo: String,
        state: OnboardingState,
        now: Date
    ) -> OnboardingStepResult {
        guard state.activeStep == .raceType else { return .unchanged(state) }
        var next = state
        next.answers.raceObjective = objective
        var patch = OnboardingPatch()
        patch.raceObjective = objective
        return committed(echo: echo, patch: patch, completed: .raceType, original: state, next: &next, now: now, extraLines: [])
    }

    private static func storeOffset(
        weeks: Int?,
        months: Int?,
        echo: String,
        state: OnboardingState,
        now: Date,
        calendar: Calendar
    ) -> OnboardingStepResult {
        let local: Date
        if let weeks {
            local = calendar.date(byAdding: .day, value: weeks * 7, to: calendar.startOfDay(for: now)) ?? now
        } else {
            local = calendar.date(byAdding: .month, value: months ?? 0, to: calendar.startOfDay(for: now)) ?? now
        }
        return storeDate(local, alreadyUTC: false, echo: echo, state: state, now: now, calendar: calendar)
    }

    private static func storeDate(
        _ date: Date,
        alreadyUTC: Bool,
        echo: String,
        state: OnboardingState,
        now: Date,
        calendar: Calendar
    ) -> OnboardingStepResult {
        guard state.activeStep == .raceDate else { return .unchanged(state) }
        let utc = alreadyUTC ? PlanHorizon.utcDay(date) : PlanHorizon.utcMidnight(localDay: date, calendar: calendar)
        guard PlanHorizon.accepts(raceDate: utc, now: now) else {
            return followUp(OnboardingCopy.tooSoon(), echo: echo, state: state)
        }
        var next = state
        next.answers.raceDate = utc
        var patch = OnboardingPatch()
        patch.raceDate = utc
        return committed(echo: echo, patch: patch, completed: .raceDate, original: state, next: &next, now: now, extraLines: [])
    }

    private static func storeJustFinish(echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.activeStep == .targetTime else { return .unchanged(state) }
        var next = state
        next.answers.targetTimeDecided = true
        next.answers.timeObjectiveMinutes = nil
        var patch = OnboardingPatch()
        patch.clearTimeObjective = true
        return committed(echo: echo, patch: patch, completed: .targetTime, original: state, next: &next, now: now, extraLines: [])
    }

    private static func storeFinishTime(_ minutes: Int, echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.activeStep == .targetTime else { return .unchanged(state) }
        guard minutes > 0, minutes <= 20 * 60 else {
            return followUp(OnboardingCopy.checkThatNumber(), echo: echo, state: state)
        }
        var next = state
        next.answers.targetTimeDecided = true
        next.answers.timeObjectiveMinutes = minutes
        var patch = OnboardingPatch()
        patch.timeObjectiveMinutes = minutes
        return committed(echo: echo, patch: patch, completed: .targetTime, original: state, next: &next, now: now, extraLines: [])
    }

    private static func storeExperience(_ years: Int, echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.activeStep == .experience else { return .unchanged(state) }
        guard years >= 0, years <= 80 else {
            return followUp(OnboardingCopy.checkThatNumber(), echo: echo, state: state)
        }
        var next = state
        next.answers.experienceYears = years
        var patch = OnboardingPatch()
        patch.experienceYears = years
        return committed(echo: echo, patch: patch, completed: .experience, original: state, next: &next, now: now, extraLines: [])
    }

    private static func storeHours(_ hours: Double, echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.activeStep == .weeklyHours else { return .unchanged(state) }
        let rounded = MetricEstimates.roundHours(hours)
        guard MetricEstimates.acceptsHours(rounded) else {
            return followUp(OnboardingCopy.checkThatNumber(), echo: echo, state: state)
        }
        var next = state
        next.answers.currentWeeklyHours = rounded
        var patch = OnboardingPatch()
        patch.currentWeeklyHours = rounded
        return committed(echo: echo, patch: patch, completed: .weeklyHours, original: state, next: &next, now: now, extraLines: [])
    }

    private static func storeEnteredVma(_ value: Double, echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.activeStep == .run else { return .unchanged(state) }
        let rounded = (value * 10).rounded() / 10
        guard MetricEstimates.vmaRange.contains(rounded) else {
            return followUp(OnboardingCopy.checkThatNumber(), echo: echo, state: state)
        }
        return storeVma(rounded, source: MetricSourceLabel.entered, echo: echo, state: state, now: now)
    }

    private static func storeEstimatedVma(echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.activeStep == .run else { return .unchanged(state) }
        let value = MetricEstimates.estimatedVma(
            experienceYears: state.answers.experienceYears,
            weeklyHours: state.answers.currentWeeklyHours
        )
        return storeVma(value, source: MetricSourceLabel.fromExperience, echo: echo, state: state, now: now)
    }

    private static func storeVma(_ value: Double, source: String, echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        var next = state
        next.answers.vma = value
        next.answers.metrics.vma = source
        var patch = OnboardingPatch()
        patch.vma = value
        patch.metrics = next.answers.metrics
        let line = OnboardingCopy.vmaLine(value: value, source: source)
        return committed(echo: echo, patch: patch, completed: .run, original: state, next: &next, now: now, extraLines: [line])
    }

    private static func storeRunTime(_ distance: RunDistance, seconds: Int, echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.activeStep == .run else { return .unchanged(state) }
        switch MetricEstimates.checkRun(distance: distance, timeSeconds: seconds) {
        case .accept(let value):
            return storeVma(value, source: MetricSourceLabel.fromRace, echo: echo, state: state, now: now)
        case .suggest(let suggested, _):
            return offerSuggestion(.run(distance, seconds: suggested, originalSeconds: seconds), echo: echo, state: state)
        case .reject:
            return followUp(OnboardingCopy.checkThatTime(), echo: echo, state: state)
        }
    }

    private static func storeEnteredCss(_ seconds: Int, echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.activeStep == .swim else { return .unchanged(state) }
        guard MetricEstimates.acceptsEnteredCss(seconds) else {
            return followUp(OnboardingCopy.checkThatNumber(), echo: echo, state: state)
        }
        return storeCss(seconds, source: MetricSourceLabel.entered, echo: echo, state: state, now: now)
    }

    private static func storeEstimatedCss(echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.activeStep == .swim else { return .unchanged(state) }
        let value = MetricEstimates.estimatedCss(
            experienceYears: state.answers.experienceYears,
            weeklyHours: state.answers.currentWeeklyHours
        )
        return storeCss(value, source: MetricSourceLabel.fromExperience, echo: echo, state: state, now: now)
    }

    private static func storeSwimTime(_ distance: SwimDistance, seconds: Int, echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.activeStep == .swim else { return .unchanged(state) }
        switch MetricEstimates.checkSwim(distance: distance, timeSeconds: seconds) {
        case .accept(let value):
            return storeCss(Int(value), source: MetricSourceLabel.fromRace, echo: echo, state: state, now: now)
        case .suggest(let suggested, _):
            return offerSuggestion(.swim(distance, seconds: suggested, originalSeconds: seconds), echo: echo, state: state)
        case .reject:
            return followUp(OnboardingCopy.checkThatTime(), echo: echo, state: state)
        }
    }

    private static func storeCss(_ seconds: Int, source: String, echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        var next = state
        next.answers.cssSecondsPer100m = seconds
        next.answers.metrics.css = source
        var patch = OnboardingPatch()
        patch.cssSecondsPer100m = seconds
        patch.metrics = next.answers.metrics
        let line = OnboardingCopy.cssLine(seconds: seconds, source: source)
        return committed(echo: echo, patch: patch, completed: .swim, original: state, next: &next, now: now, extraLines: [line])
    }

    private static func storeEnteredFtp(_ watts: Int, echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.activeStep == .bike else { return .unchanged(state) }
        guard MetricEstimates.acceptsFtp(watts) else {
            return followUp(OnboardingCopy.checkThatNumber(), echo: echo, state: state)
        }
        return storeFtp(watts, source: MetricSourceLabel.entered, echo: echo, twentyMinute: nil, state: state, now: now)
    }

    private static func storeEstimatedFtp(echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.activeStep == .bike else { return .unchanged(state) }
        let value = MetricEstimates.estimatedFtp(
            experienceYears: state.answers.experienceYears,
            weeklyHours: state.answers.currentWeeklyHours
        )
        return storeFtp(value, source: MetricSourceLabel.fromExperience, echo: echo, twentyMinute: nil, state: state, now: now)
    }

    private static func storeTwentyMinute(_ watts: Int, echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.activeStep == .bike else { return .unchanged(state) }
        let ftp = MetricEstimates.ftp(fromTwentyMinute: watts)
        guard MetricEstimates.acceptsFtp(ftp) else {
            return followUp(OnboardingCopy.checkThatNumber(), echo: echo, state: state)
        }
        return storeFtp(ftp, source: MetricSourceLabel.fromRace, echo: echo, twentyMinute: watts, state: state, now: now)
    }

    private static func storeFtp(_ watts: Int, source: String, echo: String, twentyMinute: Int?, state: OnboardingState, now: Date) -> OnboardingStepResult {
        var next = state
        next.answers.ftp = watts
        next.answers.metrics.ftp = source
        var patch = OnboardingPatch()
        patch.ftp = watts
        patch.metrics = next.answers.metrics
        let line = OnboardingCopy.ftpLine(watts: watts, source: source, twentyMinute: twentyMinute)
        return committed(echo: echo, patch: patch, completed: .bike, original: state, next: &next, now: now, extraLines: [line])
    }

    private static func storeEnteredMaxHr(_ bpm: Int, echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.activeStep == .maxHeartRate else { return .unchanged(state) }
        guard MetricEstimates.acceptsMaxHr(bpm) else {
            return followUp(OnboardingCopy.checkThatNumber(), echo: echo, state: state)
        }
        var next = state
        next.answers.maxHr = bpm
        next.answers.metrics.maxHr = MetricSourceLabel.entered
        var patch = OnboardingPatch()
        patch.maxHr = bpm
        patch.metrics = next.answers.metrics
        let line = OnboardingCopy.maxHrLine(bpm: bpm, birthYear: nil)
        return committed(echo: echo, patch: patch, completed: .maxHeartRate, original: state, next: &next, now: now, extraLines: [line])
    }

    private static func storeBirthYear(_ year: Int, echo: String, state: OnboardingState, now: Date, calendar: Calendar) -> OnboardingStepResult {
        guard state.activeStep == .maxHeartRate else { return .unchanged(state) }
        guard MetricEstimates.acceptsBirthYear(year) else {
            return followUp(OnboardingCopy.checkThatNumber(), echo: echo, state: state)
        }
        let currentYear = calendar.component(.year, from: now)
        let bpm = MetricEstimates.maxHeartRate(birthYear: year, currentYear: currentYear)
        var next = state
        next.answers.birthYear = year
        next.answers.maxHr = bpm
        next.answers.metrics.maxHr = MetricSourceLabel.fromAge
        var patch = OnboardingPatch()
        patch.birthYear = year
        patch.maxHr = bpm
        patch.metrics = next.answers.metrics
        let line = OnboardingCopy.maxHrLine(bpm: bpm, birthYear: year)
        return committed(echo: echo, patch: patch, completed: .maxHeartRate, original: state, next: &next, now: now, extraLines: [line])
    }

    private static func storeDays(_ sport: OnboardingSport, days raw: [String], state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.activeStep == sport.step else { return .unchanged(state) }
        let days = Weekday.sorted(raw)
        guard !days.isEmpty else {
            return followUp(OnboardingCopy.emptyDaysHint(), echo: nil, state: state)
        }
        var next = state
        next.answers.setDays(days, for: sport)
        var patch = OnboardingPatch()
        switch sport {
        case .swim: patch.swimDays = days
        case .bike: patch.bikeDays = days
        case .run: patch.runDays = days
        }
        if next.answers.durationsConfirmed {
            fillMissingDurations(&next.answers)
            copyDurations(from: next.answers, onto: &patch)
        }
        let text = OnboardingCopy.summary(sport: sport, days: days)
        return committed(
            echo: text,
            patch: patch,
            completed: sport.step,
            original: state,
            next: &next,
            now: now,
            extraLines: [],
            summary: state.returnToRecap ? nil : sport.step
        )
    }

    private static func storeDurations(_ map: [String: Int], state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.activeStep == .dailyDuration else { return .unchanged(state) }
        let days = state.answers.trainingDays
        guard !days.isEmpty else {
            return followUp(OnboardingCopy.emptyDaysHint(), echo: nil, state: state)
        }
        var snapped: [String: Int] = [:]
        for day in days {
            guard let raw = map[day], let value = MetricEstimates.snapDuration(raw) else {
                return followUp("Each day needs a time between 30 minutes and 7 hours.", echo: nil, state: state)
            }
            snapped[day] = value
        }
        var next = state
        for day in Weekday.ordered {
            next.answers.setDuration(snapped[day], for: day)
        }
        next.answers.durationsConfirmed = true
        var patch = OnboardingPatch()
        copyDurations(from: next.answers, onto: &patch)
        return committed(
            echo: OnboardingCopy.durationSummary(next.answers),
            patch: patch,
            completed: .dailyDuration,
            original: state,
            next: &next,
            now: now,
            extraLines: [],
            summary: state.returnToRecap ? nil : .dailyDuration
        )
    }

    private static func storeLimiters(_ text: String, echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.activeStep == .limiters else { return .unchanged(state) }
        guard let cleaned = cleanedLimiters(text) else {
            return followUp(OnboardingCopy.gentleRedirect(), echo: echo, state: state)
        }
        var next = state
        next.answers.limiters = cleaned
        next.pendingNote = nil
        var patch = OnboardingPatch()
        patch.limiters = cleaned
        return committed(echo: echo, patch: patch, completed: .limiters, original: state, next: &next, now: now, extraLines: [])
    }

    private static func offerSaveNote(_ text: String, state: OnboardingState) -> OnboardingStepResult {
        guard state.activeStep == .limiters else { return .unchanged(state) }
        var next = state
        next.mode = .confirmLimitersNote
        next.pendingNote = String(text.prefix(500))
        var result = OnboardingStepResult.unchanged(next)
        result.followUp = OnboardingCopy.saveNotePrompt()
        return result
    }

    private static func saveNote(state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard let note = state.pendingNote, state.activeStep == .limiters else { return .unchanged(state) }
        return storeLimiters(note, echo: note, state: state, now: now)
    }

    // MARK: - Modes, edits, finish

    private static func changeMode(_ mode: OnboardingMode, echo: String, state: OnboardingState, now: Date) -> OnboardingStepResult {
        var next = state
        next.mode = mode
        next.pendingSuggestion = nil
        var result = OnboardingStepResult.unchanged(next)
        result.athleteEcho = echo
        result.coachLines = OnboardingCopy.questionLines(for: next, now: now)
        return result
    }

    private static func offerSuggestion(_ suggestion: PendingSuggestion, echo: String, state: OnboardingState) -> OnboardingStepResult {
        var next = state
        next.mode = .confirmSuggestion
        next.pendingSuggestion = suggestion
        let message: String
        switch suggestion {
        case .run(let distance, let suggested, let original):
            message = OnboardingCopy.didYouMean(
                distance: distance.title,
                original: OnboardingCopy.formatRaceClock(original),
                suggested: OnboardingCopy.formatRaceClock(suggested)
            )
        case .swim(let distance, let suggested, let original):
            message = OnboardingCopy.didYouMean(
                distance: distance.title,
                original: OnboardingCopy.formatRaceClock(original),
                suggested: OnboardingCopy.formatRaceClock(suggested)
            )
        }
        var result = OnboardingStepResult.unchanged(next)
        result.athleteEcho = echo
        result.followUp = message
        return result
    }

    private static func acceptSuggestion(state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard let suggestion = state.pendingSuggestion else { return .unchanged(state) }
        var cleared = state
        cleared.mode = .ask
        cleared.pendingSuggestion = nil
        switch suggestion {
        case .run(let distance, let seconds, _):
            let echo = "Yes, \(OnboardingCopy.formatRaceClock(seconds))"
            return storeRunTime(distance, seconds: seconds, echo: echo, state: cleared, now: now)
        case .swim(let distance, let seconds, _):
            let echo = "Yes, \(OnboardingCopy.formatRaceClock(seconds))"
            return storeSwimTime(distance, seconds: seconds, echo: echo, state: cleared, now: now)
        }
    }

    private static func rejectSuggestion(state: OnboardingState) -> OnboardingStepResult {
        guard let suggestion = state.pendingSuggestion else { return .unchanged(state) }
        var next = state
        next.pendingSuggestion = nil
        switch suggestion {
        case .run(let distance, _, _):
            next.mode = .enterRunTime(distance)
        case .swim(let distance, _, _):
            next.mode = .enterSwimTime(distance)
        }
        var result = OnboardingStepResult.unchanged(next)
        result.athleteEcho = "No, I'll re-enter"
        result.coachLines = OnboardingCopy.questionLines(for: next, now: Date())
        return result
    }

    private static func beginEdit(_ step: OnboardingStep, state: OnboardingState, now: Date) -> OnboardingStepResult {
        if state.step == .recap {
            var next = state
            next.returnToRecap = true
            next.step = step
            next.mode = .ask
            next.editing = nil
            next.pendingSuggestion = nil
            var result = OnboardingStepResult.unchanged(next)
            result.coachLines = OnboardingCopy.questionLines(for: next, now: now)
            return result
        }
        let order = OnboardingStep.allCases
        guard step.isAvailability,
              let editIndex = order.firstIndex(of: step),
              let currentIndex = order.firstIndex(of: state.step),
              editIndex < currentIndex else {
            return .unchanged(state)
        }
        var next = state
        next.editing = step
        next.mode = .ask
        return .unchanged(next)
    }

    private static func finish(state: OnboardingState, now: Date) -> OnboardingStepResult {
        guard state.step == .recap, state.editing == nil else { return .unchanged(state) }
        guard OnboardingState.unansweredStep(in: state.answers, now: now) == .recap else {
            return followUp("One answer is still missing. Tap the line to fill it in.", echo: nil, state: state)
        }
        var result = OnboardingStepResult.unchanged(state)
        result.athleteEcho = "Get my plan"
        result.finish = true
        return result
    }

    // MARK: - Coach facts

    private static func applyFacts(
        _ facts: CoachFacts,
        state: OnboardingState,
        now: Date,
        calendar: Calendar
    ) -> OnboardingStepResult {
        if let follow = facts.followUp, !follow.isEmpty {
            return followUp(follow, echo: nil, state: state)
        }
        if facts.unsupportedRace {
            return followUp(OnboardingCopy.unsupportedRace(), echo: nil, state: state)
        }
        switch state.activeStep {
        case .raceType:
            if let race = facts.raceObjective {
                return storeRace(race, echo: race.rawValue, state: state, now: now)
            }
        case .raceDate:
            if let date = facts.raceDate {
                return storeDate(date, alreadyUTC: true, echo: OnboardingCopy.displayDate(date), state: state, now: now, calendar: calendar)
            }
        case .targetTime:
            if facts.justFinish { return storeJustFinish(echo: "Just finish", state: state, now: now) }
            if let minutes = facts.timeMinutes {
                return storeFinishTime(minutes, echo: OnboardingCopy.formatClock(minutes: minutes), state: state, now: now)
            }
        case .experience:
            if let years = facts.experienceYears {
                return storeExperience(years, echo: OnboardingCopy.experienceLabel(years), state: state, now: now)
            }
        case .weeklyHours:
            if let hours = facts.weeklyHours {
                return storeHours(hours, echo: OnboardingCopy.formatHours(hours), state: state, now: now)
            }
        case .run:
            if facts.unknownMetric { return storeEstimatedVma(echo: "No idea", state: state, now: now) }
            if let distance = facts.runDistance, let seconds = facts.runSeconds {
                return storeRunTime(distance, seconds: seconds, echo: "\(distance.title) \(OnboardingCopy.formatRaceClock(seconds))", state: state, now: now)
            }
            if let vma = facts.vma {
                return storeEnteredVma(vma, echo: "VMA \(OnboardingCopy.formatVma(vma))", state: state, now: now)
            }
        case .swim:
            if facts.unknownMetric { return storeEstimatedCss(echo: "No idea", state: state, now: now) }
            if let distance = facts.swimDistance, let seconds = facts.swimSeconds {
                return storeSwimTime(distance, seconds: seconds, echo: "\(distance.title) \(OnboardingCopy.formatRaceClock(seconds))", state: state, now: now)
            }
            if let pace = facts.typicalPaceSeconds ?? facts.cssSeconds {
                return storeEnteredCss(pace, echo: "CSS \(OnboardingCopy.formatPace(pace))", state: state, now: now)
            }
        case .bike:
            if facts.unknownMetric || facts.noPowerMeter {
                return storeEstimatedFtp(echo: facts.noPowerMeter ? "No power meter" : "No idea", state: state, now: now)
            }
            if let watts = facts.twentyMinWatts {
                return storeTwentyMinute(watts, echo: "\(watts) W for 20 min", state: state, now: now)
            }
            if let ftp = facts.ftp {
                return storeEnteredFtp(ftp, echo: "FTP \(ftp) W", state: state, now: now)
            }
        case .maxHeartRate:
            if let year = facts.birthYear {
                return storeBirthYear(year, echo: "Born \(year)", state: state, now: now, calendar: calendar)
            }
            if let bpm = facts.maxHr {
                return storeEnteredMaxHr(bpm, echo: "\(bpm) bpm", state: state, now: now)
            }
        case .swimDays:
            if let days = facts.swimDays { return storeDays(.swim, days: days, state: state, now: now) }
        case .bikeDays:
            if let days = facts.bikeDays { return storeDays(.bike, days: days, state: state, now: now) }
        case .runDays:
            if let days = facts.runDays { return storeDays(.run, days: days, state: state, now: now) }
        case .limiters:
            if let text = facts.limiters { return storeLimiters(text, echo: text, state: state, now: now) }
        case .dailyDuration, .recap:
            break
        }
        return followUp(OnboardingCopy.gentleRedirect(), echo: nil, state: state)
    }

    // MARK: - Typed answers

    private static func applyTyped(
        _ raw: String,
        state: OnboardingState,
        now: Date,
        calendar: Calendar
    ) -> OnboardingStepResult {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .unchanged(state) }
        if state.mode == .confirmSuggestion {
            let lower = text.lowercased()
            if ["yes", "yep", "yeah", "correct", "that's right", "thats right"].contains(lower) {
                return acceptSuggestion(state: state, now: now)
            }
            if ["no", "nope"].contains(lower) {
                return rejectSuggestion(state: state)
            }
        }
        if let local = interpret(text, state: state, now: now, calendar: calendar) {
            return local
        }
        return consult(text, state: state)
    }

    private static func interpret(
        _ text: String,
        state: OnboardingState,
        now: Date,
        calendar: Calendar
    ) -> OnboardingStepResult? {
        let lower = text.lowercased()
        switch state.activeStep {
        case .raceType:
            if mentionsUnsupportedRace(lower) {
                return followUp(OnboardingCopy.unsupportedRace(), echo: text, state: state)
            }
            if lower.contains("70.3") || lower.contains("half") {
                return storeRace(.ironman703, echo: text, state: state, now: now)
            }
            if lower.contains("olympic") {
                return storeRace(.olympic, echo: text, state: state, now: now)
            }
            return nil
        case .raceDate:
            guard let date = parseDate(text, now: now, calendar: calendar) else { return nil }
            return storeDate(date, alreadyUTC: false, echo: text, state: state, now: now, calendar: calendar)
        case .targetTime:
            if isJustFinish(lower) { return storeJustFinish(echo: text, state: state, now: now) }
            if let minutes = parseFinishMinutes(lower) {
                return storeFinishTime(minutes, echo: text, state: state, now: now)
            }
            return nil
        case .experience:
            if let years = parseExperience(lower) {
                return storeExperience(years, echo: text, state: state, now: now)
            }
            return nil
        case .weeklyHours:
            if let hours = parseHours(lower) {
                return storeHours(hours, echo: text, state: state, now: now)
            }
            return nil
        case .run:
            return interpretRun(text, lower: lower, state: state, now: now)
        case .swim:
            return interpretSwim(text, lower: lower, state: state, now: now)
        case .bike:
            return interpretBike(text, lower: lower, state: state, now: now)
        case .maxHeartRate:
            return interpretHeart(text, lower: lower, state: state, now: now, calendar: calendar)
        case .swimDays:
            return interpretDays(text, sport: .swim, state: state, now: now)
        case .bikeDays:
            return interpretDays(text, sport: .bike, state: state, now: now)
        case .runDays:
            return interpretDays(text, sport: .run, state: state, now: now)
        case .limiters:
            if isNone(lower) { return storeLimiters("none", echo: text, state: state, now: now) }
            return nil
        case .dailyDuration, .recap:
            return nil
        }
    }

    private static func interpretRun(_ text: String, lower: String, state: OnboardingState, now: Date) -> OnboardingStepResult? {
        if isNoIdea(lower) { return storeEstimatedVma(echo: text, state: state, now: now) }
        if let distance = runDistance(in: lower), let seconds = parseClockSeconds(lower) {
            return storeRunTime(distance, seconds: seconds, echo: text, state: state, now: now)
        }
        if let seconds = parseClockSeconds(lower) {
            if case .enterRunTime(let distance) = state.mode {
                return storeRunTime(distance, seconds: seconds, echo: text, state: state, now: now)
            }
        }
        if let value = parseDecimal(lower), lower.contains("vma") || lower.contains("km") || state.mode == .enterVma {
            return storeEnteredVma(value, echo: text, state: state, now: now)
        }
        if state.mode == .ask, let value = parseDecimal(lower), MetricEstimates.vmaRange.contains(value) {
            return storeEnteredVma(value, echo: text, state: state, now: now)
        }
        return nil
    }

    private static func interpretSwim(_ text: String, lower: String, state: OnboardingState, now: Date) -> OnboardingStepResult? {
        if isNoIdea(lower) { return storeEstimatedCss(echo: text, state: state, now: now) }
        if let distance = swimDistance(in: lower), let seconds = parseClockSeconds(lower) {
            return storeSwimTime(distance, seconds: seconds, echo: text, state: state, now: now)
        }
        if case .enterSwimTime(let distance) = state.mode, let seconds = parseClockSeconds(lower) {
            return storeSwimTime(distance, seconds: seconds, echo: text, state: state, now: now)
        }
        if let seconds = parseClockSeconds(lower), state.mode == .enterCss || state.mode == .enterTypicalPace || lower.contains("css") || lower.contains("pace") || lower.contains("/100") || lower.contains("per 100") {
            return storeEnteredCss(seconds, echo: text, state: state, now: now)
        }
        return nil
    }

    private static func interpretBike(_ text: String, lower: String, state: OnboardingState, now: Date) -> OnboardingStepResult? {
        if lower.contains("power meter") || lower.contains("no power") {
            return storeEstimatedFtp(echo: text, state: state, now: now)
        }
        if isNoIdea(lower) { return storeEstimatedFtp(echo: text, state: state, now: now) }
        let numbers = integers(in: lower)
        guard let watts = numbers.last else { return nil }
        let twenty = state.mode == .enterTwenty || lower.contains("20 min") || lower.contains("20-min") || lower.contains("twenty")
        if twenty {
            let power = numbers.last(where: { $0 != 20 }) ?? watts
            return storeTwentyMinute(power, echo: text, state: state, now: now)
        }
        return storeEnteredFtp(watts, echo: text, state: state, now: now)
    }

    private static func interpretHeart(
        _ text: String,
        lower: String,
        state: OnboardingState,
        now: Date,
        calendar: Calendar
    ) -> OnboardingStepResult? {
        if let year = parseBirthYear(lower), state.mode == .enterBirthYear || lower.contains("born") || lower.contains("birth") {
            return storeBirthYear(year, echo: text, state: state, now: now, calendar: calendar)
        }
        if let bpm = parseInt(lower), state.mode != .enterBirthYear {
            return storeEnteredMaxHr(bpm, echo: text, state: state, now: now)
        }
        if let year = parseBirthYear(lower) {
            return storeBirthYear(year, echo: text, state: state, now: now, calendar: calendar)
        }
        return nil
    }

    private static func interpretDays(_ text: String, sport: OnboardingSport, state: OnboardingState, now: Date) -> OnboardingStepResult? {
        guard let days = parseDays(text) else { return nil }
        return storeDays(sport, days: days, state: state, now: now)
    }

    // MARK: - Parsing helpers

    static func parseDays(_ text: String) -> [String]? {
        let lower = text.lowercased()
        if lower.contains("any day") || lower.contains("every day") || lower.contains("all week") || lower == "any" || lower == "all" {
            return Weekday.ordered
        }
        if lower.contains("weekday") && !lower.contains("weekend") { return Weekday.weekdays }
        if lower.contains("weekend") && !lower.contains("weekday") { return Weekday.weekend }
        let pairs = [
            ("monday", "Monday"), ("tuesday", "Tuesday"), ("wednesday", "Wednesday"),
            ("thursday", "Thursday"), ("friday", "Friday"), ("saturday", "Saturday"), ("sunday", "Sunday"),
            ("mon", "Monday"), ("tue", "Tuesday"), ("wed", "Wednesday"),
            ("thu", "Thursday"), ("fri", "Friday"), ("sat", "Saturday"), ("sun", "Sunday"),
        ]
        var found = Set<String>()
        for (token, day) in pairs where containsToken(token, in: lower) {
            found.insert(day)
        }
        let sorted = Weekday.sorted(Array(found))
        return sorted.isEmpty ? nil : sorted
    }

    static func parseDate(_ text: String, now: Date, calendar: Calendar) -> Date? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = firstMatch(#"in\s+(\d+)\s+weeks?"#, lower), let count = Int(match) {
            return calendar.date(byAdding: .day, value: count * 7, to: calendar.startOfDay(for: now))
        }
        if let match = firstMatch(#"in\s+(\d+)\s+months?"#, lower), let count = Int(match) {
            return calendar.date(byAdding: .month, value: count, to: calendar.startOfDay(for: now))
        }
        if let parts = groups(#"(\d{4})-(\d{2})-(\d{2})"#, lower),
           parts.count == 3,
           let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) {
            return date(year: year, month: month, day: day, calendar: calendar)
        }
        let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        for (index, name) in months.enumerated() {
            guard lower.contains(name) || lower.contains(String(name.prefix(3))) else { continue }
            guard let day = firstMatch(#"\b(\d{1,2})\b"#, lower).flatMap(Int.init), (1...31).contains(day) else { continue }
            let year = firstMatch(#"\b(20\d{2})\b"#, lower).flatMap(Int.init) ?? calendar.component(.year, from: now)
            guard let candidate = date(year: year, month: index + 1, day: day, calendar: calendar) else { continue }
            let utc = PlanHorizon.utcMidnight(localDay: candidate, calendar: calendar)
            if PlanHorizon.accepts(raceDate: utc, now: now) { return candidate }
            return date(year: year + 1, month: index + 1, day: day, calendar: calendar)
        }
        return nil
    }

    static func parseFinishMinutes(_ text: String) -> Int? {
        if let match = firstMatch(#"(\d+(?:\.\d+)?)\s*(?:hours|hour|hrs|hr)\b"#, text), let hours = Double(match) {
            let whole = Int(hours)
            let minutes = Int(((hours - Double(whole)) * 60).rounded())
            return whole * 60 + minutes
        }
        if let parts = groups(#"(\d+)\s*h\s*(\d{1,2})"#, text),
           let hours = Int(parts[0]), let minutes = Int(parts[1]), minutes < 60 {
            return hours * 60 + minutes
        }
        if let parts = groups(#"\b(\d{1,2}):(\d{2})\b"#, text),
           let hours = Int(parts[0]), let minutes = Int(parts[1]), minutes < 60 {
            return hours * 60 + minutes
        }
        return nil
    }

    static func parseExperience(_ text: String) -> Int? {
        if text.contains("just start") || text.contains("beginner") || text.contains("new to") || text.contains("no experience") || text.contains("never") {
            return 0
        }
        if text.contains("2-4") || text.contains("2–4") || text.contains("few years") || text.contains("couple") {
            return 3
        }
        if text.contains("5+") || text.contains("five plus") { return 5 }
        if text.contains("one year") || text.contains("a year") { return 1 }
        if let match = firstMatch(#"(\d+)\s*(?:\+\s*)?(?:years|year|yrs|yr)\b"#, text), let years = Int(match) {
            return years
        }
        return nil
    }

    static func parseHours(_ text: String) -> Double? {
        if text.contains("under 3") { return 2 }
        if text.contains("12+") || text.contains("12 plus") { return 14 }
        if let match = firstMatch(#"(\d+(?:\.\d+)?)\s*(?:hours|hour|hrs|hr|h)\b"#, text), let hours = Double(match) {
            return hours
        }
        if let match = firstMatch(#"^(\d+(?:\.\d+)?)$"#, text), let hours = Double(match) {
            return hours
        }
        return nil
    }

    static func parseClockSeconds(_ text: String) -> Int? {
        if let parts = groups(#"\b(\d{1,2}):(\d{2}):(\d{2})\b"#, text),
           parts.count == 3,
           let hours = Int(parts[0]), let minutes = Int(parts[1]), let seconds = Int(parts[2]),
           minutes < 60, seconds < 60 {
            return hours * 3600 + minutes * 60 + seconds
        }
        if let parts = groups(#"\b(\d{1,3}):(\d{2})\b"#, text),
           parts.count == 2,
           let minutes = Int(parts[0]), let seconds = Int(parts[1]), seconds < 60 {
            return minutes * 60 + seconds
        }
        if let match = firstMatch(#"(\d+)\s*(?:minutes|minute|mins|min)\b"#, text), let minutes = Int(match) {
            return minutes * 60
        }
        return nil
    }

    static func parseDecimal(_ text: String) -> Double? {
        firstMatch(#"(\d+(?:\.\d+)?)"#, text).flatMap(Double.init)
    }

    static func parseInt(_ text: String) -> Int? {
        firstMatch(#"(\d+)"#, text).flatMap(Int.init)
    }

    static func parseBirthYear(_ text: String) -> Int? {
        firstMatch(#"\b(19\d{2}|20\d{2})\b"#, text).flatMap(Int.init)
    }

    static func isNoIdea(_ text: String) -> Bool {
        text.contains("no idea") || text.contains("don't know") || text.contains("dont know") || text.contains("not sure") || text == "no"
    }

    static func isJustFinish(_ text: String) -> Bool {
        text.contains("just finish") || text.contains("no time") || text.contains("finish strong") || text == "finish"
    }

    static func isNone(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let phrases: Set<String> = ["none", "no", "nothing", "nope", "no injuries", "no injury", "all good", "i'm fine", "im fine", "i am fine", "nothing really"]
        return phrases.contains(trimmed)
    }

    static func mentionsUnsupportedRace(_ text: String) -> Bool {
        if text.contains("70.3") || text.contains("olympic") { return false }
        return text.contains("sprint") || text.contains("140.6") || text.contains("full iron") || (text.contains("ironman") && !text.contains("70"))
    }

    // MARK: - Result builders

    private static func committed(
        echo: String,
        patch: OnboardingPatch,
        completed: OnboardingStep,
        original: OnboardingState,
        next: inout OnboardingState,
        now: Date,
        extraLines: [String],
        summary: OnboardingStep? = nil
    ) -> OnboardingStepResult {
        let editing = original.editing != nil || original.returnToRecap
        advance(&next, from: completed)
        var lines = extraLines
        if editing {
            lines.append("Updated.")
        } else {
            lines.append(contentsOf: OnboardingCopy.questionLines(for: next, now: now))
        }
        let reaction = OnboardingCopy.fallbackReaction(after: completed, answers: next.answers, now: now)
        return OnboardingStepResult(
            state: next,
            athleteEcho: echo,
            summary: summary,
            replacesSummary: summary != nil && original.editing == summary,
            coachLines: lines,
            fallbackReaction: reaction,
            wantsReaction: !editing && reaction != nil,
            patch: patch,
            consultCoach: false,
            finish: false,
            followUp: nil
        )
    }

    private static func advance(_ state: inout OnboardingState, from completed: OnboardingStep) {
        state.mode = .ask
        state.pendingSuggestion = nil
        state.pendingNote = nil
        if state.returnToRecap {
            state.step = .recap
            state.returnToRecap = false
            state.editing = nil
            return
        }
        if state.editing != nil {
            state.editing = nil
            return
        }
        state.step = completed.next
    }

    private static func fillMissingDurations(_ answers: inout OnboardingAnswers) {
        let defaults = MetricEstimates.defaultDurations(
            days: answers.trainingDays,
            weeklyHours: answers.currentWeeklyHours ?? 3
        )
        for day in Weekday.ordered {
            if answers.trainingDays.contains(day) {
                if answers.duration(for: day) == nil {
                    answers.setDuration(defaults[day] ?? 60, for: day)
                }
            } else {
                answers.setDuration(nil, for: day)
            }
        }
    }

    private static func copyDurations(from answers: OnboardingAnswers, onto patch: inout OnboardingPatch) {
        patch.replaceDurations = true
        patch.monDuration = answers.monDuration
        patch.tueDuration = answers.tueDuration
        patch.wedDuration = answers.wedDuration
        patch.thuDuration = answers.thuDuration
        patch.friDuration = answers.friDuration
        patch.satDuration = answers.satDuration
        patch.sunDuration = answers.sunDuration
    }

    private static func cleanedLimiters(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isNone(trimmed.lowercased()) { return "none" }
        if trimmed.count > 500 { return String(trimmed.prefix(500)) }
        return trimmed
    }

    private static func followUp(_ message: String, echo: String?, state: OnboardingState) -> OnboardingStepResult {
        var result = OnboardingStepResult.unchanged(state)
        result.athleteEcho = echo
        result.followUp = message
        return result
    }

    private static func consult(_ echo: String, state: OnboardingState) -> OnboardingStepResult {
        var result = OnboardingStepResult.unchanged(state)
        result.athleteEcho = echo
        result.consultCoach = true
        return result
    }

    private static func runDistance(in text: String) -> RunDistance? {
        if text.contains("10k") || text.contains("10 k") { return .tenK }
        if text.contains("5k") || text.contains("5 k") { return .fiveK }
        return nil
    }

    private static func swimDistance(in text: String) -> SwimDistance? {
        if text.contains("1500") { return .fifteenHundred }
        if text.contains("400") { return .fourHundred }
        return nil
    }

    private static func containsToken(_ token: String, in text: String) -> Bool {
        text.range(of: "\\b\(token)\\b", options: .regularExpression) != nil
    }

    private static func integers(in text: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #"\d+"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).flatMap { Int(text[$0]) }
        }
    }

    private static func groups(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }
        var values: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let hit = Range(match.range(at: index), in: text) else { return nil }
            values.append(String(text[hit]))
        }
        return values
    }

    private static func firstMatch(_ pattern: String, _ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        let index = match.numberOfRanges > 1 ? 1 : 0
        guard let hit = Range(match.range(at: index), in: text) else { return nil }
        return String(text[hit])
    }

    private static func date(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        return calendar.date(from: parts)
    }
}
