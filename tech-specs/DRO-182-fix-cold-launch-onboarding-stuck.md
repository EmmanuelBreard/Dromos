# Feature Implementation Plan

**Overall Progress:** `100%`

## TLDR

On cold launch, if the Supabase access token is expired (tokens expire after 1h), `AuthService` incorrectly treats the user as unauthenticated and shows the onboarding screen. A one-character guard removal fixes it by letting the Supabase SDK handle token refresh transparently.

## Critical Decisions

- **Remove `!session.isExpired` guard entirely** — The Supabase Swift SDK auto-refreshes expired tokens on any network request. Checking `isExpired` before our DB queries is redundant and actively harmful. `if let session` is the correct signal for "a valid session exists".
- **No change to `.tokenRefreshed` handler** — It only updates `self.session`, which is correct; it fires *after* `.initialSession` has already set `isInitializing = false`.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Core/Services/AuthService.swift` | MODIFY | Remove `!session.isExpired` from the `.initialSession` guard on line 226 |

## Context Doc Updates

None — no new files, services, or patterns introduced.

## Tasks

- [ ] 🟩 **Step 1: Fix `.initialSession` guard in AuthService**
  - [ ] 🟩 In `AuthService.swift` line 226, change `if let session, !session.isExpired {` → `if let session {`
  - [ ] 🟩 Verify the `else` branch still handles nil session correctly (sets `session = nil`, `onboardingCompleted = false`, `hasPlan = false`, `isInitializing = false`) — no change needed there
