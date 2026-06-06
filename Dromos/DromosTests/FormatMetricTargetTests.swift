//
//  FormatMetricTargetTests.swift
//  DromosTests
//
//  DRO-297: Unit tests for `WorkoutLibraryService.displayString(for:sport:ftp:vma:css:maxHr:)`
//  covering every Target.type — both single-value and range variants where applicable.
//
//  These tests are "failing first" against the pre-existing formatters, then become
//  green once the DRO-297 display-string updates land.
//

import XCTest
@testable import Dromos

final class FormatMetricTargetTests: XCTestCase {

    private let svc = WorkoutLibraryService.shared

    // MARK: - hr_pct_max

    func test_hrPctMax_single_withMaxHr_showsPercentAndBpm() {
        // HR 88% max, maxHR 200 → 200 * 0.88 = 176 bpm
        let t: Target = .hrPctMax(value: 88, min: nil, max: nil)
        let out = svc.displayString(for: t, sport: "run", ftp: nil, vma: nil, css: nil, maxHr: 200)
        XCTAssertEqual(out, "HR 88% max (176 bpm)", "got: \(out ?? "nil")")
    }

    func test_hrPctMax_single_withoutMaxHr_showsPercentOnly() {
        let t: Target = .hrPctMax(value: 88, min: nil, max: nil)
        let out = svc.displayString(for: t, sport: "run", ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "HR 88% max", "got: \(out ?? "nil")")
    }

    func test_hrPctMax_range_withMaxHr_showsRangePercentAndBpm() {
        // HR 65–78% max, maxHR 200 → 130–156 bpm
        let t: Target = .hrPctMax(value: nil, min: 65, max: 78)
        let out = svc.displayString(for: t, sport: "bike", ftp: nil, vma: nil, css: nil, maxHr: 200)
        XCTAssertEqual(out, "HR 65–78% max (130–156 bpm)", "got: \(out ?? "nil")")
    }

    func test_hrPctMax_range_withoutMaxHr_showsRangePercentOnly() {
        let t: Target = .hrPctMax(value: nil, min: 65, max: 78)
        let out = svc.displayString(for: t, sport: "bike", ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "HR 65–78% max", "got: \(out ?? "nil")")
    }

    // MARK: - hr_zone

    func test_hrZone_z1_withMaxHr_showsZoneNameAndBpmBand() {
        // Z1: 0–60% of maxHR 200 → 0–120 bpm
        let out = svc.displayString(for: .hrZone(value: 1), sport: "run",
                                    ftp: nil, vma: nil, css: nil, maxHr: 200)
        XCTAssertEqual(out, "Z1 HR (0–120 bpm)", "got: \(out ?? "nil")")
    }

    func test_hrZone_z2_withMaxHr_showsZoneNameAndBpmBand() {
        // Z2: 60–72% of maxHR 200 → 120–144 bpm
        let out = svc.displayString(for: .hrZone(value: 2), sport: "run",
                                    ftp: nil, vma: nil, css: nil, maxHr: 200)
        XCTAssertEqual(out, "Z2 HR (120–144 bpm)", "got: \(out ?? "nil")")
    }

    func test_hrZone_z3_withMaxHr_showsZoneNameAndBpmBand() {
        // Z3: 72–82% of maxHR 200 → 144–164 bpm
        let out = svc.displayString(for: .hrZone(value: 3), sport: "bike",
                                    ftp: nil, vma: nil, css: nil, maxHr: 200)
        XCTAssertEqual(out, "Z3 HR (144–164 bpm)", "got: \(out ?? "nil")")
    }

    func test_hrZone_z4_withMaxHr() {
        // Z4: 82–92% of maxHR 200 → 164–184 bpm
        let out = svc.displayString(for: .hrZone(value: 4), sport: "bike",
                                    ftp: nil, vma: nil, css: nil, maxHr: 200)
        XCTAssertEqual(out, "Z4 HR (164–184 bpm)", "got: \(out ?? "nil")")
    }

    func test_hrZone_z5_withMaxHr() {
        // Z5: 92–100% of maxHR 200 → 184–200 bpm
        let out = svc.displayString(for: .hrZone(value: 5), sport: "run",
                                    ftp: nil, vma: nil, css: nil, maxHr: 200)
        XCTAssertEqual(out, "Z5 HR (184–200 bpm)", "got: \(out ?? "nil")")
    }

    func test_hrZone_withoutMaxHr_showsFallbackLabel() {
        let out = svc.displayString(for: .hrZone(value: 2), sport: "run",
                                    ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "Z2 HR (set max HR in profile)", "got: \(out ?? "nil")")
    }

    // MARK: - power_watts

    func test_powerWatts_single_roundsTripToWatts() {
        // Literal watts → "240 W"
        let t: Target = .powerWatts(value: 240, min: nil, max: nil)
        let out = svc.displayString(for: t, sport: "bike", ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "240 W", "got: \(out ?? "nil")")
    }

    func test_powerWatts_range_formatsRangeWithDash() {
        let t: Target = .powerWatts(value: nil, min: 240, max: 260)
        let out = svc.displayString(for: t, sport: "bike", ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "240–260 W", "got: \(out ?? "nil")")
    }

    func test_powerWatts_fractionalValues_roundsToInt() {
        // 239.6 → 240, 259.4 → 259
        let t: Target = .powerWatts(value: nil, min: 239.6, max: 259.4)
        let out = svc.displayString(for: t, sport: "bike", ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "240–259 W", "got: \(out ?? "nil")")
    }

