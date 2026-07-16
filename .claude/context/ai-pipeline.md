# AI Pipeline Reference

> Last updated: 2026-04-25

## Overview

Dromos generates triathlon training plans via a 3-step LLM pipeline in a Supabase Edge Function. User profile → macro plan (markdown) → structured JSON → specific workout assignments.

---

## Pipeline Flow

```
iOS App → POST /functions/v1/generate-plan (JWT auth)
    ↓
Step 1 (gpt-4.1): User profile → Markdown macro plan (periodized weeks)
    ↓
Step 2 (gpt-4o-mini): Markdown → Structured JSON
    ↓
Step 3 (gpt-4.1): Per 4-week block → Template IDs + day assignments
    ↓
Post-processing: 15 sequential fixer passes (no LLM)
    ↓
DB writes: training_plans → plan_weeks → plan_sessions
```

**Typical duration:** ~50-65 seconds for a 19-week plan.
**Edge Function timeout:** 150 seconds (Supabase limit). iOS client timeout set to 180s.
**Reference implementation:** `ai/eval/run-step3-blocks.js` — source of truth for post-processing logic before porting to production.

---

## Step 1: Macro Plan Generation

**Prompt:** `ai/prompts/step1-macro-plan.txt`
**Production:** `supabase/functions/generate-plan/prompts/step1-macro-plan-prompt.ts`
**Model:** gpt-4.1 | 16K tokens | temp 0.2

**Input:** User profile (experience, race goal, availability, metrics)
**Output:** Markdown plan with weeks, phases, session types, hours

**Key constraints enforced:**
- Weekly volume <= `weekly_hours` (hard ceiling)
- Max intensity slots scale with hour budget (<=5h: 1/week, 5-8h: 2, 8-12h: 3-4)
- Recovery weeks every 3-4 loading weeks (30-50% volume drop)
- Session caps: weekday <= `max_weekday_minutes`, weekend <= `max_weekend_minutes`
- All Tempo/Intervals sessions <= 60 minutes
- Brick sessions mandatory for all athletes (Base: biweekly, Build/Peak: weekly)
- Long run: ≥75min per week

**Template variables:** `{{training_philosophy}}`, `{{experience_level}}`, `{{race_distance}}`, `{{race_date}}`, `{{weekly_hours}}`, `{{current_weekly_hours}}`, `{{ftp_watts}}`, `{{vma}}`, `{{swim_css}}`, `{{max_weekday_minutes}}`, `{{max_weekend_minutes}}`, sport day counts

**DRO-288 (race-distance narrowing):** `{{race_distance}}` now resolves via `expandRaceObjective()` to one of two canonical strings — `"Olympic (1.5km swim / 40km bike / 10km run)"` or `"Half-Ironman (1.9km swim / 90km bike / 21.1km run)"`. The function still echoes any legacy enum value literally (e.g. the 1 audited production Sprint user) so their existing plan stays as-is; iOS lossily decodes the now-removed Sprint/Ironman cases on profile fetch and falls back to `.ironman703` defaults in the UI.

---

## Step 2: Markdown to JSON

**Prompt:** `ai/prompts/step2-md-to-json.txt`
**Production:** `supabase/functions/generate-plan/prompts/step2-md-to-json-prompt.ts`
**Model:** gpt-4o-mini | 16K tokens | temp 0 (JSON mode)

**Input:** Markdown from Step 1
**Output:** JSON with `plan_summary` + `weeks[]` (sessions per sport with type/duration)

Pure conversion, no transformation.

---

## Step 3: Workout Template Selection

**Prompt:** `ai/prompts/step3-workout-block.txt`
**Production:** `supabase/functions/generate-plan/prompts/step3-workout-block-prompt.ts`
**Model:** gpt-4.1 | 4K tokens | temp 0.2

**Input:** 4-week block + user constraints + previously used templates + workout library
**Output:** Template IDs + day/time assignments per session

**Block processing:** Plan split into 4-week blocks, processed sequentially. `previouslyUsed` templates passed between blocks for variety.

