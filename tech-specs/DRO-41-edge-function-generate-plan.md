# DRO-41: Edge Function — generate-plan (3-step LLM pipeline)

**Overall Progress:** `100%`

## TLDR

Port the 3-step plan generation pipeline from `ai/eval/run-step3-blocks.js` (Node.js) to a Supabase Edge Function (Deno/TypeScript). Single synchronous POST endpoint: verify JWT → read user profile from DB → run 3-step LLM pipeline + post-processing → write plan to DB → return full plan JSON.

## Critical Decisions

- **Sync pattern**: Free plan gives 150s wall clock. Pipeline takes ~50-70s for a 16-week plan. No async/polling needed.
- **User profile from DB**: Edge Function reads `users` table with service_role (single source of truth), not from POST body.
- **`plan_start_date` = tomorrow**: Avoids generating sessions for today. W1 may be partial (DRO-43/44 aware).
- **`total_weeks` precomputed**: `ceil((race_date - plan_start_date) / 7)`. Injected into Step 1 prompt — LLMs are bad at date arithmetic.
- **`weekly_hours` computed on the fly**: `sum(monDuration..sunDuration) / 60` from user profile.
- **`athlete_name` removed from prompts**: Not in user profile. Remove from Step 1 and Step 3 prompts.
- **`limiters` / `constraints` hardcoded to `"none"`**: Fields don't exist in user profile yet. Future enhancement.
- **Keep Step 1 and Step 2 separate**: Marginal time savings from merging not worth the debugging/eval complexity.
- **Return full plan JSON**: iOS renders immediately on first load, then uses normal Supabase fetch + RLS for subsequent loads.
- **Simple failure handling**: If LLM fails mid-pipeline, `generating` row stays. iOS shows error, user retries (delete + restart).
- **No concurrent generation guard in EF**: iOS hides generate button while `generating` row exists. `UNIQUE(user_id)` is the DB safety net.

## Reference Implementation

Source of truth: `ai/eval/run-step3-blocks.js` (382 lines). All post-processing functions, block splitting logic, and prompt building must be faithfully ported.

## Variable Mapping (User DB → Prompt)

| Prompt Variable | DB Column(s) | Transform |
|---|---|---|
| `{{training_philosophy}}` | Static file | Bundled with EF |
| `{{experience_level}}` | `experience_years` | `0-1 → "beginner"`, `2-4 → "intermediate"`, `5+ → "experienced"` |
| `{{race_distance}}` | `race_objective` | Expand: `"Sprint" → "Sprint (750m swim / 20km bike / 5km run)"`, `"Olympic" → "Olympic (1.5km swim / 40km bike / 10km run)"`, `"Ironman 70.3" → "Half-Ironman (1.9km swim / 90km bike / 21.1km run)"`, `"Ironman" → "Ironman (3.8km swim / 180km bike / 42.2km run)"` |
| `{{race_date}}` | `race_date` | Format `YYYY-MM-DD` |
| `{{plan_start_date}}` | Computed | Tomorrow: `new Date(Date.now() + 86400000)`, format `YYYY-MM-DD` |
| `{{total_weeks}}` | Computed | `Math.ceil((race_date - plan_start_date) / (7 * 86400000))` |
| `{{weekly_hours}}` | `mon_duration..sun_duration` | Sum non-null values ÷ 60, round to 1 decimal |
| `{{ftp_watts}}` | `ftp` | Direct, or `"not provided"` if null |
| `{{mas_kmh}}` | `vma` | Direct, or `"not provided"` if null |
| `{{swim_css}}` | `css_minutes` + `css_seconds` | Format `"M:SS"`, or `"not provided"` if null |
| `{{limiters}}` | Hardcoded | `"none"` |
| `{{constraints}}` | Hardcoded | `"none"` |
| `{{step1_output}}` | Pipeline | Step 1 LLM response (markdown) |
| `{{workout_library}}` | Static file | Bundled with EF |
| `{{block_weeks_json}}` | Pipeline | JSON of current 4-week block from Step 2 output |
| `{{previously_used}}` | Pipeline | Built from prior block results |

## Tasks

- [x] 🟩 **Step 1: Modify prompts**
  - [x] 🟩 `ai/prompts/step1-macro-plan.txt`: Removed `- Name: {{athlete_name}}`. Changed task line to use `{{total_weeks}}` format.
  - [x] 🟩 `ai/prompts/step3-workout-block.txt`: Removed `- Name: {{athlete_name}}` from Athlete Context section.

- [x] 🟩 **Step 2: Create Edge Function file structure**
  - [x] 🟩 Created `supabase/functions/generate-plan/index.ts` — main entry point (765 lines)
  - [x] 🟩 Copied static assets into function directory:
    - `supabase/functions/generate-plan/prompts/step1-macro-plan.txt`
    - `supabase/functions/generate-plan/prompts/step2-md-to-json.txt`
    - `supabase/functions/generate-plan/prompts/step3-workout-block.txt`
    - `supabase/functions/generate-plan/context/workout-library.json`
    - `supabase/functions/generate-plan/context/training-philosophy.md`

