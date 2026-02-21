# DRO-126: Redesign Login Page with Mobile-Friendly UI

**Overall Progress:** `100%`

## TLDR
Redesign LoginView and SignUpView with custom dark-themed styling: large typography, icon-prefixed rounded input fields, full-width custom button, and polished layout matching the reference mockup. Purely visual — no logic changes.

## Critical Decisions
- **Include SignUpView:** Both auth views get the matching redesign in this ticket for consistency.
- **Shared custom components:** Extract reusable `DromosTextField` and `DromosButton` into `AuthComponents.swift`.
- **Brand accent color:** Use `Color.accentColor` (#009B77) for action links, not SwiftUI `.green`.
- **Vertical centering:** GeometryReader + `.frame(minHeight:)` in AuthView for centered content.
- **Button disable ownership:** Callers own `.disabled()` logic; `DromosButton` only handles visual loading state.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Auth/AuthComponents.swift` | CREATE | Shared `DromosTextField` and `DromosButton` components |
| `Dromos/Dromos/Features/Auth/LoginView.swift` | MODIFY | Full UI redesign using shared components |
| `Dromos/Dromos/Features/Auth/SignUpView.swift` | MODIFY | Matching redesign using shared components |
| `Dromos/Dromos/Features/Auth/AuthView.swift` | MODIFY | GeometryReader centering, dark background edge-to-edge |
| `.claude/context/architecture.md` | MODIFY | Added Auth Components to shared components section |

## Context Doc Updates
- `architecture.md` — Added DromosTextField and DromosButton to Key Shared Components section

## Tasks:

- [x] 🟩 **Step 1: Create shared auth field and button styles**
  - [x] 🟩 Create `DromosTextField` — icon-prefixed rounded text field (56pt, systemGray6 bg, systemGray4 border)
  - [x] 🟩 Create `DromosButton` — full-width button (50pt, systemGray2 bg, white text, chevron)
  - [x] 🟩 Place in `AuthComponents.swift` with previews

- [x] 🟩 **Step 2: Redesign LoginView**
  - [x] 🟩 Header: `.title` → `.largeTitle`, spacing 24 → 32
  - [x] 🟩 Replace TextField/SecureField with DromosTextField
  - [x] 🟩 Replace `.borderedProminent` button with DromosButton
  - [x] 🟩 Restyle "Sign up" link: gray question + brand green bold action
  - [x] 🟩 `.textInputAutocapitalization(.never)` replacing deprecated API

- [x] 🟩 **Step 3: Redesign SignUpView**
  - [x] 🟩 Same changes as LoginView (3 DromosTextFields, DromosButton, styled link)

- [x] 🟩 **Step 4: Container & background**
  - [x] 🟩 GeometryReader for vertical centering
  - [x] 🟩 `.background(Color(uiColor: .systemBackground)).ignoresSafeArea()`
  - [x] 🟩 Keyboard dismissal preserved

- [x] 🟩 **Step 5: QA & polish**
  - [x] 🟩 Form validation works correctly
  - [x] 🟩 Error messages display properly
  - [x] 🟩 Brand accent color on action links
  - [x] 🟩 `.buttonStyle(.plain)` for correct text color inheritance
