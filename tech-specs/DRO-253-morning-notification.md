# DRO-253 — Morning notification: today's session preview at 6am

**Linear:** [DRO-253](https://linear.app/dromosapp/issue/DRO-253/morning-notification-todays-session-preview-at-6am)
**Branch:** `ebreard4/dro-253-morning-notification-todays-session-preview-at-6am`
**Overall Progress:** `0%`

## TLDR
Send a local push notification at 6:00 every morning previewing the user's training session for that day. Opt-in via a new `Profile → Settings → Notifications` row. Toggle defaults OFF; flipping ON triggers iOS permission prompt and starts a rolling 14-day schedule. One notification per day; combined for multi-session days; race day gets distinct copy. Tapping the notification opens today's session detail. Visual direction = Option 1 (Briefing line) per the [design comment on DRO-253](https://linear.app/dromosapp/issue/DRO-253/morning-notification-todays-session-preview-at-6am).

## Critical Decisions

- **Sport icon in title — SF Symbols via Unicode (primary), subtitle fallback (Phase 2 sub-task).** Standard `UNMutableNotificationContent` is plain text; we'll use the SF Symbol Unicode private-use codepoints (iOS 16+ renders them on the lock screen) for `figure.run` / `bicycle` / `figure.pool.swim` / `flag.checkered` plus a brick glyph (`arrow.triangle.merge` or `link`). If empirically a codepoint doesn't render reliably, drop the inline glyph and use `content.subtitle = "RUN"` / `"BIKE"` etc. Decision deferred to a 30-min spike during Phase 3 — codepoints will be locked in then. Reason: the design's sport-icon-in-title pattern is the strongest comprehension cue at 6am; we'd rather degrade to a subtitle than ship without sport identity.
- **Race-day celebratory card = v1.5, not v1.** The Option-1 race notification (gradient background, large title, 3-cell distance row) is not achievable with standard `UNMutableNotificationContent`; it requires a `UNNotificationContentExtension` (separate app extension target, custom SwiftUI view). To keep v1 small, race day in v1 uses a standard notification with race-specific copy (`title = "Race day · {race name}"`, `body = "{encouraging sentence}"`, `subtitle = "RACE"`). The celebratory full-card lives in a follow-up phase (Phase 7) and can be deferred indefinitely without blocking the rest of the feature.
- **Single source of truth = Supabase, not `@AppStorage`.** Mirrors the existing pattern (every other user pref persists to `users` table). Toggle state lives in `users.morning_notifications_enabled`. iOS reads on app start and writes on toggle.
- **Brick = single `PlanSession` with `isBrick=true`.** Recon confirms bricks are not multi-row; they're one session with structured `SessionStructure`. Notification body for a brick reads the structure to render `Bike 1h at 250W → Run 30' at 4:25/km`. No multi-session grouping logic needed for bricks.
- **Multi-session days (true AM+PM doubles) = combine into one notification.** Confirmed by product: the plan generator can emit two `PlanSession` rows for the same `(week_id, day)`. Detected by `>1 PlanSession` for that day. Title is `"AM Swim · 45' + PM Run · 30'"` shape; body summarizes both. Order = `orderInDay` ascending. AM/PM labels derived from `orderInDay` (first = AM, second = PM).
- **Pre-6am completion gate fires on Strava sync, not at notification time.** iOS doesn't support conditional triggers. We re-schedule (cancel-and-re-add) after every Strava sync that completes before 6am: if today's session matches an activity, that day's notification is removed from the pending queue. Acceptable: an athlete who logs a workout between sync-time and 6am will receive a redundant notification. This is rare; v1 accepts it.
- **AppDelegate adapter required.** `DromosApp.swift` is currently bare `WindowGroup`. Tap-to-open behavior requires `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)`. We add a minimal `@UIApplicationDelegateAdaptor` + `AppDelegate` class that owns the notification-center delegate and forwards the tap to a singleton `NotificationRouter` that the Home tab observes.
- **⚠️ Concurrent edit on `MainTabView.swift` with [DRO-256](https://linear.app/dromosapp/issue/DRO-256/coach-chat-v0-plan-aware-advisory-chat-re-scope-supersedes-dro-149).** DRO-256 (Coach tab) is being implemented in parallel on its own branch and adds a 4th `Tab` block inside the `TabView` body. This ticket touches different regions of the same file (a `@StateObject` near line 32 + `.task` / `.onChange(scenePhase)` hook bodies around lines 90–101). Auto-merge should be clean; if not, ~5 min manual fix. **Implementation guideline:** keep the `MainTabView.swift` diff minimal — only add what's strictly required for `NotificationService` ownership and lifecycle wiring. Do not refactor unrelated parts of the file. Whichever ticket merges to `main` first wins; the second rebases on top.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `supabase/migrations/017_add_morning_notifications.sql` | CREATE | `ALTER TABLE public.users ADD COLUMN morning_notifications_enabled BOOLEAN NOT NULL DEFAULT FALSE;` |
| `Dromos/Dromos/Core/Models/User.swift` | MODIFY | Add `var morningNotificationsEnabled: Bool` to `User` (after `birthYear`, before `onboardingCompleted` — line ~100). Add `morning_notifications_enabled: Bool?` to `UserUpdate` (line ~169). |
| `Dromos/Dromos/Core/Services/ProfileService.swift` | MODIFY | Extend `updateProfile(...)` signature with `morningNotificationsEnabled: Bool? = nil`; pipe into `UserUpdate` construction (line ~103). |
| `Dromos/Dromos/Core/Services/NotificationService.swift` | CREATE | New `@MainActor final class NotificationService: ObservableObject`. Public API: `requestAuthorization()`, `getAuthorizationStatus()`, `scheduleNext14Days(plan: TrainingPlan, completedToday: Bool)`, `cancelAllMorningPreviews()`, `refreshAuthorizationStatus()`. Owns identifier prefix `morning_preview_<yyyy-MM-dd>`. |
| `Dromos/Dromos/Core/Services/NotificationContentBuilder.swift` | CREATE | Pure struct/static functions: `buildContent(for sessions: [PlanSession], date: Date, library: WorkoutLibraryService) -> UNMutableNotificationContent`. Handles single-session, brick, multi-session, rest, race variants. Reads from `session.structure` for body shorthand. Sport icon resolution lives here. |
| `Dromos/Dromos/Core/Services/NotificationRouter.swift` | CREATE | Singleton `@MainActor final class` with `@Published var pendingNavigation: NotificationNavigationTarget?`. AppDelegate writes to it on tap; Home tab reads it on appear and clears after navigating. |
| `Dromos/Dromos/App/DromosApp.swift` | MODIFY | Add `@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate`. Create `AppDelegate.swift` (or inline) implementing `UNUserNotificationCenterDelegate` + setting `NotificationRouter.shared.pendingNavigation` on tap. |
| `Dromos/Dromos/App/AppDelegate.swift` | CREATE | Minimal `UIApplicationDelegate` + `UNUserNotificationCenterDelegate`. `application(_:didFinishLaunchingWithOptions:)` sets `UNUserNotificationCenter.current().delegate = self`. `userNotificationCenter(_:didReceive:withCompletionHandler:)` parses identifier → routes to home tab today's session. |
| `Dromos/Dromos/App/MainTabView.swift` | MODIFY | Add `@StateObject private var notificationService = NotificationService()` (~line 32). On `.task`: if `profile.morningNotificationsEnabled == true && plan != nil`, call `scheduleNext14Days(...)`. On `.onChange(of: scenePhase)` `.active`: call `refreshAuthorizationStatus()` then re-schedule (idempotent). On Strava sync completion: re-schedule. Pass `notificationService` to `ProfileView` so the settings screen can read/write it. |
| `Dromos/Dromos/Features/Profile/ProfileView.swift` | MODIFY | In `settingsDisplayView` (line ~475–491), add `NavigationLink(destination: NotificationsSettingsView(...))` row after Email. Mirror in `settingsEditingView` (line ~494–512). Pass `profileService` and `notificationService`. |
| `Dromos/Dromos/Features/Profile/NotificationsSettingsView.swift` | CREATE | `Form` with one `Section`. One `Toggle` row "Morning session preview" bound to a local `@State` mirroring `user.morningNotificationsEnabled`. On change → call `NotificationService.requestAuthorization()` (if needed) → persist via `ProfileService.updateProfile(morningNotificationsEnabled:)` → call `scheduleNext14Days(...)` (or `cancelAllMorningPreviews()`). Footer: "Get a preview of today's workout at 6am every morning." Permission-denied alert with deep-link to iOS Settings. |
| `Dromos/Dromos/Core/Services/PlanService.swift` | MODIFY | Inject `notificationService` reference (or use a `PlanDidChange` callback closure set by `MainTabView`). After `moveSession` success (line ~250) and after `fetchFullPlan` (line ~125) and after `generatePlan` completion: call `notificationService.scheduleNext14Days(...)` if toggle is ON. |

## Context Doc Updates

After implementation:
- **`schema.md`** — add `morning_notifications_enabled` row to the `public.users` table block; bump `Last updated` and migration list to `017`.
- **`architecture.md`** — add `NotificationService.swift`, `NotificationContentBuilder.swift`, `NotificationRouter.swift` to the `Core/Services/` listing. Add `NotificationsSettingsView.swift` to `Features/Profile/`. Add `AppDelegate.swift` to the `App/` block. Note the `@UIApplicationDelegateAdaptor` addition in `DromosApp.swift`. Document the rolling-14-day scheduling pattern under a new "Local Notifications" section.

## Confirmed by product (2026-05-02)

- **Multi-session days (AM+PM doubles)** — yes, possible. Multi-session combining logic stays in v1.
- **Notification time** — fixed at **06:00 local** for v1. User-configurable time deferred to v2.
- **App icon badge** — none. `content.badge = nil` always.

## Accepted v1 behaviors

- **Strava-sync race condition** — if a user logs an activity manually in Strava between 05:00 and 06:00, the rescheduling-on-sync hook will cancel that day's notification before fire. If they log it after 06:00, the notification has already fired. Accepted as v1 behavior.

## Tasks

### Phase 1 — Schema + model (DB primitives)

- [ ] 🟥 **Step 1: Add `morning_notifications_enabled` column**
  - [ ] 🟥 Write `supabase/migrations/017_add_morning_notifications.sql` with UP/DOWN comments
  - [ ] 🟥 Apply via `mcp__supabase__apply_migration`
  - [ ] 🟥 Verify default value (`FALSE`) on existing rows via `select count(*) from users where morning_notifications_enabled is null` (should be 0)

- [ ] 🟥 **Step 2: Extend `User` + `UserUpdate`**
  - [ ] 🟥 Add `morningNotificationsEnabled: Bool` to `User` struct (with default `false` for safety on decode)
  - [ ] 🟥 Add `morning_notifications_enabled: Bool?` to `UserUpdate`
  - [ ] 🟥 Verify decoder handles snake_case → camelCase via the existing `SupabaseClientProvider` decoder

- [ ] 🟥 **Step 3: Extend `ProfileService.updateProfile`**
  - [ ] 🟥 Add `morningNotificationsEnabled: Bool? = nil` parameter
  - [ ] 🟥 Pipe through to `UserUpdate` construction
  - [ ] 🟥 Smoke test: toggle the column manually via SQL, fetch via `ProfileService.fetchProfile()`, confirm Swift sees the new value

### Phase 2 — `NotificationService` skeleton + permission flow

- [ ] 🟥 **Step 4: Create `NotificationService.swift`**
  - [ ] 🟥 `@MainActor final class NotificationService: ObservableObject` per the existing service pattern
  - [ ] 🟥 `@Published var authorizationStatus: UNAuthorizationStatus = .notDetermined`
  - [ ] 🟥 `func requestAuthorization() async -> Bool` — wraps `UNUserNotificationCenter.requestAuthorization([.alert, .sound, .badge])`
  - [ ] 🟥 `func refreshAuthorizationStatus() async` — wraps `getNotificationSettings()`
  - [ ] 🟥 `func cancelAllMorningPreviews() async` — uses `getPendingNotificationRequests()` and removes those whose identifier starts with `morning_preview_`
  - [ ] 🟥 Stub `scheduleNext14Days(plan:completedToday:)` (returns immediately — implemented in Phase 3)

- [ ] 🟥 **Step 5: Create `AppDelegate` + wire in `DromosApp`**
  - [ ] 🟥 Create `App/AppDelegate.swift` — minimal `NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate`
  - [ ] 🟥 In `application(_:didFinishLaunchingWithOptions:)` set `UNUserNotificationCenter.current().delegate = self`
  - [ ] 🟥 In `userNotificationCenter(_:didReceive:withCompletionHandler:)` parse identifier → set `NotificationRouter.shared.pendingNavigation = .todaySession`
  - [ ] 🟥 In `userNotificationCenter(_:willPresent:withCompletionHandler:)` return `[.banner, .sound]` so foreground notifications still display
  - [ ] 🟥 Add `@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate` to `DromosApp`

- [ ] 🟥 **Step 6: Create `NotificationRouter`**
  - [ ] 🟥 `@MainActor final class NotificationRouter: ObservableObject` (singleton via `static let shared`)
  - [ ] 🟥 `enum NotificationNavigationTarget { case todaySession }`
  - [ ] 🟥 `@Published var pendingNavigation: NotificationNavigationTarget?`
  - [ ] 🟥 In `MainTabView.task`: read `pendingNavigation`; if set, switch tab to Home and clear it

### Phase 3 — Scheduling + content rendering

- [ ] 🟥 **Step 7: Create `NotificationContentBuilder`**
  - [ ] 🟥 Pure helper: `static func buildContent(for sessions: [PlanSession], date: Date, library: WorkoutLibraryService) -> UNMutableNotificationContent`
  - [ ] 🟥 Branch on session count + sport + isBrick + race:
    - 0 sessions → rest day content (`title = "Rest day"`, `body = "Nothing prescribed."`)
    - 1 session, sport=`race` → race-day content (`title = "Race day · \(name)"`, `body = "<encouraging sentence>"`, `subtitle = "RACE"`)
    - 1 session, isBrick → brick content (title from `displayName + duration`, body from `structure` segments joined by `→`)
    - 1 session, swim → `title = "\(displayName) · \(distance) · \(duration)"`
    - 1 session, run/bike → `title = "\(displayName) · \(duration)"`, body = sport-shorthand from `structure`
    - 2+ sessions → multi-session combined content
  - [ ] 🟥 Set `content.userInfo = ["session_date": date]`
  - [ ] 🟥 Set `content.threadIdentifier = "morning_preview"` (so future v2 grouping is consistent)
  - [ ] 🟥 Unit test stubs: each branch returns a `UNMutableNotificationContent` with expected title/body shapes

- [ ] 🟥 **Step 8: Spike — SF Symbols Unicode in title**
  - [ ] 🟥 Test on a real device + simulator: do the SF Symbol private-use codepoints for `figure.run`, `bicycle`, `figure.pool.swim`, `flag.checkered` render correctly in lock-screen notifications on iOS 16, 17, 18?
  - [ ] 🟥 If yes → embed via Unicode in `NotificationContentBuilder.titleString(for:)`. Document codepoints inline.
  - [ ] 🟥 If unreliable → drop inline glyph; instead set `content.subtitle = "RUN"` / `"BIKE"` etc. Update `NotificationContentBuilder` accordingly.

- [ ] 🟥 **Step 9: Implement `scheduleNext14Days`**
  - [ ] 🟥 Read `plan.daysForWeek(...)` for today + 14 days ahead, mapping each date → `[PlanSession]`
  - [ ] 🟥 For each date with sessions, build content via `NotificationContentBuilder`
  - [ ] 🟥 Skip date if `completedToday == true && date == today` (Strava-match gate)
  - [ ] 🟥 Skip date if no plan loaded for that day
  - [ ] 🟥 Build `UNCalendarNotificationTrigger` with hour=6, minute=0, repeats=false, dateMatching the target date in user's timezone
  - [ ] 🟥 Identifier: `"morning_preview_\(yyyy-MM-dd)"`
  - [ ] 🟥 Always cancel-then-add (idempotent): call `cancelAllMorningPreviews()` first
  - [ ] 🟥 Confirm pending count ≤ 14 via `getPendingNotificationRequests()` after scheduling

### Phase 4 — UI: `NotificationsSettingsView` + `ProfileView` integration

- [ ] 🟥 **Step 10: Create `NotificationsSettingsView`**
  - [ ] 🟥 `Form` → `Section` with one row containing a `Toggle("Morning session preview", isOn: $isOn)`
  - [ ] 🟥 Footer: `"Get a preview of today's workout at 6am every morning."`
  - [ ] 🟥 On toggle ON: call `notificationService.requestAuthorization()`. If granted → `profileService.updateProfile(morningNotificationsEnabled: true)` + `scheduleNext14Days(...)`. If denied → revert toggle OFF + show alert with "Open Settings" button (`UIApplication.openNotificationSettingsURLString`).
  - [ ] 🟥 On toggle OFF: `profileService.updateProfile(morningNotificationsEnabled: false)` + `cancelAllMorningPreviews()`
  - [ ] 🟥 Architecture: design supports adding more rows in v2 — keep the `Section` extensible (don't hardcode single-row assumptions in styling)

- [ ] 🟥 **Step 11: Add the entry point in `ProfileView`**
  - [ ] 🟥 In `settingsDisplayView` (line ~475), add `NavigationLink(destination: NotificationsSettingsView(profileService: profileService, notificationService: notificationService, user: user))` after the Email row
  - [ ] 🟥 Mirror in `settingsEditingView` (line ~494) — same row, even in edit mode (the link still navigates; toggle screen handles its own state)
  - [ ] 🟥 Pass `notificationService` from `MainTabView` → `ProfileView` (new parameter)

### Phase 5 — Edge case wiring

- [ ] 🟥 **Step 12: Foreground re-check**
  - [ ] 🟥 In `MainTabView.onChange(of: scenePhase)` `.active` clause: call `notificationService.refreshAuthorizationStatus()`
  - [ ] 🟥 If `authorizationStatus != .authorized && user.morningNotificationsEnabled == true` → flip toggle OFF in DB silently
  - [ ] 🟥 Otherwise (still authorized + toggle ON): `scheduleNext14Days(...)` (idempotent)

- [ ] 🟥 **Step 13: Plan-change hooks**
  - [ ] 🟥 After `PlanService.moveSession` success (line ~250) → if toggle ON, re-schedule
  - [ ] 🟥 After `PlanService.fetchFullPlan` (line ~125, when triggered post-generation) → if toggle ON, re-schedule
  - [ ] 🟥 Wiring approach: `PlanService` exposes a `var onPlanChanged: (@MainActor () async -> Void)?` closure; `MainTabView` sets it to invoke `notificationService.scheduleNext14Days(...)`

- [ ] 🟥 **Step 14: Strava-match completion gate**
  - [ ] 🟥 After `StravaService.syncActivities()` success → if today's session matches a Strava activity (via `SessionMatcher.match`) AND time is before 06:00 → cancel `morning_preview_<today>` from pending requests
  - [ ] 🟥 Re-schedule the rest of the window (ensures next 14 days remain consistent)

- [ ] 🟥 **Step 15: Timezone change**
  - [ ] 🟥 Subscribe to `NSSystemTimeZoneDidChangeNotification` in `NotificationService.init` → on fire, `cancelAllMorningPreviews()` + `scheduleNext14Days(...)`

### Phase 6 — QA + polish

- [ ] 🟥 **Step 16: Manual QA matrix**
  - [ ] 🟥 Toggle ON for the first time → permission prompt appears → grant → notification scheduled (verify via `getPendingNotificationRequests` log)
  - [ ] 🟥 Toggle ON → deny → toggle reverts OFF → alert shows with deep-link
  - [ ] 🟥 Toggle ON, deny, then toggle OFF in iOS Settings → app foreground → toggle silently flips OFF
  - [ ] 🟥 Toggle ON, then re-generate plan → pending requests reflect new plan (cancel-and-re-add)
  - [ ] 🟥 Toggle ON, then `moveSession` → pending requests updated for affected dates
  - [ ] 🟥 Notification fires at 06:00 in simulator (set time forward) → tap → opens to today's session detail
  - [ ] 🟥 Verify each variant renders correctly: run, bike, swim, brick, rest, race
  - [ ] 🟥 Verify multi-session day combines into one notification (if such a day exists in the test plan)

- [ ] 🟥 **Step 17: Update context docs**
  - [ ] 🟥 `schema.md` — append `morning_notifications_enabled` row to `public.users`; bump `Last updated` and migration list
  - [ ] 🟥 `architecture.md` — add new files; document local-notification scheduling pattern in a new section

### Phase 7 — v1.5 (deferred): Race-day celebratory full card

- [ ] 🟥 **Step 18 (deferred): `UNNotificationContentExtension`**
  - [ ] 🟥 Add a new app extension target `DromosNotificationContent`
  - [ ] 🟥 Custom SwiftUI view replicating the Option-1 race-day card (gradient background, large title with flag icon, encouraging line, Swim/Bike/Run cells)
  - [ ] 🟥 `NotificationContentBuilder` sets `content.categoryIdentifier = "RACE_DAY"` for race-day content
  - [ ] 🟥 Extension's `Info.plist` declares `UNNotificationExtensionCategory = "RACE_DAY"`
  - [ ] 🟥 Adds entitlement / extension capability to project
  - [ ] 🟥 QA on real device (extensions don't render in simulator long-press the same way)

  *Phase 7 is non-blocking — can ship v1 (Phases 1–6) without it. Race day in v1 is a normal notification with race-specific copy.*
