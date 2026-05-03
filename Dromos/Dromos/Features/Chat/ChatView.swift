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

                // ── Input bar (floating capsule, no divider) ───────────────
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

                    // Typing indicator — shown while the edge function is processing
                    // (isLoading = true, no chunks yet). Replaced by the streaming
                    // bubble as soon as the first token arrives.
                    if chatService.isLoading
                        && (chatService.streamingMessage == nil || chatService.streamingMessage!.isEmpty) {
                        TypingIndicator()
                            .id("typing-indicator")
                    }

                    // Streaming bubble — fills in word-by-word as tokens arrive.
                    if let streaming = chatService.streamingMessage, !streaming.isEmpty {
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
            // Auto-scroll when keyboard appears so the last AI message stays readable
            // above the keyboard while the user types.
            .onChange(of: isInputFocused) { _, focused in
                if focused {
                    Task {
                        // Brief delay lets the keyboard avoidance area settle before scrolling.
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        withAnimation {
                            // Order matters: streaming bubble > typing indicator > last message.
                            // During the pre-first-chunk gap, the typing indicator is what the
                            // user is waiting for — make sure it's visible above the keyboard.
                            let isWaitingForFirstChunk = chatService.isLoading
                                && (chatService.streamingMessage?.isEmpty ?? true)
                            if let streaming = chatService.streamingMessage, !streaming.isEmpty {
                                scrollProxy.scrollTo("streaming-bubble", anchor: .bottom)
                            } else if isWaitingForFirstChunk {
                                scrollProxy.scrollTo("typing-indicator", anchor: .bottom)
                            } else if let lastId = chatService.messages.last?.id {
                                scrollProxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .onTapGesture {
                isInputFocused = false
            }
        }
    }

    // MARK: - Input Bar

    /// Floating capsule message composer that hovers above the tab bar.
    /// Multi-line input (up to 5 lines), 1000-char cap. Send button sits inside the
    /// capsule on the trailing edge — no divider separating it from the message list.
    /// Horizontal inset matches iOS 18's floating tab bar so the two pills line up.
    private var inputBar: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("Message your coach...", text: $messageText, axis: .vertical)
                .focused($isInputFocused)
                .lineLimit(1...5)
                .padding(.leading, 18)
                .padding(.vertical, 10)
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
            .padding(.trailing, 8)
        }
        .background(
            Capsule()
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
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

// MARK: - TypingIndicator

/// Three pulsing dots shown while waiting for the first SSE chunk to arrive.
/// Mirrors the WhatsApp-style "someone is typing" pattern.
///
/// Uses TimelineView(.animation) to drive the dots frame-by-frame from the
/// system time. Earlier attempts with .animation(value:) + .repeatForever
/// triggered in .onAppear were unreliable — the animation occasionally never
/// engaged, leaving the dots static or invisible. TimelineView is deterministic:
/// it recomputes opacity from the current time on every frame, so the wave is
/// guaranteed to render.
private struct TypingIndicator: View {

    /// Total wave cycle in seconds — one full pulse per dot.
    private let cycle: Double = 1.2
    /// Per-dot phase offset so dots pulse in sequence rather than together.
    private let dotOffset: Double = 0.2

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .frame(width: 9, height: 9)
                            .foregroundStyle(Color.primary.opacity(opacity(for: index, at: t)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Spacer(minLength: 0)
            }
            .padding(.horizontal)
        }
    }

    /// Map (dot index, time) → opacity in [0.25, 1.0].
    /// Each dot rides a sine wave; the per-dot offset makes the wave travel.
    private func opacity(for index: Int, at time: TimeInterval) -> Double {
        let phase = (time - Double(index) * dotOffset).truncatingRemainder(dividingBy: cycle) / cycle
        let wave = (sin(phase * 2 * .pi) + 1) / 2 // 0..1
        return 0.25 + 0.75 * wave
    }
}

// MARK: - Preview

#Preview {
    ChatView(chatService: ChatService())
}
