//
//  WorkoutLibraryService.swift
//  Dromos
//
//  Created by Emmanuel Breard on 01/02/2026.
//

import Foundation
import OSLog

/// Service for accessing workout templates from the bundled library.
/// Provides lookup by templateId, swim distance calculation, segment flattening, and step summaries.
/// Uses a singleton pattern since the data is static and read-only.
final class WorkoutLibraryService {
    
    // MARK: - Singleton
    
    /// Shared instance of the workout library service.
    static let shared = WorkoutLibraryService()
    
    // MARK: - Properties
    
    /// Dictionary of templates keyed by templateId for O(1) lookup.
    private var templates: [String: WorkoutTemplate] = [:]
    
    /// Logger for debugging library operations.
    private let logger = Logger(subsystem: "com.dromos.app", category: "WorkoutLibrary")
    
    // MARK: - Initialization
    
    private init() {
        loadLibrary()
    }
    
    // MARK: - Public Methods
    
    /// Looks up a workout template by its templateId.
    /// - Parameter templateId: The unique identifier for the template (e.g., "SWIM_Tempo_01")
    /// - Returns: The WorkoutTemplate if found, nil otherwise
    func template(for templateId: String) -> WorkoutTemplate? {
        templates[templateId]
    }
    
    /// Calculates total swim distance for a template in meters.
    /// Walks segments recursively, summing `distanceMeters` and multiplying by `repeats` for repeat blocks.
    /// - Parameter templateId: The template identifier
    /// - Returns: Total distance in meters, or nil for non-swim templates or if template not found
    func swimDistance(for templateId: String) -> Int? {
        guard let template = templates[templateId],
              templateId.hasPrefix("SWIM_") else {
            return nil
        }
        
        return calculateDistance(segments: template.segments)
    }
    
    /// Flattens a workout template into individual segments for graph rendering.
    /// Expands nested repeats into individual iterations (e.g., 3 repeats → 3 work segments + 2 recovery segments).
    /// - Parameter templateId: The template identifier
    /// - Returns: Array of flattened segments, or empty array if template not found
    func flattenedSegments(for templateId: String) -> [FlatSegment] {
        guard let template = templates[templateId] else {
            logger.warning("Template not found: \(templateId)")
            return []
        }
        
        return flattenSegments(segments: template.segments)
    }
    
    /// Generates step summaries for a workout template with sport-specific formatting.
    /// Collapses repeat blocks into single lines, shows watts/speed/pace based on sport.
    /// - Parameters:
    ///   - templateId: The template identifier
    ///   - sport: Sport type ("swim", "bike", "run")
    ///   - ftp: Functional Threshold Power in watts (for bike)
    ///   - vma: Vitesse Maximale Aérobie in km/h (for run)
    ///   - css: Critical Swim Speed in total seconds per 100m (for swim)
    /// - Returns: Array of step summaries, or empty array if template not found
    func stepSummaries(for templateId: String, sport: String, ftp: Int?, vma: Double?, css: Int?) -> [StepSummary] {
        guard let template = templates[templateId] else {
            logger.warning("Template not found: \(templateId)")
            return []
        }
        
        return generateStepSummaries(segments: template.segments, sport: sport, ftp: ftp, vma: vma, css: css)
    }
    
    // MARK: - Private Methods
    
    /// Loads the workout library from the bundled JSON file.
    private func loadLibrary() {
        guard let url = Bundle.main.url(forResource: "workout-library", withExtension: "json") else {
            logger.error("workout-library.json not found in bundle")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let library = try JSONDecoder().decode(WorkoutLibrary.self, from: data)
            
            // Index all templates by templateId for fast lookup
            for template in library.swim {
                templates[template.templateId] = template
            }
            for template in library.bike {
                templates[template.templateId] = template
            }
            for template in library.run {
                templates[template.templateId] = template
            }
            
            logger.info("Loaded \(self.templates.count) workout templates")
        } catch {
            logger.error("Failed to load workout library: \(error.localizedDescription)")
        }
    }
    
    /// Recursively calculates total distance from an array of segments.
    /// Handles nested repeat blocks with the `repeats` multiplier.
    /// - Parameter segments: Array of workout segments
    /// - Returns: Total distance in meters
    private func calculateDistance(segments: [WorkoutSegment]) -> Int {
        var total = 0
        
        for segment in segments {
            // Check if this is a repeat block
            if let repeats = segment.repeats, let nestedSegments = segment.segments {
                // Multiply nested segment distance by repeat count
                let nestedDistance = calculateDistance(segments: nestedSegments)
                total += nestedDistance * repeats
                
                // Recovery is swum between repeats, so (repeats - 1) times
                // Example: 3 repeats = swim recovery 2 times (after rep 1 and rep 2)
                if let recovery = segment.recovery, let recoveryDistance = recovery.distanceMeters {
                    total += recoveryDistance * max(0, repeats - 1)
                }
            } else if let distance = segment.distanceMeters {
                // Simple segment with direct distance
                total += distance
            }
            
            // Check if segment has inline recovery with distance (non-repeat blocks)
            if let recovery = segment.recovery, let recoveryDistance = recovery.distanceMeters {
                // Only count if not already counted in repeat block above
                if segment.repeats == nil {
                    total += recoveryDistance
                }
            }
        }
        
        return total
    }
    
