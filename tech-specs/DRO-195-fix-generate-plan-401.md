# DRO-195 — Fix: generate-plan 401 on first-time plan generation

**Overall Progress:** `100%`

## TLDR
`generate-plan` users hit a 401 when the iOS SDK sends a missing or stale token. The gateway's `verify_jwt: true` is correct and stays — it prevents JWT impersonation since the function uses `service_role` and trusts `payload.sub` without re-verifying the signature. The fix is entirely iOS-side: fail fast on stale session and surface a clear re-auth message.

## Critical Decisions
- **Keep `verify_jwt: true` on the edge function** — the function base64-decodes the JWT without verifying the signature; the gateway is the only thing preventing a forged `sub` claim from being trusted. Do NOT change this.
- **Hard fail on refresh error** — if `refreshSession()` throws (expired refresh token), surface a user-facing message immediately rather than proceeding to a 401.
- **No edge function redeploy** — only a stale comment needs removing; no logic or config change.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `supabase/functions/generate-plan/index.ts` | MODIFY | Remove stale comment claiming `--no-verify-jwt` was set (line ~1714) |
| `Dromos/Dromos/Core/Services/PlanService.swift` | MODIFY | Add session refresh with hard fail before `isGenerating = true` in `generatePlan()` |

## Context Doc Updates
None required.

## Tasks

- [x] 🟩 **Step 1: Add session refresh with hard fail in iOS**
  - [x] 🟩 In `Dromos/Dromos/Core/Services/PlanService.swift`, in `generatePlan()` at line 44, add before `isGenerating = true`:
    ```swift
    do {
        try await client.auth.refreshSession()
    } catch {
        let msg = "Your session has expired. Please sign in again."
        self.errorMessage = msg
        throw PlanGenerationError.serverError(msg)
    }
    ```

- [x] 🟩 **Step 2: Remove stale comment in edge function**
  - [x] 🟩 In `supabase/functions/generate-plan/index.ts` around line 1714, replace the comment block explaining `--no-verify-jwt` with one that accurately explains why `verify_jwt: true` is intentional:
    ```
    // JWT is verified by the Supabase gateway (verify_jwt: true).
    // The function decodes the payload to extract user_id but does NOT re-verify
    // the signature — the gateway guarantees authenticity before we reach here.
    ```
