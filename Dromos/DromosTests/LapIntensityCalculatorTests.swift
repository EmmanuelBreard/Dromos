//
//  LapIntensityCalculatorTests.swift
//  DromosTests
//
//  Unit tests for LapIntensityCalculator sport-aware intensity normalization (DRO-223 Phase 3).
//
//  Covers:
//  - Run reference path (VMA set)
//  - Run session-normalized fallback (VMA nil)
//  - Bike power reference path (FTP set, all laps have valid watts)
//  - Bike power session-normalized fallback (FTP nil, all laps have valid watts)
//  - Bike per-activity HR fallback (one lap has zero watts → entire activity uses HR)
//  - Bike HR fallback session-normalized (maxHr nil)
//  - Swim CSS reference path
//  - Swim session-normalized fallback (CSS nil)
//  - Equal-value double-fallback (all laps same metric, no reference → all nil)
//  - All-nil metric (every lap missing the required metric → all nil)
//  - Lap missing required metric → nil for that index, others still compute
//

import XCTest
@testable import Dromos

// MARK: - Test Fixture Helper

/// Private helper to build minimal `StravaLap` instances for testing.
/// Only the fields exercised by the test are filled; the rest use safe defaults.
private func makeLap(
    speed: Double? = nil,
    watts: Double? = nil,
    hr: Double? = nil,
    distance: Double? = 1000,
    lapIndex: Int = 0
) -> StravaLap {
    StravaLap(
        id: UUID(), activityId: UUID(),
        lapIndex: lapIndex, elapsedTime: 60, movingTime: 60,
        distance: distance, averageSpeed: speed,
        averageCadence: nil, averageWatts: watts,
        averageHeartrate: hr, maxHeartrate: nil,
        startIndex: nil, endIndex: nil
    )
}

// MARK: - Run Tests

final class LapIntensityCalculator_RunTests: XCTestCase {

    // MARK: Reference path

    /// Three run laps at varying speeds with VMA = 18.0 km/h.
    /// Expected: intensity% = round((speed_kmh / 18.0) * 100)
    func test_run_referenceVMA_intensityMatchesFormula() {
        // Speeds in m/s: 3.0 → 10.8 km/h, 4.0 → 14.4 km/h, 5.0 → 18.0 km/h
        let laps = [
            makeLap(speed: 3.0, lapIndex: 0),
            makeLap(speed: 4.0, lapIndex: 1),
            makeLap(speed: 5.0, lapIndex: 2)
        ]
        let result = LapIntensityCalculator.intensities(
            for: laps, sport: "run", vma: 18.0, ftp: nil, css: nil, maxHr: nil
        )
        // 10.8 / 18.0 * 100 = 60.0 → 60
        // 14.4 / 18.0 * 100 = 80.0 → 80
        // 18.0 / 18.0 * 100 = 100.0 → 100
        XCTAssertEqual(result[0], 60)
        XCTAssertEqual(result[1], 80)
        XCTAssertEqual(result[2], 100)
        XCTAssertEqual(result.count, 3)
    }

    // MARK: Session-normalized fallback

    /// Three run laps at varying speeds with VMA = nil.
    /// Fastest lap should return ~100, slowest ~0.
    func test_run_sessionNormalizedFallback_fastestIs100SlowestIs0() {
        // Speeds: 3.0, 4.0, 5.0 m/s → min=3.0, max=5.0
        let laps = [
            makeLap(speed: 3.0, lapIndex: 0),
            makeLap(speed: 4.0, lapIndex: 1),
            makeLap(speed: 5.0, lapIndex: 2)
        ]
        let result = LapIntensityCalculator.intensities(
            for: laps, sport: "run", vma: nil, ftp: nil, css: nil, maxHr: nil
        )
        // (3.0 - 3.0) / (5.0 - 3.0) * 100 = 0
        // (4.0 - 3.0) / (5.0 - 3.0) * 100 = 50
        // (5.0 - 5.0) / (5.0 - 3.0) * 100 = 100
        XCTAssertEqual(result[0], 0)
        XCTAssertEqual(result[1], 50)
        XCTAssertEqual(result[2], 100)
        XCTAssertEqual(result.count, 3)
    }
}

// MARK: - Bike Tests

final class LapIntensityCalculator_BikeTests: XCTestCase {

    // MARK: Power reference path

