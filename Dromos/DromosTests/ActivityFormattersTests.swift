//
//  ActivityFormattersTests.swift
//  DromosTests
//
//  Unit tests for ActivityFormatters pure functions (DRO-267 / DRO-263).
//
//  Covers:
//  - `ActivityFormatters.formatDuration(seconds:)` — compact duration formatting
//  - `ActivityFormatters.formatDistance(meters:)` — km string with integer/decimal rules
//  - `ActivityFormatters.formatPaceRunPerKm(speedMps:)` — M:SS/km from m/s
//  - `ActivityFormatters.formatPaceSwimPer100m(speedMps:)` — M:SS/100m from m/s
//  - `ActivityFormatters.formatSpeedKmh(speedMps:)` — X.X km/h from m/s
//  - `ActivityFormatters.formatPower(watts:)` — integer W string
//  - `ActivityFormatters.formatHR(bpm:)` — integer bpm string
//  - Boundary cases: sub-1-min duration, exactly 60 min, pace boundary at 359.7 s,
//    fractional-km rendering near integer thresholds, speed conversion, zero guards.
//

import XCTest
@testable import Dromos

// MARK: - Duration

final class ActivityFormatters_DurationTests: XCTestCase {

    // MARK: Sub-hour formatting

    func test_duration_45min_showsApostrophe() {
        XCTAssertEqual(ActivityFormatters.formatDuration(seconds: 2700), "45'")
    }

    func test_duration_52min_showsApostrophe() {
        XCTAssertEqual(ActivityFormatters.formatDuration(seconds: 3120), "52'")
    }

    func test_duration_subMinute_shows0() {
        // 45 seconds → rounds down to 0 whole minutes → "0'"
        XCTAssertEqual(ActivityFormatters.formatDuration(seconds: 45), "0'")
    }

    func test_duration_zero_shows0() {
        XCTAssertEqual(ActivityFormatters.formatDuration(seconds: 0), "0'")
    }

    // MARK: Hour boundary

    /// Exactly 60 minutes must produce "1h 00'" (not "60'").
    func test_duration_exactly60min_shows1hWith00() {
        XCTAssertEqual(ActivityFormatters.formatDuration(seconds: 3600), "1h 00'")
    }

    // MARK: Multi-hour formatting

    func test_duration_1h30min_showsCorrectFormat() {
        XCTAssertEqual(ActivityFormatters.formatDuration(seconds: 5400), "1h 30'")
    }

    func test_duration_2h5min_showsLeadingZeroOnMinutes() {
        // 2h 05' — minutes < 10 must be zero-padded
        XCTAssertEqual(ActivityFormatters.formatDuration(seconds: 7500), "2h 05'")
    }

    func test_duration_3h0min_showsZeroPaddedMinutes() {
        XCTAssertEqual(ActivityFormatters.formatDuration(seconds: 10800), "3h 00'")
    }
}

// MARK: - Distance

final class ActivityFormatters_DistanceTests: XCTestCase {

    // MARK: Clean-integer rendering (fractional < 0.05)

    /// 10 000 m → exactly 10.0 km → integer form.
    func test_distance_10km_showsInteger() {
        XCTAssertEqual(ActivityFormatters.formatDistance(meters: 10000), "10 km")
    }

    /// 970 m → 0.97 km → fractional part 0.97 > 0.95 → rounds to 1 km.
    func test_distance_970m_roundsUpToInteger() {
        XCTAssertEqual(ActivityFormatters.formatDistance(meters: 970), "1 km")
    }

    /// 1 020 m → 1.02 km → fractional part 0.02 < 0.05 → rounds to 1 km.
    func test_distance_1020m_roundsDownToInteger() {
        XCTAssertEqual(ActivityFormatters.formatDistance(meters: 1020), "1 km")
    }

    // MARK: Decimal rendering (fractional ≥ 0.05 and ≤ 0.95)

    /// 1 500 m → 1.5 km → fractional part 0.50 → decimal form.
    func test_distance_1500m_showsDecimal() {
        XCTAssertEqual(ActivityFormatters.formatDistance(meters: 1500), "1.5 km")
    }

    /// 10 500 m → 10.5 km → decimal form.
    func test_distance_10500m_showsDecimal() {
        XCTAssertEqual(ActivityFormatters.formatDistance(meters: 10500), "10.5 km")
    }

    /// 42 195 m → 42.195 km → 1 decimal → "42.2 km".
    func test_distance_marathon_showsOneDecimal() {
        XCTAssertEqual(ActivityFormatters.formatDistance(meters: 42195), "42.2 km")
    }

    // MARK: Zero guard (callers should guard; verify sensible output)

    func test_distance_zero_returnsZeroKm() {
        XCTAssertEqual(ActivityFormatters.formatDistance(meters: 0), "0 km")
    }
}

// MARK: - Run Pace

final class ActivityFormatters_RunPaceTests: XCTestCase {

    // MARK: Typical paces

    /// 3.333… m/s → 300 s/km → "5:00/km".
    func test_runPace_exactlyFiveMinKm() {
        let mps = 1000.0 / 300.0  // exactly 5:00/km
        XCTAssertEqual(ActivityFormatters.formatPaceRunPerKm(speedMps: mps), "5:00/km")
    }

    /// 3.704 m/s → ~270 s/km → "4:30/km".
    func test_runPace_4min30() {
        let mps = 1000.0 / 270.0
        XCTAssertEqual(ActivityFormatters.formatPaceRunPerKm(speedMps: mps), "4:30/km")
    }

