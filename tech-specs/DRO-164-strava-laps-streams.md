# DRO-164: Fetch Strava Streams & Laps for Session Compliance Checking

**Overall Progress:** `0%`

## TLDR
Extend `strava-sync` to fetch lap and stream data for every synced activity, store laps in a new table and streams as JSONB, and feed formatted lap summaries into the `session-feedback` AI prompt so coaching feedback can analyze interval-level compliance.

## Critical Decisions
- **Both laps AND streams** — laps for immediate prompt enrichment, streams stored for future interval inference (auto-lap users)
- **Laps in dedicated table, streams as JSONB column** — laps are structured/queryable, streams are raw blobs consumed later
- **Skip single-lap activities** — no extra info over the existing summary
- **Skip manual activities** — no GPS/sensor data to fetch
- **Laps-only in prompt** — no raw stream data to the LLM (token budget)
- **Fetch for all activities** — including 90-day first-sync lookback, with rate limit awareness
- **No iOS UI changes** — backend plumbing only in this ticket

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `supabase/migrations/015_strava_laps_and_streams.sql` | CREATE | New `strava_activity_laps` table + `streams_data` JSONB column on `strava_activities` |
| `supabase/functions/strava-sync/index.ts` | MODIFY | Add lap + stream fetching after activity upsert, rate limit pacing |
| `ai/prompts/session-feedback-v0.txt` | MODIFY | Add `{{laps}}` section to prompt template |
| `supabase/functions/session-feedback/prompts/session-feedback-v0-prompt.ts` | REGENERATED | Auto-generated via `scripts/sync-prompts.sh` after editing canonical .txt |
| `supabase/functions/session-feedback/index.ts` | MODIFY | Fetch laps from DB, format as text, inject into prompt |

## Context Doc Updates
- `schema.md` — new `strava_activity_laps` table, new `streams_data` column on `strava_activities`
- `architecture.md` — updated `strava-sync` description (now fetches laps + streams)
- `ai-pipeline.md` — updated session-feedback prompt documentation (new `{{laps}}` variable)

## Tasks

### Phase 1: Database Migration

- [ ] **Step 1: Create migration `015_strava_laps_and_streams.sql`**

  - [ ] Create `strava_activity_laps` table:
    ```sql
    CREATE TABLE public.strava_activity_laps (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        activity_id UUID NOT NULL REFERENCES public.strava_activities(id) ON DELETE CASCADE,
        lap_index INT NOT NULL,
        elapsed_time INT NOT NULL,
        moving_time INT NOT NULL,
        distance DOUBLE PRECISION,
        average_speed DOUBLE PRECISION,
        average_cadence DOUBLE PRECISION,
        average_watts DOUBLE PRECISION,
        average_heartrate DOUBLE PRECISION,
        max_heartrate DOUBLE PRECISION,
        start_index INT,
        end_index INT,
        UNIQUE(activity_id, lap_index)
    );
    ```
  - [ ] Enable RLS on `strava_activity_laps`
  - [ ] Add RLS policy: SELECT own laps via join to `strava_activities`:
    ```sql
    CREATE POLICY "Users can read own activity laps"
        ON public.strava_activity_laps
        FOR SELECT
        USING (
            EXISTS (
                SELECT 1 FROM public.strava_activities sa
                WHERE sa.id = activity_id AND sa.user_id = auth.uid()
            )
        );
    ```
  - [ ] Add index: `CREATE INDEX idx_strava_activity_laps_activity_id ON public.strava_activity_laps(activity_id);`
  - [ ] Add `streams_data` JSONB column to `strava_activities`:
    ```sql
    ALTER TABLE public.strava_activities ADD COLUMN streams_data JSONB;
    ```
    Comment: `Raw Strava streams (time, heartrate, watts, cadence, velocity_smooth, distance arrays). NULL if not yet fetched or fetch failed.`
  - [ ] Include DOWN migration comments
  - [ ] Apply migration via Supabase MCP

---

### Phase 2: Extend `strava-sync` to Fetch Laps + Streams

- [ ] **Step 2: Add Strava API types and helpers**

  In `supabase/functions/strava-sync/index.ts`:

  - [ ] Add `StravaLap` interface:
    ```typescript
    interface StravaLap {
      lap_index: number;
      elapsed_time: number;
      moving_time: number;
      distance: number;
      average_speed: number;
      average_cadence?: number;
      average_watts?: number;
      average_heartrate?: number;
      max_heartrate?: number;
      start_index: number;
      end_index: number;
    }
    ```
  - [ ] Add `StravaStream` interface (Strava returns `{ type, data, series_type, original_size, resolution }` per stream key):
    ```typescript
    interface StravaStreamEntry {
      type: string;
      data: number[];
      series_type: string;
      original_size: number;
      resolution: string;
    }
    ```
  - [ ] Add constants:
    ```typescript
    const STRAVA_STREAM_KEYS = "time,heartrate,watts,cadence,velocity_smooth,distance";
    ```

