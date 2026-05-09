//
//  StravaLap.swift
//  Dromos
//
//  Created by Emmanuel Breard on 09/05/2026.
//

import Foundation

// MARK: - Strava Lap Model

/// Represents a single lap within a Strava activity, synced by the `strava-sync` Edge Function.
/// Maps to the `strava_activity_laps` table in Supabase.
/// Property names are camelCase; the global `convertFromSnakeCase` decoder handles DB mapping.
struct StravaLap: Codable, Identifiable {
    let id: UUID
    let activityId: UUID
    let lapIndex: Int
    let elapsedTime: Int        // seconds
    let movingTime: Int         // seconds
    let distance: Double?       // meters
    let averageSpeed: Double?   // m/s
    let averageCadence: Double? // RPM
    let averageWatts: Double?   // W
    let averageHeartrate: Double? // BPM
    let maxHeartrate: Double?   // BPM
    let startIndex: Int?        // index into streams arrays
    let endIndex: Int?          // index into streams arrays
}