    // MARK: Boundary — pace near a minute crossover

    /// 359.7 s/km must produce "6:00/km" via round-then-decompose. Naive truncation would
    /// produce "5:59/km" (Int(359.7) = 359 → 5 min 59 s); the rounding strategy lifts to 360 s
    /// before decomposition so we get 6 min 0 s.
    func test_runPace_boundary359point7s_roundsTo6min00() {
        // 1000 / mps = 359.7  →  mps = 1000 / 359.7
        let mps = 1000.0 / 359.7
        // 359.7.rounded() = 360 → 360/60 = 6 min, 360%60 = 0 s → "6:00/km"
        XCTAssertEqual(ActivityFormatters.formatPaceRunPerKm(speedMps: mps), "6:00/km")
    }

    /// 299.5 s/km rounds to 300 s → "5:00/km" (not "4:59/km" from naive truncation).
    func test_runPace_boundary299point5s_roundsTo5min00() {
        let mps = 1000.0 / 299.5
        XCTAssertEqual(ActivityFormatters.formatPaceRunPerKm(speedMps: mps), "5:00/km")
    }

    // MARK: Zero / invalid guard

    func test_runPace_zeroSpeed_returnsFallback() {
        XCTAssertEqual(ActivityFormatters.formatPaceRunPerKm(speedMps: 0), "0:00/km")
    }
}

// MARK: - Swim Pace

final class ActivityFormatters_SwimPaceTests: XCTestCase {

    // MARK: Typical paces

    /// 1.667 m/s → 60 s/100m → "1:00/100m".
    func test_swimPace_exactly1min() {
        let mps = 100.0 / 60.0
        XCTAssertEqual(ActivityFormatters.formatPaceSwimPer100m(speedMps: mps), "1:00/100m")
    }

    /// 0.909 m/s → 110 s/100m → "1:50/100m".
    func test_swimPace_1min50() {
        let mps = 100.0 / 110.0
        XCTAssertEqual(ActivityFormatters.formatPaceSwimPer100m(speedMps: mps), "1:50/100m")
    }

    // MARK: Boundary — near crossover

    /// 89.7 s/100m rounds to 90 s → "1:30/100m".
    func test_swimPace_boundary89point7s_roundsTo1min30() {
        let mps = 100.0 / 89.7
        XCTAssertEqual(ActivityFormatters.formatPaceSwimPer100m(speedMps: mps), "1:30/100m")
    }

    // MARK: Zero / invalid guard

    func test_swimPace_zeroSpeed_returnsFallback() {
        XCTAssertEqual(ActivityFormatters.formatPaceSwimPer100m(speedMps: 0), "0:00/100m")
    }
}

// MARK: - Speed (Bike)

final class ActivityFormatters_SpeedTests: XCTestCase {

    /// 1.0 m/s → 3.6 km/h → "3.6 km/h".
    func test_speed_1mps_is3point6kmh() {
        XCTAssertEqual(ActivityFormatters.formatSpeedKmh(speedMps: 1.0), "3.6 km/h")
    }

    /// 8.889 m/s → 32.0 km/h → "32.0 km/h".
    func test_speed_32kmh() {
        let mps = 32.0 / 3.6
        XCTAssertEqual(ActivityFormatters.formatSpeedKmh(speedMps: mps), "32.0 km/h")
    }

    /// 0.0 m/s → "0.0 km/h" (callers should guard; verify sensible output).
    func test_speed_zeroMps_returnsZero() {
        XCTAssertEqual(ActivityFormatters.formatSpeedKmh(speedMps: 0), "0.0 km/h")
    }

    /// Fractional speed: 6.8 m/s → 24.48 km/h → rounded to 1 decimal → "24.5 km/h".
    func test_speed_6point8mps_rounds1Decimal() {
        XCTAssertEqual(ActivityFormatters.formatSpeedKmh(speedMps: 6.8), "24.5 km/h")
    }
}

// MARK: - Power

final class ActivityFormatters_PowerTests: XCTestCase {

    func test_power_215watts_exact() {
        XCTAssertEqual(ActivityFormatters.formatPower(watts: 215.0), "215 W")
    }

    /// 196.4 W rounds to 196 W.
    func test_power_rounds_down() {
        XCTAssertEqual(ActivityFormatters.formatPower(watts: 196.4), "196 W")
    }

    /// 196.6 W rounds to 197 W.
    func test_power_rounds_up() {
        XCTAssertEqual(ActivityFormatters.formatPower(watts: 196.6), "197 W")
    }

    func test_power_zero() {
        XCTAssertEqual(ActivityFormatters.formatPower(watts: 0), "0 W")
    }
}

// MARK: - Heart Rate

final class ActivityFormatters_HRTests: XCTestCase {

    func test_hr_162bpm_exact() {
        XCTAssertEqual(ActivityFormatters.formatHR(bpm: 162.0), "162 bpm")
    }

    /// 152.4 bpm → rounds to 152.
    func test_hr_rounds_down() {
        XCTAssertEqual(ActivityFormatters.formatHR(bpm: 152.4), "152 bpm")
    }

    /// 152.6 bpm → rounds to 153.
    func test_hr_rounds_up() {
        XCTAssertEqual(ActivityFormatters.formatHR(bpm: 152.6), "153 bpm")
    }

    func test_hr_zero() {
        XCTAssertEqual(ActivityFormatters.formatHR(bpm: 0), "0 bpm")
    }
}
