# DRO-311 — PoC: Real-Edge-Function Eval Plumbing

**Overall Progress:** `100%` — plumbing PROVEN end-to-end (a full run reached `active` and the checker scored the real plan). Uncovered + fixed a production zombie bug (DRO-312) along the way.

## FINAL UPDATE (after DRO-312 migration applied)

Re-ran the PoC after allowing `'failed'` status: generation completed to `active` in ~110s (19 weeks / 118 sessions), and `check-step3-violations.js` scored the real prod plan. **Full harness path proven E2E.** Two findings:
- **Generation is intermittent** — the same low-volume Olympic profile that zombied earlier succeeded now. The primary failure is flaky (transient), not deterministic. With DRO-312 live, flaky failures now flip to `failed` (retryable) instead of zombieing.
- **The harness immediately caught real violations** on the prod-generated plan: 4 HARD sport-eligibility violations (run scheduled Sat in W13–16 though run days are Mon/Wed/Thu/Sun) + 1 soft missing-brick. Exactly the DRO-311 use case.

Ready to resume the full `/create-tech-spec DRO-311` — the invocation path, environment choice (prod + cleanup), auth (anon signUp), and DB→eval-shape adapter are all validated.

## PoC RESULTS (run 2026-07-15, against production + cleanup)

**Plumbing: PROVEN ✅** — every harness mechanism works with just the anon key + MCP:
- Programmatic auth: `signUp` returns a session JWT immediately (email confirmation off) — **no service-role key needed**.
- Profile seeding: authenticated user updates its own `public.users` row via the `"Users can update own profile"` RLS policy. (Trigger `on_auth_user_created` creates the row on signup.)
- Invocation: `functions.invoke("generate-plan")` with the session token returns `{ planId }` (201 create logged).
- Cleanup: `DELETE FROM auth.users WHERE id=…` CASCADEs to `public.users` → `training_plans` → weeks/sessions. Verified zero residual rows. **Environment verdict: production + cleanup is viable and cheap.**

**End-to-end: BLOCKED ❌ — production bug found.** Generation never reached `active`; the plan zombied at `generating`. API logs show the edge function ran (fetched `workout-library.json` at ~112s), then at ~132s issued `PATCH /training_plans → 400`. Root cause confirmed:
- `training_plans_status_check` = `CHECK (status = ANY (ARRAY['generating','active']))` — **`'failed'` is not an allowed value.**
- The background catch block (`generate-plan/index.ts:2080`) does `.update({ status: "failed" })` → rejected 400 → inner catch only logs → **status stays `generating` forever.** Any generation error becomes a permanent zombie plan. This is the likely root cause behind DRO-108 (which treated the symptom).

**Unconfirmed:** the *primary* error that triggered the catch (something threw before the weeks-insert; no `plan_weeks` POST occurred). Supabase MCP `get_logs(edge-function)` returns empty, so the console error is not retrievable via MCP — needs the Supabase dashboard function logs.

**Data hygiene finding:** rest days must be seeded as `NULL`, not `0` (`check_<day>_duration` = `NULL OR 30..420`). The eval's `athletes.yaml` uses `"0"` for rest — the harness must translate `0 → NULL` when seeding.

**Recommended next steps:** (1) separate production fix — allow `'failed'` in the status constraint (or set an `error`/timestamp) so failures surface instead of zombieing; (2) pull dashboard edge logs to identify the primary generation error; (3) resume the full harness once generation completes E2E — the harness must also treat "stuck in `generating` past timeout" as a failure, since it cannot rely on `'failed'` today.

## TLDR
Before we build the full plan-quality eval harness (DRO-311), validate the single riskiest, never-before-run assumption: **can we programmatically stand up a synthetic test user, authenticate it, invoke the *deployed* `generate-plan` edge function, and read the materialized plan back — end-to-end, for ONE scenario?** This PoC also settles the unresolved environment question (preview branch vs test project vs main+cleanup). Everything downstream (more scenarios, the DB-shape checker adapter, the markdown report, chat-adjust) is mechanical once this works.

## The question this PoC answers
> Given a synthetic athlete profile, can a Node script (running locally) create an auth user + `public.users` row in a chosen Supabase environment, obtain a valid JWT, POST to `/functions/v1/generate-plan`, poll `training_plans.status` to `active`, read back `plan_weeks` + `plan_sessions`, run the existing 8-metric checker against that DB-shaped plan, and clean up — without touching production data?

Secondary decision the PoC must return: **which environment do we run against?**
- **A — Preview branch** (`supabase create_branch`): isolated DB. *Unknown: does a branch deploy/serve the edge functions?* PoC must confirm or refute.
- **B — Dedicated test Supabase project**: fully isolated, but standing cost + separate keys.
- **C — Main project + strict cleanup**: simplest plumbing, but writes transient test rows into prod DB (must delete-user-CASCADE after each run).

The PoC tries **A first**; if branches don't serve functions, it falls back to **C** for the plumbing proof and records the recommendation for the full spec.

