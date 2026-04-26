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
    var reps: Int?
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
        case reps
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
        reps: Int? = nil,
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
        self.reps = reps
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

    /// Intensity percentage normalized 0-100 for graph bar height + color.
    /// Drives both bar height and color in the intensity graph.
    let intensityPct: Int?

    /// Distance in meters (for swim segments)
    let distanceMeters: Int?

    /// Pace label (for swim segments, e.g., "easy", "medium", "quick").
    /// Used by legacy template path; structure path leaves this nil and uses tooltipMetric instead.
    let pace: String?

    /// True for recovery segments between repeats (always shown in green)
    let isRecovery: Bool

    /// Pre-formatted tooltip metric string (e.g., "260–275 W", "RPE 6 — moderate", "5:30/km").
    /// Populated by the structure-based render path so the graph tooltip can render polymorphic Target output.
    /// Nil for legacy template path — graph view falls back to its own per-sport formatter.
    let tooltipMetric: String?

    init(
        label: String,
        durationMinutes: Double,
        intensityPct: Int?,
        distanceMeters: Int?,
        pace: String?,
        isRecovery: Bool,
        tooltipMetric: String? = nil
    ) {
        self.label = label
        self.durationMinutes = durationMinutes
        self.intensityPct = intensityPct
        self.distanceMeters = distanceMeters
        self.pace = pace
        self.isRecovery = isRecovery
        self.tooltipMetric = tooltipMetric
    }
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
    let strength: [WorkoutTemplate]?
    let race: [WorkoutTemplate]?
}

// MARK: - Session Structure (DRO-213)

/// Top-level structure of a session — what gets stored in plan_sessions.structure JSONB.
struct SessionStructure: Codable, Equatable {
    let segments: [StructureSegment]
}

/// A single segment in a session structure. Recursive — repeat segments contain nested segments.
/// Uses class for proper recursive Codable (matches existing WorkoutSegment pattern).
final class StructureSegment: Codable, Equatable {
    /// warmup | work | recovery | cooldown | repeat | rest | drill
    var label: String
    var durationMinutes: Double?
    var distanceMeters: Int?
    var target: Target?
    var cadenceRpm: Int?
    var constraints: [Constraint]?
    var cue: String?
    var drill: String?
    var repeats: Int?
    var restSeconds: Int?
    var recovery: StructureSegment?
    var segments: [StructureSegment]?

    enum CodingKeys: String, CodingKey {
        case label
        case durationMinutes = "duration_minutes"
        case distanceMeters = "distance_meters"
        case target
        case cadenceRpm = "cadence_rpm"
        case constraints
        case cue
        case drill
        case repeats
        case restSeconds = "rest_seconds"
        case recovery
        case segments
    }

    init(
        label: String,
        durationMinutes: Double? = nil,
        distanceMeters: Int? = nil,
        target: Target? = nil,
        cadenceRpm: Int? = nil,
        constraints: [Constraint]? = nil,
        cue: String? = nil,
        drill: String? = nil,
        repeats: Int? = nil,
        restSeconds: Int? = nil,
        recovery: StructureSegment? = nil,
        segments: [StructureSegment]? = nil
    ) {
        self.label = label
        self.durationMinutes = durationMinutes
        self.distanceMeters = distanceMeters
        self.target = target
        self.cadenceRpm = cadenceRpm
        self.constraints = constraints
        self.cue = cue
        self.drill = drill
        self.repeats = repeats
        self.restSeconds = restSeconds
        self.recovery = recovery
        self.segments = segments
    }

    static func == (lhs: StructureSegment, rhs: StructureSegment) -> Bool {
        lhs.label == rhs.label &&
        lhs.durationMinutes == rhs.durationMinutes &&
        lhs.distanceMeters == rhs.distanceMeters &&
        lhs.target == rhs.target &&
        lhs.cadenceRpm == rhs.cadenceRpm &&
        lhs.constraints == rhs.constraints &&
        lhs.cue == rhs.cue &&
        lhs.drill == rhs.drill &&
        lhs.repeats == rhs.repeats &&
        lhs.restSeconds == rhs.restSeconds &&
        lhs.recovery == rhs.recovery &&
        lhs.segments == rhs.segments
    }
}

/// Polymorphic intensity target — encoded with `type` discriminator.
enum Target: Codable, Equatable {
    case ftpPct(value: Double?, min: Double?, max: Double?)
    case vmaPct(value: Double?, min: Double?, max: Double?)
    case cssPct(value: Double?, min: Double?, max: Double?)
    case rpe(value: Double)
    case hrZone(value: Int)    // 1-5
    case hrPctMax(value: Double?, min: Double?, max: Double?)
    case powerWatts(value: Double?, min: Double?, max: Double?)
    case pacePerKm(value: String)       // e.g. "5:30"
    case pacePerHundredM(value: String) // e.g. "1:50"

    // MARK: - Custom Codable

    private enum TypeKey: String, CodingKey { case type }

    private enum PayloadKey: String, CodingKey {
        case value
        case min
        case max
    }

