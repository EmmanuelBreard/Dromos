//
//  SessionMatcherTests.swift
//  DromosTests
//
//  Unit tests for SessionMatcher.matchWithUnscheduled (DRO-306 / DRO-305 Phase 1).
//
//  Covers:
//  - A manual entry (isManual=true) surfaces as unscheduled even though it was never a candidate.
//  - An activity matched to a planned session is NOT in unscheduledByDay.
//  - Two activities of different sports on the same day are both present and grouped correctly.
//  - An activity whose normalizedSport is nil is excluded from unscheduledByDay.
//  - An activity whose normalizedSport is outside swim/bike/run is excluded.
//  - Existing match() wrapper compiles and returns identical statuses (back-compat guard).
//

import XCTest
@testable import Dromos

// MARK: - Test Fixture Helpers

/// Builds a minimal `StravaActivity` for testing.
/// Only fields exercised by the matcher need real values; the rest use safe defaults.
private func makeActivity(
    stravaId: Int64,
    sport: String?,
    startDateLocal: Date,
    movingTime: Int = 3600,
    isManual: Bool = false
) -> StravaActivity {
    StravaActivity(
        id: UUID(),
        userId: UUID(),
        stravaActivityId: stravaId,
        sportType: sport ?? "Run",
        normalizedSport: sport,
        name: nil,
        startDate: startDateLocal,
        startDateLocal: startDateLocal,
        elapsedTime: movingTime,
        movingTime: movingTime,
        distance: nil,
        totalElevationGain: nil,
        averageSpeed: nil,
        averageHeartrate: nil,
        averageWatts: nil,
        isManual: isManual,
        summaryPolyline: nil,
        createdAt: startDateLocal
    )
}

/// Builds a minimal `PlanSession` for testing.
private func makeSession(
    sport: String,
    day: String,
    weekId: UUID = UUID(),
    durationMinutes: Int = 60
) -> PlanSession {
    PlanSession(
        id: UUID(),
        weekId: weekId,
        day: day,
        sport: sport,
        type: "Easy",
        templateId: "t1",
        durationMinutes: durationMinutes,
        isBrick: false,
        notes: nil,
        orderInDay: 0,
        feedback: nil,
        matchedActivityId: nil
    )
}

// MARK: - Calendar Helper

/// Returns a specific date at midnight local time for deterministic tests.
private func makeDate(year: Int, month: Int, day: Int) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = 0
    comps.minute = 0
    comps.second = 0
    return Calendar.current.date(from: comps)!
}

// MARK: - matchWithUnscheduled Tests

final class SessionMatcher_MatchWithUnscheduledTests: XCTestCase {

    // MARK: Manual entry surfaces as unscheduled

    /// A manual entry (isManual=true) is never a candidate for planned matching.
    /// It must appear in `unscheduledByDay` because it is a tracked sport (run) and its
    /// stravaActivityId is not in consumedIDs (it was never consumed).
    func test_manualEntry_surfacesAsUnscheduled() {
        let activityDate = makeDate(year: 2026, month: 3, day: 10)
        let manual = makeActivity(stravaId: 1, sport: "run", startDateLocal: activityDate, isManual: true)

        // No planned sessions — nothing to consume anything.
        let result = SessionMatcher.matchWithUnscheduled(
            sessions: [],
            activities: [manual],
            today: makeDate(year: 2026, month: 3, day: 11)
        )

        let dayKey = Calendar.current.startOfDay(for: activityDate)
        XCTAssertNotNil(result.unscheduledByDay[dayKey], "Manual run should appear in unscheduledByDay")
        XCTAssertEqual(result.unscheduledByDay[dayKey]?.count, 1)
        XCTAssertEqual(result.unscheduledByDay[dayKey]?.first?.stravaActivityId, 1)
    }

    // MARK: Matched activity is NOT in unscheduled

    /// An auto activity that was consumed by a planned session match must NOT appear in
    /// unscheduledByDay — double-surfacing a completed session as both planned and unscheduled
    /// would be incorrect and confusing.
    func test_matchedActivity_notInUnscheduled() {
        let sessionDate = makeDate(year: 2026, month: 3, day: 10)
        let session = makeSession(sport: "run", day: "Tuesday", durationMinutes: 60)
        let activity = makeActivity(stravaId: 42, sport: "run", startDateLocal: sessionDate, movingTime: 3600)

        let result = SessionMatcher.matchWithUnscheduled(
            sessions: [(session: session, date: sessionDate)],
            activities: [activity],
            today: makeDate(year: 2026, month: 3, day: 11)
        )

        // Verify the session was actually matched (so the consumed-ID path was exercised).
        if case .completed(let matched) = result.statuses[session.id] {
            XCTAssertEqual(matched.stravaActivityId, 42)
        } else {
            XCTFail("Session should be .completed — test precondition failed")
        }

        // The consumed activity must NOT appear in unscheduledByDay.
        let dayKey = Calendar.current.startOfDay(for: sessionDate)
        let unscheduled = result.unscheduledByDay[dayKey] ?? []
        XCTAssertFalse(
            unscheduled.contains(where: { $0.stravaActivityId == 42 }),
            "Consumed activity must not appear in unscheduledByDay"
        )
    }

