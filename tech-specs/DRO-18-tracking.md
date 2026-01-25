# DRO-18: Batch 6 - Testing & Validation

## Progress: 0%

**Note**: This is a manual testing task. Tests must be performed manually in Xcode/Simulator or on a physical device.

---

## Test Groups Overview

| Group | Tests | Status | Pass | Fail |
|-------|-------|--------|------|------|
| 1. New User Onboarding Flow | 2 | ⏳ Pending | 0 | 0 |
| 2. Validation - Required Fields | 5 | ⏳ Pending | 0 | 0 |
| 3. Validation - Optional Fields | 4 | ⏳ Pending | 0 | 0 |
| 4. Validation - Edge Cases | 5 | ⏳ Pending | 0 | 0 |
| 5. Navigation & Back Button | 3 | ⏳ Pending | 0 | 0 |
| 6. Error Handling | 4 | ⏳ Pending | 0 | 0 |
| 7. Profile Editing | 5 | ⏳ Pending | 0 | 0 |
| 8. Multi-Device & Persistence | 3 | ⏳ Pending | 0 | 0 |
| 9. Regression Testing | 4 | ⏳ Pending | 0 | 0 |

**Total Tests**: 35

---

## Test Group 1: New User Onboarding Flow

### Test 1.1: Happy Path - Complete All Fields ⏳
- [ ] Delete app / clear user data
- [ ] Sign up with new email/password
- [ ] Verify OnboardingFlowView appears
- [ ] Screen 1: Male, birth date 25 years ago, weight 70kg
- [ ] Tap "Next" → Screen 2
- [ ] Screen 2: Olympic, race date +3 months, time 2h 30m
- [ ] Tap "Next" → Screen 3
- [ ] Screen 3: VMA 18.5, CSS 1:30, FTP 250, Experience 2
- [ ] Tap "Complete" → loading indicator
- [ ] Navigates to MainTabView
- [ ] Profile tab: verify all data displays
- [ ] Force-quit → reopen → MainTabView (no re-onboarding)
- [ ] DB: `onboarding_completed = true`, all fields saved

**Status**: ⏳ Pending
**Result**: -

### Test 1.2: Happy Path - Skip Optional Fields ⏳
- [ ] Sign up with new email
- [ ] Screen 1: Complete required fields
- [ ] Screen 2: Complete race objective + date, skip time
- [ ] Screen 3: Skip all fields
- [ ] Tap "Complete" → saves successfully
- [ ] Profile: optional fields show "Not set"

**Status**: ⏳ Pending
**Result**: -

---

## Test Group 2: Validation - Required Fields

### Test 2.1: Screen 1 - Missing Sex ⏳
- [ ] Screen 1: Leave sex unselected
- [ ] Tap "Next" → error "Please select your sex"
- [ ] No navigation (stays on Screen 1)
- [ ] Select "Male" → "Next" → Screen 2

**Status**: ⏳ Pending
**Result**: -

### Test 2.2: Screen 1 - Invalid Birth Date (Age < 13) ⏳
- [ ] Birth date 10 years ago
- [ ] Tap "Next" → error "Age must be between 13 and 99 years"
- [ ] Change to 15 years ago → error disappears
- [ ] "Next" → Screen 2

**Status**: ⏳ Pending
**Result**: -

### Test 2.3: Screen 1 - Invalid Weight (< 30kg) ⏳
- [ ] Weight 25kg
- [ ] Tap "Next" → error "Weight must be between 30 and 300 kg"
- [ ] Change to 30kg → error disappears
- [ ] "Next" → Screen 2

**Status**: ⏳ Pending
**Result**: -

### Test 2.4: Screen 2 - Missing Race Objective ⏳
- [ ] Screen 2: Skip race objective
- [ ] Tap "Next" → error appears
- [ ] Select "Ironman 70.3" → error disappears
- [ ] "Next" → Screen 3

**Status**: ⏳ Pending
**Result**: -

### Test 2.5: Screen 2 - Missing Race Date ⏳
- [ ] Screen 2: Skip race date
- [ ] Tap "Next" → error appears
- [ ] Select tomorrow → error disappears
- [ ] "Next" → Screen 3

**Status**: ⏳ Pending
**Result**: -

---

## Test Group 3: Validation - Optional Fields

