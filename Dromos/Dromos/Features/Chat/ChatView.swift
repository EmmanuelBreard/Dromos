//
//  ChatView.swift
//  Dromos
//
//  Created by Mamma Aiuto Gang on 22/02/2026.
//

import SwiftUI

// MARK: - ChatView

/// Main chat UI for the coaching conversation agent.
///
/// Layout:
///   - Welcome state (empty thread)
///   - Scrollable message list with user/assistant bubbles
///   - Inline error display
///   - Multi-line input bar with send button
///
/// The view owns no state beyond local UI — all business logic lives in ChatService.
struct ChatView: View {

    @ObservedObject var chatService: ChatService

    /// Current text in the message input field.
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Message area ───────────────────────────────────────────
                // Show the welcome greeting only when the thread is truly empty
                // (no messages, no active stream, not loading).
                if chatService.messages.isEmpty
                    && chatService.streamingMessage == nil
                    && !chatService.isLoading {
                    welcomeState
                } else {
                    messageList
                }

                // ── Inline error ───────────────────────────────────────────
                if let error = chatService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }

                // ── Input bar ──────────────────────────────────────────────
                Divider()
                inputBar
            }
            .navigationTitle("Chat")
        }
        .task {
            await chatService.fetchMessages()
        }
    }

    // MARK: - Welcome State

    /// Shown when the thread is empty and no stream is in flight.
    /// Renders the V0 opening greeting as an assistant bubble (NOT stored in DB).
    private var welcomeState: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ChatBubbleView(message: ChatMessage(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    userId: UUID(),
                    role: "assistant",
                    content: "Hi — I'm here to help you get the most out of your plan. Ask me about today's session, what your workouts mean, how to pace tomorrow's effort, or why your plan looks the way it does. I can't change your plan yet — that's coming soon — but I can help you get the most out of it.",
                    createdAt: Date()
                ))
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Message List

    /// Scrollable list of chat bubbles with auto-scroll to bottom.
    /// While a stream is in flight, a live partial-message bubble is appended below
    /// the persisted messages and updated token-by-token via `streamingMessage`.
    private var messageList: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(chatService.messages) { message in
                        ChatBubbleView(message: message)
                            .id(message.id)
                    }

                    // Streaming bubble — replaces the old TypingIndicator.
                    // Shown as soon as the SSE connection opens (streamingMessage == "")
                    // and fills in word-by-word as tokens arrive.
                    if let streaming = chatService.streamingMessage {
                        ChatBubbleView(message: ChatMessage(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                            userId: UUID(),
                            role: "assistant",
                            content: streaming,
                            createdAt: Date()
                        ))
                        .id("streaming-bubble")
                    }
                }
                .padding(.vertical, 8)
            }
            // Auto-scroll to newest persisted message when the list grows.
            .onChange(of: chatService.messages.count) { _, _ in
                withAnimation {
                    scrollProxy.scrollTo(chatService.messages.last?.id, anchor: .bottom)
                }
            }
            // Auto-scroll live during streaming so new tokens stay visible.
            .onChange(of: chatService.streamingMessage) { _, _ in
                withAnimation {
                    scrollProxy.scrollTo("streaming-bubble", anchor: .bottom)
                }
            }
            .onTapGesture {
                isInputFocused = false
            }
        }
    }

    // MARK: - Input Bar

    /// Message composition area at the bottom of the screen.
    /// Supports multi-line input (up to 5 lines) and enforces a 1000-char limit.
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message your coach...", text: $messageText, axis: .vertical)
                .focused($isInputFocused)
                .lineLimit(1...5)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                // Enforce 1000-char limit.
                .onChange(of: messageText) { _, newValue in
                    if newValue.count > 1000 {
                        messageText = String(newValue.prefix(1000))
                    }
                }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.accent)
            }
            .disabled(isSendDisabled)
            .padding(.bottom, 8)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Helpers

    /// True when the send button should be disabled.
    private var isSendDisabled: Bool {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatService.isLoading
    }

    /// Captures and clears the text field, then dispatches the async send.
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""
        isInputFocused = false
        Task {
            await chatService.sendMessage(text)
        }
    }
}

// MARK: - ChatBubbleView

/// A single chat message rendered as a bubble.
///
/// - User messages: right-aligned, accent-color background, white text.
/// - Assistant messages: left-aligned, systemGray6 background, primary text.
private struct ChatBubbleView: View {

    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
            HStack {
                if isUser { Spacer(minLength: 0) }

                Text(message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.accentColor : Color(.systemGray6))
                    .foregroundStyle(isUser ? Color.white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .frame(
                        maxWidth: 280,
                        alignment: isUser ? .trailing : .leading
                    )

                if !isUser { Spacer(minLength: 0) }
            }

            // Relative timestamp (e.g. "just now", "2 minutes ago").
            Text(message.createdAt, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal)
    }
}

// MARK: - Preview

#Preview {
    ChatView(chatService: ChatService())
}
