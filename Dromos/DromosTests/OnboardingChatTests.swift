//
//  OnboardingChatTests.swift
//  DromosTests
//
//  Step order, resume, and the rule that a bad answer is not stored.
//  DromosTests is not an Xcode target yet; these run once that target exists.
//

import XCTest
@testable import Dromos

final class OnboardingChatTests: XCTestCase {

    private let now = ISO8601DateFormatter().date(from: "2026-11-15T12:00:00Z")!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func apply(_ event: OnboardingEvent, to state: OnboardingState) -> OnboardingStepResult {
        OnboardingReducer.apply(event, to: state, now: now, calendar: calendar)
    }

    private func utc(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.timeZone = TimeZone(secondsFromGMT: 0)
        return calendar.date(from: parts)!
    }

    private func state(_ step: OnboardingStep, _ answers: OnboardingAnswers = .empty) -> OnboardingState {
        var value = OnboardingState.fresh()
        value.step = step
        value.answers = answers
        return value
    }

    // MARK: - Order and storage

    func test_olympicTap_storesRaceAndAsksForDate() {
        let result = apply(.reply(.olympic), to: .fresh())
        XCTAssertEqual(result.state.answers.raceObjective, .olympic)
        XCTAssertEqual(result.state.step, .raceDate)
        XCTAssertEqual(result.patch?.raceObjective, .olympic)
        XCTAssertFalse(result.consultCoach)
        XCTAssertNil(result.followUp)
    }

    func test_sprintText_storesNothing() {
        let result = apply(.typed("I want to do a sprint"), to: .fresh())
        XCTAssertNil(result.state.answers.raceObjective)
        XCTAssertEqual(result.state.step, .raceType)
        XCTAssertNil(result.patch)
        XCTAssertFalse(result.consultCoach)
        XCTAssertEqual(result.followUp, OnboardingCopy.unsupportedRace())
    }

    func test_vagueText_asksTheCoachAndStoresNothing() {
        let result = apply(.typed("lol whatever"), to: .fresh())
        XCTAssertNil(result.patch)
        XCTAssertTrue(result.consultCoach)
        XCTAssertEqual(result.state.step, .raceType)
        XCTAssertEqual(result.athleteEcho, "lol whatever")
    }

    func test_raceOnPlanStart_isRejected() {
        let result = apply(.confirmDate(utc(2026, 11, 16)), to: state(.raceDate))
        XCTAssertNil(result.state.answers.raceDate)
        XCTAssertNil(result.patch)
        XCTAssertEqual(result.followUp, OnboardingCopy.tooSoon())
    }

    func test_raceTheDayAfterPlanStart_isAccepted() {
        let result = apply(.confirmDate(utc(2026, 11, 17)), to: state(.raceDate))
        XCTAssertEqual(result.state.answers.raceDate, utc(2026, 11, 17))
        XCTAssertEqual(result.state.step, .targetTime)
        XCTAssertTrue(PlanHorizon.accepts(raceDate: result.state.answers.raceDate!, now: now))
    }

    func test_justFinish_leavesTimeEmptyAndMovesOn() {
        let result = apply(.reply(.justFinish), to: state(.targetTime))
        XCTAssertNil(result.state.answers.timeObjectiveMinutes)
        XCTAssertTrue(result.state.answers.targetTimeDecided)
        XCTAssertEqual(result.patch?.clearTimeObjective, true)
        XCTAssertEqual(result.state.step, .experience)
    }

    func test_experienceBands_mapToStoredYears() {
        XCTAssertEqual(apply(.reply(.expStarting), to: state(.experience)).state.answers.experienceYears, 0)
        XCTAssertEqual(apply(.reply(.expOne), to: state(.experience)).state.answers.experienceYears, 1)
        XCTAssertEqual(apply(.reply(.expMid), to: state(.experience)).state.answers.experienceYears, 3)
        XCTAssertEqual(apply(.reply(.expVeteran), to: state(.experience)).state.answers.experienceYears, 5)
    }

    func test_fiveHours_onA703_usesTheAmbitiousLine() {
        var answers = OnboardingAnswers.empty
        answers.raceObjective = .ironman703
        answers.raceDate = calendar.date(byAdding: .month, value: 6, to: now)
        let result = apply(.confirmHours(5), to: state(.weeklyHours, answers))
        XCTAssertEqual(result.state.answers.currentWeeklyHours, 5)
        XCTAssertEqual(result.state.step, .run)
        XCTAssertEqual(
            result.fallbackReaction,
            "A 70.3 in about 6 months on 5 hours a week is ambitious but doable. We'll build your bike endurance first."
        )
    }

