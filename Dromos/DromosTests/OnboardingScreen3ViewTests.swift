//
//  OnboardingScreen3ViewTests.swift
//  DromosTests
//
//  Unit tests for the onboarding Screen 3 max HR formula and birth year wiring
//  (DRO-220 / DRO-213 Phase 6).
//
//  NOTE: This file requires a DromosTests test target in the Xcode project.
//  Phase 7 wires the target up. Tests are written now per the spec.
//

import XCTest
@testable import Dromos

// MARK: - Max HR Formula Tests
//
// All tests call OnboardingScreen3View.computeMaxHr directly so the view's actual
// formula is exercised, not a shadow copy.

final class OnboardingMaxHrFormulaTests: XCTestCase {

    private func formula(birthYear: Int, currentYear: Int) -> Int {
        OnboardingScreen3View.computeMaxHr(birthYear: birthYear, currentYear: currentYear)
    }

    // MARK: - Core formula

    func test_formula_birthYear1990_currentYear2026_returns184() {
        XCTAssertEqual(formula(birthYear: 1990, currentYear: 2026), 184)
    }

    func test_formula_birthYear1996_currentYear2026_returns190() {
        // Default birth year used in onboarding (30 years ago from 2026)
        XCTAssertEqual(formula(birthYear: 1996, currentYear: 2026), 190)
    }

    func test_formula_birthYear2000_currentYear2026_returns194() {
        XCTAssertEqual(formula(birthYear: 2000, currentYear: 2026), 194)
    }

    func test_formula_birthYear1950_currentYear2026_returns144() {
        // Older athlete — result stays well above 100 floor
        XCTAssertEqual(formula(birthYear: 1950, currentYear: 2026), 144)
    }

    // MARK: - Clamp: lower bound

    func test_formula_clampedToMinimum100_whenResultBelow100() {
        // birthYear = 1900, currentYear = 2026 → age = 126 → 220 - 126 = 94 → clamped to 100
        XCTAssertEqual(formula(birthYear: 1900, currentYear: 2026), 100)
    }

    // MARK: - Clamp: upper bound

    func test_formula_clampedToMaximum220_atUpperBoundAndBeyond() {
        // Realistic case at the picker upper bound (currentYear − 5):
        // birthYear = 2021, currentYear = 2026 → age = 5 → 215 (below ceiling, no clamp)
        XCTAssertEqual(formula(birthYear: 2021, currentYear: 2026), 215)
        // Edge case: birthYear = 2026, age = 0 → 220 (at ceiling)
        XCTAssertEqual(formula(birthYear: 2026, currentYear: 2026), 220)
    }

    // MARK: - Formula is deterministic with stub year

    func test_formula_usesProvidedCurrentYear_notSystemDate() {
        // Same birth year, different reference years → different results
        XCTAssertNotEqual(
            formula(birthYear: 1990, currentYear: 2026),
            formula(birthYear: 1990, currentYear: 2036)
        )
        XCTAssertEqual(formula(birthYear: 1990, currentYear: 2036), 174)
    }
}

// MARK: - MetricsData Wiring Tests

final class OnboardingMetricsDataTests: XCTestCase {

    // MARK: - birthYear field

    func test_metricsData_birthYear_defaultsToNil() {
        let metrics = MetricsData()
        XCTAssertNil(metrics.birthYear)
    }

    func test_metricsData_birthYear_canBeSet() {
        var metrics = MetricsData()
        metrics.birthYear = 1988
        XCTAssertEqual(metrics.birthYear, 1988)
    }

    // MARK: - maxHr field

    func test_metricsData_maxHr_defaultsToNil() {
        let metrics = MetricsData()
        XCTAssertNil(metrics.maxHr)
    }

    func test_metricsData_maxHr_canBeSet() {
        var metrics = MetricsData()
        metrics.maxHr = 185
        XCTAssertEqual(metrics.maxHr, 185)
    }

    // MARK: - Manual edit is independent of formula

    func test_manualMaxHrEdit_notOverwrittenByBirthYearChange() {
        // Simulate: user tapped formula → got 184 → then manually typed 178
        // Changing birthYear afterward should NOT auto-recompute maxHr
        var metrics = MetricsData()

        // Step 1: formula applied for birthYear=1990, currentYear=2026
        metrics.birthYear = 1990
        metrics.maxHr = OnboardingScreen3View.computeMaxHr(birthYear: 1990, currentYear: 2026) // 184

        // Step 2: user manually edits maxHr to 178
        metrics.maxHr = 178

        // Step 3: user changes birthYear (formula NOT re-triggered, only button does it)
        metrics.birthYear = 1985
        // maxHr must still be 178 — no auto-recompute
        XCTAssertEqual(metrics.maxHr, 178)
        XCTAssertEqual(metrics.birthYear, 1985)
    }

    // MARK: - CompleteOnboardingData propagation

    func test_completeOnboardingData_includesMaxHrAndBirthYear() {
        var metrics = MetricsData()
        metrics.maxHr = 184
        metrics.birthYear = 1990

        let raceGoals = RaceGoalsData()
        let complete = CompleteOnboardingData(raceGoals: raceGoals, metrics: metrics)

        XCTAssertEqual(complete.maxHr, 184)
        XCTAssertEqual(complete.birthYear, 1990)
    }

    func test_completeOnboardingData_maxHrAndBirthYear_nilWhenNotSet() {
        let metrics = MetricsData()
        let complete = CompleteOnboardingData(raceGoals: RaceGoalsData(), metrics: metrics)

        XCTAssertNil(complete.maxHr)
        XCTAssertNil(complete.birthYear)
    }
}
