//
//  OnboardingCopy.swift
//  Dromos
//
//  Scripted coach lines. The model may replace a reaction, but the questions
//  and the numbers always come from here.
//

import Foundation

enum OnboardingCopy {

    static func openingLines(for state: OnboardingState, now: Date) -> [String] {
        if state.step == .raceType {
            return ["I'm your coach. We'll build your plan together — a few short questions, then I'll write your training. What are you training for? I can build an Olympic or an Ironman 70.3."]
        }
        var lines = ["Welcome back. We'll pick up where you left off."]
        lines.append(contentsOf: questionLines(for: state, now: now))
        return lines
    }

    static func completedSummaries(in answers: OnboardingAnswers, before step: OnboardingStep) -> [(OnboardingStep, String)] {
        var rows: [(OnboardingStep, String)] = []
        if stepIsAfter(.swimDays, step), !answers.swimDays.isEmpty {
            rows.append((.swimDays, summary(sport: .swim, days: answers.swimDays)))
        }
        if stepIsAfter(.bikeDays, step), !answers.bikeDays.isEmpty {
            rows.append((.bikeDays, summary(sport: .bike, days: answers.bikeDays)))
        }
        if stepIsAfter(.runDays, step), !answers.runDays.isEmpty {
            rows.append((.runDays, summary(sport: .run, days: answers.runDays)))
        }
        if stepIsAfter(.dailyDuration, step), answers.durationsConfirmed {
            rows.append((.dailyDuration, durationSummary(answers)))
        }
        return rows
    }

    static func questionLines(for state: OnboardingState, now: Date) -> [String] {
        switch state.mode {
        case .pickTime:
            return ["What time are you aiming for?"]
        case .enterVma:
            return ["What's your VMA, in km/h?"]
        case .pickRunDistance:
            return ["Was that a 5K or a 10K?"]
        case .enterRunTime(let distance):
            return ["What was your \(distance.title) time?"]
        case .enterCss:
            return ["What's your CSS, per 100m?"]
        case .pickSwimDistance:
            return ["Was that a 400m or a 1500m?"]
        case .enterSwimTime(let distance):
            return ["What was your \(distance.title) time?"]
        case .enterTypicalPace:
            return ["What pace do you usually hold per 100m?"]
        case .enterFtp:
            return ["What's your FTP, in watts?"]
        case .enterTwenty:
            return ["What was your average power for those 20 minutes?"]
        case .enterMaxHr:
            return ["What's your max heart rate?"]
        case .enterBirthYear:
            return ["What year were you born? I'll estimate max heart rate as 220 minus your age."]
        case .confirmSuggestion, .confirmLimitersNote:
            return []
        case .ask:
            return [question(for: state.activeStep)]
        }
    }

    static func question(for step: OnboardingStep) -> String {
        switch step {
        case .raceType:
            return "What are you training for? Olympic or Ironman 70.3."
        case .raceDate:
            return "When is race day? A plan needs at least a week, and it starts tomorrow."
        case .targetTime:
            return "Do you have a finish time in mind, or is the goal to finish?"
        case .experience:
            return "How long have you been training for endurance sports?"
        case .weeklyHours:
            return "Over the last 4 weeks, about how many hours a week have you trained?"
        case .run:
            return "Let's set your run speed. Do you know your VMA, or do you have a recent 5K or 10K?"
        case .swim:
            return "Now swimming. Do you know your CSS per 100m, a recent 400m or 1500m, or a typical pace?"
        case .bike:
            return "And the bike. Do you know your FTP, or a recent 20-minute all-out power?"
        case .maxHeartRate:
            return "What's your max heart rate? If you don't know it, your year of birth is enough."
        case .swimDays:
            return "Now let's set up your week. Swimming first."
        case .bikeDays:
            return "Which days can you ride?"
        case .runDays:
            return "Which days can you run?"
        case .dailyDuration:
            return "How long can you train on each of those days?"
        case .limiters:
            return "Any injuries or weak spots I should plan around?"
        case .recap:
            return "Here's what I have. Tap a line to change it, then get your plan."
        }
    }