    /// Recursively flattens segments, expanding repeats into individual iterations.
    /// - Parameter segments: Array of workout segments
    /// - Returns: Array of flattened segments
    private func flattenSegments(segments: [WorkoutSegment]) -> [FlatSegment] {
        var flattened: [FlatSegment] = []
        
        for segment in segments {
            // Handle repeat blocks
            if let repeats = segment.repeats, let nestedSegments = segment.segments {
                // Expand repeats into individual iterations
                for i in 0..<repeats {
                    // Add work segments
                    flattened.append(contentsOf: flattenSegments(segments: nestedSegments))
                    
                    // Add recovery segment between repeats (not after the last one)
                    if i < repeats - 1 {
                        if let recovery = segment.recovery {
                            flattened.append(createFlatSegment(from: recovery, isRecovery: true))
                        } else if let restSec = segment.restSeconds {
                            // FIX #2: Synthesize rest segment when recovery is nil but restSeconds exists
                            flattened.append(FlatSegment(
                                label: "rest",
                                durationMinutes: Double(restSec) / 60.0,
                                intensityPct: nil,
                                distanceMeters: nil,
                                pace: nil,
                                isRecovery: true
                            ))
                        }
                    }
                }
            } else {
                // FIX #4: Check label to determine if inline segment is recovery
                let isRecovery = segment.label.lowercased() == "recovery" || segment.label.lowercased() == "rest"
                flattened.append(createFlatSegment(from: segment, isRecovery: isRecovery))
            }
        }
        
        return flattened
    }
    
    /// Creates a FlatSegment from a WorkoutSegment.
    /// - Parameters:
    ///   - segment: The source segment
    ///   - isRecovery: Whether this segment is a recovery segment
    /// - Returns: A flattened segment
    private func createFlatSegment(from segment: WorkoutSegment, isRecovery: Bool) -> FlatSegment {
        // Calculate duration in minutes
        let durationMinutes: Double
        if let minutes = segment.durationMinutes {
            durationMinutes = Double(minutes)
        } else if let seconds = segment.durationSeconds {
            durationMinutes = Double(seconds) / 60.0
        } else if let distance = segment.distanceMeters {
            // Estimate duration from distance (for swim: ~1.5 min per 100m as baseline)
            durationMinutes = Double(distance) / 100.0 * 1.5
        } else if let restSec = segment.restSeconds {
            // FIX #1: Add restSeconds as fallback after distanceMeters
            durationMinutes = Double(restSec) / 60.0
        } else {
            durationMinutes = 0
        }
        
        // Get intensity percentage (ftpPct for bike, masPct for run)
        let intensityPct = segment.ftpPct ?? segment.masPct
        
        return FlatSegment(
            label: segment.label,
            durationMinutes: durationMinutes,
            intensityPct: intensityPct,
            distanceMeters: segment.distanceMeters,
            pace: segment.pace,
            isRecovery: isRecovery
        )
    }
    
    /// Recursively generates step summaries from segments.
    /// - Parameters:
    ///   - segments: Array of workout segments
    ///   - sport: Sport type ("swim", "bike", "run")
    ///   - ftp: Functional Threshold Power in watts (for bike)
    ///   - vma: Vitesse Maximale Aérobie in km/h (for run)
    ///   - css: Critical Swim Speed in total seconds per 100m (for swim)
    /// - Returns: Array of step summaries
    private func generateStepSummaries(segments: [WorkoutSegment], sport: String, ftp: Int?, vma: Double?, css: Int?) -> [StepSummary] {
        var summaries: [StepSummary] = []
        
        for segment in segments {
            // Handle repeat blocks (collapsed into single line)
            if let repeats = segment.repeats, let nestedSegments = segment.segments {
                // FIX #3: Pass restSeconds to formatRepeatBlock
                let repeatSummary = formatRepeatBlock(
                    repeats: repeats,
                    segments: nestedSegments,
                    recovery: segment.recovery,
                    restSeconds: segment.restSeconds,
                    sport: sport,
                    ftp: ftp,
                    vma: vma,
                    css: css
                )
                summaries.append(repeatSummary)
            } else {
                // Simple segment
                let summary = formatSegment(segment: segment, sport: sport, ftp: ftp, vma: vma, css: css)
                summaries.append(summary)
            }
        }
        
        return summaries
    }
    
