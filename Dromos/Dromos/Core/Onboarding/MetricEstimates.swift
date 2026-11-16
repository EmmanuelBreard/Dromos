//
//  MetricEstimates.swift
//  Dromos
//
//  One place for onboarding metric math. The coach function extracts what the
//  athlete said; these functions decide the number that is stored.
//

import Foundation

/// How a stored metric was obtained. Written into `users.metrics_source`.
/// Max heart rate from a birth year uses `estimated_from_age` because 220 − age
/// is neither a race result nor an experience-table guess.
enum MetricSourceLabel {
    static let entered = "entered"
    static let fromRace = "estimated_from_race"
    static let fromExperience = "estimated_from_experience"
    static let fromAge = "estimated_from_age"
}

enum RunDistance: String, Equatable {
    case fiveK = "5k"
    case tenK = "10k"

    var kilometers: Double { self == .fiveK ? 5 : 10 }
    var title: String { self == .fiveK ? "5K" : "10K" }
}

enum SwimDistance: String, Equatable {
    case fourHundred = "400"
    case fifteenHundred = "1500"

    var title: String { self == .fourHundred ? "400m" : "1500m" }
}

enum MetricEstimateOutcome: Equatable {
    case accept(Double)
    case suggest(seconds: Int, value: Double)
    case reject
}

enum MetricEstimates {

    /// Riegel's 1981 race-time exponent. VMA is taken as the speed of a
    /// flat-out 6-minute effort, which is the usual stand-in for vVO2max.
    static let riegelExponent = 1.06
    static let vmaEffortMinutes = 6.0

    static let vmaRange = 10.0...25.0
    static let cssRange = 25...300
    static let ftpRange = 50...500
    static let maxHrRange = 100...220
    static let birthYearRange = 1920...2030
    static let hoursRange = 0.0...25.0

    /// Entered CSS faster than this is treated as a typo. The database allows
    /// 25, which is faster than a human swim.
    static let enteredCssFloor = 55

    /// Just inside the men's world records, so a real elite time still passes
    /// and a 9-minute 5K does not.
    static let fiveKFloorSeconds = 12 * 60 + 30
    static let tenKFloorSeconds = 26 * 60
    static let swim400FloorSeconds = 3 * 60 + 50
    static let swim1500FloorSeconds = 14 * 60 + 45

    // MARK: - Run

    /// VMA in km/h from a 5K or 10K, rounded to one decimal.
    static func vma(distance: RunDistance, timeSeconds: Int) -> Double {
        let minutes = Double(timeSeconds) / 60
        guard minutes > 0 else { return 0 }
        let sixMinuteKm = distance.kilometers * pow(vmaEffortMinutes / minutes, 1 / riegelExponent)
        let kmPerHour = sixMinuteKm / (vmaEffortMinutes / 60)
        return (kmPerHour * 10).rounded() / 10
    }

    static func checkRun(distance: RunDistance, timeSeconds: Int) -> MetricEstimateOutcome {
        let value = vma(distance: distance, timeSeconds: timeSeconds)
        if isPlausibleRun(distance: distance, timeSeconds: timeSeconds, vma: value) {
            return .accept(value)
        }
        // A missing "1" is the common typo (9:00 meant 19:00). Try +10, then +20.
        for extra in [600, 1_200] {
            let bumped = timeSeconds + extra
            let bumpedValue = vma(distance: distance, timeSeconds: bumped)
            if isPlausibleRun(distance: distance, timeSeconds: bumped, vma: bumpedValue) {
                return .suggest(seconds: bumped, value: bumpedValue)
            }
        }
        return .reject
    }

    static func isPlausibleRun(distance: RunDistance, timeSeconds: Int, vma: Double) -> Bool {
        let floor = distance == .fiveK ? fiveKFloorSeconds : tenKFloorSeconds
        return timeSeconds >= floor && vmaRange.contains(vma)
    }

    // MARK: - Swim

    /// 400m time-trial pace is a little faster than CSS. Add 3 seconds per 100m.
    static func css(from400 seconds: Int) -> Int {
        Int((Double(seconds) / 4).rounded()) + 3
    }

    /// 1500m pace is a little slower than CSS. Subtract 2 seconds per 100m.
    static func css(from1500 seconds: Int) -> Int {
        Int((Double(seconds) / 15).rounded()) - 2
    }

    static func checkSwim(distance: SwimDistance, timeSeconds: Int) -> MetricEstimateOutcome {
        let value = distance == .fourHundred ? css(from400: timeSeconds) : css(from1500: timeSeconds)
        if isPlausibleSwim(distance: distance, timeSeconds: timeSeconds, css: value) {
            return .accept(Double(value))
        }
        for extra in [600, 1_200] {
            let bumped = timeSeconds + extra
            let bumpedValue = distance == .fourHundred ? css(from400: bumped) : css(from1500: bumped)
            if isPlausibleSwim(distance: distance, timeSeconds: bumped, css: bumpedValue) {
                return .suggest(seconds: bumped, value: Double(bumpedValue))
            }
        }
        return .reject
    }

