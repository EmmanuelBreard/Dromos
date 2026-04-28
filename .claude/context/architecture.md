# Architecture Reference

> Last updated: 2026-04-25

## Folder Structure

```
Dromos/Dromos/
├── App/                              # App entry + root navigation
│   ├── DromosApp.swift               # @main entry point
│   ├── RootView.swift                # Auth → Onboarding → Plan → MainTab routing
│   └── MainTabView.swift             # TabView (Home/Calendar/Profile) + PlanService/ProfileService/StravaService owner
│
├── Core/
│   ├── Configuration.swift           # Reads from Secrets.swift (git-ignored)
│   ├── Secrets.swift                 # supabaseURL, supabaseAnonKey (git-ignored)
│   ├── Models/
│   │   ├── TrainingPlan.swift        # TrainingPlan, PlanWeek, PlanSession, Weekday, DayInfo
│   │   ├── User.swift               # User profile + RaceObjective enum
│   │   ├── WorkoutTemplate.swift     # WorkoutTemplate, WorkoutSegment, WorkoutLibrary, FlatSegment, StepSummary
│   │   ├── StravaModels.swift        # StravaActivity, SyncResult (Equatable), SyncResponse
│   │   ├── SessionCompletionStatus.swift # SessionCompletionStatus enum + SessionMatcher (client-side matching engine)
│   │   ├── OnboardingData.swift      # Per-screen onboarding structs
│   │   └── ChatMessage.swift          # ChatMessage (Codable, Identifiable) + ChatResponse edge function DTO
│   └── Services/
│       ├── SupabaseClient.swift      # Singleton client with snake_case encoder/decoder
│       ├── AuthService.swift         # Auth state, sign up/in/out, onboarding/plan status. `isInitializing` flag (true until `.initialSession` resolves) gates RootView splash screen
│       ├── PlanService.swift         # Plan generation (edge function) + fetching (nested query) + session reordering (RPC)
│       ├── ProfileService.swift      # User profile CRUD + onboarding save
│       ├── StravaService.swift       # Strava OAuth (ASWebAuthenticationSession), disconnect, sync, activity fetch
│       ├── WorkoutLibraryService.swift # Bundled JSON library, O(1) template lookup, flattenedSegments(), stepSummaries()
│       └── ChatService.swift          # @MainActor ObservableObject: fetchMessages(), sendMessage(), clearHistory()
│
├── Features/
│   ├── Auth/                         # Login + SignUp views
│   ├── Onboarding/                   # 6-screen onboarding flow
│   ├── Home/                         # Today screen — sport-progress strip + today hero card(s) + week strip (DRO-231)
│   │   ├── HomeView.swift            # Composes the Today screen: SportProgressStrip + state-routed today hero (planned/completed/missed/multi/rest/race/empty) + WeekDayStrip; supports horizontal swipe between days on the today hero (DragGesture + .easeInOut(0.25) transition, animation parity with pill taps — DRO-242); lifecycle: .task / Strava-sync listener / homeReset re-tap (sync + scroll-to-top) / pull-to-refresh
│   │   ├── SportProgressStrip.swift  # 3-column SWIM/BIKE/RUN done-vs-planned per week, accent fill bar capped at 100% (DRO-234)
│   │   ├── TodayPlannedCard.swift    # Planned-state today card: inline `[icon] name - duration` title row + header + rationale + WorkoutShape + WorkoutStepList (DRO-235, title row updated DRO-242)
│   │   ├── TodayCompletedCard.swift  # Completed-state today card: CompletedTag + inline `[icon] name - duration` title row + CoachFeedbackBlock + ActualVsPlannedTable + optional GPS map + planned-workout disclosure (DRO-235, title row updated DRO-242)
│   │   ├── TodayMissedCard.swift     # Missed-state today card: MissedTag + inline `[icon] name - duration` title row dimmed (no rationale/shape/steps/CTA) (DRO-235, title row updated DRO-242)
│   │   ├── ActualVsPlannedTable.swift # Sport-aware 3-col grid (Metric/Actual/Planned) — run / bike (skip power if nil) / swim (DRO-235)
│   │   ├── WorkoutShape.swift        # 56pt-tall horizontal intensity bar wrapper around segment data (DRO-233)
│   │   ├── WorkoutStepList.swift     # Step list with nested RepeatBlock accent left-border + multiplier prefix (DRO-233)
│   │   ├── CoachFeedbackBlock.swift  # Soft accent fill block with feedback / silent-skeleton loading / hidden states; honors accessibilityReduceMotion (DRO-233)
│   │   ├── CompletedTag.swift        # Green ✓ "COMPLETED TODAY" pill (DRO-233)
│   │   ├── MissedTag.swift           # Red ✗ "NOT COMPLETED" pill using Color.errorStrong (DRO-233)
│   │   ├── SessionSequenceBadge.swift # Numbered circle (1/2) for multi-session days (DRO-233)
│   │   ├── EmptyHomeHero.swift       # No-plan empty state: Dromos mark + "Generate your first plan" + CTA (DRO-236)
│   │   ├── WeekDayStrip.swift        # 7-pill week row with PillState (today/completed/planned/missed/rest); pills tappable, today shows green border by default, multi-session pills render multiple SF Symbols side-by-side (DRO-236, extended DRO-242)
│   │   ├── SessionCardView.swift     # Legacy rich session card used by Calendar tab; also hosts restyled RestDayCardView + RaceDayCardView (DRO-236 restyles)
│   │   ├── ActualMetricsView.swift   # Sport-specific metric grid for Calendar's completed cards (legacy; ActualVsPlannedTable is the new equivalent on Home — see DRO-240 for consolidation)
│   │   ├── StravaRouteMapView.swift  # Non-interactive MapKit view rendering GPS route from encoded polyline; stroke now Color.accentColor (was .blue, changed in DRO-235 — affects Calendar too)
│   │   ├── WorkoutStepsView.swift    # Legacy workout step list with intensity dots (Calendar uses this; Home uses the new WorkoutStepList)
│   │   ├── WorkoutGraphView.swift    # Legacy interactive intensity bar chart with tap-to-reveal popovers (Calendar uses this; Home uses the new WorkoutShape)
│   │   └── IntensityColorHelper.swift # Color extensions: Color.intensity(for:isRecovery:), Color.phaseColor(for:), Color.errorStrong (auto-synthesized from ErrorStrong.colorset)
│   ├── Calendar/                     # Single-week paged plan view (formerly Home content)
│   │   ├── CalendarView.swift        # Single-week paged view (TabView .page style) with chevron + swipe nav, per-week Strava completion cache, skeleton loading, edit mode (session reordering)
│   │   └── CalendarWeekHeader.swift  # 2-row header: chevron-flanked semantic title (Current/Last/Next Week or Week N/M) + phase badge & date range inline
│   ├── Plan/                         # Plan generation flow
│   │   └── PlanGenerationView.swift  # Triggered from RootView when user has no plan yet
│   ├── Chat/
│   │   └── ChatView.swift            # Chat UI: message list, bubbles, typing indicator, input bar, welcome state
│   └── Profile/
│       ├── ProfileView.swift         # User profile display/edit + Strava connect/disconnect/sync UI
│       └── WebAuthPresentationContext.swift # ASWebAuthenticationPresentationContextProviding impl
│
└── Resources/
    ├── Assets.xcassets/              # Icons, colors
    └── workout-library.json          # Symlink → ai/context/workout-library.json (strength templates removed from JSON; existing `plan_sessions` rows with `sport='strength'` deleted in Phase 8 — DRO-222. mas_pct renamed to vma_pct — DRO-215)
```

