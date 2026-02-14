# DRO-43: Calendar Tab — Lightweight Overview of All Plan Weeks

**Overall Progress:** `100%`

## TLDR
Replace the placeholder Calendar tab with a week-by-week training plan overview. Users navigate between weeks via arrows, see sessions listed per day (sport icon + derived name + duration), rest days with a bed icon, and a week header showing week number, phase badge, and date range. Auto-opens to the current week.

## Critical Decisions
- **Derived workout names:** No human-readable name in workout library. Display names derived from session data: type + sport (e.g., "Easy Swim", "Tempo Run", "Intervals Bike"). Duration shown separately.
- **Duration only (no distance):** `plan_sessions` only stores `duration_minutes`. Distance display deferred — no schema change.
- **All-at-once fetch:** Single nested Supabase query fetches all weeks + sessions (~100 rows for 17 weeks). Enables instant week navigation with no per-week loading latency.
- **Current week on launch:** Calendar auto-navigates to the week containing today's date. Falls back to Week 1 if before plan start, last week if after plan end.
- **Rest day rows shown:** Days in `rest_days` array display a row with bed icon + "Rest day" label, matching the Stamina design reference.
- **rest_days normalization:** DB stores abbreviated names (`"Mon"`) while `plan_sessions.day` uses full names (`"Monday"`). Model layer normalizes this.

## Design Reference
`Calendar page.png` in project root — Stamina-style plan view.

## Files

| Action | Path |
|--------|------|
| **Create** | `Dromos/Dromos/Core/Models/TrainingPlan.swift` |
| **Create** | `Dromos/Dromos/Features/Plan/CalendarPlanView.swift` |
| **Create** | `Dromos/Dromos/Features/Plan/WeekHeaderView.swift` |
| **Create** | `Dromos/Dromos/Features/Plan/DaySessionRow.swift` |
| **Modify** | `Dromos/Dromos/Core/Services/PlanService.swift` |
| **Modify** | `Dromos/Dromos/App/MainTabView.swift` |
| **Delete** | `Dromos/Dromos/Features/Calendar/CalendarView.swift` |

## Tasks

- [x] 🟩 **Step 1: Create Swift data models**
  - [x] 🟩 Create `TrainingPlan.swift` in `Core/Models/` with three `Codable`, `Identifiable` structs:
    - `TrainingPlan`: `id` (UUID), `userId` (UUID), `status` (String), `raceDate` (String?), `raceObjective` (String?), `totalWeeks` (Int), `startDate` (String), `planWeeks` ([PlanWeek])
    - `PlanWeek`: `id` (UUID), `planId` (UUID), `weekNumber` (Int), `phase` (String), `isRecovery` (Bool), `restDays` ([String]), `notes` (String?), `startDate` (String), `planSessions` ([PlanSession])
    - `PlanSession`: `id` (UUID), `weekId` (UUID), `day` (String), `sport` (String), `type` (String), `templateId` (String), `durationMinutes` (Int), `isBrick` (Bool), `notes` (String?), `orderInDay` (Int)
  - [x] 🟩 Add `Weekday` enum with `allCases` ordered Monday→Sunday, `init(from abbreviation:)` (handles `"Mon"` → `.monday`) and `init(from fullName:)` (handles `"Monday"` → `.monday`). Include `fullName`, `abbreviation`, and `date(relativeTo weekStartDate:)` computed properties.
  - [x] 🟩 Add computed properties on `PlanSession`:
    - `displayName: String` → derives from `type` + `sport`, e.g. "Easy Swim", "Tempo Run"
    - `sportIcon: String` → SF Symbol name: swim → `"figure.pool.swim"`, bike → `"bicycle"`, run → `"figure.run"`
    - `formattedDuration: String` → e.g. "60 min", "1h 30 min"
  - [x] 🟩 Add computed property on `PlanWeek`:
    - `totalMinutes: Int` → sum of all `planSessions.durationMinutes`
    - `sessionsByDay: [Weekday: [PlanSession]]` → groups sessions by day, sorted by `orderInDay`
    - `restDaySet: Set<Weekday>` → normalized from abbreviated `restDays` array

