# Database Schema Reference

> Last updated: 2026-02-22 | Migrations: 001-013 + summary_polyline

## Tables Overview

```
auth.users → public.users (1:1) → training_plans (1:1 via UNIQUE) → plan_weeks (1:N) → plan_sessions (1:N)
public.users (1:1) → strava_connections
public.users (1:N) → strava_activities
```

All foreign keys use ON DELETE CASCADE. All tables use RLS.

---

## `public.users`

Profile data linked to `auth.users` via UUID primary key.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, FK → `auth.users(id)` CASCADE | Auth ID |
| `email` | TEXT | NOT NULL | |
| `name` | TEXT | | Display name |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` | Auto-trigger |
| `race_objective` | TEXT | CHECK IN ('Sprint','Olympic','Ironman 70.3','Ironman') OR NULL | |
| `race_date` | TIMESTAMPTZ | | Target race date |
| `time_objective_minutes` | INT | CHECK > 0 OR NULL | Target race time |
| `vma` | DECIMAL(4,2) | CHECK 10-25 OR NULL | VO2max pace (km/h) |
| `css_seconds_per100m` | INT | CHECK 25-300 OR NULL | Critical Swim Speed |
| `ftp` | INT | CHECK 50-500 OR NULL | Functional Threshold Power (watts) |
| `experience_years` | INT | CHECK >= 0 OR NULL | |
| `onboarding_completed` | BOOLEAN | NOT NULL, DEFAULT FALSE | |
| `swim_days` | JSONB | DEFAULT `'[]'` | e.g. `["Monday","Wednesday"]` (full day names) |
| `bike_days` | JSONB | DEFAULT `'[]'` | Same format as swim_days |
| `run_days` | JSONB | DEFAULT `'[]'` | Same format as swim_days |
| `mon_duration` | INT | CHECK 30-420 OR NULL | Minutes available Monday |
| `tue_duration` | INT | CHECK 30-420 OR NULL | |
| `wed_duration` | INT | CHECK 30-420 OR NULL | |
| `thu_duration` | INT | CHECK 30-420 OR NULL | |
| `fri_duration` | INT | CHECK 30-420 OR NULL | |
| `sat_duration` | INT | CHECK 30-420 OR NULL | |
| `sun_duration` | INT | CHECK 30-420 OR NULL | |
| `current_weekly_hours` | DECIMAL(3,1) | CHECK 0-25 OR NULL | Self-reported avg weekly hours |

**Triggers:** `on_auth_user_created` (auto-insert on signup), `update_users_updated_at` (auto-update timestamp)

**RLS:** SELECT/UPDATE/INSERT own row only (`auth.uid() = id`)

---

## `public.training_plans`

Top-level plan container. One active plan per user (UNIQUE on `user_id`).

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, DEFAULT `gen_random_uuid()` | |
| `user_id` | UUID | NOT NULL, UNIQUE, FK → `users(id)` CASCADE | |
| `status` | TEXT | NOT NULL, CHECK IN ('generating','active') | |
| `race_date` | DATE | | Snapshot at creation |
| `race_objective` | TEXT | | Snapshot at creation |
| `total_weeks` | INT | NOT NULL, CHECK > 0 | |
| `start_date` | DATE | NOT NULL | |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` | Auto-trigger |

**RLS:** SELECT own plan only. No client UPDATE/INSERT (Edge Function writes via `service_role`).

---

## `public.plan_weeks`

Weekly division of a plan.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, DEFAULT `gen_random_uuid()` | |
| `plan_id` | UUID | NOT NULL, FK → `training_plans(id)` CASCADE | |
| `week_number` | INT | NOT NULL, CHECK > 0 | |
| `phase` | TEXT | NOT NULL, CHECK IN ('Base','Build','Peak','Taper','Recovery') | |
| `is_recovery` | BOOLEAN | NOT NULL, DEFAULT FALSE | |
| `rest_days` | JSONB | NOT NULL, DEFAULT `'[]'` | e.g. `["Monday","Friday"]` (full day names, same format as user availability) |
| `notes` | TEXT | | Coach notes |
| `start_date` | DATE | NOT NULL | |
| UNIQUE(`plan_id`, `week_number`) | | | |

**RLS:** SELECT own weeks (via join to `training_plans`).

**Indexes:** `idx_plan_weeks_start_date` on `(start_date)`

---

## `public.plan_sessions`

Individual training sessions within a week.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, DEFAULT `gen_random_uuid()` | |
| `week_id` | UUID | NOT NULL, FK → `plan_weeks(id)` CASCADE | |
| `day` | TEXT | NOT NULL, CHECK IN (Mon-Sun) | |
| `sport` | TEXT | NOT NULL, CHECK IN ('swim','bike','run') | |
| `type` | TEXT | NOT NULL, CHECK IN ('Easy','Tempo','Intervals') | |
| `template_id` | TEXT | NOT NULL | e.g. `BIKE_Tempo_03` |
| `duration_minutes` | INT | NOT NULL, CHECK > 0 | |
| `is_brick` | BOOLEAN | NOT NULL, DEFAULT FALSE | |
| `notes` | TEXT | | |
| `order_in_day` | INT | NOT NULL, DEFAULT 0 | |
| `feedback` | TEXT | | AI-generated coaching commentary |
| `matched_activity_id` | UUID | FK → `strava_activities(id)` | Persists the Strava match for feedback |