    func test_emptyDayList_doesNotAdvance() {
        let result = apply(.confirmDays(.swim, []), to: state(.swimDays))
        XCTAssertTrue(result.state.answers.swimDays.isEmpty)
        XCTAssertNil(result.patch)
        XCTAssertEqual(result.state.step, .swimDays)
    }

    func test_swimDays_areStoredInWeekOrder() {
        let result = apply(.confirmDays(.swim, ["Friday", "Monday", "Wednesday"]), to: state(.swimDays))
        XCTAssertEqual(result.state.answers.swimDays, ["Monday", "Wednesday", "Friday"])
        XCTAssertEqual(result.state.step, .bikeDays)
        XCTAssertEqual(result.summary, .swimDays)
    }

    func test_typedWeekdays_storeTheFiveDays() {
        let result = apply(.typed("weekdays"), to: state(.bikeDays))
        XCTAssertEqual(result.state.answers.bikeDays, Weekday.weekdays)
        XCTAssertEqual(result.patch?.bikeDays, Weekday.weekdays)
    }

    func test_limitersNone_isStoredAsNone() {
        let result = apply(.reply(.noLimiters), to: state(.limiters))
        XCTAssertEqual(result.state.answers.limiters, "none")
        XCTAssertEqual(result.patch?.limiters, "none")
        XCTAssertEqual(result.state.step, .recap)
    }

    func test_saveNote_storesTheAthletesWords() {
        let offered = apply(.offerSaveNote("Left knee is sore on long runs"), to: state(.limiters))
        XCTAssertNil(offered.patch)
        XCTAssertEqual(offered.state.mode, .confirmLimitersNote)
        let saved = apply(.savePendingNote, to: offered.state)
        XCTAssertEqual(saved.state.answers.limiters, "Left knee is sore on long runs")
        XCTAssertEqual(saved.patch?.limiters, "Left knee is sore on long runs")
        XCTAssertTrue(saved.fallbackReaction?.contains("doctor or physio") == true)
    }

    func test_coachFollowUp_storesNothing() {
        var facts = CoachFacts()
        facts.followUp = "Love the enthusiasm, but I still need your race date."
        let result = apply(.resolved(facts), to: state(.raceDate))
        XCTAssertNil(result.state.answers.raceDate)
        XCTAssertNil(result.patch)
        XCTAssertEqual(result.followUp, facts.followUp)
    }

    func test_implausibleVmaFromCoach_isNotStored() {
        var facts = CoachFacts()
        facts.vma = 40
        let result = apply(.resolved(facts), to: state(.run))
        XCTAssertNil(result.state.answers.vma)
        XCTAssertNil(result.patch)
    }

    func test_getMyPlan_onlyFinishesACompleteRecap() {
        XCTAssertFalse(apply(.reply(.getPlan), to: .fresh()).finish)
        var answers = completeAnswers()
        let ready = state(.recap, answers)
        let result = apply(.reply(.getPlan), to: ready)
        XCTAssertTrue(result.finish)
        XCTAssertNil(result.patch)
        answers.limiters = nil
        XCTAssertFalse(apply(.reply(.getPlan), to: state(.recap, answers)).finish)
    }

    func test_recapEdit_returnsToRecapAfterTheChange() {
        var editing = state(.recap, completeAnswers())
        let opened = apply(.edit(.experience), to: editing)
        XCTAssertEqual(opened.state.step, .experience)
        XCTAssertTrue(opened.state.returnToRecap)
        let saved = apply(.reply(.expVeteran), to: opened.state)
        XCTAssertEqual(saved.state.step, .recap)
        XCTAssertEqual(saved.state.answers.experienceYears, 5)
        XCTAssertFalse(saved.state.returnToRecap)
        editing.answers.experienceYears = 5
        XCTAssertEqual(saved.state.answers.experienceYears, editing.answers.experienceYears)
    }

    func test_inPlaceDayEdit_keepsTheLaterStep() {
        var current = state(.runDays, completeAnswers())
        current.step = .runDays
        current.answers.runDays = []
        current.answers.durationsConfirmed = false
        let opened = apply(.edit(.swimDays), to: current)
        XCTAssertEqual(opened.state.step, .runDays)
        XCTAssertEqual(opened.state.editing, .swimDays)
        let saved = apply(.confirmDays(.swim, ["Tuesday"]), to: opened.state)
        XCTAssertNil(saved.state.editing)
        XCTAssertEqual(saved.state.step, .runDays)
        XCTAssertEqual(saved.state.answers.swimDays, ["Tuesday"])
        XCTAssertTrue(saved.replacesSummary)
    }

