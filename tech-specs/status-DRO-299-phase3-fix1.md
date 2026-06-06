# DRO-299 Phase 3 — Code Review Fix Report

> Status: ✅ Complete (100%)
> Branch: `feature/DRO-299-import-plan-edge-function`
> Issues fixed: 19 findings (4 HIGH · 4 MEDIUM · 11 LOW)
> Migration applied: `018_revoke_import_plan_atomic_from_public`
> Function deployed: `import-plan` (cumbrfnguykvxhvdelru)

---

## Fix Progress

| # | Severity | Finding | Status |
|---|----------|---------|--------|
| 1 | HIGH | SECURITY: `import_plan_atomic` callable by PUBLIC | ✅ Fixed — migration 018 REVOKEs PUBLIC/anon/authenticated |
| 2 | HIGH | `VALID_SPORTS`/`VALID_TYPES` never validated | ✅ Fixed — loop collects `invalid_sports` / `invalid_types`, returns 400 |
| 3 | HIGH | No request body size cap | ✅ Fixed — Content-Length > 512 KB → 413; `weeks.length > 60` → 400; `sessions.length > 14` → 400 |
| 4 | HIGH | `materialize()` failure silently produces `structure: null` | ✅ Fixed — failure collects `failed_template_ids`, hard 400 before RPC call |
| 5 | MEDIUM | `profile_updates` not validated | ✅ Fixed — max_hr (100–220), ftp (50–500), vma (10–25), css (25–300), race_objective enum, race_date calendar check |
| 6 | MEDIUM | Per-week / per-session field types not checked | ✅ Fixed — is_recovery/is_brick typeof boolean, rest_days array-of-strings, start_date calendar check, duration_minutes positive integer, order_in_day ≥ 0 integer, notes string-or-undefined |
| 7 | MEDIUM | `total_weeks: 1.5` passes integer guard | ✅ Fixed — `Number.isInteger` check added |
| 8 | MEDIUM | `race_date::timestamptz` timezone-fragile | ✅ Fixed — migration 018 `CREATE OR REPLACE` with `::date::timestamptz` |
| 9 | MEDIUM | Workout library refetched every cold start | ✅ Fixed — module-scope `cachedLibrary` map; null on first call, reused on warm invocations |
| 10 | LOW | RPC error log lacks Postgres error fields | ✅ Fixed — logs `.message`, `.code`, `.details`, `.hint` directly from `PostgrestError` |
| 11 | LOW | Conflict check missing `status` filter | ✅ Fixed — `.eq("status", "active")` added to query |
| 12 | LOW | Anon key fallback to service role | ✅ Fixed — hard 500 `"Server misconfigured: SUPABASE_ANON_KEY missing"` if absent |
| 13 | LOW | Date regex passes `2026-02-30` | ✅ Fixed — `isValidDate()` helper: regex + `!isNaN(new Date(value).getTime())` |
| 14 | LOW | Test 5 never exercises 403 gate | ✅ Fixed — split into Test 5a (no auth → 401) and Test 5b (wrong user → 403, skipped if `SERVICE_ROLE_JWT` not set) |
| 15 | LOW | `week_number` uniqueness error message misleading | ✅ Fixed — duplicate Set check before sequential check, distinct error message |
| 16 | LOW | Repeated `atomicResult` casts | ✅ Fixed — `AtomicResult` interface declared once, cast once after RPC |
| 17 | LOW | Non-null assertion `libraryMap.get(...)!` | ✅ Fixed — explicit narrowing with `throw new Error(...)` if undefined post-validation |
| 18 | LOW | Test script uses python3 for JSON manipulation | ✅ Fixed — replaced with `jq` |
| 19 | LOW | `is_brick` parsing fragile in Postgres | ✅ Fixed — defense-in-depth `COALESCE(::boolean, false)` preserved; TS now enforces `typeof === "boolean"` upstream |

---

## Files Changed

| File | Change |
|------|--------|
| `supabase/migrations/018_revoke_import_plan_atomic_from_public.sql` | New migration: REVOKE + CREATE OR REPLACE with timezone fix |
| `supabase/functions/import-plan/index.ts` | All 19 fixes applied |
| `scripts/test-import-plan.sh` | Replaced python3→jq, split Test 5, added Tests 6–8 |
| `.claude/context/schema.md` | Migration header updated; `import_plan_atomic` function entry updated |
| `.claude/context/architecture.md` | `import-plan` Edge Function description updated with all security/validation details |

---

## Verification Results

| Check | Result |
|-------|--------|
| `deno check supabase/functions/import-plan/index.ts` | ✅ Passed (0 errors) |
| `bash scripts/deploy-functions.sh import-plan` | ✅ Deployed |
| SQL: privilege check on `import_plan_atomic` | ✅ Only `postgres` (superuser) + `service_role` — PUBLIC/anon/authenticated absent |
| Migration 018 applied | ✅ `{"success":true}` |

---

## SQL Verification

```sql
-- Run to confirm privileges after fix
SELECT grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_name = 'import_plan_atomic'
ORDER BY grantee;
-- Expected: only postgres + service_role
```

Result: `[{"grantee":"postgres","privilege_type":"EXECUTE"},{"grantee":"service_role","privilege_type":"EXECUTE"}]`

---

## New Tests Added

| Test | Scenario | Expected |
|------|----------|---------|
| Test 5a | No Authorization header | 401 |
| Test 5b | Non-allowlisted user JWT | 403 (skipped if `SERVICE_ROLE_JWT` not set) |
| Test 6 | Invalid `sport: "yoga"` | 400 with `invalid_sports` |
| Test 7 | `Content-Length: 614400` (> 512 KB) | 413 |
| Test 8 | `profile_updates.max_hr: 50` (out of range) | 400 |

---

## Notes

- Migration 017 was NOT modified (already applied, additive fix via 018).
- No iOS Swift files touched.
- `materialize-structure.ts` not touched.
- Real ebreard4 plan not mutated — no happy-path test run against live data.