- [x] 🟩 **Step 2: Extend PlanService with data fetching**
  - [x] 🟩 Add `@Published private(set) var trainingPlan: TrainingPlan?` to PlanService
  - [x] 🟩 Add `@Published private(set) var isLoadingPlan: Bool = false`
  - [x] 🟩 Add `fetchFullPlan()` method:
    - Uses `client.from("training_plans").select("*, plan_weeks(*, plan_sessions(*))").eq("user_id", value: userId).eq("status", value: "active").single().execute().value`
    - Requires `userId` parameter (UUID) — get from AuthService's `currentUserId`
    - Sets `trainingPlan` on success, sets `errorMessage` on failure
    - Sort `planWeeks` by `weekNumber` client-side after decode (PostgREST nested selects don't guarantee order)
    - Sort each week's `planSessions` by day order then `orderInDay`
  - [x] 🟩 Add `clearPlan()` method — sets `trainingPlan = nil` (for sign-out cleanup)

- [x] 🟩 **Step 3: Create WeekHeaderView**
  - [x] 🟩 Create `WeekHeaderView.swift` in `Features/Plan/`
  - [x] 🟩 Props: `weekNumber: Int`, `totalWeeks: Int`, `phase: String`, `weekStartDate: Date`, `onPrevious: () -> Void`, `onNext: () -> Void`, `canGoPrevious: Bool`, `canGoNext: Bool`
  - [x] 🟩 Layout (matching design reference):
    - Row 1: `<` arrow | "Week N /total" (centered) | `>` arrow
    - Row 1 subtitle: Phase badge (e.g., "Base phase") with color-coded icon
    - Row 2: Date range label (e.g., "FEB 2026" or "JAN / FEB" if week spans months)
  - [x] 🟩 Phase badge colors: Base → `.blue`, Build → `.orange`, Peak → `.red`, Taper → `.purple`, Recovery → `.green`
  - [x] 🟩 Disable prev arrow on Week 1, disable next arrow on last week

- [x] 🟩 **Step 4: Create DaySessionRow**
  - [x] 🟩 Create `DaySessionRow.swift` in `Features/Plan/`
  - [x] 🟩 **Session variant** — for each `PlanSession` in a day:
    - Sport icon (colored: swim = `.cyan`, bike = `.green`, run = `.orange`) + `displayName` + `formattedDuration`
    - If `isBrick`, show a brick indicator (e.g., small link icon)
  - [x] 🟩 **Rest day variant** — for days in `restDaySet`:
    - Bed icon (`"bed.double"`) + "Rest day" label in secondary color
  - [x] 🟩 **Day header** — shown once per day group:
    - Day abbreviation + calendar date on the left (e.g., "TUE" on one line, "27" below). Derived from `PlanWeek.startDate` + day offset.

- [x] 🟩 **Step 5: Create CalendarPlanView**
  - [x] 🟩 Create `CalendarPlanView.swift` in `Features/Plan/`
  - [x] 🟩 Owns `@StateObject private var planService = PlanService()` (separate instance from PlanGenerationView)
  - [x] 🟩 Takes `authService: AuthService` as `@ObservedObject` (to get `currentUserId`)
  - [x] 🟩 `@State private var currentWeekIndex: Int = 0` — tracks which week is displayed
  - [x] 🟩 On `.task`: call `planService.fetchFullPlan(userId:)`, then compute `currentWeekIndex` from today's date vs. plan week start dates
  - [x] 🟩 **Loading state**: `ProgressView` while `isLoadingPlan`
  - [x] 🟩 **Error state**: error message + retry button (same pattern as PlanGenerationView)
  - [x] 🟩 **Content state**:
    - `WeekHeaderView` at top with prev/next bound to `currentWeekIndex`
    - `ScrollView` with `LazyVStack` iterating days in the current week (Monday→Sunday or partial):
      - For each day in the week: compute the calendar date from `week.startDate`
      - If day is in `restDaySet` and has no sessions → rest day row
      - If day has sessions → day header + `DaySessionRow` for each session
      - Skip days before `planStartDate` for partial Week 1
    - Wrap in `NavigationStack` with `.navigationTitle("Plan")`
  - [x] 🟩 Handle partial Week 1: if week's `startDate` is not a Monday, only show days from `startDate` to Sunday

- [x] 🟩 **Step 6: Wire into MainTabView**
  - [x] 🟩 Update `MainTabView.swift`: replace `CalendarView()` with `CalendarPlanView(authService: authService)`
  - [x] 🟩 Delete `Dromos/Dromos/Features/Calendar/CalendarView.swift` (and remove the Calendar folder if empty)







