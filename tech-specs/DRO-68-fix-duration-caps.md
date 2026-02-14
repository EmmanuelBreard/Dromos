# DRO-68: Add fixDurationCaps() Post-Processor

**Overall Progress:** `100%`

## TLDR
Add a deterministic `fixDurationCaps()` post-processor to Step 3 that swaps overlong templates when the total session duration on a day exceeds the athlete's available minutes. Also upgrade `fixConsecutiveRepeats` to be duration-aware, make `fixRestDays` cap-aware, and port `fixRestDays` to production (currently missing).

## Critical Decisions
- **Cap-aware `fixRestDays`** — instead of running `fixDurationCaps` twice (before and after `fixRestDays`), we make `fixRestDays` check remaining capacity before placing sessions. Single pass, no chain reactions.
- **20% duration margin** — when swapping templates, accept any template where `duration_minutes <= remaining_cap * 1.2`. Falls back to exact fit if nothing matches within margin.
- **Duration-aware `fixConsecutiveRepeats`** — prefer same-duration alternatives when swapping for variety, avoiding unnecessary cap violations downstream.
- **Session priority system** — `Intervals(3) > Tempo(2) > Easy(1)`, `+0.5` for `is_brick`. When a session can't fit anywhere, evict the lowest-priority session in the week, never drop a key session if Easy sessions exist.
- **Structured constraint parser** — build `parseConstraints()` returning `{dayCaps, sportEligibility}` from athlete profile. Reuse in `check-step3-violations.js` to replace hardcoded maps.
- **Bundle `fixRestDays` production port** — it's missing from `index.ts:664-666`, straight copy from eval.

## Pipeline Order (after changes)
```
fixTypes → fixBrickPairs → fixConsecutiveRepeats (duration-aware) → fixDurationCaps → fixRestDays (cap-aware)
```

## Files to Touch
| File | Changes |
|------|---------|
| `ai/eval/run-step3-blocks.js` | Add `parseConstraints()`, `sessionPriority()`, `fixDurationCaps()`. Update `fixConsecutiveRepeats` + `fixRestDays`. Wire into pipeline. |
| `supabase/functions/generate-plan/index.ts` | Mirror all changes. Port `fixRestDays` (currently missing). |
| `ai/eval/check-step3-violations.js` | Replace hardcoded `dayCaps`/`sportEligibility` with dynamic parsing from `athletes.yaml`. |

## Tasks

- [x] :white_check_mark: **Step 1: Add `parseConstraints()` helper**
  - [x] :white_check_mark: In `run-step3-blocks.js`: build structured `{dayCaps: {Monday: 60, ...}, sportEligibility: {Monday: ['swim','run'], ...}}` from athlete profile (reuse existing `buildConstraintString` inputs)
  - [x] :white_check_mark: In `index.ts`: mirror the same helper from `userProfile` fields
  - [x] :white_check_mark: In `check-step3-violations.js`: replace hardcoded maps with dynamic parsing from `athletes.yaml`

- [x] :white_check_mark: **Step 2: Add `sessionPriority()` helper**
  - [x] :white_check_mark: Implement priority function: `Intervals→3, Tempo→2, Easy→1, +0.5 if is_brick`
  - [x] :white_check_mark: Add in both `run-step3-blocks.js` and `index.ts`

- [x] :white_check_mark: **Step 3: Upgrade `fixConsecutiveRepeats` to be duration-aware**
  - [x] :white_check_mark: In `run-step3-blocks.js:235-281`: when picking alternative, sort candidates by `|candidate.duration - original.duration|` ascending, pick closest instead of random
  - [x] :white_check_mark: Needs workout library duration lookup (build `templateDurationMap` from library: `{SWIM_Easy_01: 40, ...}`)
  - [x] :white_check_mark: Mirror in `index.ts:379-427`

- [x] :white_check_mark: **Step 4: Implement `fixDurationCaps()`**
  - [x] :white_check_mark: For each week, for each day: sum session durations, compare to `dayCaps[day]`
  - [x] :white_check_mark: If over cap: pick longest session on day, find shorter template (same sport/type, `duration <= remaining_cap * 1.2`), prefer closest-duration match
  - [x] :white_check_mark: If no template fits: move session to nearest eligible day with remaining capacity (check sport eligibility + cap)
  - [x] :white_check_mark: If no eligible day fits: use priority system — scan week for lowest-priority session, evict it if current session outranks
  - [x] :white_check_mark: Last resort: drop lowest-priority session, log warning
  - [x] :white_check_mark: Implement in `run-step3-blocks.js`, mirror in `index.ts`

- [x] :white_check_mark: **Step 5: Upgrade `fixRestDays` to be cap-aware + port to production**
  - [x] :white_check_mark: In `run-step3-blocks.js:285-319`: when choosing target day, filter by `session.duration_minutes <= dayCaps[day] - usedMinutes[day]` and sport eligibility
  - [x] :white_check_mark: Use priority system for eviction when no day has capacity
  - [x] :white_check_mark: Port full `fixRestDays` implementation to `index.ts` (currently missing)

- [x] :white_check_mark: **Step 6: Wire pipeline + test**
  - [x] :white_check_mark: Update pipeline order in `run-step3-blocks.js`: `fixTypes → fixBrickPairs → fixConsecutiveRepeats → fixDurationCaps → fixRestDays`
  - [x] :white_check_mark: Update pipeline in `index.ts` to match (add `fixDurationCaps`)
  - [x] :white_check_mark: Run `check-step3-violations.js` — **0 duration violations** across all 3 athletes (down from 42)
  - [x] :white_check_mark: No regressions: 0 sport eligibility violations, 0 rest day violations
