# DRO-145: Session Completion Status — Visual Adherence on Training Cards

**Overall Progress:** `33%`

## TLDR

Show athletes whether each planned session was completed, missed, or still planned — directly on session cards in the Home tab. Status is computed dynamically by matching `PlanSession` records against synced `StravaActivity` data (same sport + same date). Completed sessions expand on tap to reveal actual Strava metrics and a GPS route map rendered from the activity's polyline.

## Critical Decisions

- **Client-side matching** — Matching runs on iOS, not server-side. HomeView fetches activities for the visible date range and builds a `[PlanSession.ID: StravaActivity]` dictionary. No new edge function or RPC needed.
- **Status is never persisted** — Computed at render time from date + Strava match. Moving a missed session to a future date automatically makes it planned again.
- **Planned info always preserved** — Collapsed card keeps all original content (steps, graph, duration). Actual metrics only appear in the expanded section.
- **No calories/elevation** — Dropped from scope. Expanded metrics show: actual duration, actual distance, plus sport-specific (power/pace/HR).
- **Manual Strava entries excluded** — `isManual == true` activities are filtered out of matching.
- **Home tab only** — Calendar tab untouched for now.
- **Polyline from list endpoint** — `summary_polyline` is free from Strava's `/athlete/activities` response. No extra API calls.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `supabase/migrations/YYYYMMDD_add_summary_polyline.sql` | CREATE | Add `summary_polyline TEXT` column to `strava_activities` |
| `supabase/functions/strava-sync/index.ts` | MODIFY | Extend `StravaApiActivity` interface with `map` field, pass `summary_polyline` in upsert rows |
| `Dromos/Core/Models/StravaModels.swift` | MODIFY | Add `summaryPolyline: String?` to `StravaActivity` |
| `Dromos/Core/Models/SessionCompletionStatus.swift` | CREATE | `SessionCompletionStatus` enum + `SessionMatcher` struct |
| `Dromos/Features/Home/HomeView.swift` | MODIFY | Accept `stravaService`, fetch activities on appear, build match dictionary, pass status to cards, disable edit arrows for completed |
| `Dromos/Features/Home/SessionCardView.swift` | MODIFY | Accept `completionStatus` param, render green/red left border, dimming for missed, expand/collapse for completed |
| `Dromos/Features/Home/ActualMetricsView.swift` | CREATE | Sport-specific metric grid for expanded completed cards |
| `Dromos/Features/Home/StravaRouteMapView.swift` | CREATE | MapKit view rendering a polyline from encoded string |
| `Dromos/App/MainTabView.swift` | MODIFY | Pass `stravaService` to `HomeView` |
| `.claude/context/schema.md` | MODIFY | Add `summary_polyline` column to `strava_activities` table |
| `.claude/context/architecture.md` | MODIFY | Document new files (SessionCompletionStatus, ActualMetricsView, StravaRouteMapView), update HomeView description |

## Context Doc Updates

- `schema.md` — New `summary_polyline TEXT` column on `strava_activities`
- `architecture.md` — New files: `SessionCompletionStatus.swift`, `ActualMetricsView.swift`, `StravaRouteMapView.swift`. Updated HomeView description (now receives stravaService, fetches activities, manages completion state).

## Tasks

### Phase 1: Data Pipeline — Polyline Capture
**Blocked by:** None

- [x] 🟩 **1.1 Database migration**
  - [x] 🟩 Create migration file: `ALTER TABLE public.strava_activities ADD COLUMN summary_polyline TEXT;`
  - [x] 🟩 Apply migration via Supabase MCP
  - [x] 🟩 Verify column exists with `mcp__supabase__execute_sql`

- [x] 🟩 **1.2 Edge function update** (`supabase/functions/strava-sync/index.ts`)
  - [x] 🟩 Extend `StravaApiActivity` interface (line 70) — add `map?: { summary_polyline?: string };`
  - [x] 🟩 Add `summary_polyline: a.map?.summary_polyline ?? null` to the upsert row mapping (line 301-317)

- [x] 🟩 **1.3 Swift model update** (`Dromos/Core/Models/StravaModels.swift`)
  - [x] 🟩 Add `let summaryPolyline: String?` to `StravaActivity` struct (after `isManual`)

- [x] 🟩 **1.4 Update `schema.md`**
  - [x] 🟩 Add `summary_polyline | TEXT | | Encoded polyline from Strava map` row to `strava_activities` table

### Phase 2: Matching Engine + Card States [QA-REQUIRED]
**Blocked by:** Phase 1

