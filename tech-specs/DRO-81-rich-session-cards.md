# DRO-81: Rich Session Cards with Workout Steps & Intensity Graph

**Overall Progress:** `0%`

## TLDR
Upgrade SessionCardView on the Home tab to display workout segment breakdown (text steps with real watts/speed/pace) and a visual intensity bar chart. Invert card/background color scheme to white cards on gray background. Add tap-to-reveal popover on graph bars.

## Critical Decisions
- **VMA not MAS:** The athlete field is `User.vma` (Vitesse Maximale Aérobie, km/h). Functionally equivalent to MAS. Use throughout.
- **Data plumbing via ProfileService:** MainTabView will own a `ProfileService` @StateObject (same pattern as PlanService). HomeView receives `profileService.user` to extract FTP/VMA/CSS. This keeps the existing dependency-injection pattern — no @EnvironmentObject.
- **Custom bar chart, no Charts framework:** Build with GeometryReader + HStack of colored RoundedRectangles. Simpler, no iOS 16+ Charts dependency, and matches the prototype exactly.
- **Segment flattening lives in WorkoutLibraryService:** New methods to flatten nested repeats into a linear array of `FlatSegment` structs for graph rendering. Reuses the existing recursive walking pattern from `swimDistance(for:)`.
- **Swim treatment:** Simple swims (single segment or all same pace) → distance only (current behavior). Complex swims (multiple segments with different paces/drills) → show steps + graph like bike/run.
- **Intensity color gradient (HSL):** Both step dots AND graph bars use the same color function. Maps intensity percentage to hue via HSL: `hue = max(0, 120 - ((intensityPct - 50) / 70 * 120))`, saturation 70%, lightness 50%. This produces:
  - **Green** (~hue 120) for ≤50-65% (warmup, cooldown, easy)
  - **Yellow-green** (~hue 80) for ~70-80% (steady/moderate)
  - **Orange** (~hue 30) for ~85-95% (tempo/threshold)
  - **Red** (~hue 0) for ≥100%+ (max effort intervals)
  - Recovery segments always green regardless of intensity
- **Bike uses FTP for watts:** Target power = `round(ftpPct / 100.0 × ftp)`. Displayed as "156 W". The user's FTP (in watts) is stored in `User.ftp: Int?` and workout segments have `ftpPct: Int?`.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/App/MainTabView.swift` | MODIFY | Add `@StateObject ProfileService`, pass to HomeView |
| `Dromos/Dromos/Features/Home/HomeView.swift` | MODIFY | Accept `profileService`, pass athlete metrics + template to SessionCardView, gray background |
| `Dromos/Dromos/Features/Home/SessionCardView.swift` | MODIFY | Major rewrite — new layout with steps, graph, white bg, updated card structure. RestDayCardView + RaceDayCardView get white bg. |
| `Dromos/Dromos/Features/Home/WorkoutStepsView.swift` | CREATE | Text step list component with intensity dots and sport-specific metrics |
| `Dromos/Dromos/Features/Home/WorkoutGraphView.swift` | CREATE | Horizontal bar chart with intensity colors, time axis, tap-to-reveal popover |
| `Dromos/Dromos/Core/Models/WorkoutTemplate.swift` | MODIFY | Add `FlatSegment` struct for flattened graph data |
| `Dromos/Dromos/Core/Services/WorkoutLibraryService.swift` | MODIFY | Add `flattenedSegments(for:)` and `stepSummaries(for:sport:ftp:vma:css:)` methods |

## Context Doc Updates
- `architecture.md` — New files (WorkoutStepsView, WorkoutGraphView), updated SessionCardView description, ProfileService in MainTabView

## Open Questions
- [ ] What speed/pace should swim intervals show? Options: (a) qualitative pace label ("medium", "quick"), (b) estimated pace from CSS × multiplier, (c) just distance per segment. **Recommendation:** Show distance per segment + pace label for now, since CSS→actual pace mapping is fuzzy.

## Tasks

