//
//  ChatService.swift
//  Dromos
//
//  Created by Mamma Aiuto Gang on 22/02/2026.
//  Updated by Mamma Aiuto Gang — DRO-259: SSE streaming consumer.
//

import Combine
import Foundation
import Supabase

/// Service handling all chat interactions: fetching history, sending messages, and clearing history.
///
/// Follows the @MainActor ObservableObject pattern used across Dromos services.
///
/// Message flow (DRO-259):
///   1. Optimistic user bubble appended immediately to `messages`.
///   2. JWT acquired via `client.auth.session`.
///   3. A raw `URLRequest` is fired at the `chat-adjust` edge function with
///      `Accept: text/event-stream` — the function streams back OpenAI chunks verbatim.
///   4. Each SSE `data:` line is parsed into a minimal `StreamChunk`; `delta.content`
///      fragments are appended to `streamingMessage` so the UI can show live text.
///   5. On stream completion, a final `ChatMessage` is appended to `messages` and
///      `streamingMessage` is set to nil.
///   6. On any error, the optimistic bubble is rolled back and `errorMessage` is set.
@MainActor
final class ChatService: ObservableObject {

    // MARK: - Published Properties

    /// The current conversation history, ordered by creation date ascending.
    @Published var messages: [ChatMessage] = []

    /// True while a message send or history fetch is in progress.
    @Published var isLoading = false

    /// Last error message from any chat operation, nil if no error.
    @Published var errorMessage: String?

    /// The partial assistant message text currently being streamed.
    /// - `nil`: no stream in flight.
    /// - `""` (empty string): stream has just started, no tokens yet.
    /// - non-empty string: one or more tokens have arrived.
    @Published var streamingMessage: String?

    // MARK: - Private Types

    /// Minimal Decodable struct matching OpenAI's streaming chunk shape:
    /// `{ "choices": [{ "delta": { "content": "..." } }] }`
    ///
    /// All fields are optional so parse failures are tolerated gracefully —
    /// OpenAI also sends heartbeat chunks where `content` is absent.
    private struct StreamChunk: Decodable {
        let choices: [Choice]?
        struct Choice: Decodable {
            let delta: Delta?
            struct Delta: Decodable {
                let content: String?
            }
        }
    }

    // MARK: - Private Properties

    private let client = SupabaseClientProvider.client

    // MARK: - Public Methods

    /// Fetches the full message history for the current user from `chat_messages`,
    /// ordered by `created_at` ascending (oldest first).
    func fetchMessages() async {
        guard let userId = try? await client.auth.session.user.id else {
            errorMessage = "Unable to load chat history. Please sign in again."
            return
        }

        isLoading = true
        errorMessage = nil
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

    /// Sends a user message to the `chat-adjust` Edge Function via SSE streaming.
    ///
    /// - Appends an optimistic user bubble immediately (rolled back on error).
    /// - Streams the assistant reply token-by-token into `streamingMessage`.
    /// - On stream completion, promotes the accumulated text to a permanent `ChatMessage`.
    /// - On any error, rolls back the optimistic bubble and sets `errorMessage`.
    ///
    /// - Parameter text: The message text (max 1000 chars, enforced in the UI).
    func sendMessage(_ text: String) async {
        guard !isLoading else { return }

        // Fetch the current session for the user ID and JWT.
        // `client.auth.session` also triggers the SDK's silent token refresh.
        guard let session = try? await client.auth.session else {
            errorMessage = "Unable to send message. Please sign in again."
            return
        }

        let userId = session.user.id
        let token = session.accessToken

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // --- Optimistic user bubble ---
        // Appended immediately so the UI responds before the network round-trip.
        let optimisticMessage = ChatMessage(
            id: UUID(),
            userId: userId,
            role: "user",
            content: text,
            createdAt: Date()
        )
        messages.append(optimisticMessage)

        do {
            // Build the SSE request to the chat-adjust edge function.
            let urlString = "\(Configuration.supabaseURL)/functions/v1/chat-adjust"
            guard let url = URL(string: urlString) else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(Configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONEncoder().encode(["message": text])

            // Open the streaming connection.
            // URLSession.shared default 60s timeout comfortably covers a 400-token completion.
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            // Validate HTTP status before touching the stream.
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            // Signal stream start — UI can show the streaming bubble immediately.
            streamingMessage = ""

            // Consume the SSE line stream.
            for try await line in bytes.lines {
                // SSE format: "data: <payload>" or blank separator lines.
                guard !line.isEmpty, line.hasPrefix("data: ") else { continue }

                let payload = String(line.dropFirst("data: ".count)).trimmingCharacters(in: .whitespaces)

                // [DONE] signals the end of the OpenAI stream.
                if payload == "[DONE]" { break }

                // Parse the chunk — failures are non-fatal (heartbeats, unknown fields).
                guard let data = payload.data(using: .utf8),
                      let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) else {
                    // Log malformed chunk but continue — stream integrity is server-side.
                    print("[ChatService] Skipping unparseable SSE chunk: \(payload.prefix(80))")
                    continue
                }

                // Append the token fragment to the live streaming bubble.
                if let content = chunk.choices?.first?.delta?.content {
                    streamingMessage = (streamingMessage ?? "") + content
                }
            }

            // --- Stream complete: promote to a permanent message ---
            let assistantMessage = ChatMessage(
                id: UUID(),
                userId: userId,
                role: "assistant",
                content: streamingMessage ?? "",
                createdAt: Date()
            )
            messages.append(assistantMessage)
            streamingMessage = nil
            errorMessage = nil

        } catch {
            // --- Error rollback ---
            // Discard any partial stream state and remove the optimistic user bubble.
            streamingMessage = nil
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

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
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
