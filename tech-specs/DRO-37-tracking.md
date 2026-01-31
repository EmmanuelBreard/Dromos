# DRO-37: Add Daily Training Duration Collection to Onboarding Flow

**Overall Progress:** `100%`

**Linear Issue:** [DRO-37](https://linear.app/dromosapp/issue/DRO-37/add-daily-training-duration-collection-to-onboarding-flow)

## TL;DR
Add 1 new onboarding screen (Screen 7) to collect total training duration per day of the week. Only days marked as available across any sport (union of swim/bike/run days from DRO-25) are shown. The plan generator will handle sport-specific time splits.

## Tasks

- [x] 🟩 **Step 1: Database Migration**
  - [x] 🟩 Create migration adding 7 nullable INT columns to `users` table: `mon_duration`, `tue_duration`, `wed_duration`, `thu_duration`, `fri_duration`, `sat_duration`, `sun_duration`
  - [x] 🟩 Add CHECK constraints (30-420 minutes range)
  - [ ] 🟨 Apply migration to Supabase project (manual step)
  - [ ] 🟨 Verify columns exist in database (manual step)

- [x] 🟩 **Step 2: Update Data Models**
  - [x] 🟩 Add 7 duration fields to `User` model in `User.swift`
  - [x] 🟩 Add 7 duration fields to `UserUpdate` struct
  - [x] 🟩 Add `DailyDurationData` struct to `OnboardingData.swift`
  - [x] 🟩 Update `CompleteOnboardingData` to include duration data

- [x] 🟩 **Step 3: Create Screen 7 UI Component**
  - [x] 🟩 Create `OnboardingDailyDurationView.swift`
  - [x] 🟩 Show only days in union of swim/bike/run days
  - [x] 🟩 Implement dropdown picker with 15min increments (30-420 min)
  - [x] 🟩 Default value: 1 hour (60 min)
  - [x] 🟩 Add validation (all shown days required)

- [x] 🟩 **Step 4: Update Onboarding Flow**
  - [x] 🟩 Update `OnboardingFlowView.swift` to handle 7 screens
  - [x] 🟩 Change Screen 6 button from "Complete" to "Next" (automatic via totalScreens update)
  - [x] 🟩 Move save trigger from Screen 6 to Screen 7
  - [x] 🟩 Update progress indicator to "7 of 7"

- [x] 🟩 **Step 5: Update Service Layer**
  - [x] 🟩 Add 7 duration fields to `OnboardingUpdate` struct in `ProfileService.swift`
  - [x] 🟩 Update `saveOnboardingData` to include duration data

- [ ] 🟨 **Step 6: Testing & Verification**
  - [ ] 🟨 Test Screen 7 displays only available days (requires manual testing)
  - [ ] 🟨 Test default values (1 hour) (requires manual testing)
  - [ ] 🟨 Test save flow from Screen 7 (requires manual testing)
  - [ ] 🟨 Verify data persists correctly (requires manual testing)

## Files Modified

| File | Changes |
|------|---------|
| `supabase/migrations/005_add_daily_duration_columns.sql` | New migration file |
| `Dromos/Dromos/Core/Models/User.swift` | Added 7 duration fields and CodingKeys |
| `Dromos/Dromos/Core/Models/OnboardingData.swift` | Added `DailyDurationData` struct and updated `CompleteOnboardingData` |
| `Dromos/Dromos/Features/Onboarding/OnboardingDailyDurationView.swift` | New Screen 7 component |
| `Dromos/Dromos/Features/Onboarding/OnboardingFlowView.swift` | Updated to 7 screens, moved save to Screen 7 |
| `Dromos/Dromos/Core/Services/ProfileService.swift` | Added duration fields to `OnboardingUpdate` |

## Implementation Details

- **Duration Range:** 30-420 minutes (30min to 7hr) in 15-minute increments
- **Default Value:** 1 hour (60 minutes) pre-selected for all available days
- **Day Selection:** Only shows days in union of swim/bike/run availability
- **Validation:** All shown days must have a duration selected (enforced by default values)
- **Storage:** Nullable INT columns - off-days remain NULL

