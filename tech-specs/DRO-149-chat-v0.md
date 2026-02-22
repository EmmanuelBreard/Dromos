# DRO-149: Chat V0 — Conversation Agent + Message Storage

**Overall Progress:** `100%`

## TLDR

New Chat tab (4th, between Calendar and Profile) with an AI conversation agent that gathers training constraint info (injury, illness, fatigue, equipment) and stores messages. V0 does NOT modify the plan — gives transparent coaching advice instead. Ships the chat infrastructure so V1 (DRO-132) only wires up the coaching brain on top.

## Critical Decisions

- **Single thread, not sessions** — messages append forever in one continuous thread per user. No `chat_sessions` table. Simpler schema, simpler UI. Sessions can be layered in V1 if needed.
- **Prompt fork, not modification** — duplicate `adjust-step1-conversation.txt` → `adjust-step1-v0.txt` with V0 advisory language. Original PoC-validated prompt preserved for V1.
- **Edge function writes both messages** — iOS client only reads from `chat_messages`. The edge function inserts both the user message and bot response in one request. Simpler RLS (client = SELECT + DELETE only).
- **Secure auth pattern** — use `auth.getUser(jwt)` like `strava-auth`/`strava-sync`, NOT the weak manual JWT decode from `generate-plan`.
- **Non-streaming** — full response returned at once. Typing indicator covers the ~3s wait. Streaming deferred.
- **History cap: last 50 messages** — sent to OpenAI as context. Older messages stay in DB but excluded from LLM context to avoid token overflow.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `supabase/migrations/013_create_chat_messages.sql` | CREATE | `chat_messages` table + RLS + index |
| `ai/prompts/adjust-step1-v0.txt` | CREATE | V0 fork of conversation prompt with advisory mode |
| `supabase/functions/chat-adjust/index.ts` | CREATE | Edge function: auth → history fetch → OpenAI → DB write |
| `Dromos/Dromos/Core/Models/ChatMessage.swift` | CREATE | `ChatMessage` struct (Codable, Identifiable) |
| `Dromos/Dromos/Core/Services/ChatService.swift` | CREATE | `ChatService` — send, fetch, clear |
| `Dromos/Dromos/Features/Chat/ChatView.swift` | CREATE | Chat UI — message list, input bar, typing indicator, welcome state |
| `Dromos/Dromos/App/MainTabView.swift` | MODIFY | Add `.chat` case to `AppTab`, add Chat tab between Calendar and Profile |
| `Dromos/Dromos/Features/Profile/ProfileView.swift` | MODIFY | Add "Clear Chat History" row in new "Data" section |
| `scripts/sync-prompts.sh` | MODIFY | Add V0 prompt → `chat-adjust` edge function mapping |

## Context Doc Updates

- `schema.md` — add `chat_messages` table definition, RLS policies, index
- `architecture.md` — add `Features/Chat/` folder, `ChatService`, `chat-adjust` edge function, update tab list from 3 to 4

## Tasks

- [x] 🟩 **Step 1: Database Migration**
  - [x] 🟩 Create `supabase/migrations/013_create_chat_messages.sql`:
    ```sql
    -- UP
    CREATE TABLE public.chat_messages (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
      role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
      content TEXT NOT NULL,
      status TEXT CHECK (status IN ('ready', 'need_info', 'no_action', 'escalate')),
      constraint_summary JSONB,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );

    CREATE INDEX idx_chat_messages_user_id_created_at
      ON public.chat_messages (user_id, created_at);

    ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

    -- Authenticated users can read their own messages
    CREATE POLICY "Users can read own messages"
      ON public.chat_messages FOR SELECT
      USING (auth.uid() = user_id);

    -- Authenticated users can delete their own messages (clear history)
    CREATE POLICY "Users can delete own messages"
      ON public.chat_messages FOR DELETE
      USING (auth.uid() = user_id);

    -- Edge function inserts via service_role (bypasses RLS)
    -- No INSERT policy needed for authenticated users
    ```
  - [x] 🟩 Apply migration to Supabase project

