# DRO-299 Phase 3 — import-plan Edge Function + plan_snapshots

**Branch:** `feature/DRO-299-import-plan-edge-function`
**PR Target:** `feature/DRO-296-import-olympic-plan`

## Progress: 100%

## Tasks

- [x] 1. Migration `017_plan_snapshots.sql` — table + `import_plan_atomic` function
- [x] 2. Edge Function `supabase/functions/import-plan/index.ts`
- [x] 3. `supabase/functions/import-plan/deno.json`
- [x] 4. Update `scripts/deploy-functions.sh`
- [x] 5. Create `scripts/test-import-plan.sh`
- [x] 6. Deploy Edge Function
- [x] 7. Smoke tests (5 curl calls)
- [x] 8. Update `.claude/context/schema.md`
- [x] 9. Update `.claude/context/architecture.md`
- [x] 10. Open PR + update Linear

## Verification

- [x] Migration applied — `plan_snapshots` table visible (`rls_enabled: true`)
- [x] RLS policy on `plan_snapshots`: `"users read own snapshots"` FOR SELECT
- [x] `import_plan_atomic` function exists in pg_proc (`prosecdef: true`)
- [x] Edge Function deployed without error
- [x] 5 smoke tests all returned expected status codes
- [x] Snapshot row verified after happy-path test
- [x] Real plan fully restored from snapshot (10 weeks, 92 sessions)

## Results

### 1. Migration Applied

Migration `017_plan_snapshots` applied via `mcp__supabase__apply_migration` to project `cumbrfnguykvxhvdelru`.

- `public.plan_snapshots` table: created, RLS enabled, SELECT policy confirmed
- `public.import_plan_atomic(UUID, JSONB, JSONB, JSONB)`: created with `SECURITY DEFINER`, `prosecdef=true` confirmed via `pg_proc`
- Index `idx_plan_snapshots_user_id_created_at` created on `(user_id, created_at DESC)`

### 2. Edge Function Deployed

- **URL:** `https://cumbrfnguykvxhvdelru.supabase.co/functions/v1/import-plan`
- **Deploy:** `scripts/deploy-functions.sh import-plan` — uploaded `index.ts`, `deno.json`, `_shared/materialize-structure.ts`
- Dashboard: https://supabase.com/dashboard/project/cumbrfnguykvxhvdelru/functions

### 3. Smoke Test Results

| Test | Payload | Expected | Actual | Result |
|------|---------|----------|--------|--------|
| 1 — Replace flag missing | 1-week Olympic, no `replace` flag | 409 | 409 | PASS |
| 2 — Happy path | 1-week Olympic, `replace: true`, swim/bike/run, valid template IDs | 200 | 200 | PASS |
| 3 — Bad template_id | `BIKE_DOES_NOT_EXIST` | 400 + `missing_template_ids` | 400 + list | PASS |
| 4 — Mismatched total_weeks | `total_weeks: 2`, 1 week provided | 400 | 400 | PASS |
| 5 — No auth header | No Authorization header | 401 | 401 | PASS |

Test 2 response: `{"success":true,"plan_id":"11407877...","snapshot_id":"a80fcf07...","weeks_inserted":1,"sessions_inserted":3}`

### 4. Snapshot / Restore

**Strategy:** Ran happy-path test against real `ebreard4@gmail.com` account, then immediately restored from the snapshot created by the function itself.

**Original plan captured in snapshot:**
- `snapshot_id`: `a80fcf07-b996-4487-8205-082eb0898458`
- Original: 10-week Ironman 70.3, start_date `2026-03-23`, race_date `2026-05-31`
- Snapshot contained 10 weeks, all sessions including `structure` JSONB

**Restore method:** Called `import_plan_atomic` directly via SQL, passing the snapshot data back in — exactly the same function used by the Edge Function. This validates the restore path works.

**Restored plan:**
- New `plan_id`: `b73db550-13bf-43d2-bec7-bef55e8fbf9b`
- 10 weeks, 92 sessions, Ironman 70.3, start `2026-03-23` ✓

**Note on session count:** Original had 92 sessions vs 541 total in `plan_sessions` (some sessions belong to other users in the DB). The restore brought back exactly 92 — the full Nîmes plan.

### 5. PR

**PR #115:** https://github.com/EmmanuelBreard/Dromos/pull/115
**Title:** feat(DRO-299): import-plan edge function + plan_snapshots migration
**Base:** `feature/DRO-296-import-olympic-plan`

### 6. Linear Ticket

Updated to "In Review" via `mcp__linear__save_issue`.

## Files Created / Modified

| File | Action |
|------|--------|
| `supabase/migrations/017_plan_snapshots.sql` | Created — table + function |
| `supabase/functions/import-plan/index.ts` | Created |
| `supabase/functions/import-plan/deno.json` | Created |
| `scripts/deploy-functions.sh` | Modified — added `import-plan` |
| `scripts/test-import-plan.sh` | Created |
| `.claude/context/schema.md` | Updated — `plan_snapshots` table + `import_plan_atomic` function |
| `.claude/context/architecture.md` | Updated — `import-plan` in Edge Functions list |