**RLS:** SELECT own sessions (via join to `plan_weeks` → `training_plans`). No direct UPDATE — all writes go through `reorder_sessions` RPC.

**Indexes:** `idx_plan_sessions_week_id_day` on `(week_id, day)`

---

## Functions

| Function | Type | Behavior |
|----------|------|----------|
| `handle_new_user()` | TRIGGER (AFTER INSERT on `auth.users`) | Auto-inserts `users` row with id/email/name |
| `update_updated_at()` | TRIGGER (BEFORE UPDATE) | Sets `updated_at = now()` on `users` and `training_plans` |
| `reorder_sessions(JSONB)` | RPC (SECURITY DEFINER) | Batch-updates `day`, `week_id`, `order_in_day` on `plan_sessions`. Validates per-row ownership via `auth.uid()`. GRANT EXECUTE TO authenticated. |

---

---

## `public.strava_connections`

One row per user. Stores OAuth tokens for Strava API access.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `user_id` | UUID | PK, FK → `users(id)` CASCADE | |
| `strava_athlete_id` | BIGINT | NOT NULL | Strava athlete ID |
| `access_token` | TEXT | NOT NULL | Short-lived token |
| `refresh_token` | TEXT | NOT NULL | Long-lived token |
| `expires_at` | TIMESTAMPTZ | NOT NULL | Token expiry |
| `scope` | TEXT | NOT NULL | Granted OAuth scope (e.g. `activity:read_all`) |
| `last_sync_at` | TIMESTAMPTZ | | NULL on first sync |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` | |

**RLS:** Edge Functions use `service_role` (bypasses RLS). No direct client access.

---

## `public.strava_activities`

Synced Strava activities for a user. Written by the `strava-sync` Edge Function.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, DEFAULT `gen_random_uuid()` | |
| `user_id` | UUID | NOT NULL, FK → `users(id)` CASCADE | |
| `strava_activity_id` | BIGINT | NOT NULL | Strava activity ID |
| `sport_type` | TEXT | NOT NULL | Raw Strava sport type (e.g. `Run`, `Ride`) |
| `normalized_sport` | TEXT | CHECK IN ('run','bike','swim') OR NULL | Dromos canonical sport |
| `name` | TEXT | | Activity title |
| `start_date` | TIMESTAMPTZ | NOT NULL | UTC start |
| `start_date_local` | TIMESTAMPTZ | NOT NULL | Local start |
| `elapsed_time` | INT | NOT NULL | Seconds (0 if missing) |
| `moving_time` | INT | NOT NULL | Seconds (0 if missing) |
| `distance` | DOUBLE PRECISION | | Meters |
| `total_elevation_gain` | DOUBLE PRECISION | | Meters |
| `average_speed` | DOUBLE PRECISION | | m/s |
| `average_heartrate` | DOUBLE PRECISION | | BPM |
| `average_watts` | DOUBLE PRECISION | | Watts |
| `is_manual` | BOOLEAN | NOT NULL, DEFAULT FALSE | |
| `summary_polyline` | TEXT | | Encoded polyline from Strava map |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` | |

**UNIQUE:** `(user_id, strava_activity_id)` — upsert conflict target.

**RLS:** Edge Functions use `service_role`. iOS reads via user JWT (SELECT own rows).

---

## `public.users` — additional Strava column

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `strava_athlete_id` | BIGINT | | Denormalised from `strava_connections`. NULL = not connected. |

---

## Design Notes

- **Snapshots:** `training_plans` stores `race_date` and `race_objective` to preserve plan state if user edits profile later
- **JSONB for availability:** `swim_days`, `bike_days`, `run_days` use arrays instead of join tables (lightweight, LLM-friendly)
- **No soft deletes:** Hard deletes with CASCADE
- **No custom enums:** Validation via CHECK constraints on TEXT columns
- **Write pattern:** Edge Function writes via `service_role` key (bypasses RLS); iOS reads via user JWT; session reordering uses `reorder_sessions` RPC (SECURITY DEFINER with per-row ownership validation)

---

## `public.chat_messages`

Stores the conversation history between athletes and the AI coaching agent. Single continuous thread per user (no sessions). Created by migration `013_create_chat_messages.sql`.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, DEFAULT `gen_random_uuid()` | |
| `user_id` | UUID | NOT NULL, FK → `users(id)` CASCADE | |
| `role` | TEXT | NOT NULL, CHECK IN ('user', 'assistant') | Message sender |
| `content` | TEXT | NOT NULL | Message text |
| `status` | TEXT | CHECK IN ('ready', 'need_info', 'no_action', 'escalate') OR NULL | Only set on assistant messages |
| `constraint_summary` | JSONB | | Structured constraint data when status='ready' or 'escalate' |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT `now()` | |

**Index:** `idx_chat_messages_user_id_created_at` on `(user_id, created_at)` — optimises per-user history fetch.

**RLS:**
- SELECT: `auth.uid() = user_id` (iOS reads own messages)
- DELETE: `auth.uid() = user_id` (iOS clear history)
- INSERT: No authenticated policy — `chat-adjust` Edge Function writes via `service_role`