- [ ] 🟥 **2.1 Create `SessionCompletionStatus.swift`** (`Dromos/Core/Models/SessionCompletionStatus.swift`)
  - [ ] 🟥 Define enum:
    ```swift
    enum SessionCompletionStatus {
        case planned
        case completed(activity: StravaActivity)
        case missed
    }
    ```
  - [ ] 🟥 Define `SessionMatcher` struct with static method:
    ```swift
    struct SessionMatcher {
        /// Matches plan sessions against Strava activities.
        /// - Parameters:
        ///   - sessions: Tuples of (session, resolvedDate) for each visible session
        ///   - activities: All Strava activities in the visible date range
        ///   - today: Reference date for planned vs missed cutoff (defaults to Date())
        /// - Returns: Dictionary mapping session ID to completion status
        static func match(
            sessions: [(session: PlanSession, date: Date)],
            activities: [StravaActivity],
            today: Date = Date()
        ) -> [UUID: SessionCompletionStatus]
    }
    ```
  - [ ] 🟥 Implementation logic:
    1. Filter out activities where `isManual == true`
    2. Group remaining activities by `(normalizedSport, calendarDay)` using `startDateLocal` truncated to date
    3. For each session, look up the group matching `(session.sport, sessionDate)`
    4. If matches found: pick the activity with `movingTime` closest to `session.durationMinutes * 60` → `.completed(activity:)`
    5. If no match and `sessionDate < Calendar.current.startOfDay(for: today)` → `.missed`
    6. Otherwise → `.planned`

- [ ] 🟥 **2.2 Wire stravaService into HomeView**
  - [ ] 🟥 `MainTabView.swift` (line 60-65): Add `stravaService: stravaService` to `HomeView` initializer
  - [ ] 🟥 `HomeView.swift`: Add `@ObservedObject var stravaService: StravaService` parameter
  - [ ] 🟥 Add `@State private var completionStatuses: [UUID: SessionCompletionStatus] = [:]` state
  - [ ] 🟥 Add `@State private var expandedCompletedIDs: Set<UUID> = []` for expand/collapse tracking
  - [ ] 🟥 In `contentView(plan:)` `.onAppear` block: call a new private method `loadCompletionStatuses(plan:)` that:
    1. Checks `profileService.user?.isStravaConnected == true` — if not, return early (all planned)
    2. Computes earliest and latest visible dates from visible weeks
    3. Calls `await stravaService.fetchActivities(from: earliest, to: latest)`
    4. Builds `[(PlanSession, Date)]` tuples for all visible sessions using `Weekday.date(relativeTo:)`
    5. Calls `SessionMatcher.match(sessions:activities:)` and assigns result to `completionStatuses`
  - [ ] 🟥 Also call `loadCompletionStatuses` in `.onChange(of: scrollReset)` to refresh on tab re-selection

- [ ] 🟥 **2.3 Update SessionCardView for completion states**
  - [ ] 🟥 Add new parameter: `completionStatus: SessionCompletionStatus = .planned`
  - [ ] 🟥 **Green left border (completed):** Wrap existing card content in an `HStack(spacing: 0)` with a leading `RoundedRectangle` (width: 4pt, color: `.green`, corner radius on left side only). Alternative: use `.overlay(alignment: .leading)` with a thin green rectangle inside the rounded rect clip.
  - [ ] 🟥 **Red left border + dimming (missed):** Same border approach with `.red`. Apply `.opacity(0.5)` to the entire card content.
  - [ ] 🟥 **Planned:** No changes — render exactly as today.

