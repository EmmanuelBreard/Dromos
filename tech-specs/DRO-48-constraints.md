# DRO-48: Inject Daily Availability & Duration Caps into Plan Generation

**Overall Progress:** `80%`

## TLDR
The `generate-plan` edge function hardcodes `{{constraints}}: "none"` so the LLM never sees per-day duration limits or sport-day availability. This causes sessions on wrong days, blown duration caps, and wasted weekly budget. Fix: build a constraint string from user profile data and inject it into the Step 3 prompt. Add session sizing hints and sport day availability to Step 1 so it generates appropriately-sized and correctly-distributed sessions. Rest days are derived post-Step 3 from actual sessions.

## Critical Decisions
- **Constraints in Step 3 only** — Step 1 handles high-level volume distribution; per-day scheduling rules belong in Step 3
- **Session sizing in Step 1** — Step 1 needs max session duration (weekday/weekend) so it doesn't generate sessions too long for any single day. This is volume context, not scheduling.
- **Sport day availability in Step 1** — Step 1 needs per-sport day counts (weekday/weekend) to size session counts appropriately and maximize volume utilization
- **Rest days removed from Step 1** — Step 1 no longer outputs `Rest: <day>, <day>`. Rest days are computed post-Step 3 (days with no sessions = rest days)
- **No post-processing for constraints** — rely on prompt engineering; `fixRestDays()` removed. Keep `fixTypes()`, `fixBrickPairs()`, `fixConsecutiveRepeats()`
- **Step 3 self-validation** — add mandatory pre-output validation checklist for sport eligibility, duration caps, and day utilization
- **Respect user availability as-is** — if user has adjacent rest days, we honor that. No non-adjacent rest day rule
- **REST days explicit in constraint string** — days with NULL duration rendered as `Monday: REST` so the LLM sees the full week shape
- **Limiters out of scope** — `{{limiters}}` stays `"none"` for now
- **No DB migration** — `plan_weeks.rest_days` column stays, just computed differently

## Files

| File | Role |
|------|------|
| `supabase/functions/generate-plan/index.ts` | Constraint builder, session cap computation, sport day counts, prompt injection, post-processing |
| `supabase/functions/generate-plan/prompts/step1-macro-plan-prompt.ts` | Remove constraints + rest days, add session sizing + sport day availability |
| `ai/prompts/step1-macro-plan.txt` | Mirror of above |
| `supabase/functions/generate-plan/prompts/step2-md-to-json-prompt.ts` | Remove `rest_days` from schema |
| `ai/prompts/step2-md-to-json.txt` | Mirror of above |
| `supabase/functions/generate-plan/prompts/step3-workout-block-prompt.ts` | Add constraint-aware scheduling rules + self-validation |
| `ai/prompts/step3-workout-block.txt` | Mirror of above |

## Tasks

- [x] 🟩 **Phase 1: Clean up Step 1 + Step 1b prompts** (DRO-54 — merged)
  - [x] 🟩 Remove `- Injuries / constraints: {{constraints}}` from Step 1 Athlete Profile
  - [x] 🟩 Remove `- At least 1 rest day per week` from Step 1 Intensity distribution
  - [x] 🟩 Remove `- Constraints: {{constraints}} — plan around these strictly` from Step 1 Budget section
  - [x] 🟩 Remove `Rest: <day>, <day>` from Step 1 output format
  - [x] 🟩 Remove `"rest_days": ["<day_name>"]` from Step 1b JSON schema
  - [x] 🟩 Remove `prompt.replace("{{constraints}}", "none")` from `buildStep1Prompt()` in `index.ts`
  - [x] 🟩 Sync `.ts` and `.txt` versions for both Step 1 and Step 1b

- [x] 🟩 **Phase 2: Constraint-aware scheduling (Step 3 + index.ts)** (DRO-55 — merged)
  - [x] 🟩 New `buildConstraintString(user)` in `index.ts`
  - [x] 🟩 Replace `## Athlete Context` constraints line with `## Daily Availability` section
  - [x] 🟩 Rewrite Step 3 "Day scheduling" section with 7 hard rules
  - [x] 🟩 Inject `buildConstraintString(user)` into Step 3 block loop
  - [x] 🟩 Delete `fixRestDays()` function and its call
  - [x] 🟩 Compute `rest_days` from actual sessions at DB write time
  - [x] 🟩 Sync `.ts` and `.txt` for Step 3

- [x] 🟩 **Phase 2b: Add session duration caps to Step 1** (DRO-58 — merged)
  - [x] 🟩 Add session sizing line to Step 1 Budget section
  - [x] 🟩 Compute `max_weekday_minutes` and `max_weekend_minutes` in `buildStep1Prompt()`
  - [x] 🟩 Sync `.ts` and `.txt` for Step 1

- [x] 🟨 **Phase 3: Eval & validation** (DRO-56 — partial)
  - [x] 🟩 Verify sessions only on sport-available days → ❌ swim on Thursday (not eligible)
  - [x] 🟩 Verify no duration cap violations → ❌ 90min sessions on 60min weekday days
  - [x] 🟩 Verify weekly volume approaches budget → ❌ ~10-11h of 13h, Monday unused
  - [x] 🟩 Improvement confirmed: no more 120min weekday sessions, volume up from ~8h

- [x] 🟩 **Phase 4: Sport availability in Step 1 + Step 3 self-validation** (DRO-59 — merged)
  - [x] 🟩 Add Sport Day Availability section to Step 1 prompt (per-sport weekday/weekend counts)
  - [x] 🟩 Compute sport day counts in `buildStep1Prompt()` in `index.ts`
  - [x] 🟩 Add Final Validation (MANDATORY) section to Step 3 prompt
  - [x] 🟩 Sync `.ts` and `.txt` for both Step 1 and Step 3

- [x] 🟨 **Phase 4b: Re-eval after Phase 4** (DRO-56 — rerun, partial)
  - [x] 🟩 Verify sport-day eligibility compliance → ❌ swim on Thursday still
  - [x] 🟩 Verify duration cap compliance → ❌ WORSE (90-150min single sessions on 60min days)
  - [x] 🟩 Verify volume → ✅ Improved to 10-12.5h (closer to 13h)
  - [x] 🟩 Root cause identified: 80K char workout library drowns out constraint rules (GPT-4o "lost in the middle")

- [ ] 🟥 **Phase 5: Simplify workout library + reorder Step 3 prompt** (DRO-62)
  - [ ] 🟥 New `buildSimplifiedLibrary()` function in `index.ts` — strips segments, keeps template_id/sport/type/duration
  - [ ] 🟥 New `computeSegmentDuration()` and `computeSegmentDistance()` helpers for recursive duration calc
  - [ ] 🟥 Inject simplified library instead of full 80K JSON into Step 3
  - [ ] 🟥 Reorder Step 3 prompt: Daily Availability first, library last (now tiny reference table)
  - [ ] 🟥 Sync `.ts` and `.txt` for Step 3

- [ ] 🟥 **Phase 6: Re-eval after Phase 5** (DRO-56 — rerun)
  - [ ] 🟥 Verify sport-day eligibility compliance
  - [ ] 🟥 Verify duration cap compliance
  - [ ] 🟥 Verify volume closer to 13h budget
  - [ ] 🟥 Decide if post-processing safety net is needed