---

## Shared Materializer (DRO-215 — Phase 1)

**File:** `supabase/functions/_shared/materialize-structure.ts`

Pure TypeScript function `materialize(template: WorkoutTemplate) -> SessionStructure` with no runtime dependencies. Importable by:
- Edge Functions (`generate-plan/index.ts`)
- Deno CLI scripts (backfill script at `scripts/backfill-session-structure.ts`)

**Key transforms:**
- `mas_pct` (legacy) → `vma_pct` (canonical) silently at materialisation time
- `duration_minutes` XOR `distance_meters`: when both are present, duration wins
- Swim `pace` tags → `rpe` target (slow/easy→3, medium→6, quick/threshold→7, fast→8, very_quick→9)
- `cadence_rpm` and `cue` preserved verbatim
- `duration_seconds` converted to `duration_minutes` (ceiling)
- Nested repeat segments processed recursively (unlimited depth)

**Tests:** `supabase/functions/_shared/__tests__/materialize-structure.test.ts` (17 tests, Deno test runner)

```
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
- Home (house icon) → `HomeView` (Today screen; receives shared `authService`, `planService`, `profileService`, `stravaService`, plus a `homeReset` binding for tab re-tap)
- Calendar (calendar icon) → `CalendarView` (receives shared `authService`, `planService`, `profileService`, `stravaService`, plus `calendarReset`; fetches activities and manages per-session completion status)
- Profile (person icon) → `ProfileView` (receives shared `profileService` + `stravaService`; chatService is NOT injected)

**Tab reset behavior**: Custom `Binding<AppTab>` (`tabSelection`) wraps the tab selection to detect both tab switches and same-tab re-taps. On navigation to:
- Home: toggles `homeReset` → HomeView triggers a Strava sync, refetches completion + sport totals, and scrolls the outer `ScrollView` to top
- Calendar: toggles `calendarReset` → CalendarView snaps `currentWeekIndex` back to the current week, purges that week's completion cache, and re-fetches Strava completion (re-tap = refresh)

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

**ProfileService ownership**: Created in `MainTabView` and shared between `CalendarView` and `ProfileView`. Calendar tab uses it for athlete metrics (FTP, VMA, CSS) in session card workout details, and to gate Strava activity fetching (`isStravaConnected`).

**StravaService + completion status**: `CalendarView` receives `stravaService` from `MainTabView`. On `.task` and on `calendarReset` toggle (tab re-selection), it calls `loadIfNeeded(weekIndex:plan:)` which fetches activities for the visible date range and runs `SessionMatcher.match()` to compute `[UUID: SessionCompletionStatus]`. Completed session cards show a green left border; missed cards show a red border and 0.5 opacity dimming. Completed sessions suppress edit-mode move arrows.

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
- Library JSON now has 4 top-level arrays: `swim`, `bike`, `run`, `race` (optional) — strength was removed (see DRO-222 for DB cleanup)

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
- Displays `session.notes` (coaching notes from plan) above workout steps when present
- Shows `WorkoutStepsView` for all sessions with a template (except simple swims: 1 segment, no repeats)
- Shows `WorkoutGraphView` for all sessions with a template
- Passes sport + athlete metrics to graph for tap popover formatting
- Swim exception: simple swims (1 segment, no repeats) → show distance only
- **Phase 3 additions:**
  - When `.completed`: actual Strava data (`ActualMetricsView` + `StravaRouteMapView`) is always visible as primary content
  - Planned workout (steps + intensity graph + swim distance) behind a local `@State` disclosure button ("Planned workout" with rotating chevron), default collapsed
  - No parent-controlled expand/collapse — disclosure state is fully local to `SessionCardView`

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

**SessionCardView** — Rich workout card with sport icon, duration, type tag, workout steps, intensity graph; completed cards show actual Strava data first with planned workout behind local disclosure
**ActualMetricsView** — Sport-specific metric grid for expanded completed cards (duration, distance, power/pace/HR)
**StravaRouteMapView** — Non-interactive MapKit view rendering a GPS route from encoded polyline (iOS 17+); includes static `decodePolyline(_:)` for Google-encoded polyline format
**WorkoutStepsView** — Workout step list with intensity-colored dots (Phase 2)
**WorkoutGraphView** — Interactive horizontal intensity bar chart with tap-to-reveal popovers (Phase 2-3)
**RestDayCardView** — Bed icon + "Rest Day" label
**RaceDayCardView** — Trophy icon + "Race Day" label with optional race objective; when given a `template` + `notes`, renders structured race legs (swim/T1/bike/T2/run) with cue text and durations. Race sessions (`sport='race'`) in CalendarView are routed here instead of SessionCardView.

**Auth Components** (`AuthComponents.swift` in Features/Auth/):
- `DromosTextField` — Styled text field with SF Symbol icon, optional secure input, and adaptive gray background
- `DromosButton` — Full-width primary action button with loading state and trailing chevron

**Color Extensions:**
- `Color.phaseColor(for:)` — Base=blue, Build=orange, Peak=red, Taper=purple, Recovery=green
- `Color.errorStrong` — solid red (light `#FF3B30` / dark `#FF453A`); auto-synthesized from `Assets.xcassets/ErrorStrong.colorset` (DRO-233). Used for missed-state tags + week-strip pill states. Companion to existing `Color.errorSubtle` (alpha fill).
- `PlanSession.sportColor` — swim=cyan, bike=green, run=orange, strength=purple, race=yellow
- `PlanSession.typeColor` — Easy=green, Tempo=orange, Intervals=red, Race=yellow
- `PlanSession.sportEmoji` — 🏊‍♂️, 🚴‍♂️, 🏃‍♂️, 💪, 🏁
- `PlanSession.sportIcon` — figure.pool.swim, bicycle, figure.run, figure.strengthtraining.traditional, flag.checkered
- `Color.intensity(for:isRecovery:)` — Green→yellow→orange→red gradient based on intensity % (Phase 2)