    /// Three laps with valid watts and FTP = 250 W.
    /// Expected: intensity% = round((watts / 250) * 100)
    func test_bike_powerReferenceFTP_intensityMatchesFormula() {
        // Watts: 200, 250, 300
        let laps = [
            makeLap(watts: 200, lapIndex: 0),
            makeLap(watts: 250, lapIndex: 1),
            makeLap(watts: 300, lapIndex: 2)
        ]
        let result = LapIntensityCalculator.intensities(
            for: laps, sport: "bike", vma: nil, ftp: 250, css: nil, maxHr: nil
        )
        // 200/250*100 = 80, 250/250*100 = 100, 300/250*100 = 120
        XCTAssertEqual(result[0], 80)
        XCTAssertEqual(result[1], 100)
        XCTAssertEqual(result[2], 120)
        XCTAssertEqual(result.count, 3)
    }

    // MARK: Power session-normalized fallback

    /// Three laps with valid watts, FTP = nil.
    /// Highest wattage lap → ~100.
    func test_bike_powerSessionNormalizedFallback_highestWattsIs100() {
        // Watts: 150, 225, 300
        let laps = [
            makeLap(watts: 150, lapIndex: 0),
            makeLap(watts: 225, lapIndex: 1),
            makeLap(watts: 300, lapIndex: 2)
        ]
        let result = LapIntensityCalculator.intensities(
            for: laps, sport: "bike", vma: nil, ftp: nil, css: nil, maxHr: nil
        )
        // (150-150)/(300-150)*100 = 0, (225-150)/(300-150)*100 = 50, (300-150)/(300-150)*100 = 100
        XCTAssertEqual(result[0], 0)
        XCTAssertEqual(result[1], 50)
        XCTAssertEqual(result[2], 100)
        XCTAssertEqual(result.count, 3)
    }

    // MARK: Per-activity HR fallback (one lap with zero watts)

    /// Three laps, one of them with watts = 0 (invalid).
    /// Because not all laps have valid watts, the entire activity must use HR.
    /// With maxHr = 190, expected: intensity% = round((bpm / 190) * 100).
    func test_bike_perActivityHRFallback_zeroWattsLapForcesHRForAll() {
        let laps = [
            makeLap(watts: 200, hr: 140, lapIndex: 0), // valid watts — but overridden by activity-level rule
            makeLap(watts: 0,   hr: 160, lapIndex: 1), // zero watts → triggers HR fallback for whole activity
            makeLap(watts: 250, hr: 175, lapIndex: 2)  // valid watts — but overridden
        ]
        let result = LapIntensityCalculator.intensities(
            for: laps, sport: "bike", vma: nil, ftp: 250, css: nil, maxHr: 190
        )
        // HR path: 140/190*100 ≈ 73.68 → 74, 160/190*100 ≈ 84.21 → 84, 175/190*100 ≈ 92.11 → 92
        XCTAssertEqual(result[0], 74)
        XCTAssertEqual(result[1], 84)
        XCTAssertEqual(result[2], 92)
        XCTAssertEqual(result.count, 3)
    }

    // MARK: Bike HR fallback session-normalized

    /// Same as above (one lap with zero watts) but maxHr = nil.
    /// Should session-normalize on HR. Highest HR → 100.
    func test_bike_hrFallbackSessionNormalized_highestHRIs100() {
        let laps = [
            makeLap(watts: 200, hr: 140, lapIndex: 0),
            makeLap(watts: 0,   hr: 160, lapIndex: 1), // zero watts → HR fallback for all
            makeLap(watts: 250, hr: 175, lapIndex: 2)
        ]
        let result = LapIntensityCalculator.intensities(
            for: laps, sport: "bike", vma: nil, ftp: nil, css: nil, maxHr: nil
        )
        // (140-140)/(175-140)*100 = 0, (160-140)/(175-140)*100 ≈ 57.14 → 57, (175-140)/(175-140)*100 = 100
        XCTAssertEqual(result[0], 0)
        XCTAssertEqual(result[1], 57)
        XCTAssertEqual(result[2], 100)
        XCTAssertEqual(result.count, 3)
    }
}

// MARK: - Swim Tests

final class LapIntensityCalculator_SwimTests: XCTestCase {

    // MARK: CSS reference path

    /// Three swim laps with varying speeds, CSS = 90 sec/100m.
    /// Expected: intensity% = round((90 / (100 / speed)) * 100)
    func test_swim_referenceCSSPath_intensityMatchesFormula() {
        // speed in m/s: 0.9, 1.0, 1.1
        // secondsPer100m: 100/0.9 ≈ 111.11, 100/1.0 = 100.0, 100/1.1 ≈ 90.91
        // intensity: 90/111.11*100 ≈ 81.0 → 81, 90/100.0*100 = 90, 90/90.91*100 ≈ 99.0 → 99
        let laps = [
            makeLap(speed: 0.9, lapIndex: 0),
            makeLap(speed: 1.0, lapIndex: 1),
            makeLap(speed: 1.1, lapIndex: 2)
        ]
        let result = LapIntensityCalculator.intensities(
            for: laps, sport: "swim", vma: nil, ftp: nil, css: 90, maxHr: nil
        )
        XCTAssertEqual(result[0], 81)
        XCTAssertEqual(result[1], 90)
        XCTAssertEqual(result[2], 99)
        XCTAssertEqual(result.count, 3)
    }

