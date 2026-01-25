# DRO-17: Batch 5 - Profile View Restructuring

## Progress: 100%

| Task | Status | Description |
|------|--------|-------------|
| 5.1 | ✅ Complete | Restructure ProfileView |

---

## Task Details

### Task 5.1: Restructure ProfileView
- **File**: `Dromos/Dromos/Features/Profile/ProfileView.swift`
- **Status**: ✅ Complete
- **Changes Made**:
  - ✅ Complete rewrite with 3 organized sections
  - ✅ Added 13 edit state variables for all fields
  - ✅ Implemented separate display/edit views for each section
  - ✅ Added 8 formatter methods for proper value display
  - ✅ Updated save logic to handle all onboarding fields
  - ✅ Maintained Edit/Cancel/Save toolbar pattern
  - ✅ Kept Sign Out button at bottom

---

## Section Structure

### 1. Goals Section
**Display Mode:**
- Race Type (e.g., "Olympic")
- Race Date (formatted)
- Time Objective (e.g., "5h 30m")

**Edit Mode:**
- Picker for race type (Sprint, Olympic, 70.3, Ironman)
- DatePicker for race date
- Hour/Minute text fields for time objective

### 2. Metrics Section
**Display Mode:**
- VMA (e.g., "18.5 km/h")
- CSS (e.g., "1:45 / 100m")
- FTP (e.g., "250 W")
- Experience (e.g., "2 years")

**Edit Mode:**
- Text fields for VMA, CSS (min:sec), FTP, Experience
- Proper keyboard types (decimal/number pad)
- Right-aligned for numeric inputs

### 3. Settings Section
**Display Mode:**
- Sex (e.g., "Male")
- Age (calculated from birth date, e.g., "32 years")
- Weight (e.g., "75.0 kg")
- Name
- Email (read-only)

**Edit Mode:**
- Sex buttons (Male/Female with checkmark)
- DatePicker for birth date
- Text fields for weight and name
- Email remains read-only

---

## Formatters Implemented

1. `formatDate()` - Medium date style
2. `formatTimeObjective()` - "Xh Ym" format
3. `formatVma()` - "X.X km/h"
4. `formatCss()` - "M:SS / 100m"
5. `formatFtp()` - "X W"
6. `formatExperience()` - "X year(s)"
7. `formatAge()` - "X years"
8. `formatWeight()` - "X.X kg"

All formatters return "Not set" for nil values.

---

## Key Features

- **Modular Views**: Separate view builders for each section (display + edit)
- **State Management**: Edit state loaded from user object on fetch
- **Cancel Support**: Reloads edit state to discard changes
- **Error Handling**: Alert dialog for save/fetch errors
- **Loading States**: ProgressView while fetching or saving
- **Type Safety**: Proper optional handling for all nullable fields

---

## Files Modified

| File | Lines Changed |
|------|---------------|
| `Dromos/Dromos/Features/Profile/ProfileView.swift` | Complete rewrite (499 lines) |

---

## Next Steps

1. Build and test in Xcode
2. Verify all 3 sections display correctly
3. Test edit → save → verify persistence
4. Test cancel discards changes
5. Verify formatters show "Not set" for empty fields