    // MARK: Two different sports on the same day group correctly

    /// A swim and a bike on the same calendar day — with no planned sessions — must both
    /// appear in `unscheduledByDay` under the same day key.
    func test_twoDifferentSports_sameDay_groupedUnderSameDayKey() {
        let activityDate = makeDate(year: 2026, month: 3, day: 15)
        let swim = makeActivity(stravaId: 100, sport: "swim", startDateLocal: activityDate)
        // Give the bike a slightly later time on the same day (1 hour later) to confirm
        // grouping is purely calendar-day based, not timestamp-equality based.
        let bikeDate = Calendar.current.date(byAdding: .hour, value: 5, to: activityDate)!
        let bike = makeActivity(stravaId: 101, sport: "bike", startDateLocal: bikeDate)

        let result = SessionMatcher.matchWithUnscheduled(
            sessions: [],
            activities: [swim, bike],
            today: makeDate(year: 2026, month: 3, day: 16)
        )

        let dayKey = Calendar.current.startOfDay(for: activityDate)
        guard let group = result.unscheduledByDay[dayKey] else {
            XCTFail("Expected unscheduled activities on the day key \(dayKey)"); return
        }
        XCTAssertEqual(group.count, 2, "Both swim and bike should be grouped under the same day")
        let ids = Set(group.map(\.stravaActivityId))
        XCTAssertTrue(ids.contains(100), "Swim should be in the group")
        XCTAssertTrue(ids.contains(101), "Bike should be in the group")
    }

    // MARK: Activity with nil normalizedSport is excluded

    /// An activity with `normalizedSport == nil` is excluded from unscheduledByDay.
    /// The app only renders swim / bike / run activities so surfacing unknown sports would
    /// produce cards with no meaningful data.
    func test_nilNormalizedSport_excluded() {
        let activityDate = makeDate(year: 2026, month: 3, day: 20)
        let unknown = makeActivity(stravaId: 200, sport: nil, startDateLocal: activityDate)

        let result = SessionMatcher.matchWithUnscheduled(
            sessions: [],
            activities: [unknown],
            today: makeDate(year: 2026, month: 3, day: 21)
        )

        XCTAssertTrue(result.unscheduledByDay.isEmpty, "Activity with nil sport must not appear in unscheduledByDay")
    }

    // MARK: Activity outside swim/bike/run is excluded

    /// An activity with a tracked-but-non-triathlon sport (e.g. "strength") is excluded.
    /// The filter is strictly {"swim", "bike", "run"}.
    func test_nonTriathlonSport_excluded() {
        let activityDate = makeDate(year: 2026, month: 3, day: 22)
        let strength = makeActivity(stravaId: 300, sport: "strength", startDateLocal: activityDate)
        let yoga    = makeActivity(stravaId: 301, sport: "yoga",     startDateLocal: activityDate)

        let result = SessionMatcher.matchWithUnscheduled(
            sessions: [],
            activities: [strength, yoga],
            today: makeDate(year: 2026, month: 3, day: 23)
        )

        XCTAssertTrue(result.unscheduledByDay.isEmpty, "Strength and yoga must not appear in unscheduledByDay")
    }
}

// MARK: - Back-compat: match() wrapper returns identical statuses

final class SessionMatcher_WrapperTests: XCTestCase {

