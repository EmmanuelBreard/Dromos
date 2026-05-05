//
//  PaceMathTests.swift
//  DromosTests
//
//  Unit tests for PaceMath pure functions (DRO-262 / DRO-264).
//
//  Covers:
//  - `kmH(forSliderValue:discipline:)` → speed conversions
//  - `secondsToCover(km:atSpeedKmH:)` → finish time calculations
//  - `formatTime(_:)` → M:SS and H:MM:SS formatting
//  - `formatPacePerKm(secondsPerKm:)` → pace formatting
//  - Slider boundary values produce finite, positive results
//

import XCTest
@testable import Dromos

// MARK: - Run

final class PaceMathRunTests: XCTestCase {

    // MARK: Speed conversion

    func test_run_sliderValue120_returns12kmH() {
        XCTAssertEqual(kmH(forSliderValue: 120, discipline: .run), 12.0, accuracy: 0.001)
    }

    // MARK: Finish times at 12.0 km/h

    func test_run_12kmH_1km_is300s() {
        let t = secondsToCover(km: 1.0, atSpeedKmH: 12.0)
        XCTAssertEqual(t, 300.0, accuracy: 1.0)  // 5:00
        XCTAssertEqual(formatTime(t), "5:00")
    }

    func test_run_12kmH_10km_is3000s() {
        let t = secondsToCover(km: 10.0, atSpeedKmH: 12.0)
        XCTAssertEqual(t, 3000.0, accuracy: 1.0)  // 50:00
        XCTAssertEqual(formatTime(t), "50:00")
    }

    /// Marathon at 12.0 km/h.
    /// Exact: 42.195 / 12.0 × 3600 = 12658.5 s → rounds to 12659 s = 3:30:59.
    /// (Note: the spec's "3:30:30" figure is a transcription error; 3:30:59 is the
    /// correct result from the formula.  ±2 s tolerance absorbs floating-point drift.)
    func test_run_12kmH_marathon_isApprox3h30m59s() {
        let t = secondsToCover(km: 42.195, atSpeedKmH: 12.0)
        XCTAssertEqual(t, 12658.5, accuracy: 2.0)
        // Formatted representation
        let formatted = formatTime(t)
        XCTAssertEqual(formatted, "3:30:59")
    }
}

// MARK: - Bike

final class PaceMathBikeTests: XCTestCase {

    // MARK: Speed conversion

    func test_bike_sliderValue320_returns32kmH() {
        XCTAssertEqual(kmH(forSliderValue: 320, discipline: .bike), 32.0, accuracy: 0.001)
    }

    // MARK: Finish times at 32.0 km/h

    func test_bike_32kmH_40km_is4500s() {
        let t = secondsToCover(km: 40.0, atSpeedKmH: 32.0)
        XCTAssertEqual(t, 4500.0, accuracy: 1.0)  // 1:15:00
        XCTAssertEqual(formatTime(t), "1:15:00")
    }

    func test_bike_32kmH_180km_is20250s() {
        let t = secondsToCover(km: 180.0, atSpeedKmH: 32.0)
        XCTAssertEqual(t, 20250.0, accuracy: 1.0)  // 5:37:30
        XCTAssertEqual(formatTime(t), "5:37:30")
    }
}

// MARK: - Swim

final class PaceMathSwimTests: XCTestCase {

    // MARK: Speed conversion

    /// CSS 110 s/100m → speed = 360 / 110 ≈ 3.2727 km/h.
    func test_swim_sliderValue110_returnsCorrectSpeed() {
        let speed = kmH(forSliderValue: 110, discipline: .swim)
        XCTAssertEqual(speed, 360.0 / 110.0, accuracy: 0.001)
    }

    // MARK: Finish times at CSS 110 s/100m

    func test_swim_css110_1500m_is1650s() {
        let speed = kmH(forSliderValue: 110, discipline: .swim)
        let t = secondsToCover(km: 1.5, atSpeedKmH: speed)
        XCTAssertEqual(t, 1650.0, accuracy: 1.0)  // 27:30
        XCTAssertEqual(formatTime(t), "27:30")
    }

    func test_swim_css110_3800m_is4180s() {
        let speed = kmH(forSliderValue: 110, discipline: .swim)
        let t = secondsToCover(km: 3.8, atSpeedKmH: speed)
        XCTAssertEqual(t, 4180.0, accuracy: 1.0)  // 1:09:40
        XCTAssertEqual(formatTime(t), "1:09:40")
    }
}

// MARK: - Formatting

final class PaceMathFormattingTests: XCTestCase {

    // MARK: formatTime

    func test_formatTime_subHour_showsMSS() {
        XCTAssertEqual(formatTime(300),   "5:00")   // exactly 5 min
        XCTAssertEqual(formatTime(3000),  "50:00")  // exactly 50 min
        XCTAssertEqual(formatTime(3599),  "59:59")  // just under 1 h
    }

    func test_formatTime_oneHourPlus_showsHMMSS() {
        XCTAssertEqual(formatTime(3600),  "1:00:00")  // exactly 1 h
        XCTAssertEqual(formatTime(4500),  "1:15:00")  // 1 h 15 min
        XCTAssertEqual(formatTime(20250), "5:37:30")  // 5 h 37 min 30 s
    }

