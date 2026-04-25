# Feature Implementation Plan — DRO-209

**Overall Progress:** `100%`

## TLDR
Show `RestDayCardView` (and the `restDayRow` in the calendar) whenever a day has no scheduled sessions — not only when the plan explicitly marks it as a rest day.

## Critical Decisions
- **Don't touch `isRestDay` model field** — changing `DayInfo.isRestDay` semantics would affect serialization/other callers. Fix at the view layer only.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Home/HomeView.swift` | MODIFY | Line 223: relax condition to `sessions.isEmpty` only |
| `Dromos/Dromos/Features/Plan/DaySessionRow.swift` | MODIFY | Line 46: relax condition to `sessions.isEmpty` only |

## Context Doc Updates
None — no new files, tables, or architectural patterns introduced.

## Tasks

- [x] 🟩 **Step 1: Fix `HomeView.swift`**
  - [x] 🟩 Change line 223 from `if dayInfo.isRestDay && dayInfo.sessions.isEmpty` → `if dayInfo.sessions.isEmpty`

- [x] 🟩 **Step 2: Fix `DaySessionRow.swift`**
  - [x] 🟩 Change line 46 from `if isRestDay && sessions.isEmpty` → `if sessions.isEmpty`
