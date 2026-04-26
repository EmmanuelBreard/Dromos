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
    private let logger = Logger(subsystem: "com.getdromos.app", category: "WorkoutLibrary")
    
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
            for t in library.strength ?? [] { templates[t.templateId] = t }
            for t in library.race ?? [] { templates[t.templateId] = t }

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
        var dur: Double
        if let minutes = segment.durationMinutes {
            dur = Double(minutes)
        } else if let seconds = segment.durationSeconds {
            dur = Double(seconds) / 60.0
        } else if let distance = segment.distanceMeters {
            // Estimate duration from distance (for swim: ~1.5 min per 100m as baseline)
            dur = Double(distance) / 100.0 * 1.5
        } else if let restSec = segment.restSeconds {
            // FIX #1: Add restSeconds as fallback after distanceMeters
            dur = Double(restSec) / 60.0
        } else {
            dur = 0
        }
        // Reps-based estimate for strength segments with no duration
        if dur == 0, let reps = segment.reps {
            dur = Double(reps * 4) / 60.0  // ~4 seconds per rep
        }
        let durationMinutes: Double = dur
        
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
            let duration = formatDuration(segment: segment, sport: sport)
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
        let duration = formatDuration(segment: segment, sport: sport)
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
    private func formatDuration(segment: WorkoutSegment, sport: String = "") -> String {
        if let distance = segment.distanceMeters {
            if sport == "run" && distance >= 1000 {
                let km = Double(distance) / 1000.0
                return km.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(km)) km"
                    : String(format: "%.1f km", km)
            }
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

        case "strength":
            if let reps = segment.reps {
                return "\(reps) reps"
            }
            if let secs = segment.durationSeconds {
                return "\(secs)s"
            }
            return nil

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

    // MARK: - DRO-213 Phase 5: SessionStructure rendering
    //
    // The new schema lives on PlanSession.structure (JSONB). Renderer prefers it; falls
    // back to template lookup + Swift materialize when nil (transitional path during the
    // first release that ships the new renderer).

    /// Dual-path entry: returns flattened graph segments for a session.
    /// Reads `session.structure` first; if nil, looks up the template and materializes.
    func flattenedSegments(
        for session: PlanSession,
        ftp: Int?,
        vma: Double?,
        css: Int?,
        maxHr: Int?
    ) -> [FlatSegment] {
        if let structure = session.structure {
            return flattenedSegments(
                structure: structure,
                sport: session.sport,
                ftp: ftp,
                vma: vma,
                css: css,
                maxHr: maxHr
            )
        }
        guard let template = templates[session.templateId] else { return [] }
        return flattenSegments(segments: template.segments)
    }

    /// Dual-path entry: returns step summaries for a session.
    /// Reads `session.structure` first; if nil, looks up the template and uses the legacy formatter.
    func stepSummaries(
        for session: PlanSession,
        ftp: Int?,
        vma: Double?,
        css: Int?,
        maxHr: Int?
    ) -> [StepSummary] {
        if let structure = session.structure {
            return stepSummaries(
                structure: structure,
                sport: session.sport,
                ftp: ftp,
                vma: vma,
                css: css,
                maxHr: maxHr
            )
        }
        guard let template = templates[session.templateId] else { return [] }
        return generateStepSummaries(segments: template.segments, sport: session.sport, ftp: ftp, vma: vma, css: css)
    }

    /// Returns false for simple swims (1 leaf segment, no repeats) — show distance only.
    /// Uses session.structure if present, else falls back to template lookup.
    func shouldShowWorkoutSteps(for session: PlanSession) -> Bool {
        guard session.sport.lowercased() == "swim" else { return true }
        if let structure = session.structure {
            return !(structure.segments.count == 1 && structure.segments.first?.repeats == nil)
        }
        guard let template = templates[session.templateId] else { return false }
        return !(template.segments.count == 1 && template.segments.first?.repeats == nil)
    }

    /// Total swim distance for a session, walking either structure or template.
    func swimDistance(for session: PlanSession) -> Int? {
        guard session.sport.lowercased() == "swim" else { return nil }
        if let structure = session.structure {
            return calculateDistance(structureSegments: structure.segments)
        }
        return swimDistance(for: session.templateId)
    }

    // MARK: Structure → FlatSegment

    func flattenedSegments(
        structure: SessionStructure,
        sport: String,
        ftp: Int?,
        vma: Double?,
        css: Int?,
        maxHr: Int?
    ) -> [FlatSegment] {
        flattenStructureSegments(
            structure.segments,
            sport: sport, ftp: ftp, vma: vma, css: css, maxHr: maxHr
        )
    }

    private func flattenStructureSegments(
        _ segments: [StructureSegment],
        sport: String,
        ftp: Int?,
        vma: Double?,
        css: Int?,
        maxHr: Int?
    ) -> [FlatSegment] {
        var out: [FlatSegment] = []
        for seg in segments {
            if let repeats = seg.repeats, let nested = seg.segments {
                for i in 0..<repeats {
                    out.append(contentsOf: flattenStructureSegments(
                        nested,
                        sport: sport, ftp: ftp, vma: vma, css: css, maxHr: maxHr
                    ))
                    if i < repeats - 1 {
                        if let recovery = seg.recovery {
                            out.append(makeFlatSegment(
                                from: recovery, isRecovery: true,
                                sport: sport, ftp: ftp, vma: vma, css: css, maxHr: maxHr
                            ))
                        } else if let restSec = seg.restSeconds {
                            out.append(FlatSegment(
                                label: "rest",
                                durationMinutes: Double(restSec) / 60.0,
                                intensityPct: nil,
                                distanceMeters: nil,
                                pace: nil,
                                isRecovery: true,
                                tooltipMetric: nil
                            ))
                        }
                    }
                }
            } else {
                let lower = seg.label.lowercased()
                let isRecovery = (lower == "recovery" || lower == "rest")
                out.append(makeFlatSegment(
                    from: seg, isRecovery: isRecovery,
                    sport: sport, ftp: ftp, vma: vma, css: css, maxHr: maxHr
                ))
            }
        }
        return out
    }

    private func makeFlatSegment(
        from seg: StructureSegment,
        isRecovery: Bool,
        sport: String,
        ftp: Int?,
        vma: Double?,
        css: Int?,
        maxHr: Int?
    ) -> FlatSegment {
        // Duration in minutes — prefer duration_minutes; fall back to estimate from distance for swim
        var dur: Double = seg.durationMinutes ?? 0
        if dur == 0, let distance = seg.distanceMeters {
            dur = Double(distance) / 100.0 * 1.5
        }
        let intensity = intensityPct(
            for: seg.target, sport: sport,
            ftp: ftp, vma: vma, css: css, maxHr: maxHr
        )
        let metric = displayString(
            for: seg.target, sport: sport,
            ftp: ftp, vma: vma, css: css, maxHr: maxHr
        )
        return FlatSegment(
            label: seg.label,
            durationMinutes: dur,
            intensityPct: intensity,
            distanceMeters: seg.distanceMeters,
            pace: nil,
            isRecovery: isRecovery,
            tooltipMetric: metric
        )
    }

    // MARK: Structure → StepSummary

    func stepSummaries(
        structure: SessionStructure,
        sport: String,
        ftp: Int?,
        vma: Double?,
        css: Int?,
        maxHr: Int?
    ) -> [StepSummary] {
        generateStructureStepSummaries(
            structure.segments,
            sport: sport, ftp: ftp, vma: vma, css: css, maxHr: maxHr
        )
    }

    private func generateStructureStepSummaries(
        _ segments: [StructureSegment],
        sport: String,
        ftp: Int?,
        vma: Double?,
        css: Int?,
        maxHr: Int?
    ) -> [StepSummary] {
        var out: [StepSummary] = []
        for seg in segments {
            if let repeats = seg.repeats, let nested = seg.segments {
                out.append(formatStructureRepeatBlock(
                    repeats: repeats, segments: nested,
                    recovery: seg.recovery, restSeconds: seg.restSeconds,
                    sport: sport, ftp: ftp, vma: vma, css: css, maxHr: maxHr
                ))
            } else {
                out.append(formatStructureSegment(
                    seg, sport: sport, ftp: ftp, vma: vma, css: css, maxHr: maxHr
                ))
            }
        }
        return out
    }

    private func formatStructureSegment(
        _ seg: StructureSegment,
        sport: String,
        ftp: Int?, vma: Double?, css: Int?, maxHr: Int?
    ) -> StepSummary {
        let duration = formatStructureDuration(seg, sport: sport)
        let label = seg.label
        let metric = displayString(for: seg.target, sport: sport, ftp: ftp, vma: vma, css: css, maxHr: maxHr)
        let cue = (seg.cue?.isEmpty == false) ? seg.cue : nil

        var text = "\(duration) \(label)"
        if let metric = metric { text += " - \(metric)" }
        if let cue = cue { text += " (\(cue))" }

        let intensity = intensityPct(for: seg.target, sport: sport, ftp: ftp, vma: vma, css: css, maxHr: maxHr)
        return StepSummary(text: text, intensityPct: intensity, isRepeatBlock: false)
    }

    private func formatStructureRepeatBlock(
        repeats: Int,
        segments: [StructureSegment],
        recovery: StructureSegment?,
        restSeconds: Int?,
        sport: String,
        ftp: Int?, vma: Double?, css: Int?, maxHr: Int?
    ) -> StepSummary {
        var parts: [String] = []
        for seg in segments {
            // Recursively format nested repeats so 3-level nesting (e.g. SWIM_Tempo_02) reads cleanly.
            if let innerRepeats = seg.repeats, let innerSegs = seg.segments {
                let inner = formatStructureRepeatBlock(
                    repeats: innerRepeats, segments: innerSegs,
                    recovery: seg.recovery, restSeconds: seg.restSeconds,
                    sport: sport, ftp: ftp, vma: vma, css: css, maxHr: maxHr
                )
                parts.append(inner.text)
            } else {
                let duration = formatStructureDuration(seg, sport: sport)
                let label = seg.label
                let metric = displayString(for: seg.target, sport: sport, ftp: ftp, vma: vma, css: css, maxHr: maxHr)
                if let metric = metric {
                    parts.append("\(duration) \(label) - \(metric)")
                } else {
                    parts.append("\(duration) \(label)")
                }
            }
        }
        if let recovery = recovery {
            parts.append("\(formatStructureDuration(recovery, sport: sport)) recovery")
        } else if let restSec = restSeconds {
            let m = restSec / 60, s = restSec % 60
            if m > 0 && s > 0      { parts.append("\(m)'\(String(format: "%02d", s))\" rest") }
            else if m > 0          { parts.append("\(m)' rest") }
            else                   { parts.append("\(restSec)\" rest") }
        }
        let inner = parts.joined(separator: " + ")
        let text = "\(repeats)× (\(inner))"
        let firstLeaf = segments.first
        let intensity = intensityPct(
            for: firstLeaf?.target,
            sport: sport, ftp: ftp, vma: vma, css: css, maxHr: maxHr
        )
        return StepSummary(text: text, intensityPct: intensity, isRepeatBlock: true)
    }

    private func formatStructureDuration(_ seg: StructureSegment, sport: String) -> String {
        if let distance = seg.distanceMeters {
            if sport.lowercased() == "run" && distance >= 1000 {
                let km = Double(distance) / 1000.0
                return km.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(km)) km"
                    : String(format: "%.1f km", km)
            }
            return "\(distance)m"
        }
        if let mins = seg.durationMinutes {
            // Render integer minutes when possible (5'); else with decimal (5.5')
            let intMins = Int(mins)
            if Double(intMins) == mins { return "\(intMins)'" }
            return String(format: "%.1f'", mins)
        }
        return "?"
    }

    // MARK: Polymorphic Target formatter

    /// Returns concrete actionable display string for a target (no raw %).
    /// Resolution priority by sport: run pace→HR→RPE; swim pace/100m→RPE; bike watts→HR→RPE.
    /// When a metric required to resolve a percentage target is nil, falls back to RPE-equivalent.
    func displayString(
        for target: Target?,
        sport: String,
        ftp: Int?,
        vma: Double?,
        css: Int?,
        maxHr: Int?
    ) -> String? {
        guard let target = target else { return nil }
        switch target {
        case let .ftpPct(value, min, max):
            return percentToWatts(value: value, min: min, max: max, ftp: ftp)
                ?? rpeFallback(forPctMid(value: value, min: min, max: max))
        case let .vmaPct(value, min, max):
            return percentToRunPace(value: value, min: min, max: max, vma: vma)
                ?? rpeFallback(forPctMid(value: value, min: min, max: max))
        case let .cssPct(value, min, max):
            return percentToSwimPace(value: value, min: min, max: max, css: css)
                ?? rpeFallback(forPctMid(value: value, min: min, max: max))
        case let .rpe(value):
            return rpeDisplay(value)
        case let .hrZone(value):
            return hrZoneDisplay(zone: value, maxHr: maxHr)
        case let .hrPctMax(value, min, max):
            return hrPctMaxDisplay(value: value, min: min, max: max, maxHr: maxHr)
        case let .powerWatts(value, min, max):
            return wattsRangeDisplay(value: value, min: min, max: max)
        case let .pacePerKm(value):
            return "\(value)/km"
        case let .pacePerHundredM(value):
            return "\(value)/100m"
        }
    }

    /// Returns intensity percentage 0-100 for graph bar height. Approximate.
    func intensityPct(
        for target: Target?,
        sport: String,
        ftp: Int?,
        vma: Double?,
        css: Int?,
        maxHr: Int?
    ) -> Int? {
        guard let target = target else { return nil }
        switch target {
        case let .ftpPct(value, min, max):
            return clampIntensity(forPctMid(value: value, min: min, max: max))
        case let .vmaPct(value, min, max):
            return clampIntensity(forPctMid(value: value, min: min, max: max))
        case let .cssPct(value, min, max):
            return clampIntensity(forPctMid(value: value, min: min, max: max))
        case let .rpe(value):
            return clampIntensity(value * 10.0)
        case let .hrZone(value):
            switch value { case 1: return 55; case 2: return 65; case 3: return 75; case 4: return 85; default: return 95 }
        case let .hrPctMax(value, min, max):
            return clampIntensity(forPctMid(value: value, min: min, max: max))
        case let .powerWatts(value, min, max):
            guard let ftp = ftp, ftp > 0, let mid = forPctMid(value: value, min: min, max: max) else { return 70 }
            return clampIntensity(mid / Double(ftp) * 100.0)
        case let .pacePerKm(value):
            guard let vma = vma, let kmh = paceStringToKmH(value), vma > 0 else { return 70 }
            return clampIntensity(kmh / vma * 100.0)
        case let .pacePerHundredM(value):
            // Faster pace = higher intensity. CSS is in seconds per 100m.
            guard let css = css, css > 0, let secs = paceStringToSeconds(value), secs > 0 else { return 70 }
            return clampIntensity(Double(css) / Double(secs) * 100.0)
        }
    }

    private func clampIntensity(_ v: Double?) -> Int {
        guard let v = v else { return 70 }
        return Swift.max(30, Swift.min(110, Int(v.rounded())))
    }

    private func forPctMid(value: Double?, min: Double?, max: Double?) -> Double? {
        if let v = value { return v }
        if let mn = min, let mx = max { return (mn + mx) / 2.0 }
        return nil
    }

    private func percentToWatts(value: Double?, min: Double?, max: Double?, ftp: Int?) -> String? {
        guard let ftp = ftp, ftp > 0 else { return nil }
        if let mn = min, let mx = max {
            let lo = Int((Double(ftp) * mn / 100.0).rounded())
            let hi = Int((Double(ftp) * mx / 100.0).rounded())
            return "\(lo)–\(hi) W"
        }
        if let v = value {
            return "\(Int((Double(ftp) * v / 100.0).rounded())) W"
        }
        return nil
    }

    private func percentToRunPace(value: Double?, min: Double?, max: Double?, vma: Double?) -> String? {
        guard let vma = vma, vma > 0 else { return nil }
        // VMA in km/h. mas_pct% → speed = vma * pct/100. Pace is the min:sec/km of that speed.
        if let mn = min, let mx = max {
            // Faster pace corresponds to higher percentage; format low→high pace as max%→min%.
            let fastSpeed = vma * mx / 100.0  // higher pct = faster speed = lower min:sec
            let slowSpeed = vma * mn / 100.0
            return "\(speedToPaceShort(fastSpeed))–\(speedToPaceShort(slowSpeed))/km"
        }
        if let v = value {
            let speed = vma * v / 100.0
            return "\(speedToPaceShort(speed))/km"
        }
        return nil
    }

    private func percentToSwimPace(value: Double?, min: Double?, max: Double?, css: Int?) -> String? {
        guard let css = css, css > 0 else { return nil }
        // CSS is total seconds per 100m. css_pct% reflects intensity relative to CSS — higher pct = faster pace.
        // target_seconds = css * 100 / pct. (At pct=100, target_seconds = css.)
        if let mn = min, let mx = max {
            let fastSecs = Double(css) * 100.0 / mx
            let slowSecs = Double(css) * 100.0 / mn
            return "\(secondsToMinSec(fastSecs))–\(secondsToMinSec(slowSecs))/100m"
        }
        if let v = value {
            let secs = Double(css) * 100.0 / v
            return "\(secondsToMinSec(secs))/100m"
        }
        return nil
    }

    private func wattsRangeDisplay(value: Double?, min: Double?, max: Double?) -> String? {
        if let mn = min, let mx = max { return "\(Int(mn.rounded()))–\(Int(mx.rounded())) W" }
        if let v = value { return "\(Int(v.rounded())) W" }
        return nil
    }

    private func hrZoneDisplay(zone: Int, maxHr: Int?) -> String? {
        guard let maxHr = maxHr else { return "Z\(zone) (set max HR in profile)" }
        let bounds: (lo: Double, hi: Double)
        switch zone {
        case 1: bounds = (0.50, 0.60)
        case 2: bounds = (0.60, 0.70)
        case 3: bounds = (0.70, 0.80)
        case 4: bounds = (0.80, 0.90)
        default: bounds = (0.90, 1.00)
        }
        let lo = Int((Double(maxHr) * bounds.lo).rounded())
        let hi = Int((Double(maxHr) * bounds.hi).rounded())
        return "\(lo)–\(hi) bpm"
    }

    private func hrPctMaxDisplay(value: Double?, min: Double?, max: Double?, maxHr: Int?) -> String? {
        guard let maxHr = maxHr else {
            if let mn = min, let mx = max { return "\(Int(mn.rounded()))–\(Int(mx.rounded()))% max HR" }
            if let v = value { return "\(Int(v.rounded()))% max HR" }
            return nil
        }
        if let mn = min, let mx = max {
            let lo = Int((Double(maxHr) * mn / 100.0).rounded())
            let hi = Int((Double(maxHr) * mx / 100.0).rounded())
            return "\(lo)–\(hi) bpm"
        }
        if let v = value {
            return "\(Int((Double(maxHr) * v / 100.0).rounded())) bpm"
        }
        return nil
    }

    private func rpeDisplay(_ value: Double) -> String {
        let v = Int(value.rounded())
        let descriptor: String
        switch v {
        case ...2: descriptor = "very easy"
        case 3, 4: descriptor = "easy"
        case 5: descriptor = "steady"
        case 6: descriptor = "moderate"
        case 7: descriptor = "comfortably hard"
        case 8: descriptor = "hard"
        case 9: descriptor = "very hard"
        default: descriptor = "max"
        }
        return "RPE \(v) — \(descriptor)"
    }

    /// Maps a percentage (0-110) to an RPE display when the underlying metric is missing.
    private func rpeFallback(_ pct: Double?) -> String? {
        guard let pct = pct else { return nil }
        let rpeValue: Double
        switch pct {
        case ..<55: rpeValue = 3
        case ..<65: rpeValue = 4
        case ..<75: rpeValue = 5
        case ..<82: rpeValue = 6
        case ..<90: rpeValue = 7
        case ..<98: rpeValue = 8
        case ..<105: rpeValue = 9
        default: rpeValue = 10
        }
        return rpeDisplay(rpeValue)
    }

    // MARK: Pace string helpers

    /// "5:30" → 330 seconds. Returns nil for malformed input.
    private func paceStringToSeconds(_ s: String) -> Int? {
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let m = Int(parts[0]),
              let sec = Int(parts[1]) else { return nil }
        return m * 60 + sec
    }

    /// "5:30" → 60/5.5 ≈ 10.9 km/h. Returns nil for malformed input.
    private func paceStringToKmH(_ s: String) -> Double? {
        guard let secs = paceStringToSeconds(s), secs > 0 else { return nil }
        return 3600.0 / Double(secs)
    }

    /// km/h → "5:30" pace. Same shape as `speedToPace` but without the `/km` suffix.
    private func speedToPaceShort(_ speed: Double) -> String {
        guard speed > 0 else { return "?:??" }
        let minutesPerKm = 60.0 / speed
        let m = Int(minutesPerKm)
        let s = Int((minutesPerKm - Double(m)) * 60.0)
        return String(format: "%d:%02d", m, s)
    }

    /// Total seconds → "1:38" minute:second.
    private func secondsToMinSec(_ totalSeconds: Double) -> String {
        let total = Int(totalSeconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: Distance walking for SessionStructure

    private func calculateDistance(structureSegments segments: [StructureSegment]) -> Int {
        var total = 0
        for seg in segments {
            if let repeats = seg.repeats, let nested = seg.segments {
                let nestedDist = calculateDistance(structureSegments: nested)
                total += nestedDist * repeats
                if let recovery = seg.recovery, let recoveryDistance = recovery.distanceMeters {
                    total += recoveryDistance * Swift.max(0, repeats - 1)
                }
            } else if let distance = seg.distanceMeters {
                total += distance
            }
            if let recovery = seg.recovery, let recoveryDistance = recovery.distanceMeters,
               seg.repeats == nil {
                total += recoveryDistance
            }
        }
        return total
    }

    // MARK: - Swift port of TS materializer (transitional fallback)
    //
    // Mirrors `supabase/functions/_shared/materialize-structure.ts`. Used when a session has
    // template_id but no structure (older rows pre-backfill, or legacy fallback path).

    private static let swimPaceToRpe: [String: Double] = [
        "slow": 3, "easy": 3,
        "medium": 6,
        "quick": 7, "threshold": 7,
        "fast": 8,
        "very_quick": 9
    ]

    /// Materializes a legacy WorkoutTemplate into a SessionStructure.
    func materialize(template: WorkoutTemplate) -> SessionStructure {
        SessionStructure(segments: template.segments.map(materializeSegment(_:)))
    }

    private func materializeSegment(_ src: WorkoutSegment) -> StructureSegment {
        // Pick exactly one of duration / distance: prefer duration.
        var durationMinutes: Double?
        var distanceMeters: Int?
        if let mins = src.durationMinutes {
            durationMinutes = Double(mins)
        } else if let secs = src.durationSeconds {
            durationMinutes = ceil(Double(secs) / 60.0)
        } else if let d = src.distanceMeters {
            distanceMeters = d
        }
        // Repeat containers carry no target — only leaves do.
        let target: Target? = (src.repeats != nil) ? nil : resolveLegacyTarget(src)

        let nested = src.segments?.map(materializeSegment(_:))
        let recovery = src.recovery.map(materializeSegment(_:))

        return StructureSegment(
            label: src.label,
            durationMinutes: durationMinutes,
            distanceMeters: distanceMeters,
            target: target,
            cadenceRpm: src.cadenceRpm,
            constraints: nil,
            cue: src.cue,
            drill: src.drill,
            repeats: src.repeats,
            restSeconds: src.restSeconds,
            recovery: recovery,
            segments: nested
        )
    }

    private func resolveLegacyTarget(_ s: WorkoutSegment) -> Target? {
        if let pct = s.ftpPct {
            return .ftpPct(value: Double(pct), min: nil, max: nil)
        }
        // Phase 1 backfill rule: mas_pct → vma_pct (legacy alias)
        if let pct = s.masPct {
            return .vmaPct(value: Double(pct), min: nil, max: nil)
        }
        if let pace = s.pace?.lowercased(),
           let rpe = Self.swimPaceToRpe[pace] {
            return .rpe(value: rpe)
        }
        return nil
    }
}