    // MARK: - Resume

    func test_resume_startsAtTheFirstUnansweredStep() {
        var answers = OnboardingAnswers.empty
        XCTAssertEqual(OnboardingState.unansweredStep(in: answers, now: now), .raceType)

        answers.raceObjective = .olympic
        XCTAssertEqual(OnboardingState.unansweredStep(in: answers, now: now), .raceDate)

        answers.raceDate = utc(2026, 11, 17)
        XCTAssertEqual(OnboardingState.unansweredStep(in: answers, now: now), .targetTime)

        answers.experienceYears = 1
        XCTAssertEqual(OnboardingState.unansweredStep(in: answers, now: now), .weeklyHours)

        answers.raceDate = utc(2026, 11, 16)
        XCTAssertEqual(OnboardingState.unansweredStep(in: answers, now: now), .raceDate)
    }

    func test_resume_withNoneLimiters_landsOnTheRecap() {
        let answers = completeAnswers()
        XCTAssertEqual(OnboardingState.unansweredStep(in: answers, now: now), .recap)
    }

    func test_resume_fromUserRow_skipsABlankTargetTimeOnceLaterAnswersExist() {
        var user = makeUser()
        user.raceObjective = .olympic
        user.raceDate = utc(2027, 6, 1)
        user.experienceYears = 2
        let answers = OnboardingState.answers(from: user)
        XCTAssertTrue(answers.targetTimeDecided)
        XCTAssertEqual(OnboardingState.resume(from: answers, now: now).step, .weeklyHours)
    }

    // MARK: - Metrics

    func test_noIdeaRun_usesTheExperienceTable() {
        var answers = OnboardingAnswers.empty
        answers.experienceYears = 0
        answers.currentWeeklyHours = 2
        let result = apply(.reply(.noRunIdea), to: state(.run, answers))
        XCTAssertEqual(result.state.answers.vma, 11.5)
        XCTAssertEqual(result.state.answers.metrics.vma, MetricSourceLabel.fromExperience)
        XCTAssertEqual(result.patch?.vma, 11.5)
        XCTAssertEqual(result.state.step, .swim)
        XCTAssertTrue(result.coachLines.contains { $0.contains("11.5") })
    }

    func test_fiveKIn20_estimatesVmaFromTheRace() {
        let result = apply(.confirmRunTime(.fiveK, 20 * 60), to: state(.run))
        XCTAssertEqual(result.state.answers.vma, 16.1)
        XCTAssertEqual(result.state.answers.metrics.vma, MetricSourceLabel.fromRace)
    }

    func test_fiveKIn9Minutes_asksBeforeStoring() {
        let result = apply(.typed("5k in 9:00"), to: state(.run))
        XCTAssertNil(result.state.answers.vma)
        XCTAssertNil(result.patch)
        XCTAssertEqual(result.state.mode, .confirmSuggestion)
        XCTAssertTrue(result.followUp?.contains("19:00") == true)
        let accepted = apply(.reply(.yesSuggestion), to: result.state)
        XCTAssertEqual(accepted.state.answers.vma, 16.9)
        XCTAssertEqual(accepted.state.answers.metrics.vma, MetricSourceLabel.fromRace)
        XCTAssertEqual(accepted.state.step, .swim)
    }

    func test_cssFrom400And1500() {
        let four = apply(.confirmSwimTime(.fourHundred, 8 * 60), to: state(.swim))
        XCTAssertEqual(four.state.answers.cssSecondsPer100m, 123)
        XCTAssertEqual(four.state.answers.metrics.css, MetricSourceLabel.fromRace)

        let fifteen = apply(.confirmSwimTime(.fifteenHundred, 30 * 60), to: state(.swim))
        XCTAssertEqual(fifteen.state.answers.cssSecondsPer100m, 118)
    }

    func test_ftpIs95PercentOf20MinutePower() {
        let result = apply(.confirmTwenty(200), to: state(.bike))
        XCTAssertEqual(result.state.answers.ftp, 190)
        XCTAssertEqual(result.state.answers.metrics.ftp, MetricSourceLabel.fromRace)
        XCTAssertTrue(result.coachLines.contains { $0.contains("190") })
    }