**Key constraints (11 rules in prompt):**
- REST days: no sessions on 0min availability days
- Sport eligibility: only schedule sports available on each day
- Duration caps: total session minutes/day <= available minutes
- Session spread: fill every non-REST day before doubling up
- Sport alternation: avoid same sport on consecutive single-session days
- Intensity spread: no Tempo/Intervals on consecutive days
- Brick placement: bike + run same day, both `is_brick: true`, bike first
- No same-sport doubling: max 1 bike + 1 run per day (swim exempt)
- No dual hard same day: no two Tempo/Intervals bike/run on same day
- Template variety: never same template 2 consecutive weeks (Tempo/Intervals)

**Template variables:** `{{constraints}}` (per-day availability string), `{{block_weeks_json}}`, `{{previously_used}}`, `{{workout_library}}` (simplified format)

**DRO-215 (Phase 1):** `workout-library.json` strength templates removed. `buildSimplifiedLibrary()` in `generate-plan/index.ts` already iterates only `["swim", "bike", "run"]` (see `supabase/functions/generate-plan/index.ts:303`) so no prompt change was needed. Run intensity keys renamed `mas_pct` → `vma_pct` throughout the JSON. The shared materializer (`supabase/functions/_shared/materialize-structure.ts`) handles legacy `mas_pct` keys at materialisation time for edge cases.

**DRO-216 (Phase 2):** `generate-plan/index.ts` now writes `structure` (JSONB) alongside `template_id` at the single insert site. The shared materializer (`_shared/materialize-structure.ts`) is invoked once per session at insert time using a `templateMap` hoisted out of the per-week loop. Post-processing fixers do **not** re-materialize — they swap `template_id` upstream of the insert site. Unknown `template_id` values are accumulated and emit a single per-plan summary log instead of per-session warnings. Sessions with missing `template_id` log defensively and proceed with `structure: null` (renderer falls back to template lookup). `VALID_SPORTS` validation rejects `strength` upstream so no strength sessions are ever generated. Deployed to production at version 35.

**DRO-298 (Workout Library Phase 2):** Added 30 high-fidelity templates to `ai/context/workout-library.json` (bike×10, run×10, swim×8, race×1 `RACE_OLYMPIC`, strength×1 `STRENGTH_NOTES_ONLY` placeholder). Extended `materialize-structure.ts` with new target vocabulary: `power_watts` (single + range), `pace_per_km` (absolute run pace string), `pace_per_100m` (absolute swim pace string), range forms for `ftp_pct_min/max` and `hr_pct_max_min/max`. **NOTE:** `buildSimplifiedLibrary()` in `generate-plan/index.ts` currently iterates only `["swim", "bike", "run"]` — it does NOT surface the new `power_watts`, `pace_per_km`, `pace_per_100m`, or `hr_pct_max` range fields to the LLM in Step 3. The new vocabulary is only used by the materializer at plan-write time (DRO-298 scope). Surfacing these new fields to Step 3 for LLM-aware template selection is a TODO for a future ticket.

---

## Post-Processing Fixers

Applied sequentially in Edge Function after Step 3 (no LLM). Eval source of truth: `ai/eval/run-step3-blocks.js`.

| # | Fixer | Purpose |
|---|-------|---------|
| 1 | `fixTypes()` | Extract type from template_id (source of truth) |
| 2 | `fixBrickPairs()` | Ensure bike+run pairs both marked `is_brick` |
| 3 | `fixConsecutiveRepeats()` | Swap templates if same used 2 consecutive weeks |
| 4 | `fixDurationCaps()` | Enforce per-day duration limits (4-step cascade) |
| 5 | `fixRestDays()` | Move sessions off rest days to eligible days |
| 6 | `fixMissingBricks()` | Create bike+run brick pairs (Build/Peak weekly, Base biweekly). Clears brick day, moves other sessions to empty eligible days |
| 7 | `fixBrickRunDuration()` | Enforce RUN_Easy_01 (30min) on all brick runs. Catches informal bricks (bike+run same day without `is_brick`) |
| 8 | `fixBrickOrder()` | Ensure bike before run in sessions array for brick pairs |
| 9 | `fixSameDayHardConflicts()` | Max 1 bike + 1 run per day (brick counts). No dual hard bike/run same day. Uses `tryRelocateSession` (3 strategies: direct move, cross-sport swap, downsize+move) |
| 10 | `fixIntensitySpread()` | Spread consecutive hard (Tempo/Intervals) bike/run days. Tries both days of pair, post-swap adjacency simulation, same-sport conflict checks. Swim excluded |
| 11 | `fixSportClustering()` | Swap same-sport sessions off consecutive single-session days. Skipped for ≥8h/week athletes. Cross-sport fallback with neighbor check |
| 12 | `fixVolumeGaps()` | Fill empty available days with Easy sessions based on macro plan sport targets. Skips Recovery/Taper. Prefers non-clustering sports |
| 13 | `fixDurationCaps()` *(re-run)* | Safety pass — catches cap violations from all prior changes |
| 14 | `fixSameDayHardConflicts()` *(re-run)* | Catches same-day conflicts introduced by volume gaps or cap fixes |
| 15 | `fixBrickOrder()` *(re-run)* | Final brick ordering pass |

