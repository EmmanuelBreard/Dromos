# Feature Implementation Plan — DRO-305: Surface Unscheduled Completed Sessions

**Overall Progress:** `100%` — shipped to main (PR #129), QA passed.

## TLDR
Athletes complete workouts that aren't in their plan (extra rides, recovery runs, ad-hoc swims, manual logs). These activities are **already synced** into `strava_activities` but are silently discarded after `SessionMatcher.match()` runs — invisible everywhere. This feature surfaces them as their own **UNSCHEDULED**-tagged cards in the Home (Today) and Calendar (weekly) views, counts their minutes toward weekly sport totals, and marks affected days with a distinct visual state. **Display + totals only — no promote/reschedule into the plan. No DB or sync changes.**

## Critical Decisions
- **Matcher exposes leftovers, not a new fetch** — Refactor `SessionMatcher` to surface the activities it did *not* consume, reusing the exact same consume/dedup loop. Guarantees an activity is never shown both as a planned-completion and as unscheduled. (vs. a second matching pass that could drift.)
- **New `UnscheduledActivityCard`, not a reused `TodayCompletedCard`** — `TodayCompletedCard` is structurally bound to a `PlanSession` (`session.displayName`, `session.feedback`, template segments). An unscheduled activity has no session. We get the "reuse completed card" look by composing the same **PlanSession-free sub-components**: `ActualMetricsView(activity:)`, `CompletedSegmentGraphView`, `StravaRouteMapView`. No `CoachFeedbackBlock`, no planned-workout disclosure. (Matches discovery: no feedback, no plan-vs-actual.)
- **Unscheduled = `normalizedSport ∈ {swim,bike,run}` AND not consumed by a planned match** — `isManual` activities are never consumed (excluded from matching) so they all surface, satisfying the "surface manual entries" decision. Sports outside swim/bike/run are ignored (mirrors what the app renders).
- **Totals: add to `done` only** — Unscheduled `movingTime` adds to the `done` numerator; planned `total` denominator is unchanged. Overshoot is already handled by `SportProgressStrip` (bar clamps ≤100%, numbers stay honest). Zero-planned sport renders `done / 0:00`.
- **New `.unscheduled` PillState** — Distinct visual state in `WeekDayStrip` + a distinct border in Calendar, so an unplanned-but-trained day reads differently from a planned-and-completed day.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `Dromos/Core/Models/SessionCompletionStatus.swift` | MODIFY | Extract shared matching core; add `matchWithUnscheduled(...)` returning statuses + unscheduled activities grouped by day. Keep existing `match(...)` as a thin wrapper (back-compat for current callers). |
| `Dromos/Core/Models/StravaModels.swift` | MODIFY | Add `StravaActivity.sportIcon` (maps `normalizedSport` → SF Symbol, mirrors `PlanSession.sportIcon`) and `displayName` (`name` ?? sport-based fallback) computed properties. |
| `Dromos/Core/Services/PlanService.swift` | MODIFY | `weeklySportTotals(...)` — switch to `matchWithUnscheduled`, fold unscheduled minutes into `done` for swim/bike/run. |
| `Dromos/Features/Home/UnscheduledActivityCard.swift` | CREATE | New card: `UnscheduledTag` + title row (`activity.sportIcon` + name + duration) + `ActualMetricsView` + optional `CompletedSegmentGraphView` (laps ≥ 2) + optional `StravaRouteMapView` (polyline present). Degrades gracefully for manual entries (no map/laps). |
| `Dromos/Features/Home/UnscheduledTag.swift` | CREATE | Small "UNSCHEDULED" pill, styled after `CompletedTag` but with a distinct (non-green) accent. |
| `Dromos/Features/Home/WeekDayStrip.swift` | MODIFY | Add `.unscheduled` case to `PillState` + its background/text styling (distinct from `.completed`). |
| `Dromos/Features/Home/HomeView.swift` | MODIFY | Store unscheduled activities in state; render in `todayHero` (rest+below / planned-day stack / race-day hide); extend `weekPills`/`pillState`/`glyphs`/`durationLabel` for `.unscheduled`. |
| `Dromos/Features/Calendar/CalendarView.swift` | MODIFY | Cache unscheduled activities per week; render `UnscheduledActivityCard`s in `daySectionView`; distinct day treatment. |

## Context Doc Updates
- `architecture.md` — add `UnscheduledActivityCard` + `UnscheduledTag` to the Home component list; note the new `.unscheduled` `PillState`; note `SessionMatcher.matchWithUnscheduled` and `StravaActivity.sportIcon`/`displayName`.

## Data Flow
```
strava_activities (already synced)
        │
fetchActivities(from:to:)              ← unchanged
        │
SessionMatcher.matchWithUnscheduled    ← NEW: returns (statuses, unscheduledByDay)
        ├── statuses → existing planned-session cards/pills (unchanged)
        └── unscheduledByDay → UnscheduledActivityCard(s) + .unscheduled pill state
                              → weeklySportTotals: minutes added to `done`
```

## Tasks

- [x] 🟩 **Phase 1: Matcher — expose unscheduled activities**
  - [x] 🟩 In `SessionCompletionStatus.swift`, extract the existing match loop into a private core returning `(statuses: [UUID: SessionCompletionStatus], consumedIDs: Set<Int64>)`. No behavior change.
  - [x] 🟩 Add `struct SessionMatchResult { let statuses: [UUID: SessionCompletionStatus]; let unscheduledByDay: [Date: [StravaActivity]] }` (key = `calendar.startOfDay(for: activity.startDateLocal)`).
  - [x] 🟩 Add `static func matchWithUnscheduled(sessions:activities:today:) -> SessionMatchResult`. Unscheduled = activities where `normalizedSport?.lowercased() ∈ {"swim","bike","run"}` AND `stravaActivityId ∉ consumedIDs` (so manual entries — never consumed — are all included). Group by `startOfDay`.
  - [x] 🟩 Keep existing `match(...)` as a wrapper over the core (returns `.statuses`) so the 3 current call sites compile unchanged.
  - [x] 🟩 Update the doc comment block to describe unscheduled semantics.

- [x] 🟩 **Phase 2: StravaActivity display helpers**
  - [x] 🟩 In `StravaModels.swift`, add `var sportIcon: String` mapping `normalizedSport` → SF Symbol (`swim→figure.pool.swim`, `bike→bicycle`, `run→figure.run`; fallback `figure.run`). Mirror `PlanSession.sportIcon` symbol names.
  - [x] 🟩 Add `var displayName: String` = `name` (title-cased) with a sport-based fallback (e.g. "Swim"/"Bike"/"Run") when `name` is nil/empty.

- [x] 🟩 **Phase 3: UnscheduledActivityCard + tag**
  - [x] 🟩 Create `UnscheduledTag.swift` — pill modeled on `CompletedTag` (label "UNSCHEDULED") using a distinct accent (NOT the completed green; e.g. a neutral/secondary or phase-style fill). Optional `sequenceContext` parity with the other Today tags.
  - [x] 🟩 Create `UnscheduledActivityCard.swift` with fields `activity: StravaActivity`, `sequenceContext: (index: Int, total: Int)?`. Owns a local `@StateObject StravaService` + `@State laps` fetched via `.task(id: activity.id)` (same pattern as `TodayCompletedCard`).
  - [x] 🟩 Body: `UnscheduledTag` (or `SessionSequenceBadge` in multi-session days) → title row (`activity.sportIcon` + `activity.displayName` + `ActivityFormatters` duration from `movingTime`) → `ActualMetricsView(activity:)` → `CompletedSegmentGraphView` when `laps.count >= 2` (pass `sport: activity.normalizedSport ?? ""`, athlete metrics) → `StravaRouteMapView` when `summaryPolyline != nil`. No `CoachFeedbackBlock`, no planned-workout disclosure.
  - [x] 🟩 Add SwiftUI previews: GPS run (full), manual entry (no map/laps), swim.

- [x] 🟩 **Phase 4: WeekDayStrip — `.unscheduled` state**
  - [x] 🟩 Add `case unscheduled` to `PillState`.
  - [x] 🟩 Add its `background(for:)` (distinct from `.completed` — e.g. dashed/outline or different accent) and the three text-style modifiers (`DowTextStyle`/`GlyphTextStyle`/`DurationTextStyle`).
  - [x] 🟩 Add a preview row demonstrating an unscheduled-only day.

- [x] 🟩 **Phase 5: Home wiring**
  - [x] 🟩 Add `@State private var unscheduledByDay: [Date: [StravaActivity]] = [:]`.
  - [x] 🟩 In `loadCompletionAndTotals()`, call `SessionMatcher.matchWithUnscheduled(...)`; assign `completionStatuses` + `unscheduledByDay`. `sportTotals` continues from `weeklySportTotals` (Phase 6 of PlanService already folds them in).
  - [x] 🟩 `todayHero`: resolve the selected day's unscheduled activities (map weekday → date → `startOfDay`). Behaviors:
    - Race day → **ignore** unscheduled (keep race takeover).
    - Rest day (no planned sessions) + unscheduled → render `RestDayCardView` then stack `UnscheduledActivityCard`(s) below.
    - Planned day + unscheduled → include the unscheduled card(s) in `multiSessionStack`, placed in the **bottom ("already done") bucket**; include them in the "N SESSIONS" count and "… total" duration (add `movingTime` minutes).
    - Single planned session + unscheduled → promote to the multi-session stack path.
  - [x] 🟩 `weekPills`/`pillState`: a non-today, non-race day with ≥1 unscheduled activity and no planned-`.missed`/incomplete resolves to `.unscheduled`. A planned-and-completed day stays `.completed`. Order of precedence documented in the function comment.
  - [x] 🟩 `glyphs`/`durationLabel`: include unscheduled activities so an otherwise-rest day shows its activity glyph + duration.

- [x] 🟩 **Phase 6: PlanService totals**
  - [x] 🟩 `weeklySportTotals(for:with:)` — switch from `SessionMatcher.match` to `matchWithUnscheduled`. After the existing planned `done` loop, iterate `unscheduledByDay` values; for each activity with `normalizedSport ∈ {swim,bike,run}`, add `Int((movingTime/60).rounded())` to that sport's `done`. `total` unchanged (overshoot intended).

- [x] 🟩 **Phase 7: Calendar wiring**
  - [x] 🟩 Add `@State private var unscheduledCacheByWeek: [Int: [Date: [StravaActivity]]] = [:]`.
  - [x] 🟩 `loadIfNeeded(weekIndex:plan:)` — switch to `matchWithUnscheduled`; cache both `statuses` and `unscheduledByDay`. Purge alongside `completionCacheByWeek` on sync.
  - [x] 🟩 `daySectionView` — after the planned-session loop, render `UnscheduledActivityCard`(s) for that day's unscheduled activities (skip on race days). Apply a distinct day treatment (e.g. the `.unscheduled`-equivalent border/accent already used on Home).
  - [x] 🟩 Confirm edit-mode move arrows never attach to unscheduled cards (they are not `PlanSession`s — structurally excluded).

- [x] 🟩 **Phase 8: Context docs + QA**
  - [x] 🟩 Update `.claude/context/architecture.md` (new components, `PillState.unscheduled`, matcher method, StravaActivity helpers).
  - [x] 🟩 Manual QA matrix: rest day + activity; planned day + extra activity; manual entry (no GPS); zero-plan sport in strip (`0:30 / 0:00`); race day (activity hidden); pill states in both views; Strava-disconnected user (no regressions).

## Test / Rollback
- **Tests:** `SessionMatcher` is a pure function — add unit coverage for `matchWithUnscheduled`: (a) manual entry surfaces as unscheduled, (b) a matched planned activity is NOT in unscheduled, (c) sport-day grouping, (d) non-swim/bike/run excluded. Existing `match()` tests must stay green (wrapper unchanged).
- **Rollback:** Pure additive frontend change, no migrations. Revert the PR; `strava_activities` and sync are untouched.
```
