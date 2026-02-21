# DRO-125: Remove Sex/Age/Weight from App

**Overall Progress:** `100%`

## TLDR
Remove the first onboarding screen (sex, birth date, weight) and all references to these demographic fields across the entire app — onboarding, profile, models, services, and database. These fields are unused by the AI pipeline and add unnecessary friction.

## Critical Decisions
- **DB columns dropped, not soft-deprecated** — Destructive migration is acceptable since fields are unused for training. No data preservation needed.
- **Screen numbering shifts down by 1** — Current Screen 2 (Race Goals) becomes Screen 1, etc. Total screens: 7 → 6.
- **AI pipeline unaffected** — `generate-plan` edge function does not reference sex, birth_date, or weight_kg.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Onboarding/OnboardingScreen1View.swift` | DELETE | Entire file removed |
| `Dromos/Dromos/Features/Onboarding/OnboardingFlowView.swift` | MODIFY | Remove Screen 1 case, remove `basicInfo` state, renumber screens 2-7 → 1-6, update `totalScreens` to 6, remove `BasicInfoData` from `CompleteOnboardingData` init |
| `Dromos/Dromos/Core/Models/OnboardingData.swift` | MODIFY | Delete `BasicInfoData` struct, remove `sex`/`birthDate`/`weightKg` from `CompleteOnboardingData` properties and init |
| `Dromos/Dromos/Core/Models/User.swift` | MODIFY | Remove `sex`/`birthDate`/`weightKg` properties + computed `age` from `User`, remove same from `UserUpdate` |
| `Dromos/Dromos/Core/Services/ProfileService.swift` | MODIFY | Remove `sex`/`birthDate`/`weightKg` params from `updateProfile()`, remove same from `OnboardingUpdate` struct in `saveOnboardingData()` |
| `Dromos/Dromos/Features/Profile/ProfileView.swift` | MODIFY | Remove sex/age/weight from Settings display + edit views, remove `editSex`/`editBirthDate`/`editWeightKg` state, remove `birthDateRange`, remove weight/age validation, remove `formatAge`/`formatWeight` helpers |
| `Dromos/Dromos/Features/Onboarding/OnboardingScreen2View.swift` | MODIFY | Update progress text, make `onBack` optional, hide Back button on first screen |
| `Dromos/Dromos/Features/Onboarding/OnboardingScreen3View.swift` | MODIFY | Update progress text from `"3 of 6"` to `"2 of 6"` |
| `supabase/migrations/010_drop_demographic_columns.sql` | CREATE | Drop `sex`, `birth_date`, `weight_kg` columns + `check_weight_kg` constraint |

## Context Doc Updates
- `schema.md` — Remove `sex`, `birth_date`, `weight_kg` rows from `public.users` table
- `architecture.md` — Update onboarding description from "7-screen" to "6-screen", remove `BasicInfoData` mention from `OnboardingData.swift` description, remove `age` from `User` model extensions

## Tasks:

- [x] 🟩 **Step 1: Delete OnboardingScreen1View**
  - [x] 🟩 Delete `Dromos/Dromos/Features/Onboarding/OnboardingScreen1View.swift`

- [x] 🟩 **Step 2: Clean up OnboardingData model**
  - [x] 🟩 Delete `BasicInfoData` struct from `Dromos/Dromos/Core/Models/OnboardingData.swift`
  - [x] 🟩 Remove `sex`, `birthDate`, `weightKg` properties from `CompleteOnboardingData`
  - [x] 🟩 Remove `basicInfo` parameter from `CompleteOnboardingData.init()` and all references to it inside the init body

- [x] 🟩 **Step 3: Clean up User model**
  - [x] 🟩 Remove `sex`, `birthDate`, `weightKg` properties from `User` struct
  - [x] 🟩 Remove computed `age` property from `User`
  - [x] 🟩 Remove `sex`, `birthDate`, `weightKg` from `UserUpdate` struct
  - [x] 🟩 Remove MARK comment `// MARK: - Onboarding: Basic Info (Screen 1)`

- [x] 🟩 **Step 4: Clean up ProfileService**
  - [x] 🟩 Remove `sex`, `birthDate`, `weightKg` parameters from `updateProfile()` method signature and `UserUpdate` construction
  - [x] 🟩 Remove `sex`, `birthDate`, `weightKg` from `OnboardingUpdate` struct inside `saveOnboardingData()` and its initialization

- [x] 🟩 **Step 5: Clean up ProfileView**
  - [x] 🟩 Remove `editSex`, `editBirthDate`, `editWeightKg` `@State` vars
  - [x] 🟩 Remove `birthDateRange` computed property
  - [x] 🟩 Remove Sex/Age/Weight rows from `settingsDisplayView` (keep Name and Email)
  - [x] 🟩 Remove Sex/BirthDate/Weight fields from `settingsEditingView` (keep Name and Email)
  - [x] 🟩 Remove weight validation and age validation from `validateEditFields()`
  - [x] 🟩 Remove `editSex`/`editBirthDate`/`editWeightKg` from `loadEditState()`
  - [x] 🟩 Remove `sex:`/`birthDate:`/`weightKg:` args from `profileService.updateProfile()` call in `saveProfile()`
  - [x] 🟩 Remove `formatAge()` and `formatWeight()` helper methods

- [x] 🟩 **Step 6: Update OnboardingFlowView**
  - [x] 🟩 Remove `@State private var basicInfo = BasicInfoData()`
  - [x] 🟩 Remove `case 1:` (Screen 1) from the switch
  - [x] 🟩 Renumber remaining cases: old 2→1, 3→2, 4→3, 5→4, 6→5, 7→6
  - [x] 🟩 Update Screen 2 (Race Goals, now case 1) `onBack` — make optional, hide Back button
  - [x] 🟩 Update all `screenNumber:` parameters: 4→3, 5→4, 6→5, 7→6
  - [x] 🟩 Update all `totalScreens:` from 7 to 6
  - [x] 🟩 Remove `basicInfo:` from `CompleteOnboardingData(...)` init call in `saveOnboardingData()`
  - [x] 🟩 Update doc comment from "7-screen" to "6-screen"

- [x] 🟩 **Step 7: Update screen progress indicators**
  - [x] 🟩 Update `OnboardingScreen2View.swift` progress text: `"2 of 6"` → `"1 of 6"`
  - [x] 🟩 Update `OnboardingScreen3View.swift` progress text: `"3 of 6"` → `"2 of 6"`

- [x] 🟩 **Step 8: Database migration**
  - [x] 🟩 Create `supabase/migrations/010_drop_demographic_columns.sql` with DROP COLUMN for `sex`, `birth_date`, `weight_kg` and DROP CONSTRAINT for `check_weight_kg`

- [x] 🟩 **Step 9: Update context docs**
  - [x] 🟩 Update `.claude/context/schema.md` — remove `sex`, `birth_date`, `weight_kg` rows
  - [x] 🟩 Update `.claude/context/architecture.md` — "7-screen" → "6-screen", remove `BasicInfoData` mention, remove `age` from User extensions
