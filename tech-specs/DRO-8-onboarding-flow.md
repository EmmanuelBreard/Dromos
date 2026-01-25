# Feature Implementation Plan: Onboarding Flow

**Overall Progress:** `57%` (4 of 7 phases complete)

**Linear Issue:** [DRO-8](https://linear.app/dromosapp/issue/DRO-8/implement-one-time-onboarding-flow-with-profile-sync)

## TL;DR
Build a 3-screen onboarding flow that collects user profile data (basic info, race goals, performance metrics) on first app launch. Data persists to Supabase `users` table and is editable later via restructured Profile view with Goals/Metrics/Settings sections.

---

## Critical Decisions

- **Schema approach**: Flat structure - all fields in `users` table (simple, single source of truth)
- **Resume behavior**: Restart from Screen 1 on force-quit (no interim state persistence for MVP)
- **Sex input**: Male/Female toggle buttons (not dropdown)
- **Age storage**: `birth_date: DATE` (accurate, calculate age for display/validation)
- **CSS format**: Separate `css_minutes: INT` + `css_seconds: INT` columns
- **Time objective**: Separate `time_objective_hours: INT` + `time_objective_minutes: INT` (both nullable)
- **Profile sections**: 3 sections top-to-bottom - Goals → Metrics → Settings
- **Validation UX**: "Next" button stays enabled, shows red inline errors, blocks navigation until fixed
- **Progress indicator**: Simple text "1 of 3", "2 of 3", "3 of 3"

---

## Tasks

### Phase 1: Database Foundation

- [ ] 🟥 **Task 1.1: Create Migration for User Schema Extension**
  - [ ] 🟥 Create `supabase/migrations/002_add_onboarding_fields.sql`
  - [ ] 🟥 Add new columns to `users` table:
    - `sex TEXT`
    - `birth_date DATE`
    - `weight_kg DECIMAL(5,2)`
    - `race_objective TEXT CHECK (race_objective IN ('Sprint', 'Olympic', 'Ironman 70.3', 'Ironman'))`
    - `race_date DATE`
    - `time_objective_hours INT`
    - `time_objective_minutes INT`
    - `vma DECIMAL(4,2)`
    - `css_minutes INT`
    - `css_seconds INT`
    - `ftp INT`
    - `experience_years INT`
    - `onboarding_completed BOOLEAN DEFAULT FALSE`
  - [ ] 🟥 Add CHECK constraints for validation:
    - `weight_kg BETWEEN 30 AND 300`
    - `vma BETWEEN 10 AND 25`
    - `ftp BETWEEN 50 AND 500`
    - `css_seconds BETWEEN 0 AND 59`
    - Total CSS: `(css_minutes * 60 + css_seconds) BETWEEN 25 AND 300`
    - `experience_years >= 0`
  - [ ] 🟥 Verify RLS policies cover new columns (SELECT/UPDATE for own row)
  - [ ] 🟥 Add DOWN migration for rollback

---

### Phase 2: Swift Model Layer

- [ ] 🟥 **Task 2.1: Extend User Model**
  - [ ] 🟥 Update `Core/Models/User.swift` with new properties:
    - `var sex: String?`
    - `var birthDate: Date?`
    - `var weightKg: Double?`
    - `var raceObjective: RaceObjective?` (enum)
    - `var raceDate: Date?`
    - `var timeObjectiveHours: Int?`
    - `var timeObjectiveMinutes: Int?`
    - `var vma: Double?`
    - `var cssMinutes: Int?`
    - `var cssSeconds: Int?`
    - `var ftp: Int?`
    - `var experienceYears: Int?`
    - `var onboardingCompleted: Bool`
  - [ ] 🟥 Create `RaceObjective` enum with cases: `.sprint, .olympic, .ironman703, .ironman`
  - [ ] 🟥 Implement `CodingKeys` for snake_case ↔ camelCase mapping
  - [ ] 🟥 Add computed property `age: Int?` (calculated from birthDate)

- [ ] 🟥 **Task 2.2: Create Onboarding Data Models**
  - [ ] 🟥 Create `Core/Models/OnboardingData.swift`
  - [ ] 🟥 Define `BasicInfoData` struct (sex, birthDate, weightKg)
  - [ ] 🟥 Define `RaceGoalsData` struct (raceObjective, raceDate, timeObjectiveHours, timeObjectiveMinutes)
  - [ ] 🟥 Define `MetricsData` struct (vma, cssMinutes, cssSeconds, ftp, experienceYears)
  - [ ] 🟥 Define `CompleteOnboardingData` struct combining all three

---

### Phase 3: Service Layer

- [ ] 🟥 **Task 3.1: Extend ProfileService**
  - [ ] 🟥 Add method `saveOnboardingData(userId: UUID, data: CompleteOnboardingData) async throws`
  - [ ] 🟥 Add method `markOnboardingComplete(userId: UUID) async throws`
  - [ ] 🟥 Update `fetchProfile` to include new fields in SELECT query
  - [ ] 🟥 Add error handling for validation failures (DB constraints)

- [ ] 🟥 **Task 3.2: Extend AuthService for Onboarding State**
  - [ ] 🟥 Add `@Published var onboardingCompleted: Bool = false`
  - [ ] 🟥 Update session observer to fetch `onboarding_completed` status on auth state change
  - [ ] 🟥 Add method `checkOnboardingStatus() async throws -> Bool`

---

### Phase 4: Onboarding UI Components

- [x] 🟩 **Task 4.1: Create Onboarding Screen 1 - Basic Info**
  - [x] 🟩 Create `Features/Onboarding/OnboardingScreen1View.swift`
  - [x] 🟩 Sex selection: Male/Female toggle buttons (mutually exclusive)
  - [x] 🟩 Birth date: `DatePicker` (wheel style, valid range: 1926-2013 for ages 13-100)
  - [x] 🟩 Weight: `TextField` with decimal keyboard, "kg" suffix
  - [x] 🟩 Inline validation with red error text below invalid fields
  - [x] 🟩 "Next" button (enabled, shows errors if tapped with invalid data, blocks navigation)
  - [x] 🟩 Progress indicator "1 of 3" at top

- [x] 🟩 **Task 4.2: Create Onboarding Screen 2 - Race Goals**
  - [x] 🟩 Create `Features/Onboarding/OnboardingScreen2View.swift`
  - [x] 🟩 Race objective: Picker or segmented control (Sprint/Olympic/Ironman 70.3/Ironman)
  - [x] 🟩 Race date: `DatePicker` (minimum: today, calendar style)
  - [x] 🟩 Time objective: Optional - hours + minutes `TextField`s (allow empty)
  - [x] 🟩 "Back" and "Next" buttons
  - [x] 🟩 Validation: race objective + race date required, time optional
  - [x] 🟩 Progress indicator "2 of 3" at top

- [x] 🟩 **Task 4.3: Create Onboarding Screen 3 - Performance Metrics**
  - [x] 🟩 Create `Features/Onboarding/OnboardingScreen3View.swift`
  - [x] 🟩 VMA: Optional `TextField`, "km/h" suffix, decimal input
  - [x] 🟩 CSS: Optional minutes + seconds `TextField`s
  - [x] 🟩 FTP: Optional `TextField`, "W" suffix, integer input
  - [x] 🟩 Experience years: Optional `TextField` or `Stepper`, integer
  - [x] 🟩 All fields skippable (allow empty)
  - [x] 🟩 "Back" and "Complete" buttons
  - [x] 🟩 Validation for filled fields only (if VMA entered, validate 10-25 range)
  - [x] 🟩 Progress indicator "3 of 3" at top

- [x] 🟩 **Task 4.4: Create Onboarding Container Flow**
  - [x] 🟩 Create `Features/Onboarding/OnboardingFlowView.swift`
  - [x] 🟩 Use `@State` to track current screen (1, 2, or 3)
  - [x] 🟩 Use `@State` to store collected data from each screen
  - [x] 🟩 Handle "Next"/"Back" navigation between screens
  - [x] 🟩 On "Complete": call `ProfileService.saveOnboardingData()` + `markOnboardingComplete()`
  - [x] 🟩 Show loading indicator during save
  - [x] 🟩 Handle save errors (show alert, allow retry)
  - [x] 🟩 On success: update `AuthService.onboardingCompleted` = true (triggers nav to MainTabView)

---

### Phase 5: Navigation Integration

- [ ] 🟥 **Task 5.1: Update RootView Navigation Logic**
  - [ ] 🟥 Modify `App/RootView.swift` to add 3-way conditional:
    ```swift
    if !authService.isAuthenticated {
        AuthView(authService: authService)
    } else if !authService.onboardingCompleted {
        OnboardingFlowView(authService: authService)
    } else {
        MainTabView(authService: authService)
    }
    ```
  - [ ] 🟥 Ensure `onboardingCompleted` is fetched on app launch (via `AuthService.checkOnboardingStatus()`)

- [ ] 🟥 **Task 5.2: Handle Onboarding State After SignUp**
  - [ ] 🟥 After successful `signUp()` in `AuthService`, set `onboardingCompleted = false` (default DB value)
  - [ ] 🟥 Ensure RootView reactivity triggers navigation to `OnboardingFlowView`

---

### Phase 6: Profile View Restructuring

- [ ] 🟥 **Task 6.1: Restructure ProfileView into 3 Sections**
  - [ ] 🟥 Update `Features/Profile/ProfileView.swift`
  - [ ] 🟥 Create Section 1 - **Goals** (top):
    - Display: race objective, race date, time objective (formatted as "Xh Ym" or "Not set")
    - Edit mode: Same pickers/inputs as onboarding Screen 2
  - [ ] 🟥 Create Section 2 - **Metrics**:
    - Display: VMA, CSS (formatted as "Xm Ys"), FTP, experience years (show "Not set" for nulls)
    - Edit mode: Same inputs as onboarding Screen 3
  - [ ] 🟥 Create Section 3 - **Settings** (bottom):
    - Display: sex, birth_date (show calculated age), weight_kg, name, email
    - Edit mode: Same inputs as onboarding Screen 1 + existing name field
  - [ ] 🟥 Keep existing "Edit"/"Cancel"/"Save" toolbar pattern
  - [ ] 🟥 Keep existing "Sign Out" button at bottom

- [ ] 🟥 **Task 6.2: Update ProfileService for Profile Editing**
  - [ ] 🟥 Extend `updateProfile()` method to accept all new fields as optional parameters
  - [ ] 🟥 Build dynamic UPDATE query including only non-nil fields
  - [ ] 🟥 Maintain existing error handling pattern

---

### Phase 7: Testing & Validation

- [ ] 🟥 **Task 7.1: Manual Testing Checklist**
  - [ ] 🟥 Fresh signup → onboarding shows → complete all screens → lands on MainTabView
  - [ ] 🟥 Fresh signup → complete onboarding → force-quit app → reopen → goes straight to MainTabView (no re-onboarding)
  - [ ] 🟥 Onboarding Screen 1: Tap "Next" with empty fields → red errors show → no navigation
  - [ ] 🟥 Onboarding Screen 1: Fill all fields → tap "Next" → navigates to Screen 2
  - [ ] 🟥 Onboarding Screen 2: Leave time objective empty → tap "Next" → navigates to Screen 3
  - [ ] 🟥 Onboarding Screen 3: Skip all fields → tap "Complete" → saves successfully
  - [ ] 🟥 Onboarding Screen 3: Enter VMA = 30 (invalid) → tap "Complete" → red error shows
  - [ ] 🟥 Force-quit during Screen 2 → reopen app → restarts at Screen 1 (no resume)
  - [ ] 🟥 ProfileView: All 3 sections display correctly with onboarding data
  - [ ] 🟥 ProfileView: Edit Goals section → save → verify update in DB
  - [ ] 🟥 ProfileView: Edit Metrics section → save → verify update in DB
  - [ ] 🟥 ProfileView: Edit Settings section → save → verify update in DB
  - [ ] 🟥 Validation bounds: Test weight (29kg fails, 30kg passes, 301kg fails, 300kg passes)
  - [ ] 🟥 Validation bounds: Test age via birth_date (12 years fails, 13 passes, 100 fails, 99 passes)
  - [ ] 🟥 Validation bounds: Test FTP (49W fails, 50W passes, 501W fails, 500W passes)
  - [ ] 🟥 Validation bounds: Test VMA (9.9 fails, 10.0 passes, 25.1 fails, 25.0 passes)
  - [ ] 🟥 Validation bounds: Test CSS (24s fails, 25s passes, 301s fails, 300s passes)

- [ ] 🟥 **Task 7.2: Edge Case Testing**
  - [ ] 🟥 Network error during onboarding save → alert shows → user can retry
  - [ ] 🟥 Sign out during onboarding (if possible) → sign back in → onboarding restarts
  - [ ] 🟥 Multiple devices: Complete onboarding on device A → open device B → no re-onboarding

---

## Files to Create

- `supabase/migrations/002_add_onboarding_fields.sql`
- `Dromos/Dromos/Core/Models/OnboardingData.swift`
- `Dromos/Dromos/Features/Onboarding/OnboardingFlowView.swift`
- `Dromos/Dromos/Features/Onboarding/OnboardingScreen1View.swift`
- `Dromos/Dromos/Features/Onboarding/OnboardingScreen2View.swift`
- `Dromos/Dromos/Features/Onboarding/OnboardingScreen3View.swift`

## Files to Modify

- `Dromos/Dromos/Core/Models/User.swift`
- `Dromos/Dromos/Core/Services/ProfileService.swift`
- `Dromos/Dromos/Core/Services/AuthService.swift`
- `Dromos/Dromos/App/RootView.swift`
- `Dromos/Dromos/Features/Profile/ProfileView.swift`

---

## Out of Scope (for MVP)

- Resume onboarding from last screen (restart from Screen 1 is acceptable)
- Unit/widget selection toggle (kg only for now)
- Multiple race goals (single goal for MVP)
- Computed metrics alternatives (mentioned in Linear, future work)
- Analytics/tracking of onboarding completion rates
- Onboarding preview/skip for existing users

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| User force-quits during save → partial data | DB constraints prevent invalid partial saves; all-or-nothing transaction |
| Date picker UX on small screens | Use `.wheel` style for birthDate, `.graphical` for raceDate (more specific) |
| CSS validation complexity (min+sec) | Client-side validation before save; DB CHECK constraint as fallback |
| Age calculation edge cases (leap years, timezones) | Use `Calendar.current.dateComponents` for accurate age calculation |
| Profile view becomes cluttered with 3 sections | Use SwiftUI `Section` headers for clear separation; test on iPhone SE |

---

## Success Criteria

✅ New user signs up → sees 3-screen onboarding → completes → data saves to Supabase
✅ Returning user never sees onboarding again
✅ All validation bounds enforced (client + DB)
✅ Profile view shows all collected data in 3 organized sections
✅ User can edit all onboarding fields from Profile view
✅ No regressions in existing auth/profile flows