### Test 3.1: VMA Out of Range ⏳
- [ ] VMA 9 → error "VMA must be between 10 and 25 km/h"
- [ ] VMA 26 → error persists
- [ ] VMA 18.5 → error disappears
- [ ] "Complete" → saves successfully

**Status**: ⏳ Pending
**Result**: -

### Test 3.2: CSS Out of Range ⏳
- [ ] CSS 0:20 → error "CSS must be between 0:25 and 5:00"
- [ ] CSS 5:30 → error persists
- [ ] CSS 1:30 → error disappears
- [ ] "Complete" → saves successfully

**Status**: ⏳ Pending
**Result**: -

### Test 3.3: FTP Out of Range ⏳
- [ ] FTP 45 → error "FTP must be between 50 and 500 watts"
- [ ] FTP 550 → error persists
- [ ] FTP 250 → error disappears
- [ ] "Complete" → saves successfully

**Status**: ⏳ Pending
**Result**: -

### Test 3.4: CSS Seconds Validation ⏳
- [ ] CSS 1:70 → error (seconds must be 0-59)
- [ ] CSS 1:59 → error disappears
- [ ] "Complete" → saves successfully

**Status**: ⏳ Pending
**Result**: -

---

## Test Group 4: Validation - Edge Cases (Boundary Testing)

### Test 4.1: Weight Boundaries ⏳
- [ ] 29.9 → error
- [ ] 30.0 → valid
- [ ] 300.0 → valid
- [ ] 300.1 → error

**Status**: ⏳ Pending
**Result**: -

### Test 4.2: Age Boundaries ⏳
- [ ] Exactly 13 years ago → valid
- [ ] 12 years 364 days → error
- [ ] Exactly 99 years ago → valid
- [ ] 100 years ago → error/blocked

**Status**: ⏳ Pending
**Result**: -

### Test 4.3: VMA Boundaries ⏳
- [ ] 9.9 → error
- [ ] 10.0 → valid
- [ ] 25.0 → valid
- [ ] 25.1 → error

**Status**: ⏳ Pending
**Result**: -

### Test 4.4: FTP Boundaries ⏳
- [ ] 49 → error
- [ ] 50 → valid
- [ ] 500 → valid
- [ ] 501 → error

**Status**: ⏳ Pending
**Result**: -

### Test 4.5: CSS Boundaries ⏳
- [ ] 0:24 → error
- [ ] 0:25 → valid
- [ ] 5:00 → valid
- [ ] 5:01 → error

**Status**: ⏳ Pending
**Result**: -

---

## Test Group 5: Navigation & Back Button

### Test 5.1: Back Navigation (Screen 2 → 1) ⏳
- [ ] Screen 1 → Screen 2
- [ ] "Back" → Screen 1
- [ ] Data persists

**Status**: ⏳ Pending
**Result**: -

### Test 5.2: Back Navigation (Screen 3 → 2) ⏳
- [ ] Screen 1 & 2 → Screen 3
- [ ] "Back" → Screen 2
- [ ] Data persists

**Status**: ⏳ Pending
**Result**: -

### Test 5.3: Multi-Step Back Navigation ⏳
- [ ] Complete all screens
- [ ] Back through all screens
- [ ] Data persists throughout
- [ ] Navigate forward → data still filled

**Status**: ⏳ Pending
**Result**: -

---

## Test Group 6: Error Handling

### Test 6.1: Network Error During Save ⏳
- [ ] Complete Screen 3
- [ ] Turn off Wi-Fi/cellular
- [ ] "Complete" → error alert
- [ ] Turn on network → retry → saves

**Status**: ⏳ Pending
**Result**: -

### Test 6.2: Force-Quit Mid-Onboarding ⏳
- [ ] Screen 1 → Screen 2 → force-quit
- [ ] Reopen → OnboardingFlowView shows
- [ ] Restarts at Screen 1
- [ ] DB: `onboarding_completed = false`

**Status**: ⏳ Pending
**Result**: -

### Test 6.3: Force-Quit During Save ⏳
- [ ] "Complete" → during loading → force-quit
- [ ] Reopen → OnboardingFlowView (save incomplete)
- [ ] Complete again → saves successfully

**Status**: ⏳ Pending
**Result**: -

### Test 6.4: Sign Out During Onboarding ⏳
- [ ] Start onboarding → sign out
- [ ] Sign in → onboarding restarts

**Status**: ⏳ Pending
**Result**: -

---

## Test Group 7: Profile Editing