    static func isPlausibleSwim(distance: SwimDistance, timeSeconds: Int, css: Int) -> Bool {
        let floor = distance == .fourHundred ? swim400FloorSeconds : swim1500FloorSeconds
        return timeSeconds >= floor && cssRange.contains(css)
    }

    static func acceptsEnteredCss(_ seconds: Int) -> Bool {
        seconds >= enteredCssFloor && cssRange.contains(seconds)
    }

    // MARK: - Bike

    /// Coggan: FTP is 95% of a 20-minute all-out average.
    static func ftp(fromTwentyMinute watts: Int) -> Int {
        Int((Double(watts) * 0.95).rounded())
    }

    static func acceptsFtp(_ watts: Int) -> Bool {
        ftpRange.contains(watts)
    }

    // MARK: - Heart rate

    /// 220 − age, clamped to the column check (100–220).
    static func maxHeartRate(birthYear: Int, currentYear: Int) -> Int {
        let computed = 220 - (currentYear - birthYear)
        return min(maxHrRange.upperBound, max(maxHrRange.lowerBound, computed))
    }

    static func acceptsBirthYear(_ year: Int) -> Bool {
        birthYearRange.contains(year)
    }

    static func acceptsMaxHr(_ bpm: Int) -> Bool {
        maxHrRange.contains(bpm)
    }

    // MARK: - Experience table

    /// Conservative starting points when the athlete has no test and no recent time.
    /// Rows are weekly-hour bands, columns are experience bands.
    /// Hours: under 3, 3–6, 6–10, 10+. Experience: just starting, 1 year, 2–4, 5+.
    static let vmaTable: [[Double]] = [
        [11.5, 12.0, 12.5, 13.0],
        [12.0, 13.0, 14.0, 14.5],
        [12.5, 13.5, 14.5, 15.5],
        [13.0, 14.0, 15.5, 16.5],
    ]

    /// Seconds per 100m. Higher is slower, so beginners get more time.
    static let cssTable: [[Int]] = [
        [150, 140, 130, 120],
        [140, 130, 120, 110],
        [135, 125, 115, 105],
        [130, 120, 110, 100],
    ]

    static let ftpTable: [[Int]] = [
        [120, 140, 160, 180],
        [140, 160, 185, 210],
        [155, 180, 210, 240],
        [170, 200, 230, 260],
    ]

    static func hoursBand(_ hours: Double) -> Int {
        if hours < 3 { return 0 }
        if hours < 6 { return 1 }
        if hours < 10 { return 2 }
        return 3
    }

    static func experienceBand(_ years: Int) -> Int {
        if years <= 0 { return 0 }
        if years <= 1 { return 1 }
        if years <= 4 { return 2 }
        return 3
    }

    static func estimatedVma(experienceYears: Int?, weeklyHours: Double?) -> Double {
        let row = hoursBand(weeklyHours ?? 0)
        let column = experienceBand(experienceYears ?? 0)
        return vmaTable[row][column]
    }

    static func estimatedCss(experienceYears: Int?, weeklyHours: Double?) -> Int {
        let row = hoursBand(weeklyHours ?? 0)
        let column = experienceBand(experienceYears ?? 0)
        return cssTable[row][column]
    }

    static func estimatedFtp(experienceYears: Int?, weeklyHours: Double?) -> Int {
        let row = hoursBand(weeklyHours ?? 0)
        let column = experienceBand(experienceYears ?? 0)
        return ftpTable[row][column]
    }

    // MARK: - Day length

    /// Spread weekly hours across the selected days. Each day is a multiple of
    /// 15 minutes inside the column check (30–420). A short week still gets the
    /// 30-minute minimum, because a 0-minute day is rejected by the database.
    static func defaultDurations(days: [String], weeklyHours: Double) -> [String: Int] {
        let ordered = Weekday.ordered.filter { days.contains($0) }
        guard !ordered.isEmpty else { return [:] }
        let target = Int((weeklyHours * 60).rounded())
        let even = Double(target) / Double(ordered.count)
        var each = Int((even / 15).rounded()) * 15
        each = min(420, max(30, each))
        var result = Dictionary(uniqueKeysWithValues: ordered.map { ($0, each) })
        var sum = each * ordered.count
        var index = 0
        var steps = 0
        while sum + 15 <= target && steps < 64 {
            let day = ordered[index % ordered.count]
            if let current = result[day], current + 15 <= 420 {
                result[day] = current + 15
                sum += 15
            }
            index += 1
            steps += 1
            if ordered.allSatisfy({ (result[$0] ?? 420) >= 420 }) { break }
        }
        return result
    }

    static func snapDuration(_ minutes: Int) -> Int? {
        let snapped = Int((Double(minutes) / 15.0).rounded()) * 15
        guard (30...420).contains(snapped) else { return nil }
        return snapped
    }

    static func acceptsHours(_ hours: Double) -> Bool {
        hoursRange.contains(hours)
    }

    static func roundHours(_ hours: Double) -> Double {
        (hours * 10).rounded() / 10
    }
}
