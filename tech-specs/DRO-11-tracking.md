# DRO-11: Batch 2 - Service Layer Extensions

## Progress: 100%

| Task | Status | Description |
|------|--------|-------------|
| 2.1 | ✅ Complete | Extend ProfileService |
| 2.2 | ✅ Complete | Extend AuthService |

---

## Task Details

### Task 2.1: Extend ProfileService
- **File**: `Dromos/Dromos/Core/Services/ProfileService.swift`
- **Status**: ✅ Complete
- **Changes Made**:
  - ✅ Added `saveOnboardingData()` method with `OnboardingUpdate` struct
  - ✅ Added `markOnboardingComplete()` method with `OnboardingStatusUpdate` struct
  - ✅ Extended `updateProfile()` with all onboarding fields (13 new optional parameters)

### Task 2.2: Extend AuthService
- **File**: `Dromos/Dromos/Core/Services/AuthService.swift`
- **Status**: ✅ Complete
- **Changes Made**:
  - ✅ Added `onboardingCompleted: Bool` published property
  - ✅ Added `checkOnboardingStatus()` method
  - ✅ Updated `signOut()` to reset `onboardingCompleted = false`
  - ✅ Updated `startObservingAuthState()` to call `checkOnboardingStatus()` on:
    - `.initialSession` (when session restored)
    - `.signedIn` (when user signs in)
    - `.userUpdated` (when user profile updated)
  - ✅ Updated `checkExistingSession()` to call `checkOnboardingStatus()`
  - ✅ Set `onboardingCompleted = false` on all sign out/error paths

---

## Files Modified

| File | Changes |
|------|---------|
| `Dromos/Dromos/Core/Services/ProfileService.swift` | +105 lines |
| `Dromos/Dromos/Core/Services/AuthService.swift` | +32 lines |

---

## Next Steps

1. Build iOS app to verify no compilation errors
2. Test `saveOnboardingData()` with mock data
3. Test `markOnboardingComplete()` flow
4. Verify `onboardingCompleted` updates correctly on sign in/out
