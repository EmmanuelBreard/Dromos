# Database Schema Reference

> Last updated: 2026-02-14 | Migrations: 001-009

## Tables Overview

```
auth.users → public.users (1:1) → training_plans (1:1 via UNIQUE) → plan_weeks (1:N) → plan_sessions (1:N)
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
| `sex` | TEXT | | M/F |
| `birth_date` | TIMESTAMPTZ | | |
| `weight_kg` | DECIMAL(5,2) | CHECK 30-300 OR NULL | |
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

**RLS:** SELECT own sessions (via join to `plan_weeks` → `training_plans`).

**Indexes:** `idx_plan_sessions_week_id_day` on `(week_id, day)`

---

## Functions

| Function | Type | Behavior |
|----------|------|----------|
| `handle_new_user()` | TRIGGER (AFTER INSERT on `auth.users`) | Auto-inserts `users` row with id/email/name |
| `update_updated_at()` | TRIGGER (BEFORE UPDATE) | Sets `updated_at = now()` on `users` and `training_plans` |

---

## Design Notes

- **Snapshots:** `training_plans` stores `race_date` and `race_objective` to preserve plan state if user edits profile later
- **JSONB for availability:** `swim_days`, `bike_days`, `run_days` use arrays instead of join tables (lightweight, LLM-friendly)
- **No soft deletes:** Hard deletes with CASCADE
- **No custom enums:** Validation via CHECK constraints on TEXT columns
- **Write pattern:** Edge Function writes via `service_role` key (bypasses RLS); iOS reads only via user JWT
