# DRO-311 — Plan-Quality Eval Harness (Full Spec)

**Overall Progress:** `25%`

> **SCOPE UPDATE (2026-07-16): generation-only for v1.** The adjustment eval (Phase 4 / Step 6) is **dropped** — the deployed `chat-adjust` is advisory Coach Chat V0 (no plan modification, SSE-streamed, gated to one email), so the `adjust-step*-scenarios.yaml` (plan-adjustment) flow it targets is not live. Revisit when a real plan-adjustment flow ships. The `invokeChatAdjust` stub in the client stays as a harmless placeholder.

## TLDR
An on-demand Node harness that runs availability-focused test athletes through the **real deployed** `generate-plan` edge function, scores the resulting plans with the existing 8-metric checker (HARD gates / SOFT warns), attaches an advisory coaching verdict, and emits a timestamped markdown report. Answers "did we make plans better or worse?" before shipping mechanism changes. Built on the DRO-311 PoC, which already proved the auth → seed → invoke → poll → read → check → cleanup path end-to-end against prod.

## Critical Decisions
- **Target = real deployed edge functions** (not the shadow `run-step3-blocks.js`). Proven in the PoC; catches regressions in shipped code, not a re-implementation.
- **Environment = production + strict cleanup.** Only prod exists; branches don't carry the function secrets. Synthetic users are created per run and deleted (CASCADE) in a `finally`. Proven safe in the PoC (zero residual rows).
- **Auth = anon `signUp`** → session JWT (email confirmation is off). No service-role key needed; all seeding/reads run under the test user's own JWT via RLS.
- **Rest days seed as `NULL`, not `0`** — DB constraint `check_<day>_duration` = `NULL OR 30..420`. The harness translates the scenario `0`/absent convention → `NULL`.
- **Statistics = N=3 runs/scenario; a scenario FAILS on any HARD violation in any run.** Generation is temp-0.2 (non-deterministic) and, per DRO-312, intermittently fails outright.
- **HARD (gates):** duration-cap, sport-eligibility, rest-day, same-day dual-hard, brick-order. **SOFT (warn):** missing-brick, sport-clustering, intensity-clustering.
- **Yupa coaching audit = advisory, via in-harness OpenAI rubric.** The `triathlon-coach` subagent can't be called from `node`, so the harness makes an OpenAI call using a coaching rubric derived from Yupa's 80/20 principles (mirrors promptfoo's existing `llm-rubric`). Verdict lands in the report; never gates. The `triathlon-coach` agent stays available for manual deep-dives.
- **Generation-failure ≠ quality-failure.** Post-DRO-312, a failed generation returns `status='failed'` + `error_message`. The harness records these as a distinct **generation-reliability failure**, separate from HARD-violation failures.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `ai/eval/lib/eval-supabase-client.js` | CREATE | Promote the PoC's inline client to a reusable module: `createTestUser(profile)` (with `0→NULL` rest-day translation), `signIn`, `invokeGeneratePlan(jwt)`, `pollStatus(planId)` (returns active / failed+error_message / timeout-as-failure), `readPlan(planId)`, `deleteTestUser(userId)`, `invokeChatAdjust(jwt, turns)`. |
| `ai/eval/db-plan-to-eval-shape.js` | REUSE | Already built + proven in the PoC. |
| `ai/eval/check-step3-violations.js` | MODIFY | Extract a pure `scorePlan(evalPlan, scenarioVars)` that returns the 8-metric summary (keep the CLI wrapper). Add a `HARD_VIOLATIONS`/`SOFT_VIOLATIONS` classification constant. Make constraints come from passed `scenarioVars` (not only `athletes.yaml`). |
| `ai/eval/vars/availability-scenarios.yaml` | CREATE | Availability-focused scenario set: Olympic + 70.3 × availability shapes (weekly-hours low/mid/high, day patterns, per-day caps, per-sport day eligibility). Each entry = a full `users`-table profile + `scenario_name`. Race dates are computed forward from run date (avoid past-date scenarios). |
| `ai/eval/run-generation-eval.js` | CREATE | Orchestrator: for each scenario × N=3 → seed → invoke → poll → read → adapt → `scorePlan` → classify HARD/SOFT → aggregate (reuse `aggregate-violations.js` labels) → `finally` cleanup. Records generation-reliability failures separately. |
| ~~`ai/eval/run-adjustment-eval.js`~~ | ~~CREATE~~ | **DROPPED (v1)** — deployed `chat-adjust` is advisory, not plan-adjustment. Deferred until a real adjustment flow ships. |
| `ai/eval/aggregate-violations.js` | REUSE | Existing CLEAN/VARIANCE/INVESTIGATE/SYSTEMATIC labeling across N runs. |
| `ai/eval/lib/report.js` | CREATE | Builds the timestamped markdown report (per-scenario PASS/FAIL, HARD/SOFT breakdown per run, generation-reliability, advisory verdict) + console summary. |
| `ai/eval/run-eval.sh` | CREATE | Single entry point: runs the generation eval and writes the report to `ai/eval/results/eval-report-<stamp>.md`. |
| `ai/eval/poc-generate-e2e.js` | REUSE | Kept as the minimal reference/smoke test. |

## Context Doc Updates
- `ai-pipeline.md` — add the eval harness (new runners, lib, scenario file, report) to the Eval Framework section; note it targets the real edge functions vs the shadow.
- `architecture.md` — note the `ai/eval/lib/` client pattern (programmatic auth + prod-with-cleanup test users).
- `schema.md` — `training_plans.error_message` / `failed_at` + the `'failed'` status were added under DRO-312; ensure they're reflected (if not already).

## Tasks:

- [ ] 🟥 **Step 1: Eval Supabase client library**
  - [ ] 🟥 Extract PoC logic into `ai/eval/lib/eval-supabase-client.js` (createTestUser + `0→NULL`, signIn, invoke, poll, read, delete)
  - [ ] 🟥 `pollStatus` returns `active` | `{failed, error_message}` | `timeout` (treat stuck-`generating` past timeout as failure)
  - [ ] 🟥 Add `invokeChatAdjust(jwt, turns)` for the adjustment flow

- [x] 🟩 **Step 2: Availability scenario set** (`vars/availability-scenarios.yaml`) — DRO-314
  - [x] 🟩 Define Olympic + 70.3 × availability shapes (weekly hours, day pattern, caps, sport-day eligibility) — 12 scenarios (6/distance), crossing low/mod/high weekly hours, few/many days, weekday-only/weekend-heavy/scattered patterns, even vs short-weekday/long-weekend caps, and 1-3x/week pool eligibility
  - [x] 🟩 Fixed-forward (2027) race dates per scenario; full `users`-table profile per scenario (real types, not promptfoo string vars), ready for `createTestUser(profile)`

- [ ] 🟥 **Step 3: Scorer refactor** (`check-step3-violations.js`)
  - [ ] 🟥 Export pure `scorePlan(evalPlan, scenarioVars)` returning the 8-metric summary
  - [ ] 🟥 Add `HARD_VIOLATIONS` / `SOFT_VIOLATIONS` classification
  - [ ] 🟥 Source constraints from `scenarioVars` (decouple from `athletes.yaml`)

- [ ] 🟥 **Step 4: Generation eval runner** (`run-generation-eval.js`)
  - [ ] 🟥 Loop scenarios × N=3: seed → invoke → poll → read → adapt → score → classify
  - [ ] 🟥 Aggregate via `aggregate-violations.js`; record generation-reliability failures separately
  - [ ] 🟥 Guaranteed cleanup in `finally` (delete test users)

- [~] 🟨 **Step 5: Coaching audit (advisory, in-harness OpenAI rubric)** (`ai/eval/lib/yupa-rubric.js`) — DRO-314 (module built; report wiring pending Step 7)
  - [x] 🟩 Coaching rubric prompt derived from Yupa's 80/20 principles (`.claude/agents/triathlon-coach.md`)
  - [x] 🟩 `reviewPlan(evalPlan, scenarioVars)`: one OpenAI (`gpt-4.1`, temp 0.2, strict JSON schema) call per plan → verdict (SHIP / SHIP WITH CHANGES / DO NOT SHIP) + issues + summary. Verified against the PoC sample plan (`results/poc-generate.json`) — well-formed output, advisory only, never throws on a bad plan.
  - [ ] 🟥 Attach to report, non-gating (blocked on Step 4/7's runner + report existing)

- [x] ⬛ **Step 6: Adjustment eval runner — DROPPED (v1)** — deployed `chat-adjust` is advisory Coach Chat V0, not plan-adjustment. Deferred.
  - Original intent: drive `chat-adjust` per `adjust-step1/2-scenarios.yaml` case (multi-turn)
  - [ ] 🟥 Assert `expected_status` + existing `validation` blocks

- [ ] 🟥 **Step 7: Report + entry point** (`lib/report.js`, `run-eval.sh`)
  - [ ] 🟥 Markdown report in `ai/eval/results/eval-report-<stamp>.md` + console summary
  - [ ] 🟥 `run-eval.sh` runs the generation eval and writes the report

- [ ] 🟥 **Step 8: Docs**
  - [ ] 🟥 Update `ai-pipeline.md` (+ `architecture.md`) with the harness
