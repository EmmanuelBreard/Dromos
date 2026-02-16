# DRO-103: Replace TextFields with Pickers in Onboarding

**Overall Progress:** `0%`

## TLDR
Keyboard doesn't dismiss on tap outside in onboarding, and all numeric inputs use `.numberPad`/`.decimalPad` (no return key). Instead of patching keyboard dismiss, replace all TextFields with Picker wheels — eliminates the keyboard entirely, adds built-in validation, and provides a more native iOS experience.

## Critical Decisions
- **Pickers over TextFields**: Eliminates the keyboard problem at the root. No keyboard = no dismiss issue. Also provides built-in input validation.
- **Wheel style for all**: `.wheel` picker style for all numeric inputs — natural for scrolling through numeric ranges, works well for both small (0-30) and medium (120+) option counts.
- **Toggle-to-reveal for optional fields**: Optional metrics (VMA, CSS, FTP, experience) use a Toggle to show/hide the picker. When toggle is off → value is nil. When on → picker value is bound. Avoids sentinel values.
- **No data model changes**: All picker values bind to existing data model types (`Double?`, `Int?`). Remove the `@State` string variables that were only needed for TextField-to-model conversion.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Onboarding/OnboardingScreen1View.swift` | MODIFY | Replace weight TextField with Picker, add ScrollView |
| `Dromos/Dromos/Features/Onboarding/OnboardingScreen2View.swift` | MODIFY | Replace hours/minutes TextFields with dual Picker |
| `Dromos/Dromos/Features/Onboarding/OnboardingScreen3View.swift` | MODIFY | Replace VMA, CSS, FTP, experience TextFields with toggle+picker |

## Context Doc Updates
None — no new files, patterns, or schema changes.

## Picker Specifications

| Field | Range | Step | Default | Style | Required? |
|-------|-------|------|---------|-------|-----------|
| Weight (kg) | 30–150 | 1.0 | 70.0 | `.wheel` | Yes |
| Race time hours | 0–23 | 1 | 2 | `.wheel` | No (toggle) |
| Race time minutes | 0–59 | 1 | 0 | `.wheel` | No (toggle) |
| VMA (km/h) | 13.0–25.0 | 0.1 | 18.0 | `.wheel` | No (toggle) |
| CSS minutes | 0–5 | 1 | 2 | `.wheel` | No (toggle) |
| CSS seconds | 0–59 | 1 | 0 | `.wheel` | No (toggle) |
| FTP (watts) | 50–500 | 5 | 200 | `.wheel` | No (toggle) |
| Experience (years) | 0–30 | 1 | 2 | `.wheel` | No (toggle) |

## Tasks

- [ ] 🟥 **Step 1: Screen 1 — Replace weight TextField with Picker**
  - Remove `@State private var weightText: String`
  - Replace the weight `TextField` + `.keyboardType(.decimalPad)` block (lines 143-156) with a `Picker(.wheel)` binding to `data.weightKg`
  - Range: 30-150 kg in 1.0 increments
  - Default: 70.0 kg (set via `.onAppear` if `data.weightKg` is nil)
  - Format displayed value as `"XX kg"` in each picker row
  - Wrap the outer `VStack` body content in a `ScrollView` to accommodate the wheel picker height (currently no ScrollView on Screen 1)
  - Validation: `isWeightValid` still checks 30-300 range (now always valid since picker constrains to 30-150)

- [ ] 🟥 **Step 2: Screen 2 — Replace time objective TextFields with dual Picker**
  - Remove `@State private var hoursText: String` and `minutesText: String`
  - Add `@State private var showTimeObjective: Bool = false` (initialized from `data.timeObjectiveMinutes != nil` in `.onAppear`)
  - Replace the hours/minutes TextFields (lines 121-172) with:
    - A `Toggle("I have a time goal", isOn: $showTimeObjective)`
    - When toggle off: set `data.timeObjectiveMinutes = nil`
    - When toggle on: show two side-by-side `.wheel` pickers for hours (0-23) and minutes (0-59)
    - Bind: `data.timeObjectiveMinutes = selectedHours * 60 + selectedMinutes`
    - Add `@State private var selectedHours: Int = 2` and `selectedMinutes: Int = 0`
    - Initialize from `data.timeObjectiveMinutes` in `.onAppear`

- [ ] 🟥 **Step 3: Screen 3 — Replace VMA TextField with toggle + Picker**
  - Remove `@State private var vmaText: String`
  - Add `@State private var showVma: Bool = false` (initialized from `data.vma != nil`)
  - Replace VMA TextField block (lines 128-141) with:
    - Toggle in the header HStack
    - When off: `data.vma = nil`
    - When on: `.wheel` picker, 13.0-25.0 in 0.1 steps, default 18.0
    - `@State private var selectedVma: Double = 18.0` (initialized from `data.vma` in `.onAppear`)
    - Display format: `"XX.X km/h"` per row
  - Remove the `isVmaValid` check against `vmaText.isEmpty` — picker always produces valid values
  - Simplify validation: if `showVma`, value is always valid (constrained by picker range)

- [ ] 🟥 **Step 4: Screen 3 — Replace CSS TextFields with toggle + dual Picker**
  - Remove `@State private var cssMinutesText: String` and `cssSecondsText: String`
  - Add `@State private var showCss: Bool = false` (initialized from `data.cssSecondsPer100m != nil`)
  - Replace CSS TextFields block (lines 159-210) with:
    - Toggle in the header HStack
    - When off: `data.cssSecondsPer100m = nil`
    - When on: two side-by-side `.wheel` pickers (minutes 0-5, seconds 0-59)
    - Bind: `data.cssSecondsPer100m = selectedCssMin * 60 + selectedCssSec`
    - `@State private var selectedCssMin: Int = 2` and `selectedCssSec: Int = 0`
    - Display format: minutes picker shows `"X min"`, seconds picker shows `"XX sec"`
  - Simplify `isCssValid` — picker constrains values to valid range

- [ ] 🟥 **Step 5: Screen 3 — Replace FTP TextField with toggle + Picker**
  - Remove `@State private var ftpText: String`
  - Add `@State private var showFtp: Bool = false` (initialized from `data.ftp != nil`)
  - Replace FTP TextField block (lines 228-241) with:
    - Toggle in the header HStack
    - When off: `data.ftp = nil`
    - When on: `.wheel` picker, 50-500 in 5W steps, default 200
    - `@State private var selectedFtp: Int = 200`
    - Display format: `"XXX W"` per row
  - Simplify `isFtpValid`

- [ ] 🟥 **Step 6: Screen 3 — Replace experience TextField with toggle + Picker**
  - Remove `@State private var experienceYearsText: String`
  - Add `@State private var showExperience: Bool = false` (initialized from `data.experienceYears != nil`)
  - Replace experience TextField block (lines 259-272) with:
    - Toggle in the header HStack
    - When off: `data.experienceYears = nil`
    - When on: `.wheel` picker, 0-30 years, default 2
    - `@State private var selectedExperience: Int = 2`
    - Display format: `"X years"` (or `"1 year"` for singular)
  - Simplify `isExperienceYearsValid`

- [ ] 🟥 **Step 7: Clean up validation logic across all 3 screens**
  - Screen 1: `isWeightValid` can be simplified since picker always produces valid values
  - Screen 2: time objective validation unchanged (optional, no validation needed)
  - Screen 3: remove text-based validation checks (`vmaText.isEmpty`, `ftpText.isEmpty`, etc.) — pickers guarantee valid values when toggle is on
  - Ensure `.onAppear` blocks on each screen correctly restore toggle states and picker selections when navigating back
