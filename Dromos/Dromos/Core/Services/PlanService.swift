//
//  PlanService.swift
//  Dromos
//
//  Created by Emmanuel Breard on 01/02/2026.
//

import Combine
import Foundation
import Supabase

/// Service for generating training plans via Edge Function.
/// Handles the long-running plan generation process (~140s) with progress tracking.
@MainActor
final class PlanService: ObservableObject {

    // MARK: - Published Properties

    /// Whether plan generation is currently in progress.
    @Published private(set) var isGenerating: Bool = false

    /// Last error message from plan generation, nil if no error.
    @Published var errorMessage: String?

    /// Current training plan, nil if not loaded.
    @Published private(set) var trainingPlan: TrainingPlan?

    /// Whether plan data is currently being fetched.
    @Published private(set) var isLoadingPlan: Bool = false

    // MARK: - Private Properties

    private let client = SupabaseClientProvider.client

    // MARK: - Public Methods

    /// Generate a training plan for the current user.
    /// Calls the `generate-plan` Edge Function which reads the user's profile server-side.
    /// The Bearer token is sent automatically by the SDK from the current session.
    /// - Throws: Error if generation fails
    func generatePlan() async throws {
        isGenerating = true
        errorMessage = nil

        defer { isGenerating = false }

        do {
            // Invoke the Edge Function (no body needed — Edge Function reads profile server-side)
            // The SDK automatically includes the Bearer token from the current session
            try await client.functions.invoke("generate-plan")

            // Success — plan generation completed
            // The plan is now in the database with status='active'
            // Edge Function returns 4xx/5xx on errors, which are handled in the catch block
        } catch {
            // Map various error types to user-friendly messages
            if let functionsError = error as? FunctionsError {
                switch functionsError {
                case .httpError(let code, let data):
                    // HTTP error from Edge Function
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMessage = json["error"] as? String {
                        self.errorMessage = errorMessage
                        throw PlanGenerationError.serverError(errorMessage)
                    } else {
                        let message = "Plan generation failed (HTTP \(code)). Please try again."
                        self.errorMessage = message
                        throw PlanGenerationError.serverError(message)
                    }
                case .relayError:
                    // Network/timeout error
                    let userMessage = "Unable to connect to the server. Please check your internet connection and try again."
                    self.errorMessage = userMessage
                    throw PlanGenerationError.networkError(userMessage)
                @unknown default:
                    let message = "An unexpected error occurred. Please try again."
                    self.errorMessage = message
                    throw PlanGenerationError.unknown(message)
                }
            } else if let planError = error as? PlanGenerationError {
                // Re-throw our custom errors (already have errorMessage set)
                throw planError
            } else {
                // Generic error
                let message = "Plan generation failed. Please try again."
                self.errorMessage = message
                throw PlanGenerationError.unknown(error.localizedDescription)
            }
        }
    }

    /// Fetch the full training plan for a user.
    /// Performs a nested query to fetch training_plans → plan_weeks → plan_sessions.
    /// - Parameter userId: The user's ID
    /// - Throws: Error if fetch fails
    func fetchFullPlan(userId: UUID) async throws {
        isLoadingPlan = true
        errorMessage = nil

        defer { isLoadingPlan = false }

        do {
            // Nested select: training_plans → plan_weeks → plan_sessions
            // PostgREST nested selects don't guarantee order, so we sort client-side
            let response: TrainingPlan = try await client
                .from("training_plans")
                .select("*, plan_weeks(*, plan_sessions(*))")
                .eq("user_id", value: userId.uuidString)
                .eq("status", value: "active")
                .single()
                .execute()
                .value

            // Sort planWeeks by weekNumber
            var sortedPlan = response
            sortedPlan.planWeeks.sort { $0.weekNumber < $1.weekNumber }

            let weekdayOrder: [String: Int] = [
                "Monday": 0,
                "Tuesday": 1,
                "Wednesday": 2,
                "Thursday": 3,
                "Friday": 4,
                "Saturday": 5,
                "Sunday": 6
            ]

            // Sort planSessions within each week by day order then orderInDay
            for weekIndex in sortedPlan.planWeeks.indices {
                sortedPlan.planWeeks[weekIndex].planSessions.sort { session1, session2 in
                    let dayOrder1 = weekdayOrder[session1.day] ?? 99
                    let dayOrder2 = weekdayOrder[session2.day] ?? 99
                    if dayOrder1 != dayOrder2 {
                        return dayOrder1 < dayOrder2
                    }
                    return session1.orderInDay < session2.orderInDay
                }
            }

            self.trainingPlan = sortedPlan
        } catch {
            errorMessage = "Failed to load training plan"
            throw error
        }
    }

    /// Clear the cached training plan (e.g., on sign out).
    func clearPlan() {
        trainingPlan = nil
        errorMessage = nil
    }

