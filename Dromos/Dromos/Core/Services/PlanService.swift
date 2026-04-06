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

    /// Whether a session move is in flight (prevents concurrent move races).
    @Published private(set) var isMovingSession: Bool = false

    // MARK: - Private Properties

    private let client = SupabaseClientProvider.client

    // MARK: - Public Methods

    /// Generate a training plan for the current user.
    /// Calls the `generate-plan` Edge Function which reads the user's profile server-side.
    /// The Bearer token is sent automatically by the SDK from the current session.
    /// - Throws: Error if generation fails
    func generatePlan() async throws {
        errorMessage = nil

        do {
            try await client.auth.refreshSession()
        } catch {
            let msg = "Your session has expired. Please sign in again."
            self.errorMessage = msg
            throw PlanGenerationError.serverError(msg)
        }

        isGenerating = true

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

            var sortedPlan = response
            sortPlan(&sortedPlan)
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
    ///   - toDay: Destination weekday
    ///   - toWeekId: The UUID of the destination week
    ///   - atIndex: The position in the destination day's session list to insert at
    func moveSession(sessionId: UUID, toDay: Weekday, toWeekId: UUID, atIndex: Int) async {
        guard !isMovingSession else { return }
        guard var plan = trainingPlan else { return }

        isMovingSession = true
        defer { isMovingSession = false }

        // Snapshot for rollback
        let snapshot = plan
        let toDayName = toDay.fullName

        // --- Locate source session ---
        guard
            let srcWeekIndex = plan.planWeeks.firstIndex(where: { $0.planSessions.contains(where: { $0.id == sessionId }) }),
            let srcSessionIndex = plan.planWeeks[srcWeekIndex].planSessions.firstIndex(where: { $0.id == sessionId })
        else { return }

        // --- Validate destination week exists before any mutation ---
        guard let dstWeekIndex = plan.planWeeks.firstIndex(where: { $0.id == toWeekId }) else {
            assertionFailure("moveSession: destination week \(toWeekId) not found in plan")
            return
        }

        // --- Extract and update the session ---
        var session = plan.planWeeks[srcWeekIndex].planSessions[srcSessionIndex]
        let srcDay = session.day
        let srcWeekId = session.weekId
        let isSameDay = srcDay == toDayName && srcWeekId == toWeekId

        // No-op check: same day, same position
        if isSameDay {
            let currentOrder = session.orderInDay
            let dayCount = plan.planWeeks[srcWeekIndex].planSessions.filter { $0.day == srcDay }.count
            let clamped = max(0, min(atIndex, dayCount - 1))
            if clamped == currentOrder { return }
        }

        session.day = toDayName
        session.weekId = toWeekId

        // --- Mutate source week ---
        plan.planWeeks[srcWeekIndex].planSessions.remove(at: srcSessionIndex)

        // Recalculate orderInDay for source day after removal (skip if same day — handled below)
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

        // --- Insert session into destination day at requested index ---
        var dstDaySessions = plan.planWeeks[dstWeekIndex].planSessions
            .filter { $0.day == toDayName }
            .sorted { $0.orderInDay < $1.orderInDay }

        let clampedIndex = max(0, min(atIndex, dstDaySessions.count))
        dstDaySessions.insert(session, at: clampedIndex)

        // Recalculate orderInDay sequentially for the entire destination day
        for (i, s) in dstDaySessions.enumerated() {
            if s.id == session.id {
                var updated = s
                updated.orderInDay = i
                plan.planWeeks[dstWeekIndex].planSessions.append(updated)
            } else if let idx = plan.planWeeks[dstWeekIndex].planSessions.firstIndex(where: { $0.id == s.id }) {
                plan.planWeeks[dstWeekIndex].planSessions[idx].orderInDay = i
            }
        }

        // Re-sort affected weeks to maintain the array order invariant from fetchFullPlan
        sortWeekSessions(&plan.planWeeks[dstWeekIndex])
        if !isSameDay {
            sortWeekSessions(&plan.planWeeks[srcWeekIndex])
        }

        // --- Apply optimistic update ---
        trainingPlan = plan

        // --- Build RPC payload ---
        var affectedSessions: [PlanSession] = []

        if !isSameDay {
            let srcDayUpdated = plan.planWeeks[srcWeekIndex].planSessions.filter { $0.day == srcDay }
            affectedSessions.append(contentsOf: srcDayUpdated)
        }

        let dstDayUpdated = plan.planWeeks[dstWeekIndex].planSessions.filter { $0.day == toDayName }
        affectedSessions.append(contentsOf: dstDayUpdated)

        // Deduplicate by ID
        var seen = Set<UUID>()
        affectedSessions = affectedSessions.filter { seen.insert($0.id).inserted }

        let sessionUpdates: [SessionReorderItem] = affectedSessions.map { s in
            SessionReorderItem(id: s.id.uuidString, day: s.day, weekId: s.weekId.uuidString, orderInDay: s.orderInDay)
        }

        // --- Persist to Supabase ---
        do {
            try await client.rpc("reorder_sessions", params: ["session_updates": sessionUpdates]).execute()
        } catch {
            trainingPlan = snapshot
            errorMessage = "Failed to save session order. Please try again."
        }
    }

    /// Silently refreshes the training plan without showing a loading spinner.
    /// Used for background updates (e.g. feedback generation) that should not disrupt the UI.
    func refreshPlan(userId: UUID) async {
        do {
            let response: TrainingPlan = try await client
                .from("training_plans")
                .select("*, plan_weeks(*, plan_sessions(*))")
                .eq("user_id", value: userId.uuidString)
                .eq("status", value: "active")
                .single()
                .execute()
                .value

            var sortedPlan = response
            sortPlan(&sortedPlan)
            self.trainingPlan = sortedPlan
        } catch {
            // Silent failure — don't set errorMessage for background refreshes
            print("Background plan refresh failed: \(error)")
        }
    }

    // MARK: - Private Helpers

    /// Sorts a plan's weeks by weekNumber, and each week's sessions by day order then orderInDay.
    private func sortPlan(_ plan: inout TrainingPlan) {
        plan.planWeeks.sort { $0.weekNumber < $1.weekNumber }
        for i in plan.planWeeks.indices {
            sortWeekSessions(&plan.planWeeks[i])
        }
    }

    /// Sorts a week's sessions by day order then orderInDay.
    private func sortWeekSessions(_ week: inout PlanWeek) {
        let weekdayOrder: [String: Int] = [
            "Monday": 0, "Tuesday": 1, "Wednesday": 2, "Thursday": 3,
            "Friday": 4, "Saturday": 5, "Sunday": 6
        ]
        week.planSessions.sort { a, b in
            let da = weekdayOrder[a.day] ?? 99
            let db = weekdayOrder[b.day] ?? 99
            return da != db ? da < db : a.orderInDay < b.orderInDay
        }
    }
}

// MARK: - RPC Payload Types

/// Encodable payload item for the `reorder_sessions` RPC.
/// Uses snake_case keys to match the expected JSONB schema.
/// `nonisolated encode(to:)` opts out of @MainActor isolation inferred from
/// being in the same file as PlanService, satisfying `Sendable & Encodable`.
private struct SessionReorderItem: Sendable, Encodable {
    let id: String
    let day: String
    let weekId: String
    let orderInDay: Int

    private enum CodingKeys: String, CodingKey {
        case id, day
        case weekId = "week_id"
        case orderInDay = "order_in_day"
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(day, forKey: .day)
        try container.encode(weekId, forKey: .weekId)
        try container.encode(orderInDay, forKey: .orderInDay)
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

