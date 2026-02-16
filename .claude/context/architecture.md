# Architecture Reference

> Last updated: 2026-02-14

## Folder Structure

```
Dromos/Dromos/
├── App/                              # App entry + root navigation
│   ├── DromosApp.swift               # @main entry point
│   ├── RootView.swift                # Auth → Onboarding → Plan → MainTab routing
│   └── MainTabView.swift             # TabView (Home/Calendar/Profile) + PlanService/ProfileService owner
│
├── Core/
│   ├── Configuration.swift           # Reads from Secrets.swift (git-ignored)
│   ├── Secrets.swift                 # supabaseURL, supabaseAnonKey (git-ignored)
│   ├── Models/
│   │   ├── TrainingPlan.swift        # TrainingPlan, PlanWeek, PlanSession, Weekday, DayInfo
│   │   ├── User.swift               # User profile + RaceObjective enum
│   │   ├── WorkoutTemplate.swift     # WorkoutTemplate, WorkoutSegment, WorkoutLibrary, FlatSegment, StepSummary
│   │   └── OnboardingData.swift      # Per-screen onboarding structs
│   └── Services/
│       ├── SupabaseClient.swift      # Singleton client with snake_case encoder/decoder
│       ├── AuthService.swift         # Auth state, sign up/in/out, onboarding/plan status
│       ├── PlanService.swift         # Plan generation (edge function) + fetching (nested query)
│       ├── ProfileService.swift      # User profile CRUD + onboarding save
│       └── WorkoutLibraryService.swift # Bundled JSON library, O(1) template lookup, flattenedSegments(), stepSummaries()
│
├── Features/
│   ├── Auth/                         # Login + SignUp views
│   ├── Onboarding/                   # 7-screen onboarding flow
│   ├── Home/                         # Multi-week rolling dashboard
│   │   ├── HomeView.swift            # Rolling week view with auto-scroll to today
│   │   ├── SessionCardView.swift     # Rich session card + RestDayCardView + RaceDayCardView
│   │   ├── WorkoutStepsView.swift    # Workout step list with intensity dots (Phase 2)
│   │   ├── WorkoutGraphView.swift    # Interactive intensity bar chart with tap-to-reveal popovers (Phase 2-3)
│   │   └── IntensityColorHelper.swift # Shared intensity color gradient function (Phase 2)
│   ├── Plan/                         # Week-by-week calendar navigator
│   │   ├── CalendarPlanView.swift    # Plan tab main view
│   │   ├── WeekHeaderView.swift      # Week nav + phase badge
│   │   └── DaySessionRow.swift       # Day row with sessions
│   └── Profile/
│       └── ProfileView.swift         # User profile display/edit (receives shared ProfileService)
│
└── Resources/
    ├── Assets.xcassets/              # Icons, colors
    └── workout-library.json          # Symlink → ai/context/workout-library.json
```

---

## Navigation

**Root routing** (`RootView.swift`): Conditional `Group` based on auth state:
```
Not authenticated → AuthView
Authenticated, no onboarding → OnboardingFlowView
Authenticated, no plan → PlanGenerationView
Authenticated + plan → MainTabView
```

**Tab navigation** (`MainTabView.swift`): `TabView` with iOS 18+ `Tab` syntax:
- Home (house icon) → `HomeView` (receives shared `profileService`)
- Calendar (calendar icon) → `CalendarPlanView`
- Profile (person icon) → `ProfileView` (receives shared `profileService`)

**Tab reset behavior**: Custom `Binding<AppTab>` (`tabSelection`) wraps the tab selection to detect both tab switches and same-tab re-taps. On navigation to Home or Calendar:
- Home: toggles `homeScrollReset` → HomeView scrolls to today's day section and resets progressive disclosure
- Calendar: toggles `calendarReset` → CalendarPlanView resets `currentWeekIndex` to the week containing today

**Local navigation**: `NavigationStack` inside individual tab views.

---

## State Management

| Pattern | Usage |
|---------|-------|
| `@State` | Local view state (form fields, toggles) |
| `@StateObject` | View-owned service lifetime (`PlanService`, `ProfileService` in `MainTabView`) |
| `@ObservedObject` | Service passed down to child views |
| `@Published` | Observable properties in services |
| `@MainActor` | All services are `@MainActor final class` |

No `@EnvironmentObject` — dependencies are passed as parameters.

**ProfileService ownership**: Created in `MainTabView` and shared between `HomeView` and `ProfileView`. Home tab uses it for athlete metrics (FTP, VMA, CSS) in session card workout details.

---

## Service Layer Pattern

All services follow:
```swift
@MainActor final class XxxService: ObservableObject {
    private let client = SupabaseClientProvider.client
    @Published var isLoading = false
    @Published var errorMessage: String?

    func doSomething() async { ... }
}
```

**Supabase client** (`SupabaseClient.swift`): Singleton enum `SupabaseClientProvider` with:
- Custom JSON encoder/decoder (snake_case <-> camelCase)
- 180-second URLSession timeout (for plan generation ~140s)

**Data loading**: Views use `.task { }` (fires on appear, cancels on disappear) and `.onChange(of:)` for reactive updates.

**Error display**: Services expose `@Published errorMessage: String?`, views conditionally show error UI.

---

## Workout Library

**WorkoutLibraryService** (`WorkoutLibraryService.swift`):
- Singleton service loading bundled `workout-library.json`
- O(1) template lookup by `templateId`
- `swimDistance(for:)` — Recursive distance calculation for swim templates
- `flattenedSegments(for:)` — Returns `[FlatSegment]` for graph rendering (expands repeats)
- `stepSummaries(for:sport:ftp:vma:css:)` — Returns `[StepSummary]` for text display (collapses repeats)