### Phase 1: Data Foundation + Background Inversion

- [ ] 🟥 **Step 1: Add ProfileService to MainTabView**
  - [ ] 🟥 Add `@StateObject private var profileService = ProfileService()` to `MainTabView`
  - [ ] 🟥 Fetch profile in `.task {}` alongside plan: `try? await profileService.fetchProfile(userId: userId)`
  - [ ] 🟥 Pass `profileService` to `HomeView` (new `@ObservedObject var profileService: ProfileService` param)
  - [ ] 🟥 Update `HomeView` to accept and store `profileService`
  - [ ] 🟥 Update preview providers

- [ ] 🟥 **Step 2: Add FlatSegment model + flattening logic**
  - [ ] 🟥 Add `FlatSegment` struct to `WorkoutTemplate.swift`:
    ```swift
    struct FlatSegment {
        let label: String           // "warmup", "work", "recovery", "cooldown"
        let durationMinutes: Double // total duration of this segment
        let intensityPct: Int?      // ftpPct (bike), masPct (run) — drives bar height + color
        let distanceMeters: Int?    // for swim segments
        let pace: String?           // for swim segments
        let isRecovery: Bool        // true for recovery segments between repeats
    }
    ```
  - Note: `intensityPct` is the raw value from the template (`ftpPct` for bike, `masPct` for run). This single field drives both the bar height AND the intensity color (green→red gradient). Recovery segments get `isRecovery = true` so the color function can override to green.
  - [ ] 🟥 Add `flattenedSegments(for templateId: String) -> [FlatSegment]` to `WorkoutLibraryService` — recursively walks segments, expands repeats into individual iterations (repeat of 3 → 3 work segments + 2 recovery segments)
  - [ ] 🟥 Handle nested repeats (swim can have 2-3 levels)
  - [ ] 🟥 Handle duration from `durationMinutes`, `durationSeconds`, or estimated from `distanceMeters` (swim)

- [ ] 🟥 **Step 3: Add step summary generation logic**
  - [ ] 🟥 Add `StepSummary` struct to `WorkoutTemplate.swift`:
    ```swift
    struct StepSummary {
        let text: String            // e.g., "15' warmup - 156 W"
        let intensityPct: Int?      // for color-coding the dot
        let isRepeatBlock: Bool     // true for collapsed repeat summaries
    }
    ```
  - [ ] 🟥 Add `stepSummaries(for templateId: String, sport: String, ftp: Int?, vma: Double?, css: Int?) -> [StepSummary]` to `WorkoutLibraryService`
  - [ ] 🟥 Bike format: `"15' warmup - 156 W"` → duration + label + `round(ftpPct/100 * ftp)` watts
  - [ ] 🟥 Run format: `"10' tempo - 12.0 km/h (5:00/km)"` → duration + label + `vma * masPct/100` speed + pace
  - [ ] 🟥 Repeat format: `"3× (6' work - 260 W + 4' recovery)"` → collapsed single line
  - [ ] 🟥 Swim format: `"300m warmup"` or `"4×100m medium"` → distance-based with pace label
  - [ ] 🟥 Fallback: if FTP/VMA is nil, show percentage (e.g., "88% FTP")

- [ ] 🟥 **Step 4: Invert background colors**
  - [ ] 🟥 `HomeView`: Add `.background(Color(.systemGroupedBackground))` to the ScrollView
  - [ ] 🟥 `SessionCardView`: Change `.background(Color(.secondarySystemBackground))` → `.background(Color(.systemBackground))` (white)
  - [ ] 🟥 `RestDayCardView`: Same background change
  - [ ] 🟥 `RaceDayCardView`: Same background change

### Phase 2: Workout Steps + Intensity Graph

