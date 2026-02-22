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
