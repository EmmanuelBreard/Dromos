# DRO-139: Strava Integration — OAuth + Activity Sync

**Overall Progress:** `100%`

## TLDR

Connect Dromos to Strava so we can pull athlete activities. Users connect via OAuth in Profile settings, then activities sync automatically on app open. This lays the foundation for session completion tracking and unscheduled workout display (future issues). Scoped to **auth + data sync only** — no session matching UI.

## Critical Decisions

- **Server-side token exchange** — iOS sends the OAuth `code` to an Edge Function that exchanges it for tokens. Client secret never touches the app binary.
- **Dedicated `strava_connections` table** — Stores access/refresh tokens. No client-facing RLS (only service_role can read). Keeps sensitive tokens isolated from the `users` table.
- **Connection status via `strava_athlete_id` on `users`** — iOS checks `user.stravaAthleteId != nil` for connected state. Simple, no extra RPC needed.
- **No Strava SDK** — Raw HTTP via Edge Functions. Strava has no official Swift SDK; community wrappers are unmaintained. API surface is small (OAuth + 1 endpoint).
- **Auto-sync on app open** — Background sync when app launches + last 90 days on first sync, then incremental via `last_sync_at` timestamp.
- **Webhook deferred** — Manual/auto-on-open sync is sufficient for v1. Webhook subscription will be a follow-up issue.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `supabase/migrations/012_strava_tables.sql` | CREATE | `strava_connections` + `strava_activities` tables, RLS, `strava_athlete_id` on `users` |
| `supabase/functions/strava-auth/index.ts` | CREATE | OAuth token exchange + store connection |
| `supabase/functions/strava-sync/index.ts` | CREATE | Fetch activities from Strava API, upsert into DB |
| `Dromos/Dromos/Core/Models/StravaModels.swift` | CREATE | `StravaActivity` Codable struct |
| `Dromos/Dromos/Core/Services/StravaService.swift` | CREATE | OAuth flow, sync trigger, connection state |
| `Dromos/Dromos/Core/Models/User.swift` | MODIFY | Add `stravaAthleteId: Int64?` property |
| `Dromos/Dromos/Core/Configuration.swift` | MODIFY | Add `stravaClientId` |
| `Dromos/Dromos/Core/Secrets.swift` | MODIFY | Add `stravaClientId` value |
| `Dromos/Dromos/Core/Secrets.example` | MODIFY | Add placeholder |
| `Dromos/Dromos/Features/Profile/ProfileView.swift` | MODIFY | Add "Strava" section (connect/disconnect/sync status) |
| `Dromos/Dromos/App/DromosApp.swift` | MODIFY | Add `.onOpenURL` handler for OAuth callback |
| Xcode project target | MODIFY | Add `dromos` URL scheme + `strava` to `LSApplicationQueriesSchemes` |

## Context Doc Updates

- `schema.md` — New tables (`strava_connections`, `strava_activities`), new column on `users`, new RLS policies
- `architecture.md` — New Edge Functions (`strava-auth`, `strava-sync`), new service (`StravaService`), new models, URL scheme config

## Open Questions

- [x] **Strava App Registration** — Done. Client ID and secret available.
- [x] **Strava Developer Program** — Deferred. Using sandbox mode (dev account only) for now. Will apply before beta launch.

---

## Tasks

### Phase 1: Database Schema

- [x] 🟩 **Step 1: Create migration `012_strava_tables.sql`**

  - [x] 🟩 Add `strava_athlete_id BIGINT` column to `public.users` (nullable)

  - [x] 🟩 Create `public.strava_connections` table:
    ```sql
    CREATE TABLE public.strava_connections (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
        strava_athlete_id BIGINT NOT NULL,
        access_token TEXT NOT NULL,
        refresh_token TEXT NOT NULL,
        expires_at TIMESTAMPTZ NOT NULL,
        scope TEXT NOT NULL,
        last_sync_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    -- No client-facing RLS — only service_role reads/writes
    ALTER TABLE strava_connections ENABLE ROW LEVEL SECURITY;
    -- Trigger for updated_at
    CREATE TRIGGER update_strava_connections_updated_at
        BEFORE UPDATE ON strava_connections
        FOR EACH ROW EXECUTE FUNCTION update_updated_at();
    ```

  - [x] 🟩 Create `public.strava_activities` table:
    ```sql
    CREATE TABLE public.strava_activities (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
        strava_activity_id BIGINT NOT NULL,
        sport_type TEXT NOT NULL,          -- Raw Strava: 'Run', 'Ride', 'Swim', 'TrailRun', etc.
        normalized_sport TEXT,             -- Mapped: 'swim', 'bike', 'run', or NULL
        name TEXT,
        start_date TIMESTAMPTZ NOT NULL,
        start_date_local TIMESTAMPTZ NOT NULL,
        elapsed_time INT NOT NULL,         -- seconds
        moving_time INT NOT NULL,          -- seconds
        distance DECIMAL(10,2),            -- meters
        total_elevation_gain DECIMAL(8,2), -- meters
        average_speed DECIMAL(6,3),        -- m/s
        average_heartrate DECIMAL(5,1),
        average_watts DECIMAL(6,1),
        is_manual BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        UNIQUE(user_id, strava_activity_id)
    );
    -- Client can read own activities
    ALTER TABLE strava_activities ENABLE ROW LEVEL SECURITY;
    CREATE POLICY "select_own" ON strava_activities
        FOR SELECT USING (auth.uid() = user_id);
    -- Index for querying by user + date range
    CREATE INDEX idx_strava_activities_user_date
        ON strava_activities(user_id, start_date DESC);
    ```

  - [x] 🟩 `normalized_sport` mapping logic (in Edge Function, not DB):
    ```
    Run, TrailRun, VirtualRun → 'run'
    Ride, GravelRide, MountainBikeRide, VirtualRide → 'bike'
    Swim → 'swim'
    Everything else → NULL
    ```