**FlatSegment** (`WorkoutTemplate.swift`):
- Identifiable struct for graph rendering
- Fields: `label`, `durationMinutes`, `intensityPct`, `distanceMeters`, `pace`, `isRecovery`
- Used by `WorkoutGraphView` for intensity bar chart visualization

**StepSummary** (`WorkoutTemplate.swift`):
- Identifiable struct for step-by-step text display
- Fields: `text`, `intensityPct`, `isRepeatBlock`
- Used by `WorkoutStepsView` for workout detail cards with intensity dots

---

## Phase 2-3: Workout Visualization Components

**IntensityColorHelper** (`IntensityColorHelper.swift`):
- Color extension: `Color.intensity(for:isRecovery:)`
- Maps intensity percentage (50-120) to HSL gradient (green→yellow→orange→red)
- Used consistently across step dots and graph bars for visual coherence
- Recovery segments always shown in green

**WorkoutStepsView** (`WorkoutStepsView.swift`):
- Compact vertical list of workout steps
- Each step: colored intensity dot + formatted text (sport-specific metrics)
- Examples: "15' warmup - 120 W", "3× (6' work - 260 W + 4' recovery)"

**WorkoutGraphView** (`WorkoutGraphView.swift`):
- Interactive horizontal bar chart with GeometryReader + ZStack
- Bar width = proportional to segment duration
- Bar height = normalized intensity (30%-100% of graph height)
- Bar color = intensity-based gradient (via `Color.intensity(for:isRecovery:)`)
- Time axis below with adaptive intervals (15/30/60 min), hour formatting for 60min+ labels, overlap prevention for final duration tick
- Fixed heights: 60pt graph, 20pt axis
- **Phase 3 additions:**
  - Tap any bar to reveal custom tooltip-style popover with segment details
  - Popover shows sport-specific metrics:
    - Bike: "15 min warmup — 156 W"
    - Run: "10 min tempo — 12.0 km/h (5:00/km)"
    - Swim: "100m — medium pace"
  - Tap same bar or tap outside to dismiss
  - Smooth `.easeInOut` animation on show/dismiss
  - Receives `sport`, `ftp`, `vma` for metric formatting

**SessionCardView updates** (`SessionCardView.swift`):
- Now accepts: `template: WorkoutTemplate?`, `ftp: Int?`, `vma: Double?`, `css: Int?`
- Layout: sport emoji (🏊‍♂️🚴‍♂️🏃‍♂️) + name + duration + type badge (top-right, color by type: Easy=green, Tempo=orange, Intervals=red)
- Shows `WorkoutStepsView` for all sessions with a template (except simple swims: 1 segment, no repeats)
- Shows `WorkoutGraphView` for all sessions with a template
- Passes sport + athlete metrics to graph for tap popover formatting
- Swim exception: simple swims (1 segment, no repeats) → show distance only

---

## Naming Conventions

| Category | Convention | Example |
|----------|-----------|---------|
| Files | PascalCase | `HomeView.swift`, `AuthService.swift` |
| Types | PascalCase | `TrainingPlan`, `PlanSession` |
| Functions | camelCase | `fetchFullPlan()`, `checkOnboardingStatus()` |
| Properties | camelCase | `isLoading`, `errorMessage` |
| DB columns | snake_case | `user_id`, `plan_weeks` |
| Swift properties | camelCase (auto-converted by decoder) | `userId` |
| Views | `*View` suffix | `HomeView`, `SessionCardView` |
| Services | `*Service` suffix | `AuthService`, `PlanService` |

---

## Key Shared Components

**SessionCardView** — Rich workout card with sport icon, duration, type tag, workout steps, intensity graph
**WorkoutStepsView** — Workout step list with intensity-colored dots (Phase 2)
**WorkoutGraphView** — Interactive horizontal intensity bar chart with tap-to-reveal popovers (Phase 2-3)
**RestDayCardView** — Bed icon + "Rest Day" label
**RaceDayCardView** — Trophy icon + "Race Day" label with optional race objective
**WeekHeaderView** — Week navigation arrows + phase badge + date range
**DaySessionRow** — Day header + session list (reused in Home and Plan tabs)

**Color Extensions:**
- `Color.phaseColor(for:)` — Base=blue, Build=orange, Peak=red, Taper=purple, Recovery=green
- `PlanSession.sportColor` — swim=cyan, bike=green, run=orange
- `PlanSession.typeColor` — Easy=green, Tempo=orange, Intervals=red
- `PlanSession.sportEmoji` — 🏊‍♂️, 🚴‍♂️, 🏃‍♂️
- `Color.intensity(for:isRecovery:)` — Green→yellow→orange→red gradient based on intensity % (Phase 2)

**Model Extensions:**
- `Weekday` enum with `fullName`, `abbreviation`, date calculation
- `PlanWeek` — `totalMinutes`, `sessionsByDay`, `restDaySet`
- `TrainingPlan` — `currentWeekIndex()`, `daysForWeek()`
- `User` — `age`, `formattedCSS`, `formattedTimeObjective`

---

## Edge Functions

| Function | Location | Purpose |
|----------|----------|---------|
| `generate-plan` | `supabase/functions/generate-plan/` | 3-step LLM pipeline for training plan generation |

See `ai-pipeline.md` for detailed pipeline documentation.