- [x] 🟩 **Step 2: V0 Prompt**
  - [x] 🟩 Duplicate `ai/prompts/adjust-step1-conversation.txt` → `ai/prompts/adjust-step1-v0.txt`
  - [x] 🟩 Add V0 advisory mode section after "## Your Role":
    ```
    ## V0 Advisory Mode

    You are currently in advisory mode. You do NOT have the ability to modify
    the athlete's training plan. When you have enough information about a
    constraint, acknowledge it, give practical coaching advice for the
    immediate situation (e.g., "consider skipping intensity sessions this
    week", "stick to Zone 1-2"), and let the athlete know that automatic
    plan adjustments are coming soon. Do not promise to modify their plan.
    ```
  - [x] 🟩 Update `response_text` examples in JSON output section to use transparent V0 language:
    - Ready: `"I've noted your knee injury. Plan adjustments are coming soon — for now, I'd suggest skipping your run sessions this week and focusing on swimming and easy biking."`
    - Escalate: `"Given the severity, I'd recommend generating a fresh plan once you're recovered. You can do that from your Profile tab."`
  - [x] 🟩 Update `scripts/sync-prompts.sh` — add mapping:
    - Source: `ai/prompts/adjust-step1-v0.txt`
    - Target: `supabase/functions/chat-adjust/prompts/adjust-step1-v0-prompt.ts`

- [x] 🟩 **Step 3: Edge Function — `chat-adjust`**
  - [x] 🟩 Create `supabase/functions/chat-adjust/index.ts`:
    - **Auth**: Extract JWT from `Authorization` header, validate via `authClient.auth.getUser(jwt)`. Return 401 on failure.
    - **CORS**: Inline `corsHeaders` + OPTIONS handler (same pattern as `strava-auth`).
    - **Input validation**: Parse body as `{ message: string }`. Reject if missing or > 1000 chars.
    - **Fetch context** (3 parallel queries via `Promise.all`):
      1. Last 50 messages from `chat_messages` WHERE `user_id` = userId ORDER BY `created_at` ASC
      2. User profile from `users` WHERE `id` = userId
      3. Phase map from `training_plans` JOIN `plan_weeks` WHERE `user_id` = userId AND `status` = 'active' ORDER BY `week_number`
    - **Build prompt**: Load V0 prompt template, replace `{{athlete_profile}}` with formatted user profile (race_objective, experience_years, vma, css, ftp, weekly_hours, sport days), replace `{{phase_map}}` with formatted phase map (or `"No active training plan."` if none).
    - **Build OpenAI messages array**:
      ```
      [
        { role: "system", content: renderedPrompt },
        ...historyMessages.map(m => ({ role: m.role, content: m.content })),
        { role: "user", content: newMessage }
      ]
      ```
    - **Call OpenAI**: `gpt-4o`, temperature `0`, max_tokens `1024`.
    - **Parse response**: Search for JSON block (regex `\{[\s\S]*"status"[\s\S]*\}`). If found, extract `response_text`, `status`, `constraint_summary`. If no JSON found, treat entire response as `response_text` with status `"need_info"`.
    - **DB writes** (sequential, service_role):
      1. INSERT user message: `{ user_id, role: 'user', content: message }`
      2. INSERT assistant message: `{ user_id, role: 'assistant', content: response_text, status, constraint_summary }`
    - **Return**: `{ response_text, status, constraint_summary? }`
  - [x] 🟩 Run `scripts/sync-prompts.sh` to generate the prompt `.ts` file
  - [x] 🟩 Deploy: `supabase functions deploy chat-adjust`
  - [x] 🟩 Set `OPENAI_API_KEY` secret if not already available to the function

- [x] 🟩 **Step 4: iOS Model**
  - [x] 🟩 Create `Dromos/Dromos/Core/Models/ChatMessage.swift`:
    ```swift
    struct ChatMessage: Codable, Identifiable {
        let id: UUID
        let userId: UUID
        let role: String        // "user" or "assistant"
        let content: String
        let createdAt: Date
    }
    ```
    - Only decode fields needed for display. `status` and `constraint_summary` are server-side storage only — not sent to client.
  - [x] 🟩 Create response type for edge function:
    ```swift
    struct ChatResponse: Codable {
        let responseText: String
        let status: String
    }
    ```

