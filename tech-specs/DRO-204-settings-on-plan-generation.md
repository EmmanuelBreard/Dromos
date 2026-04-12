# Feature Implementation Plan — DRO-204

**Overall Progress:** `100%`

## TLDR
Replace the red "Sign Out" button on `PlanGenerationView` with a gear icon that opens `ProfileView` as a modal sheet. Gives post-onboarding users access to account management (sign out, delete account) without waiting for plan generation.

## Critical Decisions

- **Own fresh service instances in `PlanGenerationView`**: `ProfileView` requires `ProfileService` and `StravaService`. Since `PlanGenerationView` is rendered before `MainTabView` exists, it will own its own `@StateObject` instances of both. These are lightweight objects with no shared-state implications at this stage.
- **Full `ProfileView` as sheet, no trimming**: No need to build a stripped-down settings view — `ProfileView` is already self-contained with its own `NavigationStack`, profile fetch, and all edge cases handled. Reuse it as-is.
- **No changes to `ProfileView`**: It already works standalone. Its `NavigationStack` is compatible with sheet presentation.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Plan/PlanGenerationView.swift` | MODIFY | Add `@StateObject` for `ProfileService` + `StravaService`; add `@State var showSettings`; replace Sign Out toolbar button with gear icon; add `.sheet` presenting `ProfileView` |

## Context Doc Updates

None — no new files, no new patterns, no schema changes.

## Tasks

- [x] 🟩 **Step 1: Swap toolbar button and wire up sheet**
  - [x] 🟩 Add `@StateObject private var profileService = ProfileService()` to `PlanGenerationView`
  - [x] 🟩 Add `@StateObject private var stravaService = StravaService()` to `PlanGenerationView`
  - [x] 🟩 Add `@State private var showSettings = false` to `PlanGenerationView`
  - [x] 🟩 Replace the `ToolbarItem` Sign Out button with a gear icon button (`Image(systemName: "gear")`) that sets `showSettings = true`
  - [x] 🟩 Add `.sheet(isPresented: $showSettings)` presenting `ProfileView(authService: authService, profileService: profileService, stravaService: stravaService)`
