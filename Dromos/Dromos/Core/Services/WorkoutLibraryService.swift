//
//  WorkoutLibraryService.swift
//  Dromos
//
//  Created by Emmanuel Breard on 01/02/2026.
//

import Foundation
import OSLog

/// Service for accessing workout templates from the bundled library.
/// Provides lookup by templateId and swim distance calculation.
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
}