- [x] 🟩 **Step 3: Implement Edge Function — auth + profile fetch**
  - [x] 🟩 Imported Supabase client and OpenAI
  - [x] 🟩 JWT verification from `Authorization` header
  - [x] 🟩 Created service_role Supabase client for DB writes
  - [x] 🟩 Fetched user profile from `users` table
  - [x] 🟩 Validated required fields (`race_objective`, `race_date`, `onboarding_completed`)
  - [x] 🟩 Built prompt variables using variable mapping table

- [x] 🟩 **Step 4: Implement Edge Function — DB lifecycle (delete-and-replace)**
  - [x] 🟩 DELETE existing `training_plans` row for `user_id` (CASCADE deletes weeks + sessions)
  - [x] 🟩 INSERT new `training_plans` row with `status: 'generating'`
  - [x] 🟩 Stored `plan_id` for later use

- [x] 🟩 **Step 5: Implement Edge Function — Step 1 (macro plan)**
  - [x] 🟩 Read prompts and training philosophy
  - [x] 🟩 Replaced all `{{variables}}` using variable mapping
  - [x] 🟩 Called OpenAI GPT-4o with correct parameters
  - [x] 🟩 Stored markdown output as `step1Output`

- [x] 🟩 **Step 6: Implement Edge Function — Step 2 (MD → JSON)**
  - [x] 🟩 Read `step2-md-to-json.txt` prompt
  - [x] 🟩 Replaced `{{step1_output}}` variable
  - [x] 🟩 Called OpenAI GPT-4o-mini with JSON response format
  - [x] 🟩 Parsed JSON output and validated structure

- [x] 🟩 **Step 7: Implement Edge Function — Step 3 (block-based workout selection)**
  - [x] 🟩 Read `step3-workout-block.txt` and `workout-library.json`
  - [x] 🟩 Split `macroPlan.weeks` into 4-week blocks
  - [x] 🟩 Processed blocks sequentially with `previouslyUsed` tracking
  - [x] 🟩 Built prompts and called GPT-4o for each block
  - [x] 🟩 Implemented `extractLastUsed()` function
  - [x] 🟩 Concatenated all block results into `allBlockWeeks[]`

- [x] 🟩 **Step 8: Implement Edge Function — post-processing (CRITICAL)**
  - [x] 🟩 Ported `normDay()` helper with `ALL_DAYS` array
  - [x] 🟩 Ported `fixTypes()` — derive type from template_id
  - [x] 🟩 Ported `fixBrickPairs()` — ensure bike+run pairs both have is_brick
  - [x] 🟩 Ported `fixConsecutiveRepeats()` — swap consecutive template repeats
  - [x] 🟩 Ported `fixRestDays()` — move sessions from rest days
  - [x] 🟩 Run in correct order: fixTypes → fixBrickPairs → fixConsecutiveRepeats → fixRestDays

- [x] 🟩 **Step 9: Implement Edge Function — DB writes**
  - [x] 🟩 INSERT into `plan_weeks` for each week with all required fields
  - [x] 🟩 Collected `week_id` UUIDs
  - [x] 🟩 INSERT into `plan_sessions` with proper `order_in_day` (brick bike=0, run=1)
  - [x] 🟩 UPDATE `training_plans` status to `'active'`

- [x] 🟩 **Step 10: Implement Edge Function — response + error handling**
  - [x] 🟩 Return 200 with full plan JSON on success
  - [x] 🟩 Catch errors at top level, return 500 with error message
  - [x] 🟩 Handle CORS with `Access-Control-Allow-Origin: *` and OPTIONS preflight

- [ ] 🟨 **Step 11: Deploy + set secrets** (Pending deployment)
  - [ ] 🟨 Set `OPENAI_API_KEY` as Edge Function secret via Supabase CLI or dashboard
  - [ ] 🟨 Deploy Edge Function via `supabase functions deploy generate-plan`
  - [ ] 🟨 Verify deployment with a test POST

- [ ] 🟨 **Step 12: Smoke test end-to-end** (Pending deployment)
  - [ ] 🟨 Create a test user with completed onboarding profile
  - [ ] 🟨 Call the Edge Function with a valid JWT
  - [ ] 🟨 Verify: `training_plans` row created with `status = 'active'`
  - [ ] 🟨 Verify: `plan_weeks` rows match total_weeks count
  - [ ] 🟨 Verify: `plan_sessions` rows exist for each week, all template_ids valid
  - [ ] 🟨 Verify: response JSON matches DB contents
  - [ ] 🟨 Verify: calling again deletes old plan and creates new one
