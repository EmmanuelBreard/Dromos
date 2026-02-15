# DRO-85: Sport Clustering & Brick Sessions Fix

**Overall Progress:** `0%`

## TLDR
Generated plans cluster same-sport sessions on consecutive days (Run-Run, Bike-Bike) and never include brick sessions (bike→run). Fix the Step 3 prompt + add a post-processing fixer for sport alternation, and make brick sessions standard for all athletes across all phases.

## Critical Decisions
- **Sport alternation threshold:** ≤75min = single-session day (enforce alternation); ≥90min = doubles-capable (allow same sport consecutive). The gap prevents edge-case thrashing.
- **Bricks for all athletes:** Not gated on limiters anymore. Base (every 2 weeks if capacity), Build/Peak (weekly mandatory), Taper/Recovery (none).
- **Limiters fallback:** `userProfile.limiters || "none"` — no DB migration needed now; future onboarding captures limiters automatically.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `ai/prompts/step3-workout-block.txt` | MODIFY | Add sport alternation rule (new rule 5, renumber 5-7 → 6-8) |
| `ai/prompts/step1-macro-plan.txt` | MODIFY | Replace limiter-gated brick rule (lines 61-64) with universal phase-based brick rules |
| `supabase/functions/generate-plan/index.ts` | MODIFY | Add `fixSportClustering()` function (after line 728), call it at line 981, update limiters at lines 216+945 |
| `ai/eval/check-step3-violations.js` | MODIFY | Add brick presence + sport clustering violation checks |
| `supabase/functions/generate-plan/prompts/step1-macro-plan-prompt.ts` | AUTO-REGEN | Via `scripts/sync-prompts.sh` |
| `supabase/functions/generate-plan/prompts/step3-workout-block-prompt.ts` | AUTO-REGEN | Via `scripts/sync-prompts.sh` |

## Context Doc Updates
- `ai-pipeline.md` — Add `fixSportClustering` to fixer table, update Step 1 brick rules description, note limiters placeholder

## Tasks

- [ ] 🟥 **Step 1: Add sport alternation rule to Step 3 prompt**
  - [ ] 🟥 In `ai/prompts/step3-workout-block.txt`, insert new rule 5 after rule 4 "Session spread" (line 28):
    ```
    5. **Sport alternation** — When a day has capacity for only one session
       (available minutes ≤ 75min), avoid scheduling the same sport on
       consecutive training days. Spread same-sport sessions as far apart as
       possible (e.g., run Tuesday + run Saturday, NOT run Tuesday + run
       Wednesday). This rule does NOT apply to days with ≥ 90min available
       where doubles are feasible.
    ```
  - [ ] 🟥 Renumber existing rules 5→6, 6→7, 7→8
  - [ ] 🟥 Update the Final Validation section (rule references) if it mentions rule numbers

- [ ] 🟥 **Step 2: Add `fixSportClustering()` post-processing fixer**
  - [ ] 🟥 In `supabase/functions/generate-plan/index.ts`, add function before `Deno.serve()` (after `fixRestDays` ending at line 728):
    - Uses existing `ALL_DAYS`, `normDay()`, `dayCaps`, `sportEligibility`
    - For each week: group sessions by day → identify single-session days (cap ≤ 75min AND 1 session) → check consecutive pairs for same sport → swap with non-adjacent same-sport/type session respecting eligibility + caps
    - **Skip `is_brick` sessions** — brick pairs must stay together
    - Return fix count (matches existing fixer pattern)
  - [ ] 🟥 Add call after `fixRestDays` at line 981:
    ```typescript
    fixSportClustering(allBlockWeeks, dayCaps, sportEligibility);
    ```

- [ ] 🟥 **Step 3: Make brick sessions standard for all athletes**
  - [ ] 🟥 In `ai/prompts/step1-macro-plan.txt`, replace lines 61-64 (limiter-gated brick rule under "### Limiter strategy") with:
    ```
    ### Brick Sessions (CRITICAL — applies to ALL athletes)
    Brick sessions (bike immediately followed by run) are essential triathlon training:
    - **Base**: 1x every 2 weeks IF a weekend day has ≥ 90min. Short easy run (15-20min).
    - **Build**: 1x/week MINIMUM. Tempo run (20-30min) off the bike. Prefer weekends.
    - **Peak**: 1x/week MINIMUM. Race-pace run (20-30min) off race-effort bike.
    - **Taper/Recovery**: No bricks.
    Mark ALL brick sessions in Notes as "Brick: bike→run".
    If the athlete's limiter involves transitions, increase to 2x/week in Build/Peak.
    ```
  - [ ] 🟥 Keep the remaining limiter strategy bullets (sport-hour allocation) intact

- [ ] 🟥 **Step 4: Remove hardcoded limiters**
  - [ ] 🟥 In `index.ts` line 216: `"none"` → `user.limiters || "none"` (variable is `user` in `buildStep1Prompt()`)
  - [ ] 🟥 In `index.ts` line 945: `"none"` → `userProfile.limiters || "none"` (variable is `userProfile` in main handler)

- [ ] 🟥 **Step 5: Sync production prompts**
  - [ ] 🟥 Run `scripts/sync-prompts.sh`
  - [ ] 🟥 Verify `step1-macro-plan-prompt.ts` and `step3-workout-block-prompt.ts` regenerated

- [ ] 🟥 **Step 6: Add eval checks**
  - [ ] 🟥 In `ai/eval/check-step3-violations.js`, inside the per-week loop (after line 89), add:
    - **Brick presence check:** For Build/Peak weeks, flag if zero sessions have `is_brick === true`
    - **Sport clustering check:** Identify consecutive single-session days (cap ≤ 75min, 1 session) with same sport, log as warning
  - [ ] 🟥 Update summary line (line 91) to include new violation counts

- [ ] 🟥 **Step 7: Update context docs**
  - [ ] 🟥 Update `.claude/context/ai-pipeline.md` fixer table with `fixSportClustering`
  - [ ] 🟥 Update Step 1 description to reflect universal brick rules

- [ ] 🟥 **Step 8: Verification**
  - [ ] 🟥 Run `scripts/sync-prompts.sh` — confirm .ts files regenerated
  - [ ] 🟥 Run eval: `cd ai/eval && node check-step3-violations.js` — expect 0 new violations
  - [ ] 🟥 Deploy edge function and generate plan for test athlete — visually confirm sport alternation + bricks in Build/Peak