**Total unique fixers:** 12 (3 run twice = 15 passes). Validated via batch eval: 5/5 runs, 0 violations across all 8 metrics.

---

## File Locations

### Prompts (canonical source: `ai/prompts/`)
| File | Purpose |
|------|---------|
| `ai/prompts/step1-macro-plan.txt` | Step 1 prompt (canonical) |
| `ai/prompts/step2-md-to-json.txt` | Step 2 prompt (canonical) |
| `ai/prompts/step3-workout-block.txt` | Step 3 prompt (canonical) |

Production `.ts` files in `supabase/functions/generate-plan/prompts/` are **auto-generated** — run `scripts/sync-prompts.sh` to regenerate from canonical `.txt` files, then deploy.

| File | Purpose |
|------|---------|
| `supabase/functions/generate-plan/context/training-philosophy-content.ts` | Training philosophy context |

### Edge Function
| File | Purpose |
|------|---------|
| `supabase/functions/generate-plan/index.ts` | Main pipeline orchestrator + all fixers |

### Eval Framework
| File | Purpose |
|------|---------|
| `ai/eval/vars/athletes.yaml` | Test athlete profiles (Emmanuel Half-Ironman + others) |
| `ai/eval/vars/step2-inputs.yaml` | Pre-computed Step 1 outputs for Step 2 testing |
| `ai/eval/vars/step3-inputs.yaml` | Pre-computed Step 2 outputs for Step 3 testing |
| `ai/eval/assertions/validate-macro-plan.js` | Step 1 output validation |
| `ai/eval/assertions/validate-macro-plan-md.js` | Step 1 markdown format validation |
| `ai/eval/assertions/validate-workout-selection.js` | Step 3 output validation |
| `ai/eval/check-step3-violations.js` | 8-metric violation checker (duration, sport, rest, brick, cluster, same-day, intensity, brick-order) |
| `ai/eval/run-step3-blocks.js` | Step 3 block orchestrator + all 12 fixers (source of truth) |
| `ai/eval/batch-eval.sh` | Batch runner: N parallel eval runs → plans + violations + aggregated scores |
| `ai/eval/poc-generate-e2e.js` | DRO-311 PoC: synthetic user → JWT → invoke deployed `generate-plan` → poll → read → run checker → cleanup. Reference for the full plan-quality eval harness (targets real edge functions, not the shadow `run-step3-blocks.js`). |
| `ai/eval/db-plan-to-eval-shape.js` | Adapter: DB plan (`training_plans` + nested `plan_weeks`/`plan_sessions`) → the `{weeks: [...]}` shape the checker/rubric consume. |
| `ai/eval/vars/availability-scenarios.yaml` | DRO-314: availability-focused scenario set (12 entries, Olympic + Ironman 70.3 × weekly-hours/day-pattern/duration-cap/sport-eligibility shapes). Each entry is a full `public.users` profile (real types, not promptfoo string vars) ready for `createTestUser(profile)` — rest days seeded as `0`, translated to `NULL` by the Step-1 eval-supabase client. Primary scenario set for the real-edge-function harness (distinct from `athletes.yaml`, which feeds the promptfoo markdown-pipeline evals). |
| `ai/eval/lib/yupa-rubric.js` | DRO-314: `reviewPlan(evalPlan, scenarioVars)` — one OpenAI (`gpt-4.1`) call per plan, scored against a rubric derived from `.claude/agents/triathlon-coach.md` (80/20 distribution, ramp rate, recovery cadence, brick placement, taper). Returns `{ verdict: 'SHIP'|'SHIP WITH CHANGES'|'DO NOT SHIP', issues: [{severity, note}], summary }`. Advisory only — never gates a scenario, only throws on an OpenAI API failure. |

