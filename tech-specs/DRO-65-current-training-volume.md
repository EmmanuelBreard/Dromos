# DRO-65: Use Athlete's Current Training Volume as Plan Input

**Overall Progress:** `100%`

## TLDR

Capture the athlete's current weekly training volume during onboarding (slider, 0–25h in 0.5h steps) and inject it into the Step 1 macro plan prompt so week 1 starts near the athlete's actual baseline instead of an arbitrary point. This prevents plans that are too aggressive (injury risk) or too conservative (boring).

## Critical Decisions

- **Single number, not per-sport breakdown** — one `current_weekly_hours` field is sufficient for MVP. Per-sport can come later with device integrations (Garmin/Strava).
- **Added to Screen 3 (Performance Metrics)** — groups with existing athlete-capability data (VMA, CSS, FTP, experience).
- **Required field** — unlike FTP/VMA which are optional, current volume is critical for plan quality.
- **No cross-validation with available hours** — if current volume > availability ceiling, we trust the user. The LLM will reconcile.
- **No existing-user migration path** — no real users yet, not needed.

## Tasks

- [x] 🟩 **Step 1: Database — add `current_weekly_hours` column**
  - [x] 🟩 Create migration `009_add_current_weekly_hours.sql`
  - [x] 🟩 Add `current_weekly_hours DECIMAL(3,1)` to `users` table with CHECK constraint (0–25)
  - [x] 🟩 Apply migration to Supabase

- [x] 🟩 **Step 2: iOS — add slider to Onboarding Screen 3**
  - [x] 🟩 Add `currentWeeklyHours: Double` to `MetricsData` in `OnboardingData.swift`
  - [x] 🟩 Add slider UI to `OnboardingScreen3View.swift` — label: "In the last 4 weeks, how many hours per week did you train?", range 0–25, step 0.5
  - [x] 🟩 Make field required — Screen 3 "Next" button validation must include this field
  - [x] 🟩 Update `ProfileService.saveOnboardingData()` to include `current_weekly_hours` in the upsert payload
  - [x] 🟩 Update `User.swift` model if it maps DB columns

- [x] 🟩 **Step 3: Edge Function — inject current volume into Step 1 prompt**
  - [x] 🟩 Read `current_weekly_hours` from user row in `index.ts`
  - [x] 🟩 Add `- Current training volume: {{current_weekly_hours}}h/week` to the Athlete Profile section in the Step 1 prompt template
  - [x] 🟩 Add progressive-overload-from-baseline rule to the Rules section: "Week 1 volume should start near the athlete's current training volume and build progressively toward the weekly ceiling"
  - [x] 🟩 Update the mirror file `ai/prompts/step1-macro-plan.txt` to match

## Files Affected

| File | Change |
|------|--------|
| `supabase/migrations/009_add_current_weekly_hours.sql` | New migration |
| `Dromos/Dromos/Core/Models/OnboardingData.swift` | Add field to `MetricsData` |
| `Dromos/Dromos/Core/Models/User.swift` | Add property (if mapped) |
| `Dromos/Dromos/Features/Onboarding/OnboardingScreen3View.swift` | Add slider + validation |
| `Dromos/Dromos/Core/Services/ProfileService.swift` | Include in upsert |
| `supabase/functions/generate-plan/index.ts` | Read field, pass to prompt |
| `supabase/functions/generate-plan/prompts/step1-macro-plan-prompt.ts` | Add to Athlete Profile + Rules |
| `ai/prompts/step1-macro-plan.txt` | Mirror prompt changes |
