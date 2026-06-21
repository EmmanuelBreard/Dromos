//
//  StravaModels.swift
//  Dromos
//
//  Created by Emmanuel Breard on 22/02/2026.
//

import Foundation

// MARK: - Strava Activity Model

/// Represents a Strava activity synced from the athlete's account.
/// Maps to the `strava_activities` table in Supabase.
/// Property names are camelCase; the global `convertFromSnakeCase` decoder handles DB mapping.
struct StravaActivity: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let stravaActivityId: Int64
    let sportType: String
    let normalizedSport: String?
    let name: String?
    let startDate: Date
    let startDateLocal: Date
    let elapsedTime: Int       // seconds
    let movingTime: Int        // seconds
    let distance: Double?      // meters
    let totalElevationGain: Double?
    let averageSpeed: Double?
    let averageHeartrate: Double?
    let averageWatts: Double?
    let isManual: Bool
    let summaryPolyline: String?   // Encoded GPS polyline from Strava map (nil for manual entries)
    let createdAt: Date
}

// MARK: - StravaActivity Display Helpers

extension StravaActivity {

    /// SF Symbol name for the activity's sport.
    /// Mirrors the symbol names used by `PlanSession.sportIcon` so unscheduled and planned
    /// session cards can share the same icon vocabulary.
    var sportIcon: String {
        switch normalizedSport?.lowercased() {
        case "swim": return "figure.pool.swim"
        case "bike": return "bicycle"
        case "run":  return "figure.run"
        default:     return "figure.run"
        }
    }

    /// Human-readable activity name, trimmed of surrounding whitespace.
    /// Returns the athlete's Strava title verbatim — we deliberately do NOT title-case it,
    /// because `.capitalized` corrupts the acronyms and unit suffixes common in real activity
    /// names ("VO2max intervals" → "Vo2max Intervals", "10K TT" → "10k Tt").
    /// Falls back to a sport label ("Swim" / "Bike" / "Run" / "Activity") when `name`
    /// is nil or empty — ensures the UI always has something meaningful to display even
    /// for manually logged activities that may have generic or blank titles.
    var displayName: String {
        if let raw = name {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        switch normalizedSport?.lowercased() {
        case "swim": return "Swim"
        case "bike": return "Bike"
        case "run":  return "Run"
        default:     return "Activity"
        }
    }
}

// MARK: - Sync Result

/// Summary returned by the `strava-sync` Edge Function.
struct SyncResult: Equatable {
    let syncedCount: Int
    let totalActivities: Int
    let rateLimited: Bool
}

// MARK: - Sync Response (Decodable)

/// Decodable wrapper for the `strava-sync` Edge Function response payload.
/// Uses explicit CodingKeys because the Edge Function returns snake_case JSON
/// outside of the PostgREST decoder pipeline (manual JSONDecoder required).
struct SyncResponse: Decodable {
    let syncedCount: Int
    let totalActivities: Int
    let rateLimited: Bool

    private enum CodingKeys: String, CodingKey {
        case syncedCount = "synced_count"
        case totalActivities = "total_activities"
        case rateLimited = "rate_limited"
    }

    var toSyncResult: SyncResult {
        SyncResult(
            syncedCount: syncedCount,
            totalActivities: totalActivities,
            rateLimited: rateLimited
        )
    }
}

// MARK: - Feedback Response

/// Response from the `session-feedback` Edge Function.
/// Edge Function responses use camelCase keys matching Swift property names,
/// so no explicit CodingKeys are needed.
struct FeedbackResponse: Decodable {
    let feedback: String?
    let skipped: Bool?
}
