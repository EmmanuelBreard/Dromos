# DRO-68: Add fixDurationCaps() Post-Processor

**Overall Progress:** `15%`

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

- [ ] :red_square: **Step 3: Upgrade `fixConsecutiveRepeats` to be duration-aware**
  - [ ] :red_square: In `run-step3-blocks.js:235-281`: when picking alternative, sort candidates by `|candidate.duration - original.duration|` ascending, pick closest instead of random
  - [x] :white_check_mark: Needs workout library duration lookup (build `templateDurationMap` from library: `{SWIM_Easy_01: 40, ...}`)
  - [ ] :red_square: Mirror in `index.ts:379-427`

- [ ] :red_square: **Step 4: Implement `fixDurationCaps()`**
  - [ ] :red_square: For each week, for each day: sum session durations, compare to `dayCaps[day]`
  - [ ] :red_square: If over cap: pick longest session on day, find shorter template (same sport/type, `duration <= remaining_cap * 1.2`), prefer closest-duration match
  - [ ] :red_square: If no template fits: move session to nearest eligible day with remaining capacity (check sport eligibility + cap)
  - [ ] :red_square: If no eligible day fits: use priority system — scan week for lowest-priority session, evict it if current session outranks
  - [ ] :red_square: Last resort: drop lowest-priority session, log warning
  - [ ] :red_square: Implement in `run-step3-blocks.js`, mirror in `index.ts`

- [ ] :red_square: **Step 5: Upgrade `fixRestDays` to be cap-aware + port to production**
  - [ ] :red_square: In `run-step3-blocks.js:285-319`: when choosing target day, filter by `session.duration_minutes <= dayCaps[day] - usedMinutes[day]` and sport eligibility
  - [ ] :red_square: Use priority system for eviction when no day has capacity
  - [ ] :red_square: Port full `fixRestDays` implementation to `index.ts` (currently missing)

- [ ] :red_square: **Step 6: Wire pipeline + test**
  - [ ] :red_square: Update pipeline order in `run-step3-blocks.js:380-390`: `fixTypes → fixBrickPairs → fixConsecutiveRepeats → fixDurationCaps → fixRestDays`
  - [ ] :red_square: Update pipeline in `index.ts:664-666` to match (add `fixDurationCaps` + `fixRestDays`)
  - [ ] :red_square: Run `node ai/eval/run-step3-blocks.js` for all 3 athletes
  - [ ] :red_square: Run `node ai/eval/check-step3-violations.js` and verify 0 duration violations
  - [ ] :red_square: Compare pre/post violation counts in console output
