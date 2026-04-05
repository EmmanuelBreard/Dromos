# Feature Implementation Plan — DRO-184: Hide Chat Entry Point

**Overall Progress:** `100%`

## TLDR
Gate all chat code behind `#if DEBUG` compilation flags so it is physically absent from release binaries. Devs can still access chat in debug builds. No code deleted.

## Critical Decisions
- **`#if DEBUG` over UI-only hide:** Simply removing tab/buttons leaves compiled chat code in the binary, accessible via patched clients. `#if DEBUG` ensures the code doesn't exist in production builds at all.
- **Remove chatService from ProfileView entirely:** ProfileView's only use of chatService is the "Clear Chat History" button. Removing it simplifies the interface — devs can clear chat via other means if needed during development.
- **AppTab.chat gated with `#if DEBUG`:** The enum case must also be conditionally compiled to avoid compiler warnings about unreachable cases in release.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/App/MainTabView.swift` | MODIFY | Gate `AppTab.chat`, `ChatService` StateObject, and Chat Tab block with `#if DEBUG`; remove `chatService:` from ProfileView init |
| `Dromos/Dromos/Features/Profile/ProfileView.swift` | MODIFY | Remove `chatService` ObservedObject param entirely, remove `showClearChatAlert` state, remove Data section, remove Clear Chat History alert |

## Context Doc Updates
- None — no new files, no schema changes, no new patterns.

## Tasks

- [x] 🟩 **Step 1: Update MainTabView**
  - [x] 🟩 Gate `AppTab.chat` enum case with `#if DEBUG`
  - [x] 🟩 Gate `ChatService` StateObject with `#if DEBUG`
  - [x] 🟩 Gate the Chat `Tab` block with `#if DEBUG`
  - [x] 🟩 Remove `chatService: chatService` from ProfileView init
  - [x] 🟩 Update struct doc comment to remove chat references

- [x] 🟩 **Step 2: Update ProfileView**
  - [x] 🟩 Remove `@ObservedObject var chatService: ChatService`
  - [x] 🟩 Remove `@State private var showClearChatAlert = false`
  - [x] 🟩 Remove entire `// SECTION 5: DATA` block with the "Clear Chat History" button
  - [x] 🟩 Remove `.alert("Clear Chat History?", ...)` modifier
  - [x] 🟩 Update `#Preview` to remove `chatService: ChatService()` argument