    init(from decoder: Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try typeContainer.decode(String.self, forKey: .type)
        let container = try decoder.container(keyedBy: PayloadKey.self)

        switch type_ {
        case "ftp_pct":
            let value = try container.decodeIfPresent(Double.self, forKey: .value)
            let min   = try container.decodeIfPresent(Double.self, forKey: .min)
            let max   = try container.decodeIfPresent(Double.self, forKey: .max)
            self = .ftpPct(value: value, min: min, max: max)

        case "vma_pct":
            let value = try container.decodeIfPresent(Double.self, forKey: .value)
            let min   = try container.decodeIfPresent(Double.self, forKey: .min)
            let max   = try container.decodeIfPresent(Double.self, forKey: .max)
            self = .vmaPct(value: value, min: min, max: max)

        case "css_pct":
            let value = try container.decodeIfPresent(Double.self, forKey: .value)
            let min   = try container.decodeIfPresent(Double.self, forKey: .min)
            let max   = try container.decodeIfPresent(Double.self, forKey: .max)
            self = .cssPct(value: value, min: min, max: max)

        case "rpe":
            let value = try container.decode(Double.self, forKey: .value)
            self = .rpe(value: value)

        case "hr_zone":
            let value = try container.decode(Int.self, forKey: .value)
            self = .hrZone(value: value)

        case "hr_pct_max":
            let value = try container.decodeIfPresent(Double.self, forKey: .value)
            let min   = try container.decodeIfPresent(Double.self, forKey: .min)
            let max   = try container.decodeIfPresent(Double.self, forKey: .max)
            self = .hrPctMax(value: value, min: min, max: max)

        case "power_watts":
            let value = try container.decodeIfPresent(Double.self, forKey: .value)
            let min   = try container.decodeIfPresent(Double.self, forKey: .min)
            let max   = try container.decodeIfPresent(Double.self, forKey: .max)
            self = .powerWatts(value: value, min: min, max: max)

        case "pace_per_km":
            let value = try container.decode(String.self, forKey: .value)
            self = .pacePerKm(value: value)

        case "pace_per_100m":
            let value = try container.decode(String.self, forKey: .value)
            self = .pacePerHundredM(value: value)

        default:
            throw DecodingError.dataCorruptedError(
                forKey: PayloadKey.value,
                in: container,
                debugDescription: "Unknown Target type: \(type_)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PayloadKey.self)
        var typeContainer = encoder.container(keyedBy: TypeKey.self)

        switch self {
        case let .ftpPct(value, min, max):
            try typeContainer.encode("ftp_pct", forKey: .type)
            try container.encodeIfPresent(value, forKey: .value)
            try container.encodeIfPresent(min, forKey: .min)
            try container.encodeIfPresent(max, forKey: .max)

        case let .vmaPct(value, min, max):
            try typeContainer.encode("vma_pct", forKey: .type)
            try container.encodeIfPresent(value, forKey: .value)
            try container.encodeIfPresent(min, forKey: .min)
            try container.encodeIfPresent(max, forKey: .max)

        case let .cssPct(value, min, max):
            try typeContainer.encode("css_pct", forKey: .type)
            try container.encodeIfPresent(value, forKey: .value)
            try container.encodeIfPresent(min, forKey: .min)
            try container.encodeIfPresent(max, forKey: .max)

        case let .rpe(value):
            try typeContainer.encode("rpe", forKey: .type)
            try container.encode(value, forKey: .value)

        case let .hrZone(value):
            try typeContainer.encode("hr_zone", forKey: .type)
            try container.encode(value, forKey: .value)

        case let .hrPctMax(value, min, max):
            try typeContainer.encode("hr_pct_max", forKey: .type)
            try container.encodeIfPresent(value, forKey: .value)
            try container.encodeIfPresent(min, forKey: .min)
            try container.encodeIfPresent(max, forKey: .max)

        case let .powerWatts(value, min, max):
            try typeContainer.encode("power_watts", forKey: .type)
            try container.encodeIfPresent(value, forKey: .value)
            try container.encodeIfPresent(min, forKey: .min)
            try container.encodeIfPresent(max, forKey: .max)

        case let .pacePerKm(value):
            try typeContainer.encode("pace_per_km", forKey: .type)
            try container.encode(value, forKey: .value)

        case let .pacePerHundredM(value):
            try typeContainer.encode("pace_per_100m", forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

/// Secondary constraints (e.g., HR cap).
enum Constraint: Codable, Equatable {
    case hrMax(value: Int)

    private enum TypeKey: String, CodingKey { case type }
    private enum PayloadKey: String, CodingKey { case value }

    init(from decoder: Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try typeContainer.decode(String.self, forKey: .type)
        let container = try decoder.container(keyedBy: PayloadKey.self)

        switch type_ {
        case "hr_max":
            let value = try container.decode(Int.self, forKey: .value)
            self = .hrMax(value: value)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: PayloadKey.value,
                in: container,
                debugDescription: "Unknown Constraint type: \(type_)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var typeContainer = encoder.container(keyedBy: TypeKey.self)
        var container = encoder.container(keyedBy: PayloadKey.self)

        switch self {
        case let .hrMax(value):
            try typeContainer.encode("hr_max", forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}