    // MARK: - pace_per_km

    func test_pacePerKm_appendsKmUnit() {
        let out = svc.displayString(for: .pacePerKm(value: "4:11"), sport: "run",
                                    ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "4:11/km", "got: \(out ?? "nil")")
    }

    func test_pacePerKm_subFiveMinutePace() {
        let out = svc.displayString(for: .pacePerKm(value: "3:55"), sport: "run",
                                    ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "3:55/km", "got: \(out ?? "nil")")
    }

    // MARK: - pace_per_100m

    func test_pacePer100m_appendsSwimUnit() {
        let out = svc.displayString(for: .pacePerHundredM(value: "1:50"), sport: "swim",
                                    ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "1:50/100m", "got: \(out ?? "nil")")
    }

    func test_pacePer100m_fastPace() {
        let out = svc.displayString(for: .pacePerHundredM(value: "1:20"), sport: "swim",
                                    ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "1:20/100m", "got: \(out ?? "nil")")
    }

    // MARK: - Regression: pre-existing targets unchanged

    func test_regression_ftpPct_single_unchanged() {
        let t: Target = .ftpPct(value: 80, min: nil, max: nil)
        let out = svc.displayString(for: t, sport: "bike", ftp: 250, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "200 W")
    }

    func test_regression_ftpPct_range_unchanged() {
        let t: Target = .ftpPct(value: nil, min: 95, max: 100)
        let out = svc.displayString(for: t, sport: "bike", ftp: 275, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "261–275 W")
    }

    func test_regression_vmaPct_single_unchanged() {
        // VMA 18, 90% → 16.2 km/h → 3:42/km
        let t: Target = .vmaPct(value: 90, min: nil, max: nil)
        let out = svc.displayString(for: t, sport: "run", ftp: nil, vma: 18.0, css: nil, maxHr: nil)
        XCTAssertEqual(out, "3:42/km")
    }

    func test_regression_rpe_unchanged() {
        let out = svc.displayString(for: .rpe(value: 6), sport: "swim",
                                    ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "RPE 6 — moderate")
    }

    // MARK: - intensityPct for HR targets

    func test_intensityPct_hrPctMax_single_returnsMidpoint() {
        let t: Target = .hrPctMax(value: 85, min: nil, max: nil)
        let pct = svc.intensityPct(for: t, sport: "run", ftp: nil, vma: nil, css: nil, maxHr: 200)
        XCTAssertEqual(pct, 85)
    }

    func test_intensityPct_hrPctMax_range_returnsMidpoint() {
        // mid = (65 + 78) / 2 = 71.5 → clamped to 72
        let t: Target = .hrPctMax(value: nil, min: 65, max: 78)
        let pct = svc.intensityPct(for: t, sport: "bike", ftp: nil, vma: nil, css: nil, maxHr: 200)
        XCTAssertNotNil(pct)
        XCTAssertEqual(pct!, 72, accuracy: 2)
    }

    func test_intensityPct_hrZone_mapsToTable() {
        XCTAssertEqual(svc.intensityPct(for: .hrZone(value: 1), sport: "run",
                                         ftp: nil, vma: nil, css: nil, maxHr: nil), 55)
        XCTAssertEqual(svc.intensityPct(for: .hrZone(value: 2), sport: "run",
                                         ftp: nil, vma: nil, css: nil, maxHr: nil), 65)
        XCTAssertEqual(svc.intensityPct(for: .hrZone(value: 3), sport: "run",
                                         ftp: nil, vma: nil, css: nil, maxHr: nil), 75)
        XCTAssertEqual(svc.intensityPct(for: .hrZone(value: 4), sport: "run",
                                         ftp: nil, vma: nil, css: nil, maxHr: nil), 85)
        XCTAssertEqual(svc.intensityPct(for: .hrZone(value: 5), sport: "run",
                                         ftp: nil, vma: nil, css: nil, maxHr: nil), 95)
    }

    func test_intensityPct_powerWatts_returnsReasonableValue() {
        // 240 W with FTP 250 → 96% — check it's close
        let t: Target = .powerWatts(value: 240, min: nil, max: nil)
        let pct = svc.intensityPct(for: t, sport: "bike", ftp: 250, vma: nil, css: nil, maxHr: nil)
        XCTAssertNotNil(pct)
        XCTAssertEqual(pct!, 96, accuracy: 2)
    }

    func test_intensityPct_pacePerKm_returnsReasonableValue() {
        // 4:00/km = 15 km/h; VMA 18 → 83%
        let t: Target = .pacePerKm(value: "4:00")
        let pct = svc.intensityPct(for: t, sport: "run", ftp: nil, vma: 18.0, css: nil, maxHr: nil)
        XCTAssertNotNil(pct)
        XCTAssertEqual(pct!, 83, accuracy: 2)
    }

    func test_intensityPct_pacePer100m_returnsReasonableValue() {
        // CSS 100s/100m, pace 1:40 → css/secs * 100 = 100/100 * 100 = 100%
        let t: Target = .pacePerHundredM(value: "1:40")
        let pct = svc.intensityPct(for: t, sport: "swim", ftp: nil, vma: nil, css: 100, maxHr: nil)
        XCTAssertNotNil(pct)
        XCTAssertEqual(pct!, 100, accuracy: 5)
    }
}
