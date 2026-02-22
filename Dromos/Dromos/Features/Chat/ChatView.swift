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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Message area ───────────────────────────────────────────
                if chatService.messages.isEmpty && !chatService.isLoading {
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

    /// Shown when there are no messages yet. Guides the user to start a conversation.
    private var welcomeState: some View {
        VStack {
            Spacer()
            Text("Tell me what's going on with your training — injury, illness, fatigue, or schedule changes. I'm here to help.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
    }

    // MARK: - Message List

    /// Scrollable list of chat bubbles with auto-scroll to bottom and typing indicator.
    private var messageList: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(chatService.messages) { message in
                        ChatBubbleView(message: message)
                            .id(message.id)
                    }

                    // Typing indicator — shown while waiting for assistant response.
                    if chatService.isLoading {
                        HStack {
                            TypingIndicator()
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .frame(maxWidth: UIScreen.main.bounds.width * 0.8, alignment: .leading)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .id("typing-indicator")
                    }
                }
                .padding(.vertical, 8)
            }
            // Auto-scroll to newest message when the list grows.
            .onChange(of: chatService.messages.count) { _, _ in
                withAnimation {
                    if chatService.isLoading {
                        scrollProxy.scrollTo("typing-indicator", anchor: .bottom)
                    } else {
                        scrollProxy.scrollTo(chatService.messages.last?.id, anchor: .bottom)
                    }
                }
            }
            // Also scroll when loading state changes (typing indicator appears/disappears).
            .onChange(of: chatService.isLoading) { _, newValue in
                withAnimation {
                    if newValue {
                        scrollProxy.scrollTo("typing-indicator", anchor: .bottom)
                    } else {
                        scrollProxy.scrollTo(chatService.messages.last?.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input Bar

    /// Message composition area at the bottom of the screen.
    /// Supports multi-line input (up to 5 lines) and enforces a 1000-char limit.
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message your coach...", text: $messageText, axis: .vertical)
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
                        maxWidth: UIScreen.main.bounds.width * 0.8,
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

/// Animated three-dot indicator displayed while the assistant is generating a reply.
struct TypingIndicator: View {

    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundStyle(.secondary)
                    .opacity(animating ? 0.3 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Preview

#Preview {
    ChatView(chatService: ChatService())
}
