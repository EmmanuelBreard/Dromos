# DRO-44: Home Tab — Detailed Current Week View

**Overall Progress:** `100%`

## TLDR
Replace the placeholder Home tab with a rich, day-by-day view of the current week's training sessions. Day sections show relative labels ("Today", "Tomorrow") with full dates, auto-scrolling to today. Session cards display sport icon, workout name, duration, type tag, and swim distance (from bundled workout library). Shares plan data with Calendar tab via lifted PlanService.

## Critical Decisions
- **Workout library access:** Bundle `workout-library.json` as an app resource. Instant lookup, no network call. ~2500 lines, negligible app size impact.
- **Coach notes:** Skipped for MVP — workout library has no description fields. Will add in a future issue.
- **Estimated metrics:** Swim distance only (sum `distance_meters` from library segments). No distance for bike/run — power-to-speed and VMA-to-pace conversions deferred.
- **Type tags:** Single chip per session from `type` field (e.g., "EASY", "TEMPO", "INTERVALS").
- **Day labels:** Relative for Today/Tomorrow, then full date ("Wednesday 4 February") for other days.
- **Data sharing:** Lift PlanService from CalendarPlanView to MainTabView. Single fetch, both tabs share data.

## File Impact

| Action | File |
|--------|------|
| **Create** | `Dromos/Dromos/Core/Models/WorkoutTemplate.swift` |
| **Create** | `Dromos/Dromos/Core/Services/WorkoutLibraryService.swift` |
| **Copy** | `Dromos/Dromos/Resources/workout-library.json` |
| **Rewrite** | `Dromos/Dromos/Features/Home/HomeView.swift` |
| **Create** | `Dromos/Dromos/Features/Home/SessionCardView.swift` |
| **Modify** | `Dromos/Dromos/App/MainTabView.swift` |
| **Modify** | `Dromos/Dromos/Features/Plan/CalendarPlanView.swift` |

## Tasks

- [x] ✅ **Step 1: Bundle workout library and create lookup service**
  - [x] ✅ Copy `supabase/functions/generate-plan/context/workout-library.json` into `Dromos/Dromos/Resources/` and add to Xcode target
  - [x] ✅ Create `WorkoutTemplate.swift` in `Core/Models/` with `Codable` structs:
    - `WorkoutTemplate`: `templateId` (String), `segments` ([WorkoutSegment])
    - `WorkoutSegment`: `label` (String), `durationMinutes` (Int?), `distanceMeters` (Int?), `pace` (String?), `ftpPct` (Int?), `masPct` (Int?), `cadenceRpm` (Int?), `drill` (String?), `cue` (String?), `restSeconds` (Int?), `repeats` (Int?), `segments` ([WorkoutSegment]?) — recursive for repeat blocks
  - [x] ✅ Create `WorkoutLibraryService.swift` in `Core/Services/`:
    - Loads JSON from app bundle on init, parses into `[String: WorkoutTemplate]` dictionary keyed by `templateId`
    - `func template(for templateId: String) -> WorkoutTemplate?` — lookup
    - `func swimDistance(for templateId: String) -> Int?` — walks segments recursively, sums `distanceMeters` (multiplied by `repeats` for repeat blocks). Returns total meters. Returns `nil` for non-swim templates.
    - Singleton or injected — prefer singleton since data is static and read-only

- [x] ✅ **Step 2: Lift PlanService to MainTabView level**
  - [x] ✅ In `MainTabView.swift`: add `@StateObject private var planService = PlanService()` and trigger `planService.fetchFullPlan(userId:)` in `.task`
  - [x] ✅ Pass `planService` as parameter to both `HomeView` and `CalendarPlanView`
  - [x] ✅ In `CalendarPlanView.swift`: change `@StateObject private var planService = PlanService()` → `@ObservedObject var planService: PlanService`. Remove the `.task { await loadPlan() }` that fetches the plan (MainTabView now owns this). Keep `currentWeekIndex` calculation — move it to `.onAppear` or `.onChange(of: planService.trainingPlan)` so it recalculates when data arrives.
  - [x] ✅ `HomeView` signature becomes: `@ObservedObject var authService: AuthService`, `@ObservedObject var planService: PlanService`

- [x] ✅ **Step 3: Create SessionCardView**
  - [x] ✅ Create `SessionCardView.swift` in `Features/Home/`
  - [x] ✅ Props: `session: PlanSession`, `swimDistance: Int?` (pre-computed by parent)
  - [x] ✅ Layout (card style with rounded corners and subtle background):
    - **Row 1**: Sport icon (colored, reuse `sportColor` extension) + `formattedDuration` + `displayName` (e.g., "1 hr Easy Swim")
    - **Row 2**: Type tag chip — uppercased `session.type` in a capsule/badge (e.g., "EASY"). Use sport color with low opacity background.
    - **Row 3** (swim only): If `swimDistance != nil`, show "Est. Distance" with formatted value (e.g., "550 m" or "1.5 km" if ≥ 1000m)
    - **Brick indicator**: If `session.isBrick`, show link icon or "BRICK" badge
  - [x] ✅ Rest day card variant: separate simple view with bed icon + "Rest Day" label (or embed in HomeView directly)

- [x] ✅ **Step 4: Rewrite HomeView**
  - [x] ✅ Replace placeholder content with full implementation
  - [x] ✅ **Week header** (simplified, no navigation arrows): "Week N — Phase" with phase color badge. Reuse `Color.phaseColor(for:)` from WeekHeaderView.
  - [x] ✅ **Current week calculation**: Same logic as CalendarPlanView's `calculateCurrentWeekIndex` — find week containing today, fallback to W1 (before plan) or last week (after plan)
  - [x] ✅ **Day sections**: Iterate days in current week (Monday→Sunday or partial W1). For each day:
    - **Section header**: Relative label + full date. "Today Saturday 1 February", "Tomorrow Sunday 2 February", then "Monday 3 February" etc. Use `Calendar.current.isDateInToday/isDateInTomorrow` for relative prefix.
    - **Content**: `SessionCardView` for each session in that day, or rest day card if in `restDaySet` with no sessions
    - **Partial W1**: Skip days before plan start date (reuse logic from CalendarPlanView's `daysForWeek`)
  - [x] ✅ **Auto-scroll to today**: Use `ScrollViewReader` + `.scrollTo(todayId)` on appear. Assign stable IDs to day sections.
  - [x] ✅ **States**: Loading (ProgressView), Error (message + retry), Empty (no plan message), Content
  - [x] ✅ Wrap in `NavigationStack` with `.navigationTitle("Home")`
  - [x] ✅ Add `#Preview` with mock data

- [x] ✅ **Step 5: Wire into MainTabView and verify**
  - [x] ✅ Update `MainTabView` to pass `authService` and `planService` to `HomeView`
  - [x] ✅ Ensure Home tab is the default/first tab (already is)
  - [x] ✅ Verify CalendarPlanView still works correctly with shared PlanService
  - [x] ✅ Verify sign-out clears plan data via `planService.clearPlan()`
