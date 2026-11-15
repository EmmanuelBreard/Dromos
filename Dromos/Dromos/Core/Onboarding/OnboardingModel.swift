//
//  OnboardingModel.swift
//  Dromos
//
//  The onboarding steps and the profile fields they fill. The chat UI renders
//  this state. It does not decide the order.
//

import Foundation

enum OnboardingStep: String, Equatable, CaseIterable {
    case raceType
    case raceDate
    case targetTime
    case experience
    case weeklyHours
    case run
    case swim
    case bike
    case maxHeartRate
    case swimDays
    case bikeDays
    case runDays
    case dailyDuration
    case limiters
    case recap

    var next: OnboardingStep {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return .recap }
        return all[index + 1]
    }

    var isAvailability: Bool {
        switch self {
        case .swimDays, .bikeDays, .runDays, .dailyDuration:
            return true
        default:
            return false
        }
    }
}

enum OnboardingSport: String, Equatable {
    case swim, bike, run

    var title: String {
        switch self {
        case .swim: return "Swim"
        case .bike: return "Bike"
        case .run: return "Run"
        }
    }

    var step: OnboardingStep {
        switch self {
        case .swim: return .swimDays
        case .bike: return .bikeDays
        case .run: return .runDays
        }
    }

    static func from(step: OnboardingStep) -> OnboardingSport? {
        switch step {
        case .swimDays: return .swim
        case .bikeDays: return .bike
        case .runDays: return .run
        default: return nil
        }
    }
}

enum Weekday {
    static let ordered = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    static let weekend = ["Saturday", "Sunday"]

    static func short(_ day: String) -> String {
        switch day {
        case "Monday": return "Mon"
        case "Tuesday": return "Tue"
        case "Wednesday": return "Wed"
        case "Thursday": return "Thu"
        case "Friday": return "Fri"
        case "Saturday": return "Sat"
        case "Sunday": return "Sun"
        default: return day
        }
    }

    static func union(_ groups: [String]...) -> [String] {
        let set = Set(groups.flatMap { $0 })
        return ordered.filter { set.contains($0) }
    }

    static func sorted(_ days: [String]) -> [String] {
        let known = Set(ordered)
        let unique = Set(days.filter { known.contains($0) })
        return ordered.filter { unique.contains($0) }
    }
}

/// Same rule as `computePlanHorizon` in generate-plan: the plan starts on the
/// UTC date of now + 24h, and the race must leave at least one week
/// (`ceil(days / 7) >= 1`). That accepts the day after the plan starts.
enum PlanHorizon {
    static func accepts(raceDate: Date, now: Date) -> Bool {
        let start = utcDay(now.addingTimeInterval(86_400))
        let race = utcDay(raceDate)
        let days = Int((race.timeIntervalSince(start) / 86_400).rounded())
        let weeks = Int(ceil(Double(days) / 7.0))
        return weeks >= 1
    }

