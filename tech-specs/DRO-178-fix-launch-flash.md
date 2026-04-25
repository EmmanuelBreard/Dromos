# Feature Implementation Plan — DRO-178: Fix App Launch Flash

**Overall Progress:** `100%`

## TLDR
Add an `isInitializing` flag to `AuthService` so `RootView` shows a logo+spinner splash screen during cold-start auth resolution, then jumps directly to the correct destination. Removes the Login → Onboarding → Home flash sequence and eliminates the redundant double-check on launch.

## Critical Decisions
- **`isInitializing` lives in `AuthService`, not `RootView`** — AuthService already owns all auth/onboarding/plan state. Keeping the flag there means RootView stays a pure renderer with no async logic of its own.
- **Remove `RootView.task`** — It duplicates `checkExistingSession()` which already runs in `AuthService.init`. The `.task` block is dead weight that causes two extra network calls on every cold start.
- **No animation on initial reveal** — Direct cut from splash to destination. Existing `.animation` modifiers on subsequent state changes (sign-in, sign-out) remain untouched.
- **`isInitializing` set to `false` in two places** — Both `checkExistingSession()` (cold start path) and the `.initialSession` case in `authStateChanges` (Supabase SDK path) must clear the flag, as either may fire first depending on SDK behavior.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Core/Services/AuthService.swift` | MODIFY | Add `@Published private(set) var isInitializing: Bool = true`; set to `false` at end of `checkExistingSession()` and `.initialSession` handler |
| `Dromos/Dromos/App/RootView.swift` | MODIFY | Add `isInitializing` branch at top of `Group`; remove redundant `.task` block |

## Context Doc Updates
- `architecture.md` — minor: note `isInitializing` flag on `AuthService` as the launch-gate pattern

## Tasks

- [x] 🟩 **Step 1: Add `isInitializing` flag to `AuthService`**
  - [x] 🟩 Add `@Published private(set) var isInitializing: Bool = true` to the published properties section
  - [x] 🟩 At the end of `checkExistingSession()` (both success and error paths, before returning), set `isInitializing = false`
  - [x] 🟩 At the end of the `.initialSession` case in `startObservingAuthState()` (both the valid-session and expired/nil paths), set `isInitializing = false`

- [x] 🟩 **Step 2: Update `RootView` to gate on `isInitializing`**
  - [x] 🟩 Add `isInitializing` branch as the first condition in the `Group`:
    ```swift
    if authService.isInitializing {
        VStack(spacing: 24) {
            Image("DromosLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if !authService.isAuthenticated {
        // ... existing branches unchanged
    ```
  - [x] 🟩 Remove the `.task { }` block entirely from `RootView`
  - [x] 🟩 Remove the `.animation` modifier on `isInitializing` (none needed — direct cut)