---

### Phase 2: Edge Function — `strava-auth`

- [x] 🟩 **Step 2: Create `supabase/functions/strava-auth/index.ts`**

  - [x] 🟩 Handle `POST` — OAuth token exchange:
    1. Extract `user_id` from JWT (same pattern as `generate-plan`: manual decode, `--no-verify-jwt`)
    2. Read `code` from request body
    3. Call `POST https://www.strava.com/oauth/token` with:
       - `client_id` = `Deno.env.get("STRAVA_CLIENT_ID")`
       - `client_secret` = `Deno.env.get("STRAVA_CLIENT_SECRET")`
       - `code` = from request
       - `grant_type` = `"authorization_code"`
    4. Parse response: `access_token`, `refresh_token`, `expires_at`, `athlete.id`
    5. Upsert into `strava_connections` (ON CONFLICT user_id DO UPDATE)
    6. Update `users.strava_athlete_id` = `athlete.id`
    7. Return `{ success: true, strava_athlete_id: athlete.id }`

  - [x] 🟩 Handle `DELETE` — Disconnect Strava:
    1. Extract `user_id` from JWT
    2. Delete from `strava_connections` WHERE `user_id`
    3. Set `users.strava_athlete_id` = NULL
    4. Return `{ success: true }`

  - [x] 🟩 Error handling: Strava API errors (invalid code, expired code), missing env vars

  - [x] 🟩 CORS headers (same pattern as `generate-plan`)

  - [x] 🟩 Set Supabase secrets:
    ```bash
    supabase secrets set STRAVA_CLIENT_ID=<value>
    supabase secrets set STRAVA_CLIENT_SECRET=<value>
    ```

---

### Phase 3: Edge Function — `strava-sync`

- [x] 🟩 **Step 3: Create `supabase/functions/strava-sync/index.ts`**

  - [x] 🟩 `POST` handler:
    1. Extract `user_id` from JWT
    2. Fetch `strava_connections` row for user (error if not connected)
    3. Check `expires_at` — if expired, refresh token:
       - `POST https://www.strava.com/oauth/token` with `grant_type=refresh_token`
       - Update `strava_connections` with new `access_token`, `refresh_token`, `expires_at`
    4. Determine `after` timestamp:
       - If `last_sync_at` exists → use it (minus 1 hour buffer for late-uploaded activities)
       - If NULL (first sync) → 90 days ago
    5. Fetch activities paginated:
       - `GET https://www.strava.com/api/v3/athlete/activities?after={epoch}&per_page=200&page={n}`
       - Loop until response array is empty or page > 10 (safety cap = 2000 activities)
    6. For each activity, compute `normalized_sport` from `sport_type`
    7. Batch upsert into `strava_activities` (ON CONFLICT `(user_id, strava_activity_id)` DO UPDATE)
    8. Update `strava_connections.last_sync_at` = `now()`
    9. Return `{ synced_count: N, total_activities: M }`

  - [x] 🟩 Rate limit awareness: if Strava returns 429, stop pagination and return partial result with `{ rate_limited: true }`

  - [x] 🟩 Token refresh helper function (shared between auth and sync — inline in sync, not a separate module)

---

### Phase 4: iOS Models + Service

- [x] 🟩 **Step 4: Create `Dromos/Dromos/Core/Models/StravaModels.swift`**
  ```swift
  struct StravaActivity: Codable, Identifiable {
      let id: UUID
      let userId: UUID
      let stravaActivityId: Int64
      let sportType: String
      let normalizedSport: String?
      let name: String?
      let startDate: Date
      let startDateLocal: Date
      let elapsedTime: Int      // seconds
      let movingTime: Int       // seconds
      let distance: Double?     // meters
      let totalElevationGain: Double?
      let averageSpeed: Double?
      let averageHeartrate: Double?
      let averageWatts: Double?
      let isManual: Bool
      let createdAt: Date
  }
  ```

