# DRO-24: Consolidate Split Time Fields into Single Integer Columns

**Overall Progress:** `100%`

## TLDR
Replace 4 split time columns (`css_minutes` + `css_seconds`, `time_objective_hours` + `time_objective_minutes`) with 2 consolidated integer columns (`css_seconds_per_100m`, `time_objective_minutes`). UI stays identical — conversion happens at the client/display layer. Edge Function updated in the same task.

## Critical Decisions
- **Migration number:** `007` (next sequential after existing `006_create_training_plan_tables.sql`)
- **Data state:** Dev-only, no production users. Migration can be aggressive (no careful data preservation).
- **Column naming:** Reuse `time_objective_minutes` name. Migration uses a temp column to avoid conflicts.
- **Edge Function:** Updated in same task to avoid broken deploy window.
- **`time_objective_minutes` rename strategy:** Add `time_objective_total_min` temp column -> copy computed data -> drop old `time_objective_hours` + `time_objective_minutes` -> rename temp to `time_objective_minutes`.

## Column Mapping

| Old Columns | New Column | Type | CHECK Constraint |
|---|---|---|---|
| `css_minutes` + `css_seconds` | `css_seconds_per_100m` | INT | BETWEEN 25 AND 300 |
| `time_objective_hours` + `time_objective_minutes` | `time_objective_minutes` | INT | > 0 |

## Files Affected

| # | File | Changes |
|---|---|---|
| 1 | `supabase/migrations/007_consolidate_time_fields.sql` | **NEW** — Migration |
| 2 | `Dromos/Core/Models/User.swift` | Replace 4 fields with 2, update computed props + `UserUpdate` |
| 3 | `Dromos/Core/Models/OnboardingData.swift` | Update `RaceGoalsData`, `MetricsData`, `CompleteOnboardingData` |
| 4 | `Dromos/Core/Services/ProfileService.swift` | Update `updateProfile()` params, `OnboardingUpdate`, `saveOnboardingData()` |
| 5 | `Dromos/Features/Onboarding/OnboardingScreen2View.swift` | Convert hours:min UI <-> total minutes |
| 6 | `Dromos/Features/Onboarding/OnboardingScreen3View.swift` | Convert min:sec UI <-> total seconds |
| 7 | `Dromos/Features/Profile/ProfileView.swift` | Edit state vars, load/save, formatters, validation |
| 8 | `supabase/functions/generate-plan/index.ts` | Update `formatCSS()` + `buildStep1Prompt()` |

## Tasks

- [x] 🟩 **Step 1: Database Migration**
  - [x] 🟩 Created `supabase/migrations/007_consolidate_time_fields.sql`
    - [x] 🟩 Added `css_seconds_per_100m INT` column
    - [x] 🟩 Added `time_objective_total_min INT` temp column
    - [x] 🟩 Computed values from old split columns
    - [x] 🟩 Dropped old columns: `css_minutes`, `css_seconds`, `time_objective_hours`, `time_objective_minutes`
    - [x] 🟩 Dropped old CHECK constraints: `check_css_seconds`, `check_css_total`
    - [x] 🟩 Renamed `time_objective_total_min` -> `time_objective_minutes`
    - [x] 🟩 Added new CHECK constraints: `css_seconds_per_100m BETWEEN 25 AND 300`, `time_objective_minutes > 0`
    - [x] 🟩 Included DOWN migration in comments
  - [ ] 🟨 Apply migration via Supabase MCP (pending deployment)

- [x] 🟩 **Step 2: Swift Models**
  - [x] 🟩 `User.swift`: Replaced `timeObjectiveHours`/`timeObjectiveMinutes` with single `timeObjectiveMinutes: Int?`. Replaced `cssMinutes`/`cssSeconds` with `cssSecondsPer100m: Int?`. Updated computed `formattedCSS` and `formattedTimeObjective`. Updated `UserUpdate` struct.
  - [x] 🟩 `OnboardingData.swift`: Updated `RaceGoalsData` (single `timeObjectiveMinutes`), `MetricsData` (single `cssSecondsPer100m`), `CompleteOnboardingData` (same + updated init).

- [x] 🟩 **Step 3: ProfileService**
  - [x] 🟩 Updated `updateProfile()` signature: replaced 4 params with 2 (`timeObjectiveMinutes`, `cssSecondsPer100m`)
  - [x] 🟩 Updated `OnboardingUpdate` struct inside `saveOnboardingData()`: replaced 4 fields with 2
  - [x] 🟩 Updated `UserUpdate` construction in `updateProfile()`

- [x] 🟩 **Step 4: Onboarding Views**
  - [x] 🟩 `OnboardingScreen2View.swift`: Kept hours:minutes text fields for UX. On init, decompose `data.timeObjectiveMinutes` into hours/minutes for display. On change, recompose `hours * 60 + minutes` back into `data.timeObjectiveMinutes`.
  - [x] 🟩 `OnboardingScreen3View.swift`: Kept min:sec text fields for UX. On init, decompose `data.cssSecondsPer100m` into minutes/seconds for display. On change, recompose `minutes * 60 + seconds` back into `data.cssSecondsPer100m`. Updated validation to use single field.

- [x] 🟩 **Step 5: ProfileView**
  - [x] 🟩 Updated edit state vars: kept `editTimeHours`/`editTimeMinutes` and `editCssMinutes`/`editCssSeconds` for UI, but convert to/from consolidated values
  - [x] 🟩 Updated `loadEditState()`: decompose consolidated values into display components
  - [x] 🟩 Updated `saveProfile()`: recompose display components into consolidated values
  - [x] 🟩 Updated `validateEditFields()`: validate against new ranges (CSS 25-300 total seconds, time > 0 total minutes)
  - [x] 🟩 Updated display formatters `formatTimeObjective()` and `formatCss()` to derive from single value

- [x] 🟩 **Step 6: Edge Function**
  - [x] 🟩 `generate-plan/index.ts`: Updated `formatCSS()` to accept single `css_seconds_per_100m` param and derive `M:SS` from it. Updated `buildStep1Prompt()` to read `user.css_seconds_per_100m` instead of `user.css_minutes`/`user.css_seconds`.

- [ ] 🟨 **Step 7: Verify & Test** (pending migration application)
  - [ ] 🟨 Confirm migration applies cleanly on Supabase
  - [ ] 🟨 Run through onboarding flow end-to-end (screens 2 + 3)
  - [ ] 🟨 Verify profile edit/save round-trips correctly
  - [ ] 🟨 Verify Edge Function reads new columns without errors
