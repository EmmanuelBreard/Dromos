//
//  WorkoutTemplate.swift
//  Dromos
//
//  Created by Emmanuel Breard on 01/02/2026.
//

import Foundation

// MARK: - Workout Template

/// Represents a workout template from the workout library.
/// Templates are keyed by `templateId` and contain an array of segments.
struct WorkoutTemplate: Codable {
    let templateId: String
    let segments: [WorkoutSegment]

    enum CodingKeys: String, CodingKey {
        case templateId = "template_id"
        case segments
    }
}

// MARK: - Workout Segment

/// A segment within a workout template.
/// Segments can be simple (work, warmup, cooldown) or nested repeats.
/// Fields are optional since different segment types use different subsets.
/// Uses `class` instead of `struct` to support recursive nesting (segments within segments).
final class WorkoutSegment: Codable {
    let label: String
    let durationMinutes: Int?
    let durationSeconds: Int?
    let distanceMeters: Int?
    let pace: String?
    let ftpPct: Int?
    let masPct: Int?
    let cadenceRpm: Int?
    let drill: String?
    let cue: String?
    let equipment: String?
    let terrain: String?
    let restSeconds: Int?
    let repeats: Int?
    let segments: [WorkoutSegment]?
    let recovery: WorkoutSegment?

    enum CodingKeys: String, CodingKey {
        case label
        case durationMinutes = "duration_minutes"
        case durationSeconds = "duration_seconds"
        case distanceMeters = "distance_meters"
        case pace
        case ftpPct = "ftp_pct"
        case masPct = "mas_pct"
        case cadenceRpm = "cadence_rpm"
        case drill
        case cue
        case equipment
        case terrain
        case restSeconds = "rest_seconds"
        case repeats
        case segments
        case recovery
    }
}

// MARK: - Workout Library JSON Structure

/// Root structure for the workout library JSON file.
/// Contains arrays of templates grouped by sport.
struct WorkoutLibrary: Codable {
    let swim: [WorkoutTemplate]
    let bike: [WorkoutTemplate]
    let run: [WorkoutTemplate]
}