    /// Formats a repeat block as a collapsed summary line.
    /// Example: "3× (6' work - 260 W + 4' recovery)"
    /// - Parameters:
    ///   - repeats: Number of repeats
    ///   - segments: Nested segments within the repeat
    ///   - recovery: Optional recovery segment
    ///   - restSeconds: Optional rest seconds from parent segment
    ///   - sport: Sport type
    ///   - ftp: FTP in watts
    ///   - vma: VMA in km/h
    ///   - css: CSS in seconds per 100m
    /// - Returns: A step summary for the repeat block
    private func formatRepeatBlock(
        repeats: Int,
        segments: [WorkoutSegment],
        recovery: WorkoutSegment?,
        restSeconds: Int?,
        sport: String,
        ftp: Int?,
        vma: Double?,
        css: Int?
    ) -> StepSummary {
        var parts: [String] = []
        
        // Format work segments (usually just one, but could be multiple)
        for segment in segments {
            let duration = formatDuration(segment: segment)
            let label = segment.label
            let metric = formatMetric(segment: segment, sport: sport, ftp: ftp, vma: vma, css: css)
            
            if let metric = metric {
                parts.append("\(duration) \(label) - \(metric)")
            } else {
                parts.append("\(duration) \(label)")
            }
        }
        
        // FIX #3: Add recovery text when recovery is nil but restSeconds exists
        if let recovery = recovery {
            let duration = formatDuration(segment: recovery)
            parts.append("\(duration) recovery")
        } else if let restSec = restSeconds {
            let seconds = restSec % 60
            let minutes = restSec / 60
            if minutes > 0 && seconds > 0 {
                parts.append("\(minutes)'\(String(format: "%02d", seconds))\" rest")
            } else if minutes > 0 {
                parts.append("\(minutes)' rest")
            } else {
                parts.append("\(restSec)\" rest")
            }
        }
        
        let innerText = parts.joined(separator: " + ")
        let text = "\(repeats)× (\(innerText))"
        
        // Use intensity from first work segment for dot color
        let intensityPct = segments.first?.ftpPct ?? segments.first?.masPct
        
        return StepSummary(text: text, intensityPct: intensityPct, isRepeatBlock: true)
    }
    
    /// Formats a simple segment as a step summary.
    /// - Parameters:
    ///   - segment: The segment to format
    ///   - sport: Sport type
    ///   - ftp: FTP in watts
    ///   - vma: VMA in km/h
    ///   - css: CSS in seconds per 100m
    /// - Returns: A step summary
    private func formatSegment(segment: WorkoutSegment, sport: String, ftp: Int?, vma: Double?, css: Int?) -> StepSummary {
        let duration = formatDuration(segment: segment)
        let label = segment.label
        let metric = formatMetric(segment: segment, sport: sport, ftp: ftp, vma: vma, css: css)
        
        let text: String
        if let metric = metric {
            text = "\(duration) \(label) - \(metric)"
        } else {
            text = "\(duration) \(label)"
        }
        
        let intensityPct = segment.ftpPct ?? segment.masPct
        
        return StepSummary(text: text, intensityPct: intensityPct, isRepeatBlock: false)
    }
    
    /// Formats the duration of a segment (minutes or distance for swim).
    /// - Parameter segment: The segment
    /// - Returns: Formatted duration string (e.g., "15'", "300m")
    private func formatDuration(segment: WorkoutSegment) -> String {
        if let distance = segment.distanceMeters {
            return "\(distance)m"
        } else if let minutes = segment.durationMinutes {
            return "\(minutes)'"
        } else if let seconds = segment.durationSeconds {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            if remainingSeconds == 0 {
                return "\(minutes)'"
            } else {
                // FIX #5: Format seconds with leading zero (2'30" not 2'.30")
                return "\(minutes)'\(String(format: "%02d", remainingSeconds))\""
            }
        }
        return "?"
    }
    
    /// Formats the sport-specific metric for a segment.
    /// - Parameters:
    ///   - segment: The segment
    ///   - sport: Sport type
    ///   - ftp: FTP in watts
    ///   - vma: VMA in km/h
    ///   - css: CSS in seconds per 100m
    /// - Returns: Formatted metric string, or nil if not applicable
    private func formatMetric(segment: WorkoutSegment, sport: String, ftp: Int?, vma: Double?, css: Int?) -> String? {
        switch sport.lowercased() {
        case "bike":
            if let ftpPct = segment.ftpPct {
                if let ftp = ftp {
                    let watts = Int(round(Double(ftpPct) / 100.0 * Double(ftp)))
                    return "\(watts) W"
                } else {
                    return "\(ftpPct)% FTP"
                }
            }
            
        case "run":
            if let masPct = segment.masPct {
                if let vma = vma {
                    let speed = vma * Double(masPct) / 100.0
                    let pace = speedToPace(speed: speed)
                    return String(format: "%.1f km/h (%@)", speed, pace)
                } else {
                    return "\(masPct)% VMA"
                }
            }
            
        case "swim":
            // FIX #7: CSS-based pace calculation deferred — showing pace label only for now
            if let pace = segment.pace {
                return pace
            }
            
        default:
            break
        }
        
        return nil
    }
    
    /// Converts speed (km/h) to pace (min:sec per km).
    /// - Parameter speed: Speed in km/h
    /// - Returns: Formatted pace string (e.g., "5:00/km")
    func speedToPace(speed: Double) -> String {
        guard speed > 0 else { return "?:??/km" }
        
        let minutesPerKm = 60.0 / speed
        let minutes = Int(minutesPerKm)
        let seconds = Int((minutesPerKm - Double(minutes)) * 60.0)
        
        return String(format: "%d:%02d/km", minutes, seconds)
    }
}
