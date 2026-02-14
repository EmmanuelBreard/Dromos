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
    // FIX #1: Changed to var to support convenience initializer for previews
    var label: String
    var durationMinutes: Int?
    var durationSeconds: Int?
    var distanceMeters: Int?
    var pace: String?
    var ftpPct: Int?
    var masPct: Int?
    var cadenceRpm: Int?
    var drill: String?
    var cue: String?
    var equipment: String?
    var terrain: String?
    var restSeconds: Int?
    var repeats: Int?
    var segments: [WorkoutSegment]?
    var recovery: WorkoutSegment?

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
    
    // MARK: - Convenience Initializer for Previews
    
    /// Convenience initializer for creating WorkoutSegment instances in previews and tests.
    /// All parameters default to nil except label (required).
    convenience init(
        label: String = "",
        durationMinutes: Int? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Int? = nil,
        pace: String? = nil,
        ftpPct: Int? = nil,
        masPct: Int? = nil,
        cadenceRpm: Int? = nil,
        drill: String? = nil,
        cue: String? = nil,
        equipment: String? = nil,
        terrain: String? = nil,
        restSeconds: Int? = nil,
        repeats: Int? = nil,
        segments: [WorkoutSegment]? = nil,
        recovery: WorkoutSegment? = nil
    ) {
        self.init()
        self.label = label
        self.durationMinutes = durationMinutes
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.pace = pace
        self.ftpPct = ftpPct
        self.masPct = masPct
        self.cadenceRpm = cadenceRpm
        self.drill = drill
        self.cue = cue
        self.equipment = equipment
        self.terrain = terrain
        self.restSeconds = restSeconds
        self.repeats = repeats
        self.segments = segments
        self.recovery = recovery
    }
    
    /// Default initializer for convenience init
    private init() {
        self.label = ""
    }
}

// MARK: - Flat Segment

/// A flattened segment for graph rendering.
/// Expands nested repeats into individual iterations for visualization.
struct FlatSegment: Identifiable {
    // FIX #9: Add Identifiable conformance
    let id = UUID()
    
    /// Segment label (e.g., "warmup", "work", "recovery", "cooldown")
    let label: String
    
    /// Total duration of this segment in minutes
    let durationMinutes: Double
    
    /// Intensity percentage — ftpPct for bike, masPct for run.
    /// Drives both bar height and color in the intensity graph.
    let intensityPct: Int?
    
    /// Distance in meters (for swim segments)
    let distanceMeters: Int?
    
    /// Pace label (for swim segments, e.g., "easy", "medium", "quick")
    let pace: String?
    
    /// True for recovery segments between repeats (always shown in green)
    let isRecovery: Bool
}

// MARK: - Step Summary

/// A summarized workout step for text display.
/// Collapses repeat blocks into single lines, shows sport-specific metrics.
struct StepSummary: Identifiable {
    // FIX #9: Add Identifiable conformance
    let id = UUID()
    
    /// The formatted text for this step.
    /// Examples:
    /// - Bike: "15' warmup - 156 W"
    /// - Run: "10' tempo - 12.0 km/h (5:00/km)"
    /// - Swim: "300m warmup" or "4×100m medium"
    /// - Repeat: "3× (6' work - 260 W + 4' recovery)"
    let text: String
    
    /// Intensity percentage for color-coding the dot.
    /// Uses ftpPct (bike) or masPct (run) to drive the intensity color gradient.
    let intensityPct: Int?
    
    /// True for collapsed repeat block summaries
    let isRepeatBlock: Bool
}

// MARK: - Workout Library JSON Structure

/// Root structure for the workout library JSON file.
/// Contains arrays of templates grouped by sport.
struct WorkoutLibrary: Codable {
    let swim: [WorkoutTemplate]
    let bike: [WorkoutTemplate]
    let run: [WorkoutTemplate]
}