- [x] 🟩 **Step 5: iOS Service**
  - [x] 🟩 Create `Dromos/Dromos/Core/Services/ChatService.swift` following existing service pattern:
    ```swift
    @MainActor final class ChatService: ObservableObject {
        private let client = SupabaseClientProvider.client
        @Published var messages: [ChatMessage] = []
        @Published var isLoading = false
        @Published var errorMessage: String?
    }
    ```
  - [x] 🟩 `fetchMessages()` — SELECT from `chat_messages` WHERE user_id = currentUserId ORDER BY created_at ASC. Populates `messages`.
  - [x] 🟩 `sendMessage(_ text: String) async` — Calls `client.functions.invoke("chat-adjust", options: .init(body: ["message": text]))`. Parses `ChatResponse`. Appends both user message (optimistic) and bot response to `messages`. On error, removes optimistic message and sets `errorMessage`.
  - [x] 🟩 `clearHistory() async` — DELETE from `chat_messages` WHERE user_id = currentUserId. Clears `messages` array.

- [x] 🟩 **Step 6: Chat UI**
  - [x] 🟩 Create `Dromos/Dromos/Features/Chat/ChatView.swift`:
    - **Message list**: `ScrollViewReader` wrapping `ScrollView` → `LazyVStack`. Each message rendered as a bubble (`ChatBubbleView`). Auto-scroll to bottom via `.onChange(of: chatService.messages.count)`.
    - **Chat bubbles**: User messages right-aligned with accent background + white text. Bot messages left-aligned with `Color(.systemGray6)` background. Rounded corners (16pt). Timestamp below each bubble (relative format).
    - **Typing indicator**: When `chatService.isLoading`, show a bot-side bubble with 3 animated dots (simple `withAnimation(.easeInOut.repeatForever())` on opacity).
    - **Input bar**: `HStack` with `TextField("Message your coach...", text: $messageText)` + send button (`Image(systemName: "arrow.up.circle.fill")`). Send button disabled when `messageText.isEmpty || chatService.isLoading`. TextField disabled when `chatService.isLoading`. Enforce 1000 char limit via `.onChange(of: messageText)` truncation.
    - **Welcome state**: When `chatService.messages.isEmpty && !chatService.isLoading`, show centered text: "Tell me what's going on with your training — injury, illness, fatigue, or schedule changes. I'm here to help."
    - **Error display**: If `chatService.errorMessage` is set, show inline system message in red. Clear on next successful send.
  - [x] 🟩 Wrap in `NavigationStack` with `.navigationTitle("Chat")`
  - [x] 🟩 Load messages on appear: `.task { await chatService.fetchMessages() }`

- [x] 🟩 **Step 7: Tab Integration**
  - [x] 🟩 Add `case chat` to `AppTab` enum in `MainTabView.swift`
  - [x] 🟩 Create `@StateObject private var chatService = ChatService()` in `MainTabView`
  - [x] 🟩 Add Chat tab between Calendar and Profile:
    ```swift
    Tab("Chat", systemImage: "bubble.left.fill", value: .chat) {
        ChatView(chatService: chatService)
    }
    ```
  - [x] 🟩 Pass `chatService` to `ProfileView` (needed for clear history count/state)

- [x] 🟩 **Step 8: Clear Chat History in Settings**
  - [x] 🟩 Add `@ObservedObject var chatService: ChatService` parameter to `ProfileView`
  - [x] 🟩 Add new "Data" section in `ProfileView` Form, between Strava section and Sign Out section:
    ```swift
    Section("Data") {
        Button("Clear Chat History", role: .destructive) {
            showClearChatAlert = true
        }
    }
    ```
  - [x] 🟩 Add `@State private var showClearChatAlert = false` and confirmation alert:
    ```swift
    .alert("Clear Chat History?", isPresented: $showClearChatAlert) {
        Button("Cancel", role: .cancel) {}
        Button("Clear", role: .destructive) {
            Task { await chatService.clearHistory() }
        }
    } message: {
        Text("This will delete all your chat messages. This action cannot be undone.")
    }
    ```
  - [x] 🟩 Update `MainTabView` to pass `chatService` to `ProfileView`

- [x] 🟩 **Step 9: Context Doc Updates**
  - [x] 🟩 Update `.claude/context/schema.md` — add `chat_messages` table definition
  - [x] 🟩 Update `.claude/context/architecture.md` — add `Features/Chat/` folder, `ChatService`, `chat-adjust` edge function, update tab list to 4 tabs
