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

// ChatResponse was removed in DRO-259.
// The chat-adjust edge function now returns a Server-Sent Events stream;
// ChatService consumes the stream directly and no longer decodes a JSON envelope.