    // MARK: Swim session-normalized fallback

    /// Three swim laps, CSS = nil. Fastest lap → ~100.
    func test_swim_sessionNormalizedFallback_fastestIs100() {
        // Speeds: 0.9, 1.0, 1.2 m/s
        let laps = [
            makeLap(speed: 0.9, lapIndex: 0),
            makeLap(speed: 1.0, lapIndex: 1),
            makeLap(speed: 1.2, lapIndex: 2)
        ]
        let result = LapIntensityCalculator.intensities(
            for: laps, sport: "swim", vma: nil, ftp: nil, css: nil, maxHr: nil
        )
        // (0.9-0.9)/(1.2-0.9)*100 = 0, (1.0-0.9)/(1.2-0.9)*100 ≈ 33.33 → 33, (1.2-0.9)/(1.2-0.9)*100 = 100
        XCTAssertEqual(result[0], 0)
        XCTAssertEqual(result[1], 33)
        XCTAssertEqual(result[2], 100)
        XCTAssertEqual(result.count, 3)
    }
}

// MARK: - Edge Case Tests

final class LapIntensityCalculator_EdgeCaseTests: XCTestCase {

    // MARK: Equal-value double-fallback

    /// Run equal-value: 3 laps at the same averageSpeed with VMA = nil → all return nil.
    /// The calculator cannot differentiate effort when every lap reports the same metric
    /// AND no reference is set. Returning all-nil signals the Phase 4 renderer to apply
    /// "100% height + green/easy color" rendering per the tech spec Resolved Decisions (DRO-223).
    func test_equalValueDoubleFallback_allLapsSameSpeed_allReturnNil() {
        let laps = [
            makeLap(speed: 4.0, lapIndex: 0),
            makeLap(speed: 4.0, lapIndex: 1),
            makeLap(speed: 4.0, lapIndex: 2)
        ]
        let result = LapIntensityCalculator.intensities(
            for: laps, sport: "run", vma: nil, ftp: nil, css: nil, maxHr: nil
        )
        XCTAssertEqual(result, [nil, nil, nil])
    }

    /// Swim equal-value: 3 laps at the same speed with `css = nil` → all return nil
    /// (calculator can't differentiate; renderer handles the visual via all-nil detection).
    func test_equalValueDoubleFallback_swim_allLapsSameSpeed_allReturnNil() {
        let laps = [
            makeLap(speed: 1.5, distance: 100, lapIndex: 0),
            makeLap(speed: 1.5, distance: 100, lapIndex: 1),
            makeLap(speed: 1.5, distance: 100, lapIndex: 2),
        ]
        let result = LapIntensityCalculator.intensities(
            for: laps, sport: "swim", vma: nil, ftp: nil, css: nil, maxHr: nil
        )
        XCTAssertEqual(result, [nil, nil, nil])
    }

    // MARK: All-nil metric

    /// All-nil metric: when every lap is missing the required metric for its sport,
    /// every result is nil (calculator yields no information at all).
    func test_allLapsMissingMetric_swim_allReturnNil() {
        let laps = [
            makeLap(speed: nil, distance: 100, lapIndex: 0),
            makeLap(speed: nil, distance: 100, lapIndex: 1),
        ]
        let result = LapIntensityCalculator.intensities(
            for: laps, sport: "swim", vma: nil, ftp: nil, css: nil, maxHr: nil
        )
        XCTAssertEqual(result, [nil, nil])
    }

    // MARK: Lap missing required metric

    /// A swim lap with averageSpeed == nil must return nil for that index.
    /// Other laps in the same array still compute normally.
    func test_lapMissingRequiredMetric_swimLapNilSpeed_returnsNilForThatIndex() {
        let laps = [
            makeLap(speed: 1.0, lapIndex: 0), // valid
            makeLap(speed: nil, lapIndex: 1), // missing speed → nil
            makeLap(speed: 1.2, lapIndex: 2)  // valid
        ]
        let result = LapIntensityCalculator.intensities(
            for: laps, sport: "swim", vma: nil, ftp: nil, css: 90, maxHr: nil
        )
        XCTAssertNotNil(result[0], "First lap (valid speed) should compute normally")
        XCTAssertNil(result[1], "Second lap (nil speed) must return nil")
        XCTAssertNotNil(result[2], "Third lap (valid speed) should compute normally")
        XCTAssertEqual(result.count, 3)
    }
}
