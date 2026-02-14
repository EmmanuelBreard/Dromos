# DRO-57: iOS Client Timeout During Plan Generation

**Overall Progress:** `0%`

## TLDR
The `generate-plan` edge function completes successfully (~143s) but the iOS client's URLSession times out before receiving the response. Fix: configure a custom URLSession with 180s timeout on the shared SupabaseClient.

## Critical Decisions
- **Global timeout on shared client** — The Supabase Swift SDK only supports URLSession configuration at the client level (not per-invoke). A global 180s timeout is safe because fast calls still return immediately; the timeout is just a maximum.
- **No separate client** — Creating a second SupabaseClient for plan generation would cause auth session sharing issues. Not worth the complexity.
- **No UI changes** — Progress indicator / messaging is out of scope for this task.
- **Keep error messages generic** — No special timeout-specific messaging.

## Files

| File | Role |
|------|------|
| `Dromos/Dromos/Core/Services/SupabaseClient.swift` | Add custom URLSession with 180s timeout |
| `Dromos/Dromos/Core/Services/PlanService.swift` | Remove outdated timeout comment |

## Tasks

- [ ] 🟥 **Step 1: Configure URLSession timeout in SupabaseClient.swift**
  - [ ] 🟥 Create a custom `URLSessionConfiguration` with `timeoutIntervalForRequest = 180`
  - [ ] 🟥 Pass the custom URLSession via `SupabaseClientOptions(global: .init(session: ...))`

- [ ] 🟥 **Step 2: Clean up outdated comment in PlanService.swift**
  - [ ] 🟥 Remove the 3-line comment block (lines 50-52) about SDK timeout margins since the issue is now resolved
