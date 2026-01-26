# Feature Implementation Plan: Weekly Training Availability

**Overall Progress:** `33%` (Steps 1-2 complete - Database Migration and Data Models)

**Linear Issue:** [DRO-25](https://linear.app/dromosapp/issue/DRO-25/add-weekly-availability-collection-to-onboarding-flow)

## TLDR
Add 3 new onboarding screens (4, 5, 6) to collect athlete's weekly training availability for swim, bike, and run. Users select specific days of the week they can train for each sport. Data stored as JSONB arrays in Supabase for future training plan generation.

## Critical Decisions
- **One screen per sport** - Better UX than cramming all 3 sports on one screen
- **Reusable component approach** - Single `OnboardingAvailabilityView` parameterized by sport (less duplication, maintainable)
- **JSONB array storage with capitalized day names** - `["Monday", "Wednesday"]` format is LLM-friendly and easy to update
- **Validation: minimum 1 day per sport** - Ensures data quality for training plan generation
- **Grid layout with "Any day" toggle** - Follows design reference, clean UX

## Tasks

- [x] 🟩 **Step 1: Database Migration**
  - [x] 🟩 Create migration adding 3 JSONB columns to `users` table: `swim_days`, `bike_days`, `run_days`
  - [x] 🟩 Set default value to empty array `'[]'::jsonb` for each column
  - [x] 🟩 Apply migration to Supabase project
  - [x] 🟩 Verify columns exist in database

- [x] 🟩 **Step 2: Update Data Models**
  - [x] 🟩 Add availability fields to `User` model in `User.swift`
  - [x] 🟩 Add availability fields to `UserUpdate` struct
  - [x] 🟩 Add `AvailabilityData` struct to `OnboardingData.swift`
  - [x] 🟩 Update `CompleteOnboardingData` to include swim/bike/run days

- [ ] 🟥 **Step 3: Create Reusable UI Component**
  - [ ] 🟥 Create `OnboardingAvailabilityView.swift` in `Features/Onboarding/`
  - [ ] 🟥 Implement sport enum (swim, bike, run) with display properties
  - [ ] 🟥 Build grid layout for 7 day buttons (Mon-Sun, 2 columns)
  - [ ] 🟥 Implement selection state (checkmark + highlighted border)
  - [ ] 🟥 Add "Any day" toggle at bottom (selects/deselects all)
  - [ ] 🟥 Add validation: minimum 1 day required
  - [ ] 🟥 Show error message on Next tap if no days selected
  - [ ] 🟥 Implement Back/Next navigation callbacks

- [ ] 🟥 **Step 4: Update Onboarding Flow**
  - [ ] 🟥 Modify `OnboardingFlowView.swift` to extend from 3 to 6 screens
  - [ ] 🟥 Add `@State` for availability data (swim, bike, run)
  - [ ] 🟥 Add cases 4, 5, 6 to screen navigation switch statement
  - [ ] 🟥 Wire up Screen 4 (swim), Screen 5 (bike), Screen 6 (run)
  - [ ] 🟥 Move `onComplete` callback from Screen 3 to Screen 6
  - [ ] 🟥 Update progress indicators: Screen 1-3 stay "X of 6", new screens show "4 of 6", "5 of 6", "6 of 6"
  - [ ] 🟥 Update `CompleteOnboardingData` initialization to include availability

- [ ] 🟥 **Step 5: Update ProfileService**
  - [ ] 🟥 Modify `saveOnboardingData()` to handle swim/bike/run days
  - [ ] 🟥 Update `OnboardingUpdate` struct to include 3 JSONB fields
  - [ ] 🟥 Ensure proper encoding of string arrays to JSONB

- [ ] 🟥 **Step 6: Manual Testing**
  - [ ] 🟥 Test Screen 1-3 still work correctly
  - [ ] 🟥 Test Screen 4: select swim days, validate "Next" requires ≥1 day
  - [ ] 🟥 Test Screen 5: select bike days, validate Back/Next navigation
  - [ ] 🟥 Test Screen 6: select run days, verify save triggers
  - [ ] 🟥 Test "Any day" toggle selects/deselects all days
  - [ ] 🟥 Verify data saved correctly in Supabase (check `users` table)
  - [ ] 🟥 Test onboarding completion flow (navigates to MainTabView)
  - [ ] 🟥 Test error handling during save operation

## Database Schema

```sql
-- UP
ALTER TABLE public.users
  ADD COLUMN swim_days JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN bike_days JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN run_days JSONB DEFAULT '[]'::jsonb;

-- DOWN
ALTER TABLE public.users
  DROP COLUMN swim_days,
  DROP COLUMN bike_days,
  DROP COLUMN run_days;
```

## Data Format

```json
{
  "swim_days": ["Monday", "Wednesday", "Friday"],
  "bike_days": ["Tuesday", "Thursday"],
  "run_days": ["Saturday", "Sunday"]
}
```

## Files Modified/Created

**Created:**
- `Dromos/Dromos/Features/Onboarding/OnboardingAvailabilityView.swift`

**Modified:**
- `Dromos/Dromos/Core/Models/User.swift`
- `Dromos/Dromos/Core/Models/OnboardingData.swift`
- `Dromos/Dromos/Features/Onboarding/OnboardingFlowView.swift`
- `Dromos/Dromos/Core/Services/ProfileService.swift`

**Database:**
- New migration: `add_availability_columns`

## Validation Rules

- Swim availability: minimum 1 day required
- Bike availability: minimum 1 day required
- Run availability: minimum 1 day required
- Error message: "Please select at least one day"
- Error shown on "Next" tap (follows existing onboarding pattern)

## Notes

- Progress indicators update from "X of 3" to "X of 6"
- Screen 3 button changes from "Complete" to "Next"
- Screen 6 button remains "Complete" and triggers save
- All availability fields are persisted but validated (minimum 1 day each)
- Follows existing onboarding patterns for consistency