    /// Move a session to a new day/week at a specific index, with optimistic local mutation and Supabase persistence.
    /// Handles both cross-day moves and same-day reorders.
    /// On RPC failure, restores the previous state and sets `errorMessage`.
    /// - Parameters:
    ///   - sessionId: The ID of the session to move
    ///   - toDay: Full weekday name of the destination day (e.g., "Monday")
    ///   - toWeekId: The UUID of the destination week
    ///   - atIndex: The position in the destination day's session list to insert at
    func moveSession(sessionId: UUID, toDay: String, toWeekId: UUID, atIndex: Int) async {
        guard var plan = trainingPlan else { return }

        // Snapshot for rollback
        let snapshot = plan

        // --- Locate source session ---
        guard
            let srcWeekIndex = plan.planWeeks.firstIndex(where: { $0.planSessions.contains(where: { $0.id == sessionId }) }),
            let srcSessionIndex = plan.planWeeks[srcWeekIndex].planSessions.firstIndex(where: { $0.id == sessionId })
        else { return }

        // --- Extract and update the session ---
        var session = plan.planWeeks[srcWeekIndex].planSessions[srcSessionIndex]
        let srcDay = session.day
        let srcWeekId = session.weekId

        session.day = toDay
        session.weekId = toWeekId

        // --- Mutate source week ---
        plan.planWeeks[srcWeekIndex].planSessions.remove(at: srcSessionIndex)

        // Recalculate orderInDay for source day after removal (skip if same day — handled below)
        let isSameDay = srcDay == toDay && srcWeekId == toWeekId

        if !isSameDay {
            let srcDaySessions = plan.planWeeks[srcWeekIndex].planSessions
                .filter { $0.day == srcDay }
                .sorted { $0.orderInDay < $1.orderInDay }

            for (i, s) in srcDaySessions.enumerated() {
                if let idx = plan.planWeeks[srcWeekIndex].planSessions.firstIndex(where: { $0.id == s.id }) {
                    plan.planWeeks[srcWeekIndex].planSessions[idx].orderInDay = i
                }
            }
        }

        // --- Locate or confirm destination week ---
        guard let dstWeekIndex = plan.planWeeks.firstIndex(where: { $0.id == toWeekId }) else {
            // Destination week not found — abort without mutating state
            return
        }

        // --- Insert session into destination day at requested index ---
        var dstDaySessions = plan.planWeeks[dstWeekIndex].planSessions
            .filter { $0.day == toDay }
            .sorted { $0.orderInDay < $1.orderInDay }

        let clampedIndex = max(0, min(atIndex, dstDaySessions.count))
        dstDaySessions.insert(session, at: clampedIndex)

        // Recalculate orderInDay sequentially for the entire destination day
        for (i, s) in dstDaySessions.enumerated() {
            if s.id == session.id {
                // This is our moved session — add it to the destination week's session list
                var updated = s
                updated.orderInDay = i
                plan.planWeeks[dstWeekIndex].planSessions.append(updated)
            } else if let idx = plan.planWeeks[dstWeekIndex].planSessions.firstIndex(where: { $0.id == s.id }) {
                plan.planWeeks[dstWeekIndex].planSessions[idx].orderInDay = i
            }
        }

        // --- Apply optimistic update ---
        trainingPlan = plan

        // --- Build RPC payload ---
        // Collect all affected sessions: source day + destination day (deduped by ID)
        var affectedSessions: [PlanSession] = []

        // Source day sessions (from source week, if not same-day move)
        if !isSameDay {
            let srcDayUpdated = plan.planWeeks[srcWeekIndex].planSessions.filter { $0.day == srcDay }
            affectedSessions.append(contentsOf: srcDayUpdated)
        }

        // Destination day sessions (from destination week)
        let dstDayUpdated = plan.planWeeks[dstWeekIndex].planSessions.filter { $0.day == toDay }
        affectedSessions.append(contentsOf: dstDayUpdated)

        // Deduplicate by ID (same-day move would have duplicates otherwise)
        var seen = Set<UUID>()
        affectedSessions = affectedSessions.filter { seen.insert($0.id).inserted }

        let sessionUpdates: [SessionReorderItem] = affectedSessions.map { s in
            SessionReorderItem(id: s.id.uuidString, day: s.day, weekId: s.weekId.uuidString, orderInDay: s.orderInDay)
        }

        // --- Persist to Supabase ---
        do {
            try await client.rpc("reorder_sessions", params: ["session_updates": sessionUpdates]).execute()
        } catch {
            // Rollback optimistic update and surface error
            trainingPlan = snapshot
            errorMessage = "Failed to save session order. Please try again."
        }
    }
}

// MARK: - RPC Payload Types

/// Encodable payload item for the `reorder_sessions` RPC.
/// Uses snake_case keys to match the expected JSONB schema.
private struct SessionReorderItem: Encodable {
    let id: String
    let day: String
    let weekId: String
    let orderInDay: Int

    enum CodingKeys: String, CodingKey {
        case id
        case day
        case weekId = "week_id"
        case orderInDay = "order_in_day"
    }
}

// MARK: - Error Types

/// Errors that can occur during plan generation.
enum PlanGenerationError: LocalizedError {
    case serverError(String)
    case networkError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .serverError(let message):
            return message
        case .networkError(let message):
            return message
        case .unknown(let message):
            return message
        }
    }
}