- [ ] **Step 3: Add `fetchLapsAndStreams` function**

  New async function called after activity upsert in step 7. Takes `accessToken`, `activities` (the just-upserted activities array with their strava_activity_ids and DB UUIDs), and the `db` client.

  Logic:
  1. Filter out manual activities (`is_manual === true`)
  2. For each activity, sequentially (to respect rate limits):
     a. `GET /activities/{strava_activity_id}/laps` → parse as `StravaLap[]`
     b. `GET /activities/{strava_activity_id}/streams?keys={STRAVA_STREAM_KEYS}&key_by_type=true` → parse as stream object
     c. If 429 response on either call, stop processing remaining activities (log warning, break)
     d. If other error, log and continue to next activity
  3. For laps: skip if only 1 lap returned. Otherwise, upsert into `strava_activity_laps` with conflict on `(activity_id, lap_index)`
  4. For streams: update `strava_activities.streams_data` with the raw JSON object

  Important: we need the DB `id` (UUID) for each activity to write laps/streams. The upsert in step 7 doesn't return IDs. Two options:
  - **Option A:** After upsert, query `strava_activities` to get `id` by `(user_id, strava_activity_id)` for all synced activities
  - **Option B:** Use `.upsert(...).select('id, strava_activity_id')` to get IDs back from the upsert

  Use **Option B** — modify existing upsert to `.select('id, strava_activity_id')` so we get the mapping without an extra query.

- [ ] **Step 4: Integrate into main handler**

  After the existing activity upsert (step 7, around line 323):
  1. Extract `id` ↔ `strava_activity_id` mapping from upsert result
  2. Build activity info array (strava_activity_id, db_id, is_manual) from the mapping + original activity data
  3. Call `fetchLapsAndStreams(accessToken, activityInfos, db)`
  4. The function is fire-and-don't-fail — errors are logged but sync still succeeds

  Update the response to include `laps_fetched_count` alongside existing `synced_count`.

---

### Phase 3: Enrich Session Feedback Prompt with Laps

- [ ] **Step 5: Update canonical prompt**

  Edit `ai/prompts/session-feedback-v0.txt`:

  Add a new section between `## Actual (Strava)` and `## This Week`:
  ```
  ## Laps
  {{laps}}
  ```

  Update `## Rules` — add one bullet:
  ```
  - If lap data is provided, use it to analyze interval execution: did the athlete hold consistent effort across laps? Did they fade? Did splits match what the session type would demand (e.g., even splits for tempo, progressive for build runs)? If laps are just auto-splits (e.g., every 1km), comment on pacing consistency across splits.
  ```

  Run `scripts/sync-prompts.sh` to regenerate the `.ts` file.

- [ ] **Step 6: Update `session-feedback/index.ts` to fetch and format laps**

  After fetching the activity (step 7 of the existing handler, ~line 254):

  1. Add a new parallel fetch for laps:
     ```typescript
     // d) Activity laps
     db
       .from("strava_activity_laps")
       .select("lap_index, elapsed_time, moving_time, distance, average_speed, average_cadence, average_watts, average_heartrate, max_heartrate")
       .eq("activity_id", stravaActivityId)
       .order("lap_index", { ascending: true }),
     ```

  2. Add a `formatLaps` function that takes `laps[]` and `sport` string, returns formatted text:
     - For each lap: `"Lap {n}: {duration} duration, avg {hr} bpm, {sport-specific metric}, {distance}"`
       - Run: pace as min:sec/km
       - Bike: power as W
       - Swim: pace as min:sec/100m
     - Compute rest between laps: `lap[n+1].start_index - lap[n].end_index` mapped to elapsed time if available, else `"(rest unknown)"`
     - If no laps: return `"No lap data available."`
     - Reuse existing `formatPace()` helper for pace formatting

  3. Replace `{{laps}}` in the rendered prompt with `formatLaps(laps, session.sport)`

---

### Phase 4: Context Docs & Cleanup

- [ ] **Step 7: Update context docs**
  - [ ] `schema.md` — add `strava_activity_laps` table, `streams_data` column, RLS policy, index
  - [ ] `architecture.md` — update `strava-sync` description to mention lap + stream fetching
  - [ ] `ai-pipeline.md` — document `{{laps}}` template variable in session-feedback section

- [ ] **Step 8: Deploy & verify**
  - [ ] Deploy migration via Supabase MCP
  - [ ] Deploy `strava-sync` edge function: `scripts/deploy-functions.sh strava-sync`
  - [ ] Deploy `session-feedback` edge function: `scripts/deploy-functions.sh session-feedback`
  - [ ] Manual test: trigger sync for a connected Strava user, verify laps appear in `strava_activity_laps` and `streams_data` is populated
  - [ ] Manual test: trigger session feedback for a completed session with laps, verify prompt includes lap data and feedback references interval execution