    static func utcDay(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: parts) ?? date
    }

    /// The calendar day the athlete picked, stored as UTC midnight so the
    /// date cannot drift when the phone is not on UTC.
    static func utcMidnight(localDay date: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return utc.date(from: parts) ?? date
    }

    static func earliestLocalDay(now: Date, calendar: Calendar) -> Date {
        var day = calendar.startOfDay(for: now)
        for _ in 0..<14 {
            let utc = utcMidnight(localDay: day, calendar: calendar)
            if accepts(raceDate: utc, now: now) { return day }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return day
    }

    static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

enum OnboardingMode: Equatable {
    case ask
    case pickTime
    case enterVma
    case pickRunDistance
    case enterRunTime(RunDistance)
    case enterCss
    case pickSwimDistance
    case enterSwimTime(SwimDistance)
    case enterTypicalPace
    case enterFtp
    case enterTwenty
    case enterMaxHr
    case enterBirthYear
    case confirmSuggestion
    case confirmLimitersNote
}

enum PendingSuggestion: Equatable {
    case run(RunDistance, seconds: Int, originalSeconds: Int)
    case swim(SwimDistance, seconds: Int, originalSeconds: Int)
}

struct OnboardingAnswers: Equatable {
    var raceObjective: RaceObjective?
    var raceDate: Date?
    var timeObjectiveMinutes: Int?
    /// "Just finish" leaves the column null. This flag is how a closed app
    /// tells that apart from "we have not asked yet", once a later answer exists.
    var targetTimeDecided: Bool
    var experienceYears: Int?
    var currentWeeklyHours: Double?
    var vma: Double?
    var cssSecondsPer100m: Int?
    var ftp: Int?
    var maxHr: Int?
    var birthYear: Int?
    var metrics: MetricsSource
    var swimDays: [String]
    var bikeDays: [String]
    var runDays: [String]
    var monDuration: Int?
    var tueDuration: Int?
    var wedDuration: Int?
    var thuDuration: Int?
    var friDuration: Int?
    var satDuration: Int?
    var sunDuration: Int?
    var durationsConfirmed: Bool
    var limiters: String?

    static let empty = OnboardingAnswers(
        raceObjective: nil,
        raceDate: nil,
        timeObjectiveMinutes: nil,
        targetTimeDecided: false,
        experienceYears: nil,
        currentWeeklyHours: nil,
        vma: nil,
        cssSecondsPer100m: nil,
        ftp: nil,
        maxHr: nil,
        birthYear: nil,
        metrics: MetricsSource(),
        swimDays: [],
        bikeDays: [],
        runDays: [],
        monDuration: nil,
        tueDuration: nil,
        wedDuration: nil,
        thuDuration: nil,
        friDuration: nil,
        satDuration: nil,
        sunDuration: nil,
        durationsConfirmed: false,
        limiters: nil
    )

    func days(for sport: OnboardingSport) -> [String] {
        switch sport {
        case .swim: return swimDays
        case .bike: return bikeDays
        case .run: return runDays
        }
    }

    mutating func setDays(_ days: [String], for sport: OnboardingSport) {
        let sorted = Weekday.sorted(days)
        switch sport {
        case .swim: swimDays = sorted
        case .bike: bikeDays = sorted
        case .run: runDays = sorted
        }
    }

    var trainingDays: [String] {
        Weekday.union(swimDays, bikeDays, runDays)
    }

    func duration(for day: String) -> Int? {
        switch day {
        case "Monday": return monDuration
        case "Tuesday": return tueDuration
        case "Wednesday": return wedDuration
        case "Thursday": return thuDuration
        case "Friday": return friDuration
        case "Saturday": return satDuration
        case "Sunday": return sunDuration
        default: return nil
        }
    }

    mutating func setDuration(_ minutes: Int?, for day: String) {
        switch day {
        case "Monday": monDuration = minutes
        case "Tuesday": tueDuration = minutes
        case "Wednesday": wedDuration = minutes
        case "Thursday": thuDuration = minutes
        case "Friday": friDuration = minutes
        case "Saturday": satDuration = minutes
        case "Sunday": sunDuration = minutes
        default: break
        }
    }

    /// Fields that mean the athlete already passed the optional time question.
    var passedTargetTime: Bool {
        if targetTimeDecided || timeObjectiveMinutes != nil { return true }
        if experienceYears != nil || currentWeeklyHours != nil { return true }
        if vma != nil || cssSecondsPer100m != nil || ftp != nil || maxHr != nil { return true }
        if !swimDays.isEmpty || !bikeDays.isEmpty || !runDays.isEmpty { return true }
        if durationsConfirmed || limiters != nil { return true }
        return false
    }
}

/// Columns to write after one accepted answer. Nil fields are left alone.
struct OnboardingPatch: Equatable {
    var raceObjective: RaceObjective? = nil
    var raceDate: Date? = nil
    var timeObjectiveMinutes: Int? = nil
    var clearTimeObjective = false
    var experienceYears: Int? = nil
    var currentWeeklyHours: Double? = nil
    var vma: Double? = nil
    var cssSecondsPer100m: Int? = nil
    var ftp: Int? = nil
    var maxHr: Int? = nil
    var birthYear: Int? = nil
    var metrics: MetricsSource? = nil
    var swimDays: [String]? = nil
    var bikeDays: [String]? = nil
    var runDays: [String]? = nil
    var replaceDurations = false
    var monDuration: Int? = nil
    var tueDuration: Int? = nil
    var wedDuration: Int? = nil
    var thuDuration: Int? = nil
    var friDuration: Int? = nil
    var satDuration: Int? = nil
    var sunDuration: Int? = nil
    var limiters: String? = nil

    static let empty = OnboardingPatch()

    var isEmpty: Bool {
        raceObjective == nil && raceDate == nil && timeObjectiveMinutes == nil && !clearTimeObjective
            && experienceYears == nil && currentWeeklyHours == nil && vma == nil
            && cssSecondsPer100m == nil && ftp == nil && maxHr == nil && birthYear == nil
            && metrics == nil && swimDays == nil && bikeDays == nil && runDays == nil
            && !replaceDurations && limiters == nil
    }
}

struct OnboardingState: Equatable {
    var answers: OnboardingAnswers
    var step: OnboardingStep
    var mode: OnboardingMode
    var editing: OnboardingStep?
    var returnToRecap: Bool
    var pendingSuggestion: PendingSuggestion?
    var pendingNote: String?

    static func fresh() -> OnboardingState {
        OnboardingState(
            answers: .empty,
            step: .raceType,
            mode: .ask,
            editing: nil,
            returnToRecap: false,
            pendingSuggestion: nil,
            pendingNote: nil
        )
    }

    var activeStep: OnboardingStep { editing ?? step }

    /// First step that does not yet have a usable answer.
    static func resume(from answers: OnboardingAnswers, now: Date) -> OnboardingState {
        OnboardingState(
            answers: answers,
            step: unansweredStep(in: answers, now: now),
            mode: .ask,
            editing: nil,
            returnToRecap: false,
            pendingSuggestion: nil,
            pendingNote: nil
        )
    }

    static func unansweredStep(in answers: OnboardingAnswers, now: Date) -> OnboardingStep {
        if answers.raceObjective == nil { return .raceType }
        if answers.raceDate == nil || !PlanHorizon.accepts(raceDate: answers.raceDate!, now: now) {
            return .raceDate
        }
        if !answers.passedTargetTime { return .targetTime }
        if answers.experienceYears == nil { return .experience }
        if answers.currentWeeklyHours == nil { return .weeklyHours }
        if answers.vma == nil { return .run }
        if answers.cssSecondsPer100m == nil { return .swim }
        if answers.ftp == nil { return .bike }
        if answers.maxHr == nil { return .maxHeartRate }
        if answers.swimDays.isEmpty { return .swimDays }
        if answers.bikeDays.isEmpty { return .bikeDays }
        if answers.runDays.isEmpty { return .runDays }
        if !answers.durationsConfirmed || !durationsMatchDays(answers) { return .dailyDuration }
        if answers.limiters == nil { return .limiters }
        return .recap
    }

    static func durationsMatchDays(_ answers: OnboardingAnswers) -> Bool {
        let days = answers.trainingDays
        guard !days.isEmpty else { return false }
        return days.allSatisfy { answers.duration(for: $0) != nil }
    }

    static func answers(from user: User) -> OnboardingAnswers {
        var answers = OnboardingAnswers.empty
        answers.raceObjective = user.raceObjective
        answers.raceDate = user.raceDate
        answers.timeObjectiveMinutes = user.timeObjectiveMinutes
        answers.experienceYears = user.experienceYears
        answers.currentWeeklyHours = user.currentWeeklyHours
        answers.vma = user.vma
        answers.cssSecondsPer100m = user.cssSecondsPer100m
        answers.ftp = user.ftp
        answers.maxHr = user.maxHr
        answers.birthYear = user.birthYear
        answers.metrics = user.metricsSource ?? MetricsSource()
        answers.swimDays = Weekday.sorted(user.swimDays ?? [])
        answers.bikeDays = Weekday.sorted(user.bikeDays ?? [])
        answers.runDays = Weekday.sorted(user.runDays ?? [])
        answers.monDuration = user.monDuration
        answers.tueDuration = user.tueDuration
        answers.wedDuration = user.wedDuration
        answers.thuDuration = user.thuDuration
        answers.friDuration = user.friDuration
        answers.satDuration = user.satDuration
        answers.sunDuration = user.sunDuration
        answers.limiters = user.limiters.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let sportsReady = !answers.swimDays.isEmpty && !answers.bikeDays.isEmpty && !answers.runDays.isEmpty
        answers.durationsConfirmed = sportsReady && durationsMatchDays(answers)
        answers.targetTimeDecided = answers.passedTargetTime
        return answers
    }
}

/// What the coach function extracted. The reducer checks it again before saving.
struct CoachFacts: Equatable {
    var raceObjective: RaceObjective?
    var unsupportedRace = false
    var raceDate: Date?
    var justFinish = false
    var timeMinutes: Int?
    var experienceYears: Int?
    var weeklyHours: Double?
    var vma: Double?
    var runDistance: RunDistance?
    var runSeconds: Int?
    var cssSeconds: Int?
    var swimDistance: SwimDistance?
    var swimSeconds: Int?
    var typicalPaceSeconds: Int?
    var ftp: Int?
    var twentyMinWatts: Int?
    var noPowerMeter = false
    var maxHr: Int?
    var birthYear: Int?
    var limiters: String?
    var unknownMetric = false
    var swimDays: [String]?
    var bikeDays: [String]?
    var runDays: [String]?
    var followUp: String?
}

enum QuickReplyID: String, Equatable, CaseIterable {
    case olympic
    case ironman703
    case weeks8
    case weeks16
    case months6
    case justFinish
    case haveTime
    case expStarting
    case expOne
    case expMid
    case expVeteran
    case hours2
    case hours4
    case hours6_5
    case hours10
    case hours14
    case knowVma
    case haveRunRace
    case noRunIdea
    case run5k
    case run10k
    case knowCss
    case swim400
    case swim1500
    case typicalPace
    case noSwimIdea
    case knowFtp
    case twentyMin
    case noPower
    case noBikeIdea
    case knowMaxHr
    case knowBirthYear
    case noLimiters
    case saveNote
    case yesSuggestion
    case noSuggestion
    case weekdays
    case weekends
    case anyDay
    case keepDurations
    case getPlan
}

struct QuickReply: Equatable, Identifiable {
    var id: QuickReplyID
    var title: String
}

enum OnboardingEvent: Equatable {
    case reply(QuickReplyID)
    case typed(String)
    case confirmDate(Date)
    case confirmMinutes(Int)
    case confirmHours(Double)
    case confirmVma(Double)
    case confirmRunTime(RunDistance, Int)
    case confirmCss(Int)
    case confirmSwimTime(SwimDistance, Int)
    case confirmFtp(Int)
    case confirmTwenty(Int)
    case confirmMaxHr(Int)
    case confirmBirthYear(Int)
    case confirmDays(OnboardingSport, [String])
    case confirmDurations([String: Int])
    case edit(OnboardingStep)
    case resolved(CoachFacts)
    case savePendingNote
    case offerSaveNote(String)
}

struct OnboardingStepResult: Equatable {
    var state: OnboardingState
    var athleteEcho: String?
    var summary: OnboardingStep?
    var replacesSummary: Bool
    var coachLines: [String]
    var fallbackReaction: String?
    var wantsReaction: Bool
    var patch: OnboardingPatch?
    var consultCoach: Bool
    var finish: Bool
    var followUp: String?

    static func unchanged(_ state: OnboardingState) -> OnboardingStepResult {
        OnboardingStepResult(
            state: state,
            athleteEcho: nil,
            summary: nil,
            replacesSummary: false,
            coachLines: [],
            fallbackReaction: nil,
            wantsReaction: false,
            patch: nil,
            consultCoach: false,
            finish: false,
            followUp: nil
        )
    }
}
