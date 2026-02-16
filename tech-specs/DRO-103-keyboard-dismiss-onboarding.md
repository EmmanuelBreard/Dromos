# DRO-103: Replace TextFields with Pickers in Onboarding

**Overall Progress:** `100%`

## TLDR
Keyboard doesn't dismiss on tap outside in onboarding, and all numeric inputs use `.numberPad`/`.decimalPad` (no return key). Instead of patching keyboard dismiss, replace all TextFields with Picker wheels — eliminates the keyboard entirely, adds built-in validation, and provides a more native iOS experience.

## Critical Decisions
- **Pickers over TextFields**: Eliminates the keyboard problem at the root. No keyboard = no dismiss issue. Also provides built-in input validation.
- **Wheel style for all**: `.wheel` picker style for all numeric inputs — natural for scrolling through numeric ranges.
- **All fields mandatory with defaults**: All metrics (VMA, CSS, FTP, experience, time objective) are always visible with sensible defaults. No toggles needed.
- **No data model changes**: All picker values bind to existing data model types (`Double?`, `Int?`).
- **Consistent ScrollView layout**: All 3 screens use `ScrollView { VStack { content + buttons } }.padding()` pattern.
- **Explicit withAnimation for transitions**: Fixed transition direction bug by replacing implicit `.animation()` with explicit `withAnimation` blocks.

## Files Touched
| File | Action | Changes |
|------|--------|---------|
| `OnboardingScreen1View.swift` | MODIFY | Weight picker, ScrollView wrap, removed dead Spacer |
| `OnboardingScreen2View.swift` | MODIFY | Time objective dual picker, ScrollView wrap |
| `OnboardingScreen3View.swift` | MODIFY | VMA/CSS/FTP/experience pickers, hint texts above pickers |
| `OnboardingFlowView.swift` | MODIFY | withAnimation transition fix |
| `CHANGELOG.md` | MODIFY | Updated unreleased section |

## Tasks

- [x] 🟩 **Phase 1: Screen 1 — Weight picker** (PR #40)
- [x] 🟩 **Phase 2: Screen 2 — Race time dual picker** (PR #40)
- [x] 🟩 **Phase 3: Screen 3 — All metrics pickers** (PR #40)
- [x] 🟩 **QA Fix: Remove toggles, all metrics mandatory** (PR #42)
- [x] 🟩 **QA Fix: Hint texts above pickers** (direct commits)
- [x] 🟩 **QA Fix: ScrollView standardization** (direct commits)
- [x] 🟩 **QA Fix: Transition direction** (direct commit)
