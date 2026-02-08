# DRO-60: Rename step1b → step2 & Delete Dead Prompt

**Overall Progress:** `100%`

## TLDR
Delete the unused `step2-workout-selection.txt` prompt and rename all `step1b` files/references to `step2` so file naming aligns with the eval pipeline numbering: step1 = macro plan, step2 = md-to-json, step3 = workout blocks.

## Critical Decisions
- **No logic changes** — purely file renames + reference updates. Zero functional impact.
- **Eval pipeline already uses step2 naming** — only the prompt source files still say `step1b`.

## Tasks:

- [x] 🟩 **Step 1: Delete dead file**
  - [x] 🟩 Delete `ai/prompts/step2-workout-selection.txt`

- [x] 🟩 **Step 2: Rename prompt files**
  - [x] 🟩 `ai/prompts/step1b-md-to-json.txt` → `ai/prompts/step2-md-to-json.txt`
  - [x] 🟩 `supabase/functions/generate-plan/prompts/step1b-md-to-json.txt` → `step2-md-to-json.txt`
  - [x] 🟩 `supabase/functions/generate-plan/prompts/step1b-md-to-json-prompt.ts` → `step2-md-to-json-prompt.ts`

- [x] 🟩 **Step 3: Update code references**
  - [x] 🟩 `supabase/functions/generate-plan/index.ts:7` — import path + variable renamed `STEP1B_MD_TO_JSON_PROMPT` → `STEP2_MD_TO_JSON_PROMPT`
  - [x] 🟩 `supabase/functions/generate-plan/index.ts:228` — variable reference updated

- [x] 🟩 **Step 4: Update eval config**
  - [x] 🟩 `ai/eval/promptfooconfig.step2.yaml:12` — prompt path updated

- [x] 🟩 **Step 5: Update doc references**
  - [x] 🟩 `tech-specs/DRO-48-constraints.md:27-28` — file path references updated
  - [x] 🟩 `tech-specs/DRO-41-edge-function-generate-plan.md:58,83` — file path references updated
  - [x] 🟩 `ai/curtis-prompts/DRO-48-phase1.md:84,104,126` — file path references updated

- [x] 🟩 **Step 6: Verify**
  - [x] 🟩 Grep for any remaining `step1b` references — clean (only this tech spec)
  - [x] 🟩 Grep for any remaining `step2-workout-selection` references — clean (only this tech spec)
  - [x] 🟩 No broken imports confirmed
