//
//  ChatMessage.swift
//  Dromos
//
//  Created by Mamma Aiuto Gang on 22/02/2026.
//

import Foundation

/// A single message in the coaching chat conversation.
/// Matches the `public.chat_messages` table in Supabase.
///
/// The global SupabaseClient decoder handles snake_case → camelCase mapping
/// automatically, so `user_id` → `userId`, `created_at` → `createdAt`, etc.
struct ChatMessage: Codable, Identifiable {
    /// Unique message identifier (UUID primary key from DB).
    let id: UUID

    /// The authenticated user who owns this message.
    let userId: UUID

    /// Message sender: "user" or "assistant".
    let role: String

    /// The text content of the message.
    let content: String

    /// Timestamp when the message was created (from DB `created_at`).
    let createdAt: Date
}

/// Response payload returned by the `chat-adjust` Edge Function.
///
/// NOTE: Edge function responses do NOT go through the global Supabase decoder.
/// Use a local JSONDecoder with `.convertFromSnakeCase` when decoding this type.
struct ChatResponse: Codable {
    /// The assistant's reply text to display in the chat UI.
    let responseText: String

    /// Classification of the conversation state:
    /// - "ready": constraint identified, advice given
    /// - "need_info": gathering more info
    /// - "no_action": no constraint detected
    /// - "escalate": severity requires human attention / plan regeneration
    let status: String

    private enum CodingKeys: String, CodingKey {
        case responseText = "response_text"
        case status
    }
}