**Model Extensions:**
- `Weekday` enum with `fullName`, `abbreviation`, date calculation
- `PlanWeek` — `totalMinutes`, `sessionsByDay`, `restDaySet`
- `TrainingPlan` — `currentWeekIndex()`, `daysForWeek()`
- `User` — `formattedCSS`, `formattedTimeObjective`

---

## Edge Functions

| Function | Location | Purpose |
|----------|----------|---------|
| `generate-plan` | `supabase/functions/generate-plan/` | 3-step LLM pipeline for training plan generation |
| `strava-auth` | `supabase/functions/strava-auth/` | POST: OAuth code exchange + token storage. DELETE: token revocation + full cleanup (strava_activities + strava_connections). JWT validated via `auth.getUser()`. |
| `strava-sync` | `supabase/functions/strava-sync/` | POST: Paginated Strava activity fetch (up to 2000), token auto-refresh, upsert into `strava_activities`, then fetch laps + streams per activity (non-fatal). Laps stored in `strava_activity_laps`, streams as JSONB on activity row. JWT validated via `auth.getUser()`. |
| `session-feedback` | `supabase/functions/session-feedback/` | POST: Auth → fetch session/activity/profile/week context → OpenAI gpt-4.1 → write feedback to plan_sessions. JWT validated via `auth.getUser()`. |
| `chat-adjust` | `supabase/functions/chat-adjust/` | POST: Auth → history fetch → OpenAI gpt-4o → DB write (both user & assistant messages). JWT validated via `auth.getUser()`. Returns `{ response_text, status, constraint_summary? }`. |