    func test_noPowerMeter_usesTheFtpTable() {
        var answers = OnboardingAnswers.empty
        answers.experienceYears = 5
        answers.currentWeeklyHours = 12
        let result = apply(.reply(.noPower), to: state(.bike, answers))
        XCTAssertEqual(result.state.answers.ftp, 260)
        XCTAssertEqual(result.state.answers.metrics.ftp, MetricSourceLabel.fromExperience)
    }

    func test_birthYear_estimatesMaxHrAndRecordsTheSource() {
        let result = apply(.confirmBirthYear(1990), to: state(.maxHeartRate))
        XCTAssertEqual(result.state.answers.birthYear, 1990)
        XCTAssertEqual(result.state.answers.maxHr, 184)
        XCTAssertEqual(result.state.answers.metrics.maxHr, MetricSourceLabel.fromAge)
        XCTAssertEqual(result.patch?.maxHr, 184)
    }

    func test_enteredMaxHr_doesNotInventABirthYear() {
        let result = apply(.confirmMaxHr(178), to: state(.maxHeartRate))
        XCTAssertEqual(result.state.answers.maxHr, 178)
        XCTAssertNil(result.state.answers.birthYear)
        XCTAssertEqual(result.state.answers.metrics.maxHr, MetricSourceLabel.entered)
        XCTAssertNil(result.patch?.birthYear)
    }

    func test_birthYearOutsideTheColumn_isRejected() {
        let result = apply(.confirmBirthYear(1919), to: state(.maxHeartRate))
        XCTAssertNil(result.state.answers.birthYear)
        XCTAssertNil(result.patch)
    }

    func test_durationDefaults_splitWeeklyHoursOnThe15MinuteGrid() {
        let days = ["Monday", "Wednesday", "Friday", "Saturday"]
        let durations = MetricEstimates.defaultDurations(days: days, weeklyHours: 5)
        XCTAssertEqual(durations["Monday"], 75)
        XCTAssertEqual(durations.values.reduce(0, +), 300)

        let short = MetricEstimates.defaultDurations(
            days: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"],
            weeklyHours: 2
        )
        XCTAssertTrue(short.values.allSatisfy { $0 == 30 })
    }

    func test_quickRepliesExistForEveryQuestion() {
        for step in OnboardingStep.allCases {
            var value = OnboardingState.fresh()
            value.step = step
            let replies = OnboardingCopy.replies(for: value)
            XCTAssertFalse(replies.isEmpty, "Missing quick replies for \(step)")
        }
    }

    // MARK: - Helpers

    private func completeAnswers() -> OnboardingAnswers {
        var answers = OnboardingAnswers.empty
        answers.raceObjective = .ironman703
        answers.raceDate = utc(2027, 5, 16)
        answers.targetTimeDecided = true
        answers.experienceYears = 3
        answers.currentWeeklyHours = 5
        answers.vma = 14
        answers.cssSecondsPer100m = 120
        answers.ftp = 180
        answers.maxHr = 184
        answers.birthYear = 1990
        answers.metrics = MetricsSource(vma: MetricSourceLabel.entered, css: MetricSourceLabel.entered, ftp: MetricSourceLabel.entered, maxHr: MetricSourceLabel.fromAge)
        answers.swimDays = ["Monday", "Wednesday"]
        answers.bikeDays = ["Tuesday", "Saturday"]
        answers.runDays = ["Thursday", "Sunday"]
        answers.monDuration = 60
        answers.tueDuration = 60
        answers.wedDuration = 60
        answers.thuDuration = 60
        answers.satDuration = 90
        answers.sunDuration = 45
        answers.durationsConfirmed = true
        answers.limiters = "none"
        return answers
    }

    private func makeUser() -> User {
        User(
            id: UUID(),
            email: "athlete@example.com",
            name: nil,
            raceObjective: nil,
            raceDate: nil,
            timeObjectiveMinutes: nil,
            vma: nil,
            cssSecondsPer100m: nil,
            ftp: nil,
            experienceYears: nil,
            currentWeeklyHours: nil,
            swimDays: nil,
            bikeDays: nil,
            runDays: nil,
            monDuration: nil,
            tueDuration: nil,
            wedDuration: nil,
            thuDuration: nil,
            friDuration: nil,
            satDuration: nil,
            sunDuration: nil,
            maxHr: nil,
            birthYear: nil,
            onboardingCompleted: false,
            stravaAthleteId: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}