- [ ] 🟥 **Step 5: Create WorkoutStepsView**
  - [ ] 🟥 Create `Dromos/Dromos/Features/Home/WorkoutStepsView.swift`
  - [ ] 🟥 Takes `[StepSummary]` as input
  - [ ] 🟥 Renders each step as: colored circle (intensity dot) + text
  - [ ] 🟥 Create shared `intensityColor(for pct: Int?) -> Color` helper (used by both dots and graph bars):
    - Uses `Color(hue:saturation:brightness:)` with `hue = max(0, (120 - ((pct - 50) / 70 * 120))) / 360`
    - Green (hue ~0.33) for warmup/cooldown/easy ≤65%
    - Yellow-green (hue ~0.22) for moderate ~70-80%
    - Orange (hue ~0.08) for tempo/threshold ~85-95%
    - Red (hue ~0.0) for max effort ≥100%
    - Recovery segments → always green
    - `nil` intensity → default green
  - [ ] 🟥 Compact vertical list with small spacing

- [ ] 🟥 **Step 6: Create WorkoutGraphView**
  - [ ] 🟥 Create `Dromos/Dromos/Features/Home/WorkoutGraphView.swift`
  - [ ] 🟥 Takes `[FlatSegment]` and total duration as input
  - [ ] 🟥 `GeometryReader` with `HStack(spacing: 2)` of colored `RoundedRectangle`s
  - [ ] 🟥 Width = `(segment.duration / totalDuration) * availableWidth`
  - [ ] 🟥 Height = normalized intensity (min 30% height for low-intensity segments so they're visible)
  - [ ] 🟥 Color = same `intensityColor(for:)` function as step dots — ensures dots and bars always match (cf. prototype screenshots: green dot = green bar, orange dot = orange bar)
  - [ ] 🟥 Time axis below: labels at ~15 min intervals (e.g., "0'", "15'", "30'", "45'", "60'")
  - [ ] 🟥 Fixed height for graph area (~60pt) with time axis below (~20pt)

- [ ] 🟥 **Step 7: Integrate into SessionCardView**
  - [ ] 🟥 Update `SessionCardView` init to accept: `template: WorkoutTemplate?`, `ftp: Int?`, `vma: Double?`, `css: Int?`
  - [ ] 🟥 Keep existing header row: sport icon + name + duration
  - [ ] 🟥 Move type badge to top-right (replace brick indicator position, keep brick below if applicable)
  - [ ] 🟥 Add `WorkoutStepsView` below header (only when template has >1 segment)
  - [ ] 🟥 Add `WorkoutGraphView` below steps (for all sessions with a template)
  - [ ] 🟥 Swim exception: simple swims (1 segment, no repeats) → show distance only (keep current behavior)
  - [ ] 🟥 Update `HomeView.daySectionView` to pass template + athlete metrics to SessionCardView

### Phase 3: Tap Interaction + Polish

- [ ] 🟥 **Step 8: Add tap-to-reveal popover on graph bars**
  - [ ] 🟥 Add `@State var selectedSegmentIndex: Int?` to `WorkoutGraphView`
  - [ ] 🟥 Each bar gets `.onTapGesture` that sets/toggles selectedSegmentIndex
  - [ ] 🟥 Show a small popover/overlay above the tapped bar with:
    - Bike: "15 min warmup — 156 W"
    - Run: "10 min tempo — 12.0 km/h (5:00/km)"
    - Swim: "100m — medium pace"
  - [ ] 🟥 Tap elsewhere or tap same bar to dismiss
  - [ ] 🟥 Subtle animation on show/dismiss

- [ ] 🟥 **Step 9: Edge cases + previews**
  - [ ] 🟥 Handle missing template (templateId not found in library) → fallback to current simple card
  - [ ] 🟥 Handle nil FTP/VMA → show percentage instead of absolute value
  - [ ] 🟥 Handle very long workouts (3h+) — ensure time axis doesn't get too crowded
  - [ ] 🟥 Handle very short segments (<2 min) — ensure bars are still tappable (minimum width)
  - [ ] 🟥 Update all preview providers with rich examples (easy bike, interval bike, steady run, interval run, simple swim, complex swim)
  - [ ] 🟥 Test with actual workout-library.json templates to verify formatting