    static func replies(for state: OnboardingState) -> [QuickReply] {
        if state.mode == .confirmSuggestion {
            return [QuickReply(id: .yesSuggestion, title: "Yes, that's the one"), QuickReply(id: .noSuggestion, title: "No, I'll re-enter")]
        }
        if state.mode == .confirmLimitersNote {
            return [QuickReply(id: .saveNote, title: "Save note"), QuickReply(id: .noLimiters, title: "None")]
        }
        switch state.mode {
        case .pickRunDistance:
            return [QuickReply(id: .run5k, title: "5K"), QuickReply(id: .run10k, title: "10K")]
        case .pickSwimDistance:
            return [QuickReply(id: .swim400, title: "400m"), QuickReply(id: .swim1500, title: "1500m")]
        case .enterVma, .enterRunTime, .enterCss, .enterSwimTime, .enterTypicalPace, .enterFtp, .enterTwenty, .enterMaxHr, .enterBirthYear, .pickTime:
            return []
        case .ask, .confirmSuggestion, .confirmLimitersNote:
            break
        }
        switch state.activeStep {
        case .raceType:
            return [QuickReply(id: .olympic, title: "Olympic"), QuickReply(id: .ironman703, title: "Ironman 70.3")]
        case .raceDate:
            return [
                QuickReply(id: .weeks8, title: "In 8 weeks"),
                QuickReply(id: .weeks16, title: "In 16 weeks"),
                QuickReply(id: .months6, title: "In 6 months"),
            ]
        case .targetTime:
            return [QuickReply(id: .justFinish, title: "Just finish"), QuickReply(id: .haveTime, title: "I have a time")]
        case .experience:
            return [
                QuickReply(id: .expStarting, title: "Just starting"),
                QuickReply(id: .expOne, title: "1 year"),
                QuickReply(id: .expMid, title: "2–4 years"),
                QuickReply(id: .expVeteran, title: "5+ years"),
            ]
        case .weeklyHours:
            return [
                QuickReply(id: .hours2, title: "Under 3h"),
                QuickReply(id: .hours4, title: "3–5h"),
                QuickReply(id: .hours6_5, title: "5–8h"),
                QuickReply(id: .hours10, title: "8–12h"),
                QuickReply(id: .hours14, title: "12h+"),
            ]
        case .run:
            return [
                QuickReply(id: .knowVma, title: "I know my VMA"),
                QuickReply(id: .haveRunRace, title: "I have a race time"),
                QuickReply(id: .noRunIdea, title: "No idea"),
            ]
        case .swim:
            return [
                QuickReply(id: .knowCss, title: "I know my CSS"),
                QuickReply(id: .swim400, title: "400m time"),
                QuickReply(id: .swim1500, title: "1500m time"),
                QuickReply(id: .typicalPace, title: "Typical pace"),
                QuickReply(id: .noSwimIdea, title: "No idea"),
            ]
        case .bike:
            return [
                QuickReply(id: .knowFtp, title: "I know my FTP"),
                QuickReply(id: .twentyMin, title: "20-min power"),
                QuickReply(id: .noPower, title: "I don't use a power meter"),
                QuickReply(id: .noBikeIdea, title: "No idea"),
            ]
        case .maxHeartRate:
            return [
                QuickReply(id: .knowMaxHr, title: "I know my max HR"),
                QuickReply(id: .knowBirthYear, title: "Use my year of birth"),
            ]
        case .swimDays, .bikeDays, .runDays:
            return [
                QuickReply(id: .weekdays, title: "Weekdays"),
                QuickReply(id: .weekends, title: "Weekends"),
                QuickReply(id: .anyDay, title: "Any day"),
            ]
        case .dailyDuration:
            return [QuickReply(id: .keepDurations, title: "Use these times")]
        case .limiters:
            return [QuickReply(id: .noLimiters, title: "None")]
        case .recap:
            return [QuickReply(id: .getPlan, title: "Get my plan")]
        }
    }

    static func fallbackReaction(after step: OnboardingStep, answers: OnboardingAnswers, now: Date) -> String? {
        switch step {
        case .raceType:
            return answers.raceObjective == .ironman703
                ? "A 70.3. We'll build the endurance for it."
                : "Olympic it is. Fast and sharp."
        case .raceDate:
            guard let date = answers.raceDate else { return "Got the date." }
            return "Race day is \(displayDate(date)). \(horizonPhrase(from: now, to: date, calendar: utcCalendar))."
        case .targetTime:
            if let minutes = answers.timeObjectiveMinutes {
                return "We'll aim around \(formatClock(minutes: minutes))."
            }
            return "Finishing is a fine goal. We'll train so you arrive ready."
        case .experience:
            return "Thanks — that sets the starting point."
        case .weeklyHours:
            return hoursReaction(answers: answers, now: now)
        case .limiters:
            if answers.limiters == "none" {
                return "Good. We'll keep the plan balanced."
            }
            return "I'll plan around that. If it's painful or getting worse, please see a doctor or physio — I can't diagnose it."
        default:
            return nil
        }
    }