    func test_formatTime_zero_showsZeroMSS() {
        XCTAssertEqual(formatTime(0), "0:00")
    }

    // MARK: formatPacePerKm

    func test_formatPacePerKm_300s_shows5min00() {
        XCTAssertEqual(formatPacePerKm(secondsPerKm: 300), "5:00 / km")
    }

    func test_formatPacePerKm_270s_shows4min30() {
        XCTAssertEqual(formatPacePerKm(secondsPerKm: 270), "4:30 / km")
    }
}

// MARK: - Boundary values

final class PaceMathBoundaryTests: XCTestCase {

    /// For every discipline, slider at min and max must produce a finite, positive speed
    /// and a positive finish time for each configured distance.
    func test_allDisciplines_sliderAtMinAndMax_producePositiveFiniteTimes() {
        for discipline in Discipline.allCases {
            let config = discipline.config
            for sliderVal in [config.min, config.max] {
                let speed = kmH(forSliderValue: sliderVal, discipline: discipline)
                XCTAssertFalse(speed.isNaN,      "\(discipline) slider=\(sliderVal): speed is NaN")
                XCTAssertFalse(speed.isInfinite, "\(discipline) slider=\(sliderVal): speed is infinite")
                XCTAssertGreaterThan(speed, 0,   "\(discipline) slider=\(sliderVal): speed must be > 0")

                for entry in config.distances {
                    let t = secondsToCover(km: entry.km, atSpeedKmH: speed)
                    XCTAssertFalse(t.isNaN,      "\(discipline)/\(entry.name) slider=\(sliderVal): time is NaN")
                    XCTAssertGreaterThan(t, 0,   "\(discipline)/\(entry.name) slider=\(sliderVal): time must be > 0")
                }
            }
        }
    }
}

// MARK: - PaceSeed factory

final class PaceSeedTests: XCTestCase {

    /// Unknown sport → nil seed.
    func test_from_unknownSport_returnsNil() {
        let session = makePlanSession(sport: "strength")
        XCTAssertNil(PaceSeed.from(session: session, profile: nil))
    }

    /// Run with known VMA.
    func test_from_runWithVma_usesVmaSliderValue() {
        let session = makePlanSession(sport: "run")
        var profile = makeMinimalUser()
        profile.vma = 14.0
        let seed = PaceSeed.from(session: session, profile: profile)
        XCTAssertNotNil(seed)
        XCTAssertEqual(seed?.discipline, .run)
        XCTAssertEqual(seed?.sliderValue, 140)  // 14.0 × 10 = 140
    }

    /// Run with no VMA → falls back to default (120).
    func test_from_runNoVma_usesDefault() {
        let session = makePlanSession(sport: "run")
        let seed = PaceSeed.from(session: session, profile: nil)
        XCTAssertEqual(seed?.sliderValue, Discipline.run.config.defaultValue)
    }

    /// Swim with known CSS.
    func test_from_swimWithCSS_usesCSSSliderValue() {
        let session = makePlanSession(sport: "swim")
        var profile = makeMinimalUser()
        profile.cssSecondsPer100m = 95
        let seed = PaceSeed.from(session: session, profile: profile)
        XCTAssertEqual(seed?.discipline, .swim)
        XCTAssertEqual(seed?.sliderValue, 95)
    }

    /// Bike always returns the default in V0.
    func test_from_bike_returnsDefault() {
        let session = makePlanSession(sport: "bike")
        let seed = PaceSeed.from(session: session, profile: nil)
        XCTAssertEqual(seed?.discipline, .bike)
        XCTAssertEqual(seed?.sliderValue, Discipline.bike.config.defaultValue)
    }

    /// VMA that would exceed max is clamped to max.
    func test_from_runVmaClamped_whenAboveMax() {
        let session = makePlanSession(sport: "run")
        var profile = makeMinimalUser()
        profile.vma = 999.0  // absurdly high
        let seed = PaceSeed.from(session: session, profile: profile)
        XCTAssertEqual(seed?.sliderValue, Discipline.run.config.max)
    }

    /// CSS below slider min is clamped to min.
    func test_from_swimCSSClamped_whenBelowMin() {
        let session = makePlanSession(sport: "swim")
        var profile = makeMinimalUser()
        profile.cssSecondsPer100m = 1  // below 60
        let seed = PaceSeed.from(session: session, profile: profile)
        XCTAssertEqual(seed?.sliderValue, Discipline.swim.config.min)
    }
}

// MARK: - Test helpers

/// Minimal `PlanSession` stub for testing the sport mapping.
private func makePlanSession(sport: String) -> PlanSession {
    PlanSession(
        id: UUID(),
        weekId: UUID(),
        day: "Monday",
        sport: sport,
        type: "Easy",
        templateId: "test-template",
        durationMinutes: 60,
        isBrick: false,
        notes: nil,
        orderInDay: 0,
        feedback: nil,
        matchedActivityId: nil,
        structure: nil
    )
}

/// Minimal `User` stub — fills only the required non-optional fields.
private func makeMinimalUser() -> User {
    User(
        id: UUID(),
        email: "test@dromos.app",
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
        createdAt: Date(),
        updatedAt: Date()
    )
}
