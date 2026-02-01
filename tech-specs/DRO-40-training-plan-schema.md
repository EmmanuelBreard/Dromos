# DRO-40: DB Schema — training_plans, plan_weeks, plan_sessions

**Overall Progress:** `100%`

## TLDR

Create 3 Postgres tables (`training_plans`, `plan_weeks`, `plan_sessions`) that serve as the contract between the Edge Function writer (DRO-41) and the iOS display layer (DRO-43/44). SELECT-only RLS — Edge Function writes via service_role key.

## Critical Decisions

- **No `total_hours` column**: Computed client-side from `SUM(duration_minutes)` of fetched sessions. Always accurate, zero duplication.
- **No `archived` status**: Old plan is deleted before generating a new one. Status enum is just `generating` | `active`.
- **`rest_days JSONB` on `plan_weeks`**: Stored explicitly from macro plan rather than derived from session absence. Enables "Rest Day" labels without ambiguity.
- **`notes TEXT` on `plan_weeks`**: Stores per-week coach notes from macro plan. Usage TBD.
- **`plan_sessions.notes` nullable**: Column exists but left NULL for now. Future: coach notes per session.
- **SELECT-only RLS**: Edge Function uses `service_role` key for all writes (INSERT/UPDATE/DELETE). iOS client reads via user JWT + RLS.
- **Delete-and-replace on re-generation**: No plan history. `UNIQUE(user_id)` on `training_plans` enforced at DB level.
- **Migration numbered `006`**: Continues from existing migration sequence despite only `003` being tracked.

## Tasks

- [x] 🟩 **Step 1: Verify `update_updated_at()` function exists**
  - [x] 🟩 Confirmed function exists in migration 001 (named `update_updated_at()`)
  - [x] 🟩 Included CREATE OR REPLACE at top of migration for safety

- [x] 🟩 **Step 2: Create migration `006_create_training_plan_tables`**
  - [x] 🟩 Create `training_plans` table (id, user_id UNIQUE, status, race_date, race_objective, total_weeks, start_date, timestamps)
  - [x] 🟩 Create `plan_weeks` table (id, plan_id FK, week_number, phase, is_recovery, rest_days JSONB, notes, start_date, UNIQUE on plan_id+week_number)
  - [x] 🟩 Create `plan_sessions` table (id, week_id FK, day, sport, type, template_id, duration_minutes, is_brick, notes, order_in_day)
  - [x] 🟩 Add CHECK constraints on all enum-like TEXT columns
  - [x] 🟩 Add indexes: `plan_sessions(week_id, day)`, `plan_weeks(start_date)`
  - [x] 🟩 Add `updated_at` trigger on `training_plans`
  - [x] 🟩 Enable RLS + create SELECT-only policies on all 3 tables

- [ ] 🟨 **Step 3: Verify migration** (Pending application)
  - [ ] 🟨 Confirm all tables, columns, and types are correct via `information_schema`
  - [ ] 🟨 Confirm RLS is enabled on all 3 tables
  - [ ] 🟨 Confirm indexes exist
  - [ ] 🟨 Run security advisors to check for issues
  - **Note**: Migration file ready. Apply via Supabase CLI: `supabase db push` or via Supabase dashboard SQL editor.

- [x] 🟩 **Step 4: Create local migration file**
  - [x] 🟩 Write `supabase/migrations/006_create_training_plan_tables.sql` with complete SQL including UP/DOWN migrations
