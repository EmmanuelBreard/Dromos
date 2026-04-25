# DRO-200 — Account Deletion

**Overall Progress:** `100%`

## TLDR

Add a "Delete Account" button to the Profile screen (Sign Out section) that permanently deletes the user's `auth.users` row via a new `delete-account` Edge Function. All downstream data (profile, plan, Strava, chat) is wiped via existing `ON DELETE CASCADE` chains. Required for Apple App Store compliance (Guideline 5.1.1).

## Critical Decisions

- **Edge Function for deletion** — Supabase client SDK cannot delete `auth.users` from the client; a `service_role` Edge Function is the only viable path.
- **No extra data cleanup needed** — All FK chains already use `ON DELETE CASCADE`. Deleting `auth.users` is sufficient.
- **Same section as Sign Out** — Delete Account lives in the existing bottom `Section` in `ProfileView`, below Sign Out.
- **Simple confirmation alert** — No re-authentication required. One alert with Cancel / Delete.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `supabase/functions/delete-account/index.ts` | CREATE | New Edge Function: validates JWT, calls `auth.admin.deleteUser(userId)` via service_role |
| `Dromos/Dromos/Core/Services/AuthService.swift` | MODIFY | Add `deleteAccount()` async method |
| `Dromos/Dromos/Features/Profile/ProfileView.swift` | MODIFY | Add Delete Account button + confirmation alert state |

## Context Doc Updates

- `architecture.md` — New Edge Function `delete-account` added

---

## Tasks

- [x] 🟩 **Step 1: Create `delete-account` Edge Function**
  - [x] 🟩 Create `supabase/functions/delete-account/index.ts`
  - [x] 🟩 Extract and validate the Bearer JWT from the `Authorization` header; return 401 if missing or invalid
  - [x] 🟩 Call `supabaseAdmin.auth.admin.deleteUser(userId)` using the service role client
  - [x] 🟩 Return `200 {}` on success, `500 { error: "..." }` on failure
  - [x] 🟩 Follow the exact same structure as `supabase/functions/strava-auth/index.ts` for CORS headers and error handling

- [x] 🟩 **Step 2: Add `deleteAccount()` to `AuthService`**
  - [x] 🟩 In `Dromos/Dromos/Core/Services/AuthService.swift`, add `deleteAccount()` async throws method
  - [x] 🟩 Call the `delete-account` Edge Function via `client.functions.invoke("delete-account", options: .init())`
  - [x] 🟩 On success: call `client.auth.signOut()` (best-effort), then clear `session`, `onboardingCompleted`, `hasPlan`
  - [x] 🟩 On failure: throw the error (do not clear session — account still exists)

- [x] 🟩 **Step 3: Update `ProfileView` UI**
  - [x] 🟩 In `Dromos/Dromos/Features/Profile/ProfileView.swift`, add `@State private var showDeleteAccountAlert = false`
  - [x] 🟩 Add "Delete Account" button with `role: .destructive` in the Sign Out `Section`, below the Sign Out button; tapping sets `showDeleteAccountAlert = true`
  - [x] 🟩 Add `.alert("Delete Account", isPresented: $showDeleteAccountAlert)` with message "This will permanently delete your account and all data. This cannot be undone." and buttons Cancel + Delete (destructive)
  - [x] 🟩 In the Delete button action: set `isLoading = true`, call `authService.deleteAccount()`, on success call `profileService.clearProfile()`, on failure show `errorMessage` via existing `showError` alert
  - [x] 🟩 Ensure `isLoading = false` in both success and failure paths (use `defer` or explicit set)
