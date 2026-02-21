# DRO-108: Edge Function — Cleanup Zombie Plan on Failure

**Overall Progress:** `100%`

## TLDR
When `generate-plan` crashes after creating the `training_plans` row, the row is left with `status = 'generating'` forever. Add cleanup in the catch block to delete the zombie row, and surface the actual error message to the iOS client for easier debugging.

## Critical Decisions
- **Delete vs mark `failed`**: Delete the row. A `failed` status would require iOS changes to handle a third state, and the row has no useful data (0 weeks, 0 sessions). The retry path already deletes existing plans, so this is consistent.
- **Best-effort cleanup**: The cleanup delete is wrapped in its own try/catch — if even the cleanup fails (e.g., DB down), we still return the 500 to the client. We don't let a cleanup failure mask the original error.
- **Surface error detail**: Include the error message in the 500 response so the iOS error toast gives actionable info (e.g., "OpenAI timeout" vs generic "Please try again").

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `supabase/functions/generate-plan/index.ts` | MODIFY | Add cleanup + error detail in catch block (lines 2107-2121) |

## Context Doc Updates
None — no architectural change.

## Tasks

- [x] 🟩 **Step 1: Hoist `planId` declaration and add cleanup in catch block**

  **What:** Move `planId` to an outer `let` so it's accessible in the catch block, then add cleanup logic.

  **File:** `supabase/functions/generate-plan/index.ts`

  1. Before the try block (around line 1680, inside the `Deno.serve` handler but before `try {`), add:
     ```typescript
     let planId: string | null = null;
     ```

  2. At line 1821, change `const planId = plan.id;` to:
     ```typescript
     planId = plan.id;
     ```

  3. Replace the catch block (lines 2107-2121) with:
     ```typescript
     } catch (error) {
       console.error("Plan generation failed:", error);

       // Best-effort cleanup: delete the zombie plan row
       if (planId && typeof dbClient !== "undefined") {
         try {
           await dbClient
             .from("training_plans")
             .delete()
             .eq("id", planId);
           console.log(`Cleaned up zombie plan ${planId}`);
         } catch (cleanupError) {
           console.error("Failed to clean up zombie plan:", cleanupError);
         }
       }

       const message =
         error instanceof Error
           ? `Plan generation failed: ${error.message}`
           : "Plan generation failed. Please try again.";

       return new Response(
         JSON.stringify({ error: message }),
         {
           status: 500,
           headers: {
             "Content-Type": "application/json",
             "Access-Control-Allow-Origin": "*",
           },
         }
       );
     }
     ```

  **Why `planId` guard:** If the error happens before the plan row is created (e.g., validation failure, env var missing), `planId` is still `null` and we skip cleanup — correct behavior since there's nothing to clean up.

  **Verify:** Deploy to staging, trigger a failure (e.g., temporarily invalid OpenAI key), confirm:
  - No orphaned `training_plans` rows with `status = 'generating'`
  - 500 response includes the actual error message
  - `console.log` confirms cleanup ran

- [x] 🟩 **Step 2: Deploy and verify**
  - `supabase functions deploy generate-plan --no-verify-jwt`
  - Check Supabase Edge Function logs for `Cleaned up zombie plan` message on next failure
  - Confirm existing happy path (successful plan generation) is unaffected — `planId` is assigned before any LLM call, so the change is safe

## Rollback
Revert the catch block to the original 3-line version. No DB migration, no schema change — zero rollback risk.