**Deployment:** All functions are deployed with `--no-verify-jwt` (gateway JWT check disabled — each function validates JWTs itself via `auth.getUser()`). Use `scripts/deploy-functions.sh` to deploy one or all functions with the correct flags.

See `ai-pipeline.md` for `generate-plan` pipeline documentation.

## Strava Integration

**Auth flow**: `StravaService.startOAuth()` → `ASWebAuthenticationSession` (ephemeral, `prefersEphemeralWebBrowserSession = true`) → `/oauth/authorize` (web endpoint, NOT `/oauth/mobile/authorize` which opens native Strava app and breaks callback interception) → callback → `exchangeCode()` → `strava-auth` Edge Function. `isConnecting` is set to `true` before the browser launches and cleared via `defer` inside `exchangeCode`.

**Disconnect flow**: `StravaService.disconnect()` → `strava-auth` DELETE → revokes token with Strava, deletes `strava_activities` rows, deletes `strava_connections` row, nulls `users.strava_athlete_id`.

**Sync flow**: `StravaService.syncActivities()` → `strava-sync` POST → token refresh if needed → paginated Strava API fetch → upsert `strava_activities` → fetch laps + streams per activity (sequential, non-fatal) → update `last_sync_at`.

**Activity storage**: `strava_activities` table. Synced from `StravaActivity` model (camelCase, auto-decoded from snake_case via global decoder).