    /// Verifies that the `match(...)` thin wrapper over `matchCore` returns the exact same
    /// statuses as calling `matchWithUnscheduled(...).statuses` — ensuring zero behaviour
    /// change for the three existing call sites.
    func test_matchWrapper_returnsSameStatusesAsFullResult() {
        let sessionDate = makeDate(year: 2026, month: 4, day: 1)
        let session = makeSession(sport: "bike", day: "Wednesday", durationMinutes: 90)
        let activity = makeActivity(stravaId: 55, sport: "bike", startDateLocal: sessionDate, movingTime: 5400)
        let today = makeDate(year: 2026, month: 4, day: 2)

        let legacyStatuses = SessionMatcher.match(
            sessions: [(session: session, date: sessionDate)],
            activities: [activity],
            today: today
        )

        let fullResult = SessionMatcher.matchWithUnscheduled(
            sessions: [(session: session, date: sessionDate)],
            activities: [activity],
            today: today
        )

        XCTAssertEqual(legacyStatuses.count, fullResult.statuses.count)
        for (uuid, legacyStatus) in legacyStatuses {
            guard let fullStatus = fullResult.statuses[uuid] else {
                XCTFail("UUID \(uuid) missing from fullResult.statuses"); continue
            }
            // Compare the underlying stravaActivityId for .completed, or verify enum shape.
            switch (legacyStatus, fullStatus) {
            case (.completed(let a1), .completed(let a2)):
                XCTAssertEqual(a1.stravaActivityId, a2.stravaActivityId)
            case (.missed, .missed), (.planned, .planned):
                break // shapes match
            default:
                XCTFail("Status mismatch for UUID \(uuid): \(legacyStatus) vs \(fullStatus)")
            }
        }
    }
}

// MARK: - StravaActivity Display Helpers Tests

final class StravaActivity_DisplayHelpersTests: XCTestCase {

    // MARK: sportIcon

    func test_sportIcon_swim_returnsFigurePoolSwim() {
        let a = makeActivity(stravaId: 1, sport: "swim", startDateLocal: Date())
        XCTAssertEqual(a.sportIcon, "figure.pool.swim")
    }

    func test_sportIcon_bike_returnsBicycle() {
        let a = makeActivity(stravaId: 2, sport: "bike", startDateLocal: Date())
        XCTAssertEqual(a.sportIcon, "bicycle")
    }

    func test_sportIcon_run_returnsFigureRun() {
        let a = makeActivity(stravaId: 3, sport: "run", startDateLocal: Date())
        XCTAssertEqual(a.sportIcon, "figure.run")
    }

    func test_sportIcon_unknownSport_fallsBackToFigureRun() {
        let a = makeActivity(stravaId: 4, sport: "yoga", startDateLocal: Date())
        XCTAssertEqual(a.sportIcon, "figure.run")
    }

    func test_sportIcon_nilSport_fallsBackToFigureRun() {
        let a = makeActivity(stravaId: 5, sport: nil, startDateLocal: Date())
        XCTAssertEqual(a.sportIcon, "figure.run")
    }

    // MARK: displayName

    func test_displayName_withName_returnsTitleCased() {
        var a = makeActivity(stravaId: 10, sport: "run", startDateLocal: Date())
        // Re-create with a non-nil name — makeActivity sets name to nil, so we build inline.
        let named = StravaActivity(
            id: UUID(), userId: UUID(), stravaActivityId: 10,
            sportType: "run", normalizedSport: "run",
            name: "morning run",
            startDate: Date(), startDateLocal: Date(),
            elapsedTime: 3600, movingTime: 3600,
            distance: nil, totalElevationGain: nil,
            averageSpeed: nil, averageHeartrate: nil, averageWatts: nil,
            isManual: false, summaryPolyline: nil, createdAt: Date()
        )
        _ = a // suppress unused warning
        XCTAssertEqual(named.displayName, "Morning Run")
    }

    func test_displayName_nilName_swim_returnsSport() {
        let a = makeActivity(stravaId: 11, sport: "swim", startDateLocal: Date())
        XCTAssertEqual(a.displayName, "Swim")
    }

    func test_displayName_nilName_bike_returnsSport() {
        let a = makeActivity(stravaId: 12, sport: "bike", startDateLocal: Date())
        XCTAssertEqual(a.displayName, "Bike")
    }

    func test_displayName_nilName_run_returnsSport() {
        let a = makeActivity(stravaId: 13, sport: "run", startDateLocal: Date())
        XCTAssertEqual(a.displayName, "Run")
    }

    func test_displayName_nilName_unknownSport_returnsActivity() {
        let a = makeActivity(stravaId: 14, sport: nil, startDateLocal: Date())
        XCTAssertEqual(a.displayName, "Activity")
    }

    func test_displayName_emptyName_fallsBackToSport() {
        let emptyNamed = StravaActivity(
            id: UUID(), userId: UUID(), stravaActivityId: 15,
            sportType: "run", normalizedSport: "run",
            name: "   ",   // whitespace only — should fall back
            startDate: Date(), startDateLocal: Date(),
            elapsedTime: 3600, movingTime: 3600,
            distance: nil, totalElevationGain: nil,
            averageSpeed: nil, averageHeartrate: nil, averageWatts: nil,
            isManual: false, summaryPolyline: nil, createdAt: Date()
        )
        XCTAssertEqual(emptyNamed.displayName, "Run")
    }
}
