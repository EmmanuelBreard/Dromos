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

**DRO-215 (Phase 1):** `workout-library.json` strength templates removed. `buildSimplifiedLibrary()` in `generate-plan/index.ts` already iterates only `["swim", "bike", "run"]` so no prompt change was needed. Run intensity keys renamed `mas_pct` → `vma_pct` throughout the JSON. The shared materializer (`supabase/functions/_shared/materialize-structure.ts`) handles legacy `mas_pct` keys at materialisation time for edge cases.

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

### Workout Library
- **Canonical file:** `ai/context/workout-library.json`
- **iOS:** Symlink at `Dromos/Dromos/Resources/workout-library.json` → canonical file. Loaded by `WorkoutLibraryService`.
- **Edge Function:** Fetched at runtime from Supabase Storage (`static-assets/workout-library.json`). Upload via `scripts/upload-static-assets.sh`.
- **Easy intensity varies by duration:** Easy templates are NOT flat — shorter sessions use higher % (run: 65% MAS, bike: 70% FTP) while long sessions use lower % (run: 62% MAS, bike: 65% FTP). Brick runs (`RUN_Easy_01`) use the lowest (60% MAS).

---

## Models Used

| Step | Model | Max Tokens | Temperature | Why |
|------|-------|-----------|-------------|-----|
| Step 1 | gpt-4.1 | 16,384 | 0.2 | Complex planning requires strong reasoning |
| Step 2 | gpt-4o-mini | 16,384 | 0 | Deterministic JSON conversion (cheap) |
| Step 3 | gpt-4.1 | 4,096 | 0.2 | Template matching needs reasoning per block |

---

## Chat Adjust Pipeline (V0)

**Feature:** DRO-149 Chat V0
**Edge Function:** `supabase/functions/chat-adjust/index.ts`

Single-step pipeline — no multi-step orchestration needed. The agent both converses and classifies in one turn.

### Prompt
| File | Purpose |
|------|---------|
| `ai/prompts/adjust-step1-v0.txt` | V0 fork of conversation prompt — advisory mode (no plan modification) |
| `supabase/functions/chat-adjust/prompts/adjust-step1-v0-prompt.ts` | Auto-generated TS module. Run `scripts/sync-prompts.sh` to regenerate. |

### Flow
1. Extract and validate JWT via `auth.getUser()`
2. Parse `{ message: string }` body (max 1000 chars)
3. Fetch in parallel: last 50 chat messages (chronological), user profile, active plan weeks
4. Render prompt by replacing `{{athlete_profile}}` and `{{phase_map}}` placeholders
5. Call OpenAI `gpt-4o` with history + new message (temperature 0, max_tokens 1024)
6. Parse response: extract outermost JSON block if present, else treat as `need_info`
7. Insert user message then assistant message via service_role
8. Return `{ response_text, status, constraint_summary? }`

### Model
| Step | Model | Max Tokens | Temperature | Why |
|------|-------|-----------|-------------|-----|
| Intake agent | gpt-4.1 | 1,024 | 0 | Deterministic classification; short response |

### Statuses
| Status | Meaning |
|--------|---------|
| `need_info` | Agent still gathering required fields; plain text reply |
| `ready` | All required fields collected; constraint summary present |
| `no_action` | Not a training disruption (chitchat, gratitude) |
| `escalate` | Disruption too severe to modify plan; recommend plan regeneration |

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
