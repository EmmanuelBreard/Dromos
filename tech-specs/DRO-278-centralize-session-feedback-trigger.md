# DRO-278: Centralize Session-Feedback Trigger

**Linear:** [DRO-278](https://linear.app/dromosapp/issue/DRO-278/centralize-session-feedback-trigger-so-all-tabs-get-feedback)
**Implementation:** [DRO-280](https://linear.app/dromosapp/issue/DRO-280/dro-278-phase-1-centralize-session-feedback-trigger) ([PR #103](https://github.com/EmmanuelBreard/Dromos/pull/103))
**Overall Progress:** `100%`

## TLDR

Move the AI session-feedback trigger out of `CalendarView` and into a single, tab-agnostic listener at `MainTabView` level, with the actual logic owned by `PlanService`. After this change, every Strava sync — regardless of which tab is active — generates feedback for any completed session in the plan that lacks it. Fixes the bug where today's session card on the Home tab never received feedback because `HomeView` was missing the trigger that `CalendarView` had.

## Critical Decisions

- **Trigger lives at `MainTabView` level** — A single `.onChange(of: stravaService.isSyncing)` above the tabs guarantees the trigger fires regardless of which tab the user is on. This removes the view-coupling pattern that caused the bug.
- **Logic lives in `PlanService`** — Plan ownership and `refreshPlan()` already live there. Adding a `generatePendingFeedback(stravaService:profileService:)` method keeps `StravaService` free of plan/feedback concerns. The alternative (logic inside `StravaService.syncActivities`) was rejected — it would invert the dependency direction (Strava → Plan).
- **Scope = whole plan, not just visible week** — The current `CalendarView` implementation is per-visible-week, which is why past weeks the user never opened could end up without feedback. Broadening to "all sessions in the plan with `feedback IS NULL` and a matching activity" makes the system self-healing on every sync. Cost is bounded by sessions actually missing feedback (the Edge Function is idempotent).
- **Activities fetched once per generation pass** — `PlanService.generatePendingFeedback` runs a single `stravaService.fetchActivities(from:to:)` over the plan's date range, then runs `SessionMatcher.match()` once. Avoids fan-out queries.
- **Sequential Edge Function calls** — Same as today's CalendarView behavior. Avoids OpenAI rate-limit risk; sessions missing feedback are bounded (typically 0-2 per sync).
- **No new RLS / migration** — Pure iOS refactor. `feedback` and `matched_activity_id` columns already exist (DRO-158).
- **CalendarView keeps its in-memory matching cache** — Only the *feedback trigger* is removed. CalendarView still computes per-week completion status for its UI (border colors, edit-mode gating).

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Core/Services/PlanService.swift` | MODIFY | Add `generatePendingFeedback(stravaService:profileService:) async` — broadened-scope port of `CalendarView.generatePendingFeedback`. Internally fetches activities for the plan's date range, runs `SessionMatcher.match()`, calls `stravaService.generateSessionFeedback` sequentially for sessions with `feedback == nil`, then `refreshPlan(userId:)` once. |
| `Dromos/Dromos/App/MainTabView.swift` | MODIFY | Add `.onChange(of: stravaService.isSyncing)` at the `TabView` level — fires `planService.generatePendingFeedback(...)` once per sync completion. Also call it once at the end of `loadData()` so cold-launch backfill works. |
| `Dromos/Dromos/Features/Calendar/CalendarView.swift` | MODIFY | Remove the private `generatePendingFeedback(plan:weekIndex:)` method (lines 483-512) and its three call sites (lines 165, 181, 199). Keep `loadIfNeeded` and `completionCacheByWeek` — those still drive the UI. |
| `.claude/context/architecture.md` | MODIFY | Update the `MainTabView` and `CalendarView` descriptions to reflect that the feedback trigger is centralized at MainTabView. |

## Context Doc Updates

- `architecture.md` — note that `MainTabView` owns the post-sync feedback trigger; CalendarView's responsibilities reduce to "computes per-week completion status for its UI". `ai-pipeline.md` does not need an update (the prompt and Edge Function are unchanged).

## Tasks

### Phase 1: Centralize logic in `PlanService`

- [x] 🟩 **Step 1.1: Add `generatePendingFeedback` to `PlanService`**
  - [x] 🟩 In [`Dromos/Dromos/Core/Services/PlanService.swift`](Dromos/Dromos/Core/Services/PlanService.swift) (after `refreshPlan`, around line 311), add:
    ```swift
    /// Generates AI coach feedback for every completed session in the plan that
    /// currently has `feedback == nil`. Idempotent — sessions with feedback are
    /// skipped (Edge Function double-checks). Calls fire sequentially to avoid
    /// OpenAI rate limits. After the loop, the plan is refreshed once so the UI
    /// reflects the new feedback values.
    ///
    /// No-op if Strava is not connected or the plan is not loaded.
    func generatePendingFeedback(
        stravaService: StravaService,
        profileService: ProfileService
    ) async {
        guard profileService.user?.isStravaConnected == true else { return }
        guard let plan = trainingPlan else { return }

        // Build (session, date) tuples across the entire plan.
        let sessionsWithDates: [(session: PlanSession, date: Date)] = plan.planWeeks
            .compactMap { week -> [(session: PlanSession, date: Date)]? in
                guard let weekStart = week.startDateAsDate else { return nil }
                return week.planSessions.compactMap { session in
                    guard let weekday = Weekday(fullName: session.day) else { return nil }
                    return (session, weekday.date(relativeTo: weekStart))
                }
            }
            .flatMap { $0 }

        // Bound activity fetch to the plan's date range.
        let dates = sessionsWithDates.map(\.date)
        guard let minDate = dates.min(), let maxDate = dates.max() else { return }
        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: maxDate) ?? maxDate

        let activities = await stravaService.fetchActivities(from: minDate, to: endDate)
        let statuses = SessionMatcher.match(sessions: sessionsWithDates, activities: activities)

        // Generate feedback only for matched sessions that don't already have it.
        var didGenerate = false
        for (sessionId, status) in statuses {
            guard case .completed(let activity) = status else { continue }
            let session = plan.planWeeks
                .flatMap(\.planSessions)
                .first { $0.id == sessionId }
            guard let session, session.feedback == nil else { continue }

            let feedback = await stravaService.generateSessionFeedback(
                sessionId: sessionId,
                activityId: activity.id
            )
            if feedback != nil { didGenerate = true }
        }

        if didGenerate {
            await refreshPlan(userId: plan.userId)
        }
    }
    ```
  - [x] 🟩 Verify the file imports / type references compile (`SessionMatcher`, `Weekday`, `StravaService`, `ProfileService` are all already in scope via `Core/Models` and `Core/Services`).

### Phase 2: Wire the trigger in `MainTabView`

- [x] 🟩 **Step 2.1: Add post-sync `.onChange` listener**
  - [x] 🟩 In [`Dromos/Dromos/App/MainTabView.swift`](Dromos/Dromos/App/MainTabView.swift), add a new `.onChange` modifier alongside the existing `.onChange(of: scenePhase)` (after line 112):
    ```swift
    .onChange(of: stravaService.isSyncing) { oldValue, newValue in
        // Centralized feedback trigger — fires on every sync completion regardless
        // of which tab is active. Replaces the per-tab triggers that caused DRO-278.
        if oldValue && !newValue {
            Task {
                await planService.generatePendingFeedback(
                    stravaService: stravaService,
                    profileService: profileService
                )
            }
        }
    }
    ```

- [x] 🟩 **Step 2.2: Cold-launch coverage**
  - [x] 🟩 Confirmed the `.onChange(isSyncing)` listener already covers cold launch — `isSyncing` flips during `loadData`'s `await stravaService.syncActivities()`. **No explicit call added to `loadData()`** to avoid duplicating the cold-launch fire.

### Phase 3: Remove duplicated logic from `CalendarView`

- [x] 🟩 **Step 3.1: Remove the three `generatePendingFeedback` call sites**
  - [x] 🟩 In [`Dromos/Dromos/Features/Calendar/CalendarView.swift`](Dromos/Dromos/Features/Calendar/CalendarView.swift):
    - Line 165 (inside `.onChange(of: currentWeekIndex)`): remove `await generatePendingFeedback(plan: plan, weekIndex: newIdx)`.
    - Line 181 (inside `.onChange(of: calendarReset)` same-week branch): remove `await generatePendingFeedback(plan: plan, weekIndex: target)`.
    - Line 199 (inside `.onChange(of: stravaService.isSyncing)`): remove `await generatePendingFeedback(plan: plan, weekIndex: currentWeekIndex)`.

- [x] 🟩 **Step 3.2: Delete the helper**
  - [x] 🟩 Remove the entire `generatePendingFeedback(plan:weekIndex:)` method (lines 483-512) including its `// MARK: - Session Feedback` comment block.

- [x] 🟩 **Step 3.3: Verify CalendarView still compiles + matches**
  - [x] 🟩 `loadIfNeeded(weekIndex:plan:)` and `completionCacheByWeek` remain — they drive the green/red border UI and are independent of the feedback trigger.

### Phase 4: Manual test

- [x] 🟩 **Step 4.1: Reproduce the original bug pre-fix to confirm** — Today's session (Sunday 2026-05-10) had `feedback = NULL` and `matched_activity_id = NULL` pre-fix.
- [x] 🟩 **Step 4.2: Test from Today/Home tab only** — Feedback appears on Today card after cold-launch sync without visiting Calendar.
- [x] 🟩 **Step 4.3: Regression check on Calendar tab** — Past weeks still display existing feedback; no missing or duplicated feedback.
- [x] 🟩 **Step 4.4: Idempotency check** — Second sync triggers zero new Edge Function calls.
- [x] 🟩 **Step 4.5: Cold-launch dedup check** — Listener fires once per sync; the listener-only path (no explicit `loadData()` call) avoided duplicate fires.

### Phase 5: Update context docs

- [x] 🟩 **Step 5.1: Update `architecture.md`**
  - [x] 🟩 In the `MainTabView.swift` line of the folder structure (around line 12), append: `+ centralized session-feedback trigger via .onChange(stravaService.isSyncing) (DRO-278)`.
  - [x] 🟩 In the `CalendarView.swift` line (around line 64), remove any mention of feedback generation responsibility.
  - [x] 🟩 In the `Service Layer Pattern` section, add a one-line note: "PlanService also owns post-sync coach-feedback generation across all plan weeks (`generatePendingFeedback` — DRO-278)."

## Rollback Plan

- Revert the three modified Swift files (`PlanService.swift`, `MainTabView.swift`, `CalendarView.swift`).
- No DB or Edge Function changes — no data migration to roll back.
- Worst case: feedback generation falls back to the pre-DRO-278 behavior (Calendar-tab-only triggers). Already-generated feedback rows are unaffected (`feedback` column is additive).

## Risks

- **Race between sync and generation.** `MainTabView`'s `.onChange(isSyncing)` fires when `isSyncing` flips false. By that point, `strava-sync` Edge Function has finished writing `strava_activities` rows. `fetchActivities` reads fresh DB state. Low risk.
- **Plan refresh ordering.** Inside `generatePendingFeedback`, `refreshPlan(userId:)` is called once after the loop. If the user navigates away mid-generation, `@Published trainingPlan` still updates correctly because `PlanService` is `@MainActor`. No state leak.
- **Concurrent sync** — `StravaService.syncActivities` already guards with `guard !isSyncing else { return }`. The `.onChange` listener only fires on the *trailing edge* of a sync, so concurrent generation from two listeners is impossible.
- **Edge Function cost.** Bounded by completed-but-unfed-back sessions per sync. In practice 0-1 per day for an active user. No cost regression vs. today.
