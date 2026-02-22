//
//  SessionCompletionStatus.swift
//  Dromos
//
//  Created by Mamma Aiuto Gang on 22/02/2026.
//

import Foundation

// MARK: - Session Completion Status

/// Completion status for a planned training session.
/// Computed dynamically at render time by matching a PlanSession against synced StravaActivity data.
/// Never persisted — moving a missed session to a future date automatically makes it planned again.
enum SessionCompletionStatus {
    /// Session is scheduled in the future or today has not yet passed — no Strava match found.
    case planned
    /// Session has a matching Strava activity: same sport, same calendar day, closest duration.
    case completed(activity: StravaActivity)
    /// Session date is in the past and no matching Strava activity was found.
    case missed
}

// MARK: - Session Matcher

/// Matches planned training sessions against synced Strava activities to determine completion status.
///
/// Matching rules:
/// - Manual Strava entries (`isManual == true`) are excluded from matching.
/// - Activities are grouped by `(normalizedSport, calendarDay)` using `startDateLocal`.
/// - A session matches if both sport and calendar day align.
/// - When multiple activities match, the closest duration (by `movingTime`) wins.
/// - Each activity can only be matched once — consumed activities are tracked to prevent double-counting.
/// - Past sessions without a match are marked `.missed`.
/// - Future/today sessions without a match remain `.planned`.
struct SessionMatcher {

    private static let dayFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    /// Matches plan sessions against Strava activities to determine per-session completion status.
    ///
    /// - Parameters:
    ///   - sessions: Tuples of (session, resolvedDate) for each visible planned session.
    ///   - activities: All Strava activities in the visible date range (may include manual entries).
    ///   - today: Reference date for the planned vs. missed cutoff. Defaults to `Date()`.
    /// - Returns: Dictionary mapping each session UUID to its `SessionCompletionStatus`.
    static func match(
        sessions: [(session: PlanSession, date: Date)],
        activities: [StravaActivity],
        today: Date = Date()
    ) -> [UUID: SessionCompletionStatus] {

        let calendar = Calendar.current

        // Step 1: Exclude manual activities — they were not logged via GPS and may be inaccurate.
        let autoActivities = activities.filter { !$0.isManual }

        // Step 2: Group activities by (normalizedSport, calendarDay) for O(1) lookup.
        // Key: "(sport)-(yyyy-MM-dd)" built from startDateLocal truncated to calendar day.
        var activityGroups: [String: [StravaActivity]] = [:]
        for activity in autoActivities {
            guard let sport = activity.normalizedSport?.lowercased() else { continue }
            let dayStart = calendar.startOfDay(for: activity.startDateLocal)
            let key = groupKey(sport: sport, day: dayStart)
            activityGroups[key, default: []].append(activity)
        }

        // Step 3: Classify each session.
        // Track consumed activity IDs to prevent a single activity from matching multiple sessions.
        let todayStart = calendar.startOfDay(for: today)
        var consumedActivityIDs: Set<Int64> = []
        var result: [UUID: SessionCompletionStatus] = [:]

        for (session, sessionDate) in sessions {
            let sessionDayStart = calendar.startOfDay(for: sessionDate)
            let key = groupKey(sport: session.sport.lowercased(), day: sessionDayStart)

            // Filter candidates to exclude already-consumed activities.
            let candidates = (activityGroups[key] ?? []).filter { !consumedActivityIDs.contains($0.stravaActivityId) }

            if !candidates.isEmpty {
                // Step 4: Match found — pick the activity whose movingTime is closest to the planned duration.
                let targetSeconds: Int = session.durationMinutes * 60
                // guard-let instead of force-unwrap: candidates may be empty after consumed-ID filtering.
                guard let best = candidates.min(by: { a, b in
                    let diffA = abs(a.movingTime - targetSeconds)
                    let diffB = abs(b.movingTime - targetSeconds)
                    return diffA < diffB
                }) else { continue }

                // Mark this activity as consumed so it cannot match another session.
                consumedActivityIDs.insert(best.stravaActivityId)
                result[session.id] = .completed(activity: best)

            } else if sessionDayStart < todayStart {
                // Step 5: No match and the session is in the past → missed.
                result[session.id] = .missed

            } else {
                // Step 6: No match but session is today or future → still planned.
                result[session.id] = .planned
            }
        }

        return result
    }

    // MARK: - Private Helpers

    /// Builds a stable dictionary key from a normalized sport name and a calendar day start date.
    /// Format: "swim-2026-02-17", "bike-2026-02-18", "run-2026-02-19".
    private static func groupKey(sport: String, day: Date) -> String {
        return "\(sport)-\(Self.dayFormatter.string(from: day))"
    }
}