## Known invocation contract (from code)
- Endpoint: `POST {SUPABASE_URL}/functions/v1/generate-plan`, header `Authorization: Bearer <user access_token>`. Request body is ignored — the function reads the user from the JWT (`generate-plan/index.ts:1730` `authClient.auth.getUser(jwt)`) and the profile from `public.users` (`index.ts:1748`).
- Preconditions on the `users` row: `race_objective`, `race_date`, `onboarding_completed = true` (validated `index.ts:1768`); availability fields (`{day}_duration`, `swim/bike/run_days`) drive scheduling.
- Response: `{ planId }` returned immediately; generation runs in `EdgeRuntime.waitUntil` (`index.ts:1832`). Caller must **poll** `training_plans.status` until `active` or `failed` (contract mirrors `PlanService.swift:61`).
- Auth-user creation path: service_role admin API `auth.admin.createUser({ email, password, email_confirm: true })` → `signInWithPassword` (anon key) to mint the JWT → `auth.admin.deleteUser` for teardown (CASCADE removes `users` + `training_plans` + `plan_weeks` + `plan_sessions`).
- Required secrets (NOT currently in `.env`): `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (project ref `cumbrfnguykvxhvdelru`; fetch via Supabase dashboard or the Supabase MCP `get_project_url` / `get_publishable_keys`). Add to `.env` (already git-ignored).

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `ai/eval/poc-generate-e2e.js` | CREATE | The PoC script: seed user → auth → invoke → poll → read-back → check → cleanup. Self-contained, one scenario. |
| `ai/eval/poc-lib/supabase-eval-client.js` | CREATE | Thin helper wrapping createUser / signIn / invoke / poll / readPlan / deleteUser (reused by full harness later). |
| `ai/eval/db-plan-to-eval-shape.js` | CREATE | Adapter: `plan_weeks` + `plan_sessions` (DB) → the `{ weeks: [{ week_number, phase, sessions: [...] }] }` shape `check-step3-violations.js` expects. This is the one genuinely new piece of glue; proving it here de-risks the full spec. |
| `.env` | MODIFY | Add `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (local only, git-ignored). |
| `ai/eval/package.json` | MODIFY | Add `@supabase/supabase-js` dependency. |

*(No production code, edge functions, prompts, or DB migrations are modified by the PoC.)*

## Success criteria
The PoC **passes** if, for one Olympic scenario, a single `node ai/eval/poc-generate-e2e.js` run:
1. Creates a synthetic auth user + profile and obtains a valid JWT (no manual token pasting).
2. Invokes the deployed `generate-plan` and receives a `planId`.
3. Polls to `status = active` within the function timeout and reads back ≥1 `plan_week` with `plan_sessions`.
4. Feeds the DB-shaped plan through `check-step3-violations.js` and prints the 8-metric summary.
5. Cleans up: the test user and all cascaded rows are gone afterward (verified by re-query).
6. Prints a one-line **environment verdict**: which of A/B/C worked, and the recommended choice for the full harness.

It **fails / needs escalation** if auth can't be minted programmatically, the branch can't serve functions AND main-project writes are deemed unacceptable, or the DB→eval-shape adapter can't reconstruct what the checker needs.

## Out of scope for the PoC
- `chat-adjust` (adjustment flow) — deferred to the full spec once generation plumbing is proven.
- Multiple scenarios / N=3 repeats — one scenario, one run.
- Yupa integration, markdown report, availability scenario matrix — full-spec concerns.

## Expected timeline
A few hours. If green, run `/create-tech-spec DRO-311` again for the full feature spec, now grounded in a proven invocation path and a settled environment choice.

## Tasks:

- [ ] 🟥 **Step 1: Secrets + deps**
  - [ ] 🟥 Fetch `SUPABASE_URL` / `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` (dashboard or Supabase MCP) and add to `.env`
  - [ ] 🟥 Add `@supabase/supabase-js` to `ai/eval/package.json` and install

- [ ] 🟥 **Step 2: Eval Supabase client helper** (`ai/eval/poc-lib/supabase-eval-client.js`)
  - [ ] 🟥 `createTestUser(profile)` — admin createUser + insert `public.users` row (onboarding_completed=true)
  - [ ] 🟥 `signIn(email, password)` — mint JWT via anon client
  - [ ] 🟥 `invokeGeneratePlan(jwt)` — POST to `/functions/v1/generate-plan`, return planId
  - [ ] 🟥 `pollStatus(planId)` — poll `training_plans.status` until active/failed (with timeout)
  - [ ] 🟥 `readPlan(planId)` — nested read of `plan_weeks` + `plan_sessions`
  - [ ] 🟥 `deleteTestUser(userId)` — admin deleteUser (CASCADE)

- [ ] 🟥 **Step 3: DB→eval-shape adapter** (`ai/eval/db-plan-to-eval-shape.js`)
  - [ ] 🟥 Map DB rows to `{ weeks: [{ week_number, phase, sessions: [{ day, sport, type, duration_minutes, is_brick }] }] }`
  - [ ] 🟥 Verify it matches what `check-step3-violations.js` consumes

- [ ] 🟥 **Step 4: Environment probe**
  - [ ] 🟥 Attempt A: create preview branch, check whether `/functions/v1/generate-plan` is served on it
  - [ ] 🟥 If A fails, fall back to C (main project + guaranteed cleanup) for the plumbing proof
  - [ ] 🟥 Record the environment verdict + recommendation

- [ ] 🟥 **Step 5: End-to-end PoC script** (`ai/eval/poc-generate-e2e.js`)
  - [ ] 🟥 Wire Steps 2–4 into one run for a single Olympic scenario
  - [ ] 🟥 Run the 8-metric checker on the read-back plan and print the summary
  - [ ] 🟥 Confirm teardown leaves no residual rows

- [ ] 🟥 **Step 6: Write up findings**
  - [ ] 🟥 Record pass/fail against success criteria, environment verdict, and any surprises
  - [ ] 🟥 Feed conclusions into the full `/create-tech-spec DRO-311` run