### Workout Library
- **Canonical file:** `ai/context/workout-library.json`
- **iOS:** Symlink at `Dromos/Dromos/Resources/workout-library.json` → canonical file. Loaded by `WorkoutLibraryService`.
- **Edge Function:** Fetched at runtime from Supabase Storage (`static-assets/workout-library.json`). Upload via `scripts/upload-static-assets.sh`.
- **Race templates (`race[]`):** 3 curated templates — `RACE_Race_01` (Ironman 70.3, 1.9/90/21.1), `RACE_Race_02` (Olympic race sim, 1.5/40/10 with FTP/VMA targets), and `RACE_OLYMPIC` (full Olympic triathlon with distance-only work segments: swim 1500m, bike 40km, run 10km + T1/T2 transitions — added DRO-298). The previous full-IM marathon stub was removed in DRO-288.
- **Easy intensity varies by duration:** Easy templates are NOT flat — shorter sessions use higher % (run: 65% MAS, bike: 70% FTP) while long sessions use lower % (run: 62% MAS, bike: 65% FTP). Brick runs (`RUN_Easy_01`) use the lowest (60% MAS).

---

## Models Used

| Step | Model | Max Tokens | Temperature | Why |
|------|-------|-----------|-------------|-----|
| Step 1 | gpt-4.1 | 16,384 | 0.2 | Complex planning requires strong reasoning |
| Step 2 | gpt-4o-mini | 16,384 | 0 | Deterministic JSON conversion (cheap) |
| Step 3 | gpt-4.1 | 4,096 | 0.2 | Template matching needs reasoning per block |

---

## Coach Chat Pipeline (V0 — DRO-256)

**Feature:** DRO-256 Coach Chat V0 — plan-aware advisory (supersedes the dormant DRO-149 constraint-detection chat)
**Edge Function:** `supabase/functions/chat-adjust/index.ts` (re-used; behavior fully replaced)

Plan-aware conversational coach. **Advisory only** in V0 — answers questions about today's session, pacing, post-session feedback, and plan rationale, but does NOT modify the plan. Streams responses end-to-end via Server-Sent Events. Gated to `ebreard4@gmail.com` only via a server-side email allowlist for V0 dogfood.

### Prompt
| File | Purpose |
|------|---------|
| `ai/prompts/coach-chat-v0.txt` | Validated prompt with two sections separated by `--- DYNAMIC ---`. STATIC (system message): persona (efficient/sharp/warm; he-pronoun; no name), 4 in-scope topics + length caps, 4 V1 advisory punts + Calendar pointer, no-fabrication rule. DYNAMIC (user message, rendered per request): athlete profile, plan summary, today / yesterday / tomorrow sessions, week map, last 3 completed sessions with lap data. |
| `supabase/functions/chat-adjust/prompts/coach-chat-v0-prompt.ts` | Auto-generated. Run `scripts/sync-prompts.sh` to regenerate. |
| `scripts/test-coach-chat.mjs` | Validation harness — fetches user profile + plan, renders prompt, calls gpt-4.1 directly. Use for prompt iteration without touching DB. |

The legacy `ai/prompts/adjust-step1-v0.txt` is kept on disk as historical reference but no longer imported.

