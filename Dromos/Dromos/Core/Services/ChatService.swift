//
//  ChatService.swift
//  Dromos
//
//  Created by Mamma Aiuto Gang on 22/02/2026.
//

import Combine
import Foundation
import Supabase

/// Service handling all chat interactions: fetching history, sending messages, and clearing history.
///
/// Follows the @MainActor ObservableObject pattern used across Dromos services.
/// The client writes messages to `chat_messages` via the `chat-adjust` Edge Function
/// (which uses service_role to bypass RLS for inserts). The iOS client only does
/// SELECT (fetchMessages) and DELETE (clearHistory) — matching the RLS policies.
@MainActor
final class ChatService: ObservableObject {

    // MARK: - Published Properties

    /// The current conversation history, ordered by creation date ascending.
    @Published var messages: [ChatMessage] = []

    /// True while a message send or history fetch is in progress.
    @Published var isLoading = false

    /// Last error message from any chat operation, nil if no error.
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let client = SupabaseClientProvider.client

    // MARK: - Public Methods

    /// Fetches the full message history for the current user from `chat_messages`,
    /// ordered by `created_at` ascending (oldest first).
    ///
    /// The global Supabase decoder handles snake_case → camelCase mapping automatically.
    func fetchMessages() async {
        guard let userId = try? await client.auth.session.user.id else {
            errorMessage = "Unable to load chat history. Please sign in again."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let fetched: [ChatMessage] = try await client
                .from("chat_messages")
                .select()
                .eq("user_id", value: userId)
                .order("created_at")
                .execute()
                .value

            messages = fetched
            errorMessage = nil
        } catch {
            errorMessage = "Unable to load chat history. Please try again."
        }
    }

    /// Sends a user message to the `chat-adjust` Edge Function, which:
    ///   1. Inserts the user message into `chat_messages` (service_role bypasses RLS)
    ///   2. Calls OpenAI with history context
    ///   3. Inserts the assistant response into `chat_messages`
    ///   4. Returns `{ response_text, status }` to the client
    ///
    /// Optimistic UI: the user bubble appears immediately. On error, it is removed
    /// and `errorMessage` is set so the user can retry.
    ///
    /// - Parameter text: The message text (max 1000 chars, enforced in the UI).
    func sendMessage(_ text: String) async {
        guard let userId = try? await client.auth.session.user.id else {
            errorMessage = "Unable to send message. Please sign in again."
            return
        }

        isLoading = true
        defer { isLoading = false }

        // --- Optimistic user bubble ---
        // Append immediately so the UI responds before the network round-trip.
        let optimisticMessage = ChatMessage(
            id: UUID(),
            userId: userId,
            role: "user",
            content: text,
            createdAt: Date()
        )
        messages.append(optimisticMessage)

        do {
            // Invoke the edge function — it writes both messages to the DB.
            // The Supabase Swift SDK generic invoke decodes the response using
            // the registered decoder (snake_case is handled by the SDK's FunctionInvokeOptions).
            let chatResponse: ChatResponse = try await client.functions.invoke(
                "chat-adjust",
                options: FunctionInvokeOptions(body: ["message": text])
            )

            // Append the assistant's reply as a local message object.
            // The actual DB row was written by the edge function; this mirrors it in the UI.
            let assistantMessage = ChatMessage(
                id: UUID(),
                userId: userId,
                role: "assistant",
                content: chatResponse.responseText,
                createdAt: Date()
            )
            messages.append(assistantMessage)
            errorMessage = nil

        } catch {
            // Rollback: remove the optimistic user bubble so the user can retry.
            messages.removeAll { $0.id == optimisticMessage.id }
            errorMessage = "Failed to send message. Please try again."
        }
    }

    /// Deletes all chat messages for the current user from `chat_messages`
    /// and clears the local `messages` array.
    ///
    /// This is permitted by the "Users can delete own messages" RLS policy.
    func clearHistory() async {
        guard let userId = try? await client.auth.session.user.id else {
            errorMessage = "Unable to clear history. Please sign in again."
            return
        }

        do {
            try await client
                .from("chat_messages")
                .delete()
                .eq("user_id", value: userId)
                .execute()

            messages = []
            errorMessage = nil
        } catch {
            errorMessage = "Unable to clear chat history. Please try again."
        }
    }
}
