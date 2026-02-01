# DRO-42: Plan Generation Trigger + Loading UX Post-Onboarding

**Overall Progress:** `100%`

## TLDR
Add a plan generation screen between onboarding completion and the main app. RootView gains a 4th routing state (`onboarded + no active plan`) that shows `PlanGenerationView` with a "Generate My Plan" CTA. Tapping it calls the `generate-plan` Edge Function (~140s), shows rotating progress phrases, then navigates to MainTabView on success.

## Critical Decisions
- **4-state RootView (Option A):** AuthService checks `training_plans` for an active plan on launch. Handles the "quit mid-generation" edge case — user returns to PlanGenerationView instead of an empty MainTabView.
- **Long HTTP await:** Single `functions.invoke()` call with ~180s timeout. No polling. Simpler than fire-and-forget + status polling.
- **Non-cancellable:** No back/cancel button during generation. Avoids orphaned server-side work complexity.
- **Post-success → MainTabView:** No intermediate success screen. Home/Calendar will display plan data in DRO-43/44.
- **Rotating progress phrases:** Messages cycle every ~15s to keep user engaged during the long wait.

## Files

| Action | Path |
|--------|------|
| **Create** | `Dromos/Dromos/Features/Plan/PlanGenerationView.swift` |
| **Create** | `Dromos/Dromos/Core/Services/PlanService.swift` |
| **Modify** | `Dromos/Dromos/Core/Services/AuthService.swift` |
| **Modify** | `Dromos/Dromos/App/RootView.swift` |

## Tasks

- [x] 🟩 **Step 1: Add `hasPlan` state to AuthService**
  - [x] 🟩 Add `@Published private(set) var hasPlan: Bool = false`
  - [x] 🟩 Add `checkPlanStatus()` method — queries `training_plans` table for `status = 'active'` row matching current user. Sets `hasPlan` accordingly.
  - [x] 🟩 Call `checkPlanStatus()` after `checkOnboardingStatus()` succeeds (in `checkExistingSession()`, `startObservingAuthState()` signedIn/initialSession events, and the `.task` in RootView)
  - [x] 🟩 Reset `hasPlan = false` on sign out
  - [x] 🟩 Add `markHasPlanLocally()` convenience (called by PlanGenerationView after successful generation, same pattern as `markOnboardingCompleteLocally()`)

- [x] 🟩 **Step 2: Update RootView routing**
  - [x] 🟩 Add 4th branch: `onboardingCompleted && !hasPlan` → `PlanGenerationView(authService:)`
  - [x] 🟩 Add `.animation(.default, value: authService.hasPlan)`
  - [x] 🟩 Call `checkPlanStatus()` alongside `checkOnboardingStatus()` in `.task`

- [x] 🟩 **Step 3: Create PlanService**
  - [x] 🟩 New `@MainActor final class PlanService: ObservableObject`
  - [x] 🟩 `@Published private(set) var isGenerating: Bool = false`
  - [x] 🟩 `@Published var errorMessage: String?`
  - [x] 🟩 `generatePlan()` method:
    - Calls `SupabaseClientProvider.client.functions.invoke("generate-plan")` (no body needed — Edge Function reads profile server-side)
    - Bearer token sent automatically by the SDK from current session
    - Handle `FunctionsError.httpError(code, data)` — parse `{ "error": "..." }` from response body
    - Handle `FunctionsError.relayError` — network/timeout error
    - On success: set `isGenerating = false`, return
    - On failure: set `errorMessage` with user-friendly text, set `isGenerating = false`

- [x] 🟩 **Step 4: Create PlanGenerationView**
  - [x] 🟩 Three states: **idle** (CTA), **generating** (loading), **error** (retry)
  - [x] 🟩 **Idle state:**
    - Icon (`figure.run.circle` or similar)
    - Headline: "Your plan is ready to be built"
    - Subtitle: brief context line
    - "Generate My Plan" button → calls `planService.generatePlan()`
  - [x] 🟩 **Generating state:**
    - ProgressView spinner
    - Rotating phrases every ~15s using a Timer: "Analyzing your goals...", "Building weekly structure...", "Selecting workouts...", "Optimizing your schedule...", "Finalizing your plan..."
    - No back/cancel button
  - [x] 🟩 **Error state:**
    - Error message from PlanService
    - "Try Again" button → retries `generatePlan()`
  - [x] 🟩 **On success:** call `authService.markHasPlanLocally()` to trigger RootView transition to MainTabView
  - [x] 🟩 Sign Out toolbar button (same pattern as OnboardingFlowView — escape hatch)