    static func hoursReaction(answers: OnboardingAnswers, now: Date) -> String {
        let hours = answers.currentWeeklyHours ?? 0
        let hoursText = formatHours(hours)
        guard let race = answers.raceObjective else {
            return "\(hoursText) a week. I'll build from there."
        }
        let horizon = answers.raceDate.map { horizonPhrase(from: now, to: $0, calendar: utcCalendar) } ?? "on that timeline"
        if race == .ironman703 && hours <= 6 {
            return "A 70.3 \(horizon) on \(hoursText) a week is ambitious but doable. We'll build your bike endurance first."
        }
        if race == .olympic && hours < 3 {
            return "An Olympic on \(hoursText) a week is a light start. We'll build steadily."
        }
        if hours >= 10 {
            return "You're already at \(hoursText) a week. I'll add load carefully."
        }
        let name = race == .ironman703 ? "70.3" : "Olympic"
        return "\(hoursText) a week is a solid base for a \(name)."
    }

    static func vmaLine(value: Double, source: String?) -> String {
        let number = formatVma(value)
        if source == MetricSourceLabel.fromExperience {
            return "I'll start your VMA at \(number) km/h. That's a conservative estimate from your experience and weekly hours, and I'll refine it."
        }
        return "That puts your VMA around \(number) km/h."
    }

    static func cssLine(seconds: Int, source: String?) -> String {
        let pace = formatPace(seconds)
        if source == MetricSourceLabel.fromExperience {
            return "I'll start your CSS at \(pace) per 100m. Conservative estimate — I'll refine it."
        }
        return "That puts your CSS around \(pace) per 100m."
    }

    static func ftpLine(watts: Int, source: String?, twentyMinute: Int?) -> String {
        if source == MetricSourceLabel.fromExperience {
            return "I'll start your FTP at \(watts) W. Conservative estimate from your experience and hours, and I'll refine it."
        }
        if let twentyMinute {
            return "\(twentyMinute) W for 20 minutes is about \(watts) W FTP."
        }
        return "That puts your FTP around \(watts) W."
    }

    static func maxHrLine(bpm: Int, birthYear: Int?) -> String {
        if let birthYear {
            return "I'll use \(bpm) bpm — 220 minus your age, from \(birthYear)."
        }
        return "\(bpm) bpm, got it."
    }

    static func tooSoon() -> String {
        "A plan needs at least a week, and it starts tomorrow. That date is too soon — pick one a bit further out."
    }

    static func unsupportedRace() -> String {
        "I coach Olympic and Ironman 70.3 for now. Sprint and full Ironman aren't in yet — which of these two are you racing?"
    }

    static func didYouMean(distance: String, original: String, suggested: String) -> String {
        "A \(distance) in \(original) would be faster than a world record. Did you mean \(suggested)?"
    }

    static func checkThatTime() -> String {
        "That time doesn't look right. Send it again, with the distance."
    }

    static func checkThatNumber() -> String {
        "That number is outside the range I can train from. Try it once more."
    }

    static func emptyDaysHint() -> String {
        "Pick at least one day."
    }

    static func coachUnavailableFollowUp() -> String {
        "I missed that — the connection dropped. Use one of the buttons, or send it once more."
    }

    static func saveNotePrompt() -> String {
        "I couldn't check that just now. If it's an injury or a weak spot, tap Save note and I'll keep your words. If it was something else, tap None."
    }

    static func gentleRedirect() -> String {
        "Love the enthusiasm, but I still need an answer I can train from."
    }

    static func summary(sport: OnboardingSport, days: [String]) -> String {
        let names = days.map(Weekday.short).joined(separator: ", ")
        return "\(sport.title): \(names)"
    }

