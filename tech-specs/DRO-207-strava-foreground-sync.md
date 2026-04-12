# Feature Implementation Plan

**Overall Progress:** `100%`

## TLDR
`syncActivities()` only fires on cold launch (`.task {}`). Add a `scenePhase` observer to `MainTabView` so a sync is also triggered every time the app returns to the foreground. One file, one modifier.

## Critical Decisions
- **Observer lives in `MainTabView`** — it already owns both `stravaService` and `profileService`, so the connection check and sync call are naturally co-located there. No new service or abstraction needed.
- **No sync on cold launch from the observer** — `scenePhase` fires `.active` on cold launch too, but at that moment `profileService.user` is still `nil` (profile hasn't loaded yet), so the guard naturally no-ops. The existing `.task {}` path handles cold-launch sync as before. No deduplication logic needed.
- **Silent background sync** — no loading indicator added. `HomeView` already reacts to `stravaService.isSyncing` transitions, so the session card updates automatically when sync completes.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/App/MainTabView.swift` | MODIFY | Add `@Environment(\.scenePhase)` property + `.onChange(of: scenePhase)` modifier on the `TabView` |

## Context Doc Updates
None — no new files, tables, services, or patterns introduced.

## Tasks

- [x] 🟩 **Step 1: Add `scenePhase` observer to `MainTabView`**
  - [x] 🟩 Add `@Environment(\.scenePhase) private var scenePhase` property
  - [x] 🟩 Add `.onChange(of: scenePhase)` modifier to the `TabView` in `body`:
    ```swift
    .onChange(of: scenePhase) { _, newPhase in
        if newPhase == .active, profileService.user?.isStravaConnected == true {
            Task { await stravaService.syncActivities() }
        }
    }
    ```
  - [x] 🟩 Verify the modifier is placed **after** `.task { await loadData() }` on the `TabView`