- [x] 🟩 **Step 5: Add `stravaAthleteId` to `User` model**
  - In `Dromos/Dromos/Core/Models/User.swift`, add:
    ```swift
    let stravaAthleteId: Int64?  // Non-nil = Strava connected
    ```
  - Computed property:
    ```swift
    var isStravaConnected: Bool { stravaAthleteId != nil }
    ```

- [x] 🟩 **Step 6: Create `Dromos/Dromos/Core/Services/StravaService.swift`**
  ```swift
  @MainActor final class StravaService: ObservableObject {
      private let client = SupabaseClientProvider.client
      @Published var isSyncing = false
      @Published var lastSyncResult: SyncResult?
      @Published var errorMessage: String?

      // OAuth: opens ASWebAuthenticationSession
      func startOAuth() async { ... }

      // Called from .onOpenURL — sends code to strava-auth Edge Function
      func handleCallback(url: URL) async { ... }

      // Disconnect: calls DELETE on strava-auth
      func disconnect() async { ... }

      // Sync: calls strava-sync Edge Function
      func syncActivities() async { ... }

      // Fetch stored activities from DB
      func fetchActivities(from: Date?, to: Date?) async -> [StravaActivity] { ... }
  }
  ```
  - `startOAuth()` uses `ASWebAuthenticationSession`:
    - URL: `https://www.strava.com/oauth/mobile/authorize`
    - Params: `client_id`, `redirect_uri=dromos://strava-callback`, `response_type=code`, `scope=activity:read_all`, `approval_prompt=auto`
    - Callback scheme: `dromos`
  - `handleCallback(url:)`: extracts `code` from URL query params, calls `strava-auth` Edge Function
  - `syncActivities()`: calls `strava-sync` Edge Function, updates `isSyncing`/`lastSyncResult`
  - `fetchActivities()`: direct Supabase query on `strava_activities` table (RLS allows SELECT)

- [x] 🟩 **Step 7: Update `Configuration.swift` + `Secrets.swift`**
  - `Secrets.swift`: add `static let stravaClientId = "<value>"`
  - `Secrets.example`: add placeholder
  - `Configuration.swift`: add `static var stravaClientId: String { Secrets.stravaClientId }`

---

### Phase 5: iOS URL Scheme + OAuth Callback

- [x] 🟩 **Step 8: Register URL scheme in Xcode**
  - Add URL scheme `dromos` to the app target (Target → Info → URL Types)
  - Add `strava` to `LSApplicationQueriesSchemes` (for canOpenURL check)

- [x] 🟩 **Step 9: Handle OAuth callback in `DromosApp.swift`**
  - Add `.onOpenURL` modifier on the `WindowGroup`:
    ```swift
    .onOpenURL { url in
        guard url.scheme == "dromos", url.host == "strava-callback" else { return }
        Task { await stravaService.handleCallback(url: url) }
    }
    ```
  - `StravaService` needs to be accessible from `DromosApp` — create as `@StateObject` or pass through environment. Follow the same pattern as `AuthService` (created in `DromosApp`, passed down).

---

### Phase 6: iOS Profile UI — Strava Section

- [x] 🟩 **Step 10: Add Strava section to `ProfileView.swift`**
  - New `Section("Strava")` in the Form, positioned before "Sign Out":
    - **Not connected**: "Connect Strava" button → triggers `stravaService.startOAuth()`
    - **Connected**: Show Strava athlete ID + last sync time + "Disconnect" button (with confirmation alert)
    - **Syncing**: Show progress indicator with "Syncing activities..."
    - **Sync result**: Brief text "X activities synced" (dismisses after 3s)

- [x] 🟩 **Step 11: Auto-sync on app open**
  - In `MainTabView.swift` or `RootView.swift`, trigger `stravaService.syncActivities()` in `.task {}` when user is authenticated and `isStravaConnected`:
    ```swift
    .task {
        if profileService.user?.isStravaConnected == true {
            await stravaService.syncActivities()
        }
    }
    ```
  - Sync is silent (no UI unless error) — `isSyncing` is available for future UI if needed

---

## Notes

- **Strava rate limits**: 100 req/15 min, 1000 req/day per app. With `per_page=200` and 10-page cap, worst case is 11 requests per sync (10 pages + 1 token refresh). Safe for single-user testing; monitor as user count grows.
- **Strava app sandbox**: New apps only work with the developer's own account. Apply to Strava Developer Program before beta launch.
- **Future: webhook sync** — Replace on-demand sync with Strava push subscriptions. Requires a new `strava-webhook` Edge Function with GET (validation) and POST (event) handlers. Separate issue.
- **Future: session matching** — Match `strava_activities` to `plan_sessions` by date + `normalized_sport`. The `normalized_sport` column is pre-computed for this purpose.
- **Deploy commands**:
  ```bash
  # Deploy edge functions
  supabase functions deploy strava-auth --no-verify-jwt
  supabase functions deploy strava-sync --no-verify-jwt
  # Run migration
  supabase db push
  ```