### Flow
1. CORS preflight, POST guard, env check
2. JWT validated via `auth.getUser()`
3. **Email allowlist gate**: reject 403 if `user.email !== "ebreard4@gmail.com"`
4. Parse `{ message: string }` body (max 1000 chars)
5. **Insert user message** into `chat_messages` BEFORE the OpenAI call (so user input is durable on AI failure)
6. Parallel fetch: last 10 chat messages (chronological), user profile, active plan + weeks (`.maybeSingle()` so `generating` plans degrade gracefully)
7. Resolve current/yesterday/tomorrow weeks using `Intl.DateTimeFormat` in `Europe/Paris` (V0 single-user TZ); fetch `plan_sessions` for current week; fetch `strava_activities` + `strava_activity_laps` for matched activities
8. Yesterday loader: separate `plan_weeks!inner` query covers the prior-week boundary case; activity + laps fetched for matched yesterday session if present
9. Recent-completed loader: cross-plan query ordered by `(start_date DESC, day DESC)`, slice top 3
10. Render DYNAMIC by replacing `{{athlete_profile}}`, `{{plan_summary}}`, `{{today_session}}`, `{{yesterday_session}}`, `{{week_map}}`, `{{recent_completed}}`, `{{tomorrow_session}}`
11. Build OpenAI message array: `[system(STATIC), user(DYNAMIC), ...history(ASC), user(message)]` — this prefix ordering maximizes OpenAI's prompt cache hit rate within a multi-turn conversation
12. Call OpenAI `gpt-4.1` with `stream: true` + `stream_options: { include_usage: true }` via raw `fetch` (no SDK)
13. Stream upstream body through a `TransformStream<Uint8Array, Uint8Array>`: forwards bytes verbatim to client + parses each `data:` line in parallel to accumulate `delta.content` server-side
14. On `[DONE]`: insert complete assistant message with `status=NULL`, `constraint_summary=NULL`; log structured token usage `{ event: "chat-adjust-tokens", prompt, completion, cached }`
15. On upstream abort mid-stream: `pipeThrough` rejects, `flush` does NOT run, no partial assistant row persisted
16. Return `text/event-stream; charset=utf-8` with CORS headers

### Model
| Model | Max Tokens | Temperature | Stream | Why |
|-------|-----------|-------------|--------|-----|
| gpt-4.1 | 400 | 0.3 | true | Plan-aware coaching with mild creativity for tone; capped low to keep cost bounded ($~0.0026/message at 60% cache hit) |

### Status & constraint columns
The `status` and `constraint_summary` columns on `chat_messages` are kept (NULL for V0) for forward-compat with V1 plan-modification work. V0 responses are pure conversational text.

### Caching
The static system message is ~1.2k tokens (above OpenAI's 1024-token cache threshold). System+DYNAMIC prefix is reused turn-to-turn within a conversation, hitting the prefix cache after the first turn.

### iOS client
`Dromos/Dromos/Core/Services/ChatService.swift` — uses `URLSession.bytes(for:)` to consume SSE; manual JWT via `client.auth.session.accessToken`. `@Published streamingMessage: String?` drives the partial-bubble UI in `ChatView`. Empty-stream guard surfaces an error rather than promoting an empty assistant bubble.

### Validation harness
`scripts/test-coach-chat.mjs` runs ~21 representative cases (4 in-scope topics × 3 phrasings, 4 punts, 2 off-topic, 2 edge cases, yesterday-hallucination regression). Used during Phase 1 (PoC gate) and any future prompt iteration. ~$0.05 per full run.

---

## Session Feedback Pipeline

**Feature:** DRO-158
**Edge Function:** `supabase/functions/session-feedback/index.ts`

### Session Feedback Prompt

**Prompt:** `ai/prompts/session-feedback-v0.txt`
**Production:** `supabase/functions/session-feedback/prompts/session-feedback-v0-prompt.ts`
**Model:** gpt-4.1 | 150 tokens | temp 0.7

**Template variables:** `{{phase}}`, `{{week_number}}`, `{{is_recovery}}`, `{{race_objective}}`, `{{race_date}}`, `{{vma}}`, `{{ftp}}`, `{{css}}`, `{{sport}}`, `{{type}}`, `{{planned_duration}}`, `{{planned_workout}}`, `{{moving_time_min}}`, `{{distance_km}}`, `{{avg_hr}}`, `{{formatted_pace}}`, `{{avg_watts}}`, `{{laps}}`, `{{week_sessions}}`

**`{{laps}}`:** Formatted per-lap summary from `strava_activity_laps`. Each lap shows duration, avg HR, sport-specific metric (pace/power), and distance. Falls back to "No lap data available." when empty. Fed to the LLM for interval-level coaching feedback.
