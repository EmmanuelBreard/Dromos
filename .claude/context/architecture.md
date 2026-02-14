# Architecture Reference

> Last updated: 2026-02-14

## Folder Structure

```
Dromos/Dromos/
├── App/                              # App entry + root navigation
│   ├── DromosApp.swift               # @main entry point
│   ├── RootView.swift                # Auth → Onboarding → Plan → MainTab routing
│   └── MainTabView.swift             # TabView (Home/Calendar/Profile) + PlanService owner
│
├── Core/
│   ├── Configuration.swift           # Reads from Secrets.swift (git-ignored)
│   ├── Secrets.swift                 # supabaseURL, supabaseAnonKey (git-ignored)
│   ├── Models/
│   │   ├── TrainingPlan.swift        # TrainingPlan, PlanWeek, PlanSession, Weekday, DayInfo
│   │   ├── User.swift               # User profile + RaceObjective enum
│   │   ├── WorkoutTemplate.swift     # WorkoutTemplate, WorkoutSegment, WorkoutLibrary
│   │   └── OnboardingData.swift      # Per-screen onboarding structs
│   └── Services/
│       ├── SupabaseClient.swift      # Singleton client with snake_case encoder/decoder
│       ├── AuthService.swift         # Auth state, sign up/in/out, onboarding/plan status
│       ├── PlanService.swift         # Plan generation (edge function) + fetching (nested query)
│       ├── ProfileService.swift      # User profile CRUD + onboarding save
│       └── WorkoutLibraryService.swift # Bundled JSON library, O(1) template lookup
│
├── Features/
│   ├── Auth/                         # Login + SignUp views
│   ├── Onboarding/                   # 5-screen onboarding flow
│   ├── Home/                         # Multi-week rolling dashboard
│   │   ├── HomeView.swift            # Rolling week view with auto-scroll to today
│   │   └── SessionCardView.swift     # Session card + RestDayCardView + RaceDayCardView
│   ├── Plan/                         # Week-by-week calendar navigator
│   │   ├── CalendarPlanView.swift    # Plan tab main view
│   │   ├── WeekHeaderView.swift      # Week nav + phase badge
│   │   └── DaySessionRow.swift       # Day row with sessions
│   └── Profile/
│       └── ProfileView.swift         # User profile display/edit
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
- Home (house icon) → `HomeView`
- Calendar (calendar icon) → `CalendarPlanView`
- Profile (person icon) → `ProfileView`

**Local navigation**: `NavigationStack` inside individual tab views.

---

## State Management

| Pattern | Usage |
|---------|-------|
| `@State` | Local view state (form fields, toggles) |
| `@StateObject` | View-owned service lifetime (`PlanService` in `MainTabView`) |
| `@ObservedObject` | Service passed down to child views |
| `@Published` | Observable properties in services |
| `@MainActor` | All services are `@MainActor final class` |

No `@EnvironmentObject` — dependencies are passed as parameters.

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

**SessionCardView** — Rich workout card with sport icon, duration, type tag, swim distance
**RestDayCardView** — Bed icon + "Rest Day" label
**RaceDayCardView** — Trophy icon + "Race Day" label with optional race objective
**WeekHeaderView** — Week navigation arrows + phase badge + date range
**DaySessionRow** — Day header + session list (reused in Home and Plan tabs)

**Color Extensions:**
- `Color.phaseColor(for:)` — Base=blue, Build=orange, Peak=red, Taper=purple, Recovery=green
- `PlanSession.sportColor` — swim=cyan, bike=green, run=orange

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