    static func durationSummary(_ answers: OnboardingAnswers) -> String {
        let parts = answers.trainingDays.map { day in
            let minutes = answers.duration(for: day) ?? 0
            return "\(Weekday.short(day)) \(formatDuration(minutes))"
        }
        return "Time: " + parts.joined(separator: ", ")
    }

    struct RecapRow: Equatable, Identifiable {
        var id: OnboardingStep { step }
        var step: OnboardingStep
        var text: String
    }

    static func recapRows(_ answers: OnboardingAnswers) -> [RecapRow] {
        var rows: [RecapRow] = []
        rows.append(RecapRow(step: .raceType, text: "Race: \(answers.raceObjective?.rawValue ?? "—")"))
        rows.append(RecapRow(step: .raceDate, text: "Date: \(answers.raceDate.map(displayDate) ?? "—")"))
        let time = answers.timeObjectiveMinutes.map { formatClock(minutes: $0) } ?? "Just finish"
        rows.append(RecapRow(step: .targetTime, text: "Goal: \(time)"))
        rows.append(RecapRow(step: .experience, text: "Experience: \(experienceLabel(answers.experienceYears))"))
        rows.append(RecapRow(step: .weeklyHours, text: "Recent training: \(answers.currentWeeklyHours.map(formatHours) ?? "—") a week"))
        rows.append(RecapRow(step: .run, text: "VMA: \(answers.vma.map { formatVma($0) + " km/h" } ?? "—")\(sourceSuffix(answers.metrics.vma))"))
        rows.append(RecapRow(step: .swim, text: "CSS: \(answers.cssSecondsPer100m.map { formatPace($0) + " /100m" } ?? "—")\(sourceSuffix(answers.metrics.css))"))
        rows.append(RecapRow(step: .bike, text: "FTP: \(answers.ftp.map { "\($0) W" } ?? "—")\(sourceSuffix(answers.metrics.ftp))"))
        let hr = answers.maxHr.map { "\($0) bpm" } ?? "—"
        rows.append(RecapRow(step: .maxHeartRate, text: "Max HR: \(hr)\(sourceSuffix(answers.metrics.maxHr))"))
        rows.append(RecapRow(step: .swimDays, text: summary(sport: .swim, days: answers.swimDays)))
        rows.append(RecapRow(step: .bikeDays, text: summary(sport: .bike, days: answers.bikeDays)))
        rows.append(RecapRow(step: .runDays, text: summary(sport: .run, days: answers.runDays)))
        rows.append(RecapRow(step: .dailyDuration, text: durationSummary(answers)))
        let note = answers.limiters == "none" ? "None" : (answers.limiters ?? "—")
        rows.append(RecapRow(step: .limiters, text: "Limiters: \(note)"))
        return rows
    }

    static func sourceSuffix(_ source: String?) -> String {
        switch source {
        case MetricSourceLabel.fromRace: return " (from a recent time)"
        case MetricSourceLabel.fromExperience: return " (starting estimate)"
        case MetricSourceLabel.fromAge: return " (from age)"
        case MetricSourceLabel.entered: return ""
        default: return ""
        }
    }

    static func experienceLabel(_ years: Int?) -> String {
        switch years {
        case nil: return "—"
        case 0: return "Just starting"
        case 1: return "1 year"
        default: return "\(years!) years"
        }
    }

    static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    static func formatClock(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return String(format: "%dh %02dmin", hours, mins)
    }

    static func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours == 0 { return "\(mins) min" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)min"
    }

    static func formatPace(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func formatRaceClock(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func formatHours(_ hours: Double) -> String {
        let number = hours == hours.rounded() ? "\(Int(hours))" : String(format: "%.1f", hours)
        let unit = hours == 1 ? "hour" : "hours"
        return "\(number) \(unit)"
    }

    static func formatVma(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func horizonPhrase(from now: Date, to race: Date, calendar: Calendar) -> String {
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: race)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        if days >= 45 {
            let months = max(1, Int((Double(days) / 30.0).rounded()))
            return "in about \(months) months"
        }
        let weeks = max(1, days / 7)
        return "in \(weeks) weeks"
    }

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private static func stepIsAfter(_ earlier: OnboardingStep, _ current: OnboardingStep) -> Bool {
        let all = OnboardingStep.allCases
        guard let left = all.firstIndex(of: earlier), let right = all.firstIndex(of: current) else { return false }
        return right > left
    }
}