- [ ] 🟥 **2.4 Update HomeView card rendering**
  - [ ] 🟥 In `daySectionView` (line 207-251): pass `completionStatus: completionStatuses[session.id] ?? .planned` to each `SessionCardView`
  - [ ] 🟥 Wrap completed cards in a `Button` / `.onTapGesture` that toggles `expandedCompletedIDs` membership
  - [ ] 🟥 Missed cards: no tap gesture (already not tappable — just don't wrap them)

- [ ] 🟥 **2.5 Edit mode constraints**
  - [ ] 🟥 In `daySectionView` edit mode block (line 218-249): check if `completionStatuses[session.id]` is `.completed` — if so, hide the move arrows entirely (don't render the `VStack` with chevrons)
  - [ ] 🟥 Completed sessions should not be draggable/movable

- [ ] 🟥 **2.6 Update architecture.md**
  - [ ] 🟥 Add `SessionCompletionStatus.swift` to Models section
  - [ ] 🟥 Update HomeView description: now receives `stravaService`, fetches activities, manages completion state

### Phase 3: Expanded Detail View + GPS Map [QA-REQUIRED]
**Blocked by:** Phase 2

- [ ] 🟥 **3.1 Create `ActualMetricsView.swift`** (`Dromos/Features/Home/ActualMetricsView.swift`)
  - [ ] 🟥 Accepts `activity: StravaActivity`
  - [ ] 🟥 Layout: compact 2-column grid using `LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())])` or simple `HStack`/`VStack` layout
  - [ ] 🟥 Each metric cell: label (caption, secondary) + value (subheadline, bold)
  - [ ] 🟥 **Common metrics (all sports):**
    - Duration: format `activity.movingTime` seconds → "Xh Xmin" or "X min"
    - Distance: format `activity.distance` meters → "X.X km" (or "X m" if < 1km)
  - [ ] 🟥 **Cycling** (`normalizedSport == "bike"`):
    - Avg Power: `activity.averageWatts` → "XXX W" (omit if nil)
    - Avg HR: `activity.averageHeartrate` → "XXX bpm" (omit if nil)
    - Avg Speed: `activity.averageSpeed` m/s → "XX.X km/h" (omit if nil)
  - [ ] 🟥 **Running** (`normalizedSport == "run"`):
    - Avg Pace: `activity.averageSpeed` m/s → "X:XX /km" (omit if nil or 0)
    - Avg HR: `activity.averageHeartrate` → "XXX bpm" (omit if nil)
  - [ ] 🟥 **Swimming** (`normalizedSport == "swim"`):
    - Avg Pace: `activity.averageSpeed` m/s → "X:XX /100m" (omit if nil or 0)
    - Avg HR: `activity.averageHeartrate` → "XXX bpm" (omit if nil)
  - [ ] 🟥 Nil metrics are **omitted entirely** from the grid (not shown as "N/A")

- [ ] 🟥 **3.2 Polyline decoder utility**
  - [ ] 🟥 Add a static function (in `StravaRouteMapView.swift` or a shared utility) that decodes Google's encoded polyline format:
    ```swift
    import CoreLocation

    static func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D]
    ```
  - [ ] 🟥 Standard algorithm: iterate characters, subtract 63, extract 5-bit chunks, combine, apply sign, divide by 1e5. ~30 lines, no external dependency.

- [ ] 🟥 **3.3 Create `StravaRouteMapView.swift`** (`Dromos/Features/Home/StravaRouteMapView.swift`)
  - [ ] 🟥 Accepts `encodedPolyline: String`
  - [ ] 🟥 Uses `Map` (SwiftUI MapKit, iOS 17+) with a `MapPolyline` overlay
  - [ ] 🟥 Decode polyline → `[CLLocationCoordinate2D]` → `MKPolyline`
  - [ ] 🟥 Auto-fit the map region to the polyline bounds with padding
  - [ ] 🟥 Non-interactive: `.mapInteractionModes([])` — static visual snapshot
  - [ ] 🟥 Fixed height: ~150pt. Rounded corners to match card style.
  - [ ] 🟥 Polyline stroke: sport color from `PlanSession.sportColor` (or a fixed accent color)

- [ ] 🟥 **3.4 Integrate expanded section into SessionCardView**
  - [ ] 🟥 Add `isExpanded: Bool = false` and `onToggleExpand: (() -> Void)? = nil` parameters
  - [ ] 🟥 When `completionStatus` is `.completed(let activity)` and `isExpanded == true`, render below existing card content:
    1. A thin `Divider()`
    2. Section header: "Actual Performance" (caption, secondary color)
    3. `ActualMetricsView(activity: activity)`
    4. If `activity.summaryPolyline != nil`: `StravaRouteMapView(encodedPolyline: polyline)`
  - [ ] 🟥 Wrap the entire card in a `.onTapGesture` that calls `onToggleExpand?()` (only for completed status)
  - [ ] 🟥 Expand/collapse with `withAnimation(.easeInOut(duration: 0.25))` — content appears/disappears smoothly

- [ ] 🟥 **3.5 Wire expand state from HomeView**
  - [ ] 🟥 Pass `isExpanded: expandedCompletedIDs.contains(session.id)` to `SessionCardView`
  - [ ] 🟥 Pass `onToggleExpand` closure that toggles the session ID in `expandedCompletedIDs` with animation
  - [ ] 🟥 Reset `expandedCompletedIDs` on `scrollReset` change (same as tab re-selection behavior)

- [ ] 🟥 **3.6 Update architecture.md**
  - [ ] 🟥 Add `ActualMetricsView` and `StravaRouteMapView` to Key Shared Components section