### Test 7.1: Edit Goals Section ⏳
- [ ] "Edit" → change race objective Olympic → Ironman
- [ ] Change race date → "Save"
- [ ] Verify updates
- [ ] Force-quit → reopen → changes persisted

**Status**: ⏳ Pending
**Result**: -

### Test 7.2: Edit Metrics Section ⏳
- [ ] "Edit" → VMA 18.5 → 20.0
- [ ] FTP 250 → 280 → "Save"
- [ ] Verify updates
- [ ] DB: new values saved

**Status**: ⏳ Pending
**Result**: -

### Test 7.3: Edit Settings Section ⏳
- [ ] "Edit" → weight 70 → 75
- [ ] Change name → "Save"
- [ ] Verify updates

**Status**: ⏳ Pending
**Result**: -

### Test 7.4: Cancel Edit ⏳
- [ ] "Edit" → change race objective
- [ ] "Cancel" → change discarded

**Status**: ⏳ Pending
**Result**: -

### Test 7.5: Clear Optional Field ⏳
- [ ] "Edit" → clear VMA
- [ ] "Save" → shows "Not set"
- [ ] DB: `vma = NULL`

**Status**: ⏳ Pending
**Result**: -

---

## Test Group 8: Multi-Device & Persistence

### Test 8.1: Same Account Different Device ⏳
- [ ] Device A: Complete onboarding
- [ ] Device B: Sign in → MainTabView (no re-onboarding)
- [ ] Profile: all data synced

**Status**: ⏳ Pending
**Result**: -

### Test 8.2: Sign Out / Sign In ⏳
- [ ] Complete onboarding → sign out
- [ ] Sign in → MainTabView
- [ ] Profile: data persisted

**Status**: ⏳ Pending
**Result**: -

### Test 8.3: Delete & Reinstall App ⏳
- [ ] Complete onboarding → delete app
- [ ] Reinstall → sign in → MainTabView
- [ ] Onboarding remembered

**Status**: ⏳ Pending
**Result**: -

---

## Test Group 9: Regression Testing

### Test 9.1: Existing Auth Flow ⏳
- [ ] Sign up works
- [ ] Sign in works
- [ ] Sign out works

**Status**: ⏳ Pending
**Result**: -

### Test 9.2: Existing Profile View ⏳
- [ ] Name edit works
- [ ] Email read-only
- [ ] Sign out button works

**Status**: ⏳ Pending
**Result**: -

### Test 9.3: Existing Home & Calendar Tabs ⏳
- [ ] Home tab: no regressions
- [ ] Calendar tab: no regressions

**Status**: ⏳ Pending
**Result**: -

### Test 9.4: Existing Database Migrations ⏳
- [ ] `001_create_users_table.sql` runs
- [ ] `002_add_onboarding_fields.sql` runs
- [ ] Test rollback (DOWN)
- [ ] Test re-apply (UP)

**Status**: ⏳ Pending
**Result**: -

---

## Bug Report Template

**Test ID**: [e.g., Test 3.2]
**Expected**: [What should happen]
**Actual**: [What actually happened]
**Steps to Reproduce**:
1. ...
2. ...

**Screenshots**: [Attach]
**Priority**: [High / Medium / Low]

---

## Testing Instructions

### How to Run Tests

1. **Build the app** in Xcode
2. **Run on simulator** or physical device
3. **Work through each test group** sequentially
4. **Update this document** with results:
   - Change ⏳ to ✅ for passing tests
   - Change ⏳ to ❌ for failing tests
   - Add notes in the Result field
5. **Take screenshots** of key flows and errors
6. **Check Supabase database** after tests that modify data
7. **File bug reports** for any failures

### Database Verification Queries

```sql
-- Check onboarding status
SELECT id, email, onboarding_completed
FROM public.users
WHERE email = 'test@example.com';

-- Check all onboarding fields
SELECT * FROM public.users
WHERE email = 'test@example.com';

-- Check specific field values
SELECT
  email,
  race_objective,
  vma,
  ftp,
  onboarding_completed
FROM public.users
WHERE email = 'test@example.com';
```

---

## Summary

Once all tests are complete, provide:

1. **Pass Rate**: X/35 tests passed
2. **Critical Bugs**: List of high-priority failures
3. **Screenshots**: Key flows and error states
4. **Database Snapshots**: Before/after onboarding
5. **Recommendations**: Any improvements or fixes needed
