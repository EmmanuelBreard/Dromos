# DRO-296 — Import High-Fidelity Olympic Plan for ebreard4 + Generalize Ingest

**Linear:** https://linear.app/dromosapp/issue/DRO-296/import-high-fidelity-olympic-plan-for-ebreard4-generalize-plan-ingest
**Overall Progress:** `60% (Phases 1-3 of 5 shipped via /ship 2026-06-06; Phases 4-5 reserved for manual payload authoring + final QA)`

> **Note:** Phases 1, 2, 3 were shipped via /ship on 2026-06-06 — DRO-297, DRO-298, DRO-299 closed. Renderer + library + Edge Function are in main. Phases 4 + 5 (payload authoring + ingest + final QA) remain manual and require coach-mode work outside of the agent pipeline.

## TLDR

Push a hand-crafted 15-week Olympic-distance training plan (race Sep 19 2026) for `ebreard4@gmail.com` into Dromos with **zero loss of detail** for swim/bike/run sessions. Build a reusable `import-plan` Edge Function so future hand-crafted plans can be ingested the same way. Strength sessions are stored as `sport='strength'` with `notes`-only display (no segments, no graph). Source plan: `miscellaneous/training-plan-olympic-sept-2026.md`.

The schema already supports rich Target types (`hr_pct_max` ranges, `power_watts` ranges, `pace_per_km`, `hr_zone`, etc.) and the materializer passes them through — but the iOS renderer has only been exercised with `vma_pct`/`ftp_pct`/swim `pace`. This spec covers the renderer audit + fixes needed for high-fidelity display.

## Critical Decisions

- **Fidelity-first:** All swim/bike/run sessions use rich Target types — never collapse a range to a midpoint, never drop HR caps. The renderer must handle every Target.type defined in `materialize-structure.ts:25-39`.
- **Strength: lite/notes-only.** `sport='strength'`, `template_id='STRENGTH_NOTES_ONLY'` (single placeholder), no segments. Renderer shows session name, duration, and the notes block (exercise list). No workout graph.
- **Brick modeling:** Two separate `plan_sessions` (bike + run), both `is_brick: true`, `order_in_day: 0` and `1`. Same convention as DRO-170.
- **Tune-up race Sep 12:** `sport='race'`, `type='Race'`. Same renderer as A-race.
- **Profile updates:** `race_objective='Olympic'`, `race_date='2026-09-19'`, `max_hr=193` (was 192), keep `ftp=275`, `vma=18.00`, `css_seconds_per100m=110` (was 115 — recalibrated to 1:50/100m threshold).
- **Rest day:** Thursday weeks 1-14, Monday week 15 (race recovery). Stored in `plan_weeks.rest_days` JSONB.
- **Phase mapping:** Block 1→Recovery, Block 2→Base, Block 3→Build, Block 4→Peak, Block 5→Taper, Block 6→Taper.
- **Ingest path:** Reusable `import-plan` Edge Function, allowlist-gated to `ebreard4@gmail.com` for V0. Takes a typed JSON body. Validates template_ids exist. Atomically deletes existing plan + inserts new one in a transaction. Writes `structure` JSONB via the shared `materialize` function.
- **Rollback:** Edge Function snapshots existing plan to a `plan_snapshots` JSONB row before delete, so we can recover.
- **No new sport/type values:** existing CHECK constraints suffice (strength is already in `plan_sessions.sport` allowlist per DRO-170; type 'Race' for race days).

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `ai/context/workout-library.json` | MODIFY | Add ~35 new templates (10 bike, 10 run, 8 swim, 1 strength placeholder, 2 race, 4 brick-pair pieces). Use rich targets (hr_pct_max ranges, power_watts, pace_per_km, hr_zone). |
| `Dromos/Dromos/Core/Models/WorkoutTemplate.swift` | MODIFY | Ensure decoder supports all Target types end-to-end (hr_pct_max ranges, power_watts ranges, pace_per_km, pace_per_100m, hr_zone, hr_max). Add `strength` to `WorkoutLibrary` struct as optional. |
| `Dromos/Dromos/Core/Services/WorkoutLibraryService.swift` | MODIFY | Update `loadLibrary()` to index strength templates. Update `stepSummaries(for:sport:ftp:vma:css:)` to add `maxHR` parameter for HR-based display. Update `formatMetric()` to render HR/power/pace targets. |
| `Dromos/Dromos/Features/Home/WorkoutStepsView.swift` (legacy, calendar) | MODIFY | Render all Target types: "HR 130-150 bpm", "240-260W", "4:11/km", "Z2 HR". Fall back gracefully when target is null (strength). |
| `Dromos/Dromos/Features/Home/WorkoutStepList.swift` (new Home renderer) | MODIFY | Same display logic as above. |
| `Dromos/Dromos/Features/Home/WorkoutGraphView.swift` (legacy, calendar) | MODIFY | Add intensity coloring for HR-based segments. Map `hr_pct_max` to existing intensity gradient. Skip graph entirely for strength. |
| `Dromos/Dromos/Features/Home/WorkoutShape.swift` (new Home renderer) | MODIFY | Same logic for HR-based intensity coloring. Skip for strength. |
| `Dromos/Dromos/Features/Home/SessionCardView.swift` | MODIFY | Strength path: skip graph, show notes prominently. Pass `maxHR` to step formatters. |
| `Dromos/Dromos/Features/Home/TodayPlannedCard.swift` | MODIFY | Same as SessionCardView — strength path + maxHR passthrough. |
| `Dromos/Dromos/Features/Home/IntensityColorHelper.swift` | MODIFY | Add `Color.intensity(forHRPctMax:)` to map HR % to existing green→red gradient. |
| `supabase/functions/_shared/materialize-structure.ts` | NO CHANGE | Already supports everything. Verify with new template tests. |
| `supabase/functions/_shared/__tests__/materialize-structure.test.ts` | MODIFY | Add 8-10 tests covering: hr_pct_max range, power_watts range, pace_per_km, distance-based intervals with active recovery, nested repeats with hr_zone children. |
| `supabase/functions/import-plan/index.ts` | CREATE | New Edge Function. JWT auth + email allowlist. Validates body, snapshots existing plan, deletes via CASCADE, inserts new plan+weeks+sessions in transaction. Materializes each template into `structure` JSONB. |
| `supabase/functions/import-plan/deno.json` | CREATE | Standard Deno config. |
| `supabase/migrations/017_plan_snapshots.sql` | CREATE | New `plan_snapshots` table for rollback. |
| `scripts/deploy-functions.sh` | MODIFY | Add `import-plan` to the deployable list. |
| `scripts/seed-ebreard4-olympic-plan.ts` | CREATE | Deno CLI script that loads `miscellaneous/training-plan-olympic-sept-2026.md` → builds the JSON payload → calls `import-plan` Edge Function with service-role JWT. One-off but kept for reference. |
| `scripts/payloads/ebreard4-olympic-2026-09-19.json` | CREATE | The materialized payload (committed for diff visibility). |

## Context Doc Updates

- `schema.md` — Document the new `plan_snapshots` table. Note that `users.max_hr` is required for HR-based session display.
- `architecture.md` — New `import-plan` Edge Function description. Strength rendering convention (notes-only, no graph). HR target display in WorkoutStepsView/WorkoutStepList.

---

## Tasks

### Phase 1: Renderer audit + Target-type display

Verify and fix iOS rendering for every `Target.type` value in the materializer. **Without this, templates with HR/power/pace targets render as blank or fall through to RPE.**

- [ ] 🟩 **Step 1.1: Audit current renderer behavior**
  - [ ] 🟩 Read `Dromos/Dromos/Core/Services/WorkoutLibraryService.swift` → `formatMetric()`. List which Target types are handled. Expected: `vma_pct`, `ftp_pct`, swim `pace` (RPE-converted). Likely missing: `hr_pct_max`, `hr_zone`, `power_watts`, `pace_per_km`, `pace_per_100m`.
  - [ ] 🟩 Write a small failing UI snapshot test (or just a unit test) for each missing case before fixing.

- [ ] 🟩 **Step 1.2: Extend `stepSummaries` and `formatMetric` to handle all Target types**
  - [ ] 🟩 Add `maxHR: Int?` parameter to `stepSummaries(for:sport:ftp:vma:css:maxHR:)` and propagate via callers.
  - [ ] 🟩 Display rules:
    - `hr_pct_max` single value: "HR 88% max (170 bpm)" — compute bpm from `maxHR * pct/100`
    - `hr_pct_max` range: "HR 65-78% max (125-150 bpm)"
    - `hr_zone` value: "Z2 HR" (or "Z2 HR (125-150 bpm)" if maxHR available — derive zone bands from HRmax)
    - `power_watts` single: "240 W"
    - `power_watts` range: "240-260 W"
    - `pace_per_km`: "4:11/km"
    - `pace_per_100m`: "1:50/100m"
    - `rpe`: "RPE 7" (already exists)

- [ ] 🟩 **Step 1.3: Intensity coloring for HR-based segments**
  - [ ] 🟩 `IntensityColorHelper.swift`: add `Color.intensity(forHRPctMax: Double, isRecovery: Bool)` that maps 60-95% range to existing green→red gradient. Anchor: 65%=green, 80%=yellow, 90%=red.
  - [ ] 🟩 `WorkoutGraphView.swift` + `WorkoutShape.swift`: when segment target is `hr_pct_max` or `hr_zone`, use the new HR-based color path. Fall through gracefully when target is null.

- [ ] 🟩 **Step 1.4: Strength rendering path**
  - [ ] 🟩 In `SessionCardView` and `TodayPlannedCard`: when `sport == 'strength'`, hide `WorkoutGraphView`/`WorkoutShape` and `WorkoutStepsView`/`WorkoutStepList`. Show only the session header (name, duration) and the notes block (which contains the exercise list as markdown).
  - [ ] 🟩 Use existing strength sport color (purple) and emoji (💪) — already in `PlanSession.sportColor`/`sportEmoji`.

- [ ] 🟩 **Step 1.5: Manual QA matrix**
  - [ ] 🟩 Sample one session per Target type and screenshot the rendered card. Attach to the issue.

### Phase 2: Workout library — high-fidelity templates

Author the new templates. Naming convention: `{SPORT}_{TYPE}_{KEYS}` (e.g., `BIKE_VO2_5x3min_290W`, `RUN_Z2_long_cap150bpm`).

- [ ] 🟩 **Step 2.1: Bike templates (10 unique)**
  Examples below — the executor authors full segment blocks following these shapes:

  - `BIKE_Z2_endurance_90min` — single Z2 power range (180-200W) + cap (`hr_pct_max` max 78)
  - `BIKE_SS_4x6min_245W` — repeat block: 6min @ ftp_pct range 88-93 + 4min recovery @ ftp_pct 55
  - `BIKE_THR_2x15min_260W` — repeat: 15min @ power_watts 260 + 8min rec
  - `BIKE_VO2_5x3min_290W` — repeat: 3min @ power_watts range 290-300 + 3min rec
  - `BIKE_VO2_5x4min_290W` — repeat: 4min @ power_watts 290 + 3min rec
  - `BIKE_OU_2x10min_95_110` — over-under: 1min @ ftp_pct 110 + 3min @ ftp_pct 95, ×repeat
  - `BIKE_RACE_40min_IF85` — single 40min @ power_watts range 230-235
  - `BIKE_BRICK_75min_IF85` — warmup + race-effort 40min + cooldown
  - `BIKE_VO2_3x6min_295W` — repeat 6min @ 295W + 4min rec
  - `BIKE_OPENER_45min_3x3min` — light opener with VO2 reps

  All include cadence_rpm where prescribed.

- [ ] 🟩 **Step 2.2: Run templates (10 unique)**
  - `RUN_Z2_long_cap150bpm` — single segment, hr_pct_max max 78, duration variable
  - `RUN_Z2_easy_cap140bpm` — single segment, hr_pct_max max 73
  - `RUN_TEMPO_4x4min_4_15km` — repeat 4min @ pace_per_km 4:15 + 2min walk
  - `RUN_VO2_5x400m_3_35km` — distance-based repeat 400m @ pace 3:35 + 400m walk recovery (distance-based)
  - `RUN_VO2_5x600m_3_45km` — 600m @ 3:45 + 90s jog
  - `RUN_VO2_4x800m_3_40km` — 800m @ 3:40 + 400m jog
  - `RUN_VO2_5x800m_3_40km`
  - `RUN_RACE_4x1km_4_00km` — 1km @ pace 4:00 + 90s jog
  - `RUN_THR_3x10min_4_22km` — 10min @ 4:22/km + 5min rec
  - `RUN_BRICK_25min_15rp_10z2` — 15min @ pace 4:00 then 10min Z2

- [ ] 🟩 **Step 2.3: Swim templates (8 unique)**
  - `SWIM_Z2_endurance_2500m` — pace tag "easy" / RPE 3
  - `SWIM_THR_6x150_1_50` — repeat 150m @ pace_per_100m 1:50 + 30s rest
  - `SWIM_CSS_8x100_1_45` — repeat 100m @ pace 1:45 + 20s rest
  - `SWIM_RACE_2x750_1_48` — 2× 750m @ pace 1:48 + 60s rest
  - `SWIM_VO2_8x50_fast` — repeat 50m fast + 15s rest
  - `SWIM_OPENER_1500m_race_pace`
  - `SWIM_TT_1500m`
  - `SWIM_DRILLS_1800m`

- [ ] 🟩 **Step 2.4: Race + brick + strength**
  - `RACE_OLYMPIC` — race template (renderer routes to RaceDayCardView)
  - `BRICK_BIKE_75_RUN_15` (already exists or pair as 2 sessions — use convention from DRO-170)
  - `STRENGTH_NOTES_ONLY` — single placeholder template with `segments: []`, duration null. Renderer reads `plan_sessions.notes`.

- [ ] 🟩 **Step 2.5: Materializer tests**
  - [ ] 🟩 Extend `materialize-structure.test.ts`: each new Target-type pattern gets ≥1 test. Run `deno test`.

### Phase 3: `import-plan` Edge Function

- [ ] 🟩 **Step 3.1: Migration — `plan_snapshots` table**
  - [ ] 🟩 Create `supabase/migrations/017_plan_snapshots.sql`:
    ```sql
    -- UP
    CREATE TABLE public.plan_snapshots (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
      snapshot JSONB NOT NULL,           -- full plan + weeks + sessions
      reason TEXT NOT NULL,              -- e.g. 'import-plan-replace'
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    ALTER TABLE public.plan_snapshots ENABLE ROW LEVEL SECURITY;
    CREATE POLICY "users read own snapshots" ON public.plan_snapshots
      FOR SELECT USING (auth.uid() = user_id);
    -- No INSERT/DELETE/UPDATE policies — Edge Function writes via service_role

    -- DOWN
    -- DROP TABLE public.plan_snapshots;
    ```

- [ ] 🟩 **Step 3.2: Edge Function scaffold**
  - [ ] 🟩 `supabase/functions/import-plan/index.ts`. Pattern matches `chat-adjust/index.ts`:
    - JWT validation via `auth.getUser()`
    - Email allowlist gate: `if (user.email !== 'ebreard4@gmail.com') return 403`
    - Parse body (typed)
    - Use `service_role` client for DB writes

- [ ] 🟩 **Step 3.3: Body schema**
  ```ts
  interface ImportPlanBody {
    plan: {
      race_objective: 'Sprint' | 'Olympic' | 'Ironman 70.3' | 'Ironman';
      race_date: string;        // 'YYYY-MM-DD'
      start_date: string;       // 'YYYY-MM-DD'
      total_weeks: number;
    };
    profile_updates?: Partial<{
      max_hr: number;
      ftp: number;
      vma: number;
      css_seconds_per100m: number;
      race_objective: string;
      race_date: string;
    }>;
    weeks: Array<{
      week_number: number;
      phase: 'Base' | 'Build' | 'Peak' | 'Taper' | 'Recovery';
      is_recovery: boolean;
      rest_days: string[];       // ['Thursday'] or ['Monday']
      notes?: string;
      start_date: string;
      sessions: Array<{
        day: 'Monday' | ... | 'Sunday';
        sport: 'swim' | 'bike' | 'run' | 'strength' | 'race';
        type: 'Easy' | 'Tempo' | 'Intervals' | 'Race';
        template_id: string;     // must exist in workout-library.json
        duration_minutes: number;
        is_brick: boolean;
        notes?: string;
        order_in_day: number;
      }>;
    }>;
  }
  ```

- [ ] 🟩 **Step 3.4: Validation**
  - [ ] 🟩 Load `workout-library.json` server-side (bundled). For each session.template_id, verify it exists. 400 with list of missing IDs on failure.
  - [ ] 🟩 Verify `weeks.length === plan.total_weeks` and week_numbers are sequential.
  - [ ] 🟩 Verify each week.sessions.day is one of 7 valid day names.
  - [ ] 🟩 Reject if user already has a plan and `body.replace !== true` (safety).

- [ ] 🟩 **Step 3.5: Snapshot + delete + insert (in a transaction)**
  - [ ] 🟩 Read existing plan + weeks + sessions, write to `plan_snapshots`.
  - [ ] 🟩 DELETE existing `training_plans` row (CASCADE handles weeks + sessions).
  - [ ] 🟩 INSERT new `training_plans` row (status='active').
  - [ ] 🟩 For each week: INSERT `plan_weeks`. For each session: import the template, call `materialize()`, insert with `structure` populated.
  - [ ] 🟩 Apply `profile_updates` if present.
  - [ ] 🟩 Return `{ plan_id, weeks_inserted, sessions_inserted, snapshot_id }`.

- [ ] 🟩 **Step 3.6: Deploy + smoke test**
  - [ ] 🟩 Add `import-plan` to `scripts/deploy-functions.sh`.
  - [ ] 🟩 Deploy. Hit with curl using a service-role JWT and a minimal 1-week payload — verify happy path + 3 failure modes (bad template_id, mismatched weeks, non-allowlisted user).

### Phase 4: Plan payload author + ingest

- [ ] 🟩 **Step 4.1: Build the payload**
  - [ ] 🟩 `scripts/payloads/ebreard4-olympic-2026-09-19.json` — hand-author from `miscellaneous/training-plan-olympic-sept-2026.md`. ~150 sessions.
  - [ ] 🟩 Include `profile_updates`: `max_hr: 193, ftp: 275, css_seconds_per100m: 110, race_objective: 'Olympic', race_date: '2026-09-19'`.
  - [ ] 🟩 Per-session `notes` field carries qualitative cues from the plan (e.g. "Hold back the first 2km off the bike", "Cap HR at 150 bpm").
  - [ ] 🟩 Strength sessions: `template_id: 'STRENGTH_NOTES_ONLY'`, `notes` is the exercise list as markdown bullets.

- [ ] 🟩 **Step 4.2: Ingest**
  - [ ] 🟩 `scripts/seed-ebreard4-olympic-plan.ts` — Deno CLI that loads the payload + posts to `import-plan` with a service-role JWT.
  - [ ] 🟩 Run against staging (if any) or directly against production after manual review.

- [ ] 🟩 **Step 4.3: DB verify**
  - [ ] 🟩 SQL: confirm 15 weeks inserted, ~140 sessions, all template_ids resolve, `structure` is populated for non-strength sessions.

### Phase 5: Manual QA in the app

- [ ] 🟩 **Step 5.1: Visual QA**
  - [ ] 🟩 Open Home tab — today shows correct session
  - [ ] 🟩 Open Calendar — swipe through 15 weeks
  - [ ] 🟩 Verify HR-cap sessions display "HR <150 bpm" (or zone band)
  - [ ] 🟩 Verify power-target sessions display "240W" or "240-260W"
  - [ ] 🟩 Verify pace-target run sessions display "4:11/km"
  - [ ] 🟩 Verify strength sessions show notes block only, no graph
  - [ ] 🟩 Verify brick days show two stacked sessions with brick badge
  - [ ] 🟩 Verify Race A (Sep 12) + Race B (Sep 19) route to RaceDayCardView
  - [ ] 🟩 Verify Thursday is the rest day (weeks 1-14)

- [ ] 🟩 **Step 5.2: Coach chat smoke test**
  - [ ] 🟩 Send a chat message asking about a Block 3 VO2 session. Verify the agent doesn't choke on HR/power targets.

- [ ] 🟩 **Step 5.3: Session feedback smoke test**
  - [ ] 🟩 Sync a recent Strava activity. Verify `session-feedback` runs without error on a swim/bike/run.
  - [ ] 🟩 Strength: confirm matcher gracefully skips strength (no Strava sport mapping).

## Risks

1. **Renderer regressions for existing plans.** All renderer changes affect every session, not just the new plan. Mitigation: ship behind no flag but write snapshot tests for the existing `vma_pct`/`ftp_pct`/swim-pace cases before touching the code.
2. **`chat-adjust` agent prompt expects specific intensity language.** Adding HR/power/pace strings may confuse it. Mitigation: include 1-2 sample sessions in the prompt context (already does — verify in `coach-chat-v0.txt`).
3. **`session-feedback` template format reliance.** The feedback prompt references `template_id` patterns. Mitigation: verify it doesn't hard-code on `_Tempo_` vs `_VO2_` substring matches.
4. **Edge Function size — bundled workout-library.json.** ~5000 lines after additions. Deno deploy handles it, but cold-start latency rises.
5. **Profile race_date is TIMESTAMPTZ; plan race_date is DATE.** Match conversions carefully (`2026-09-19T00:00:00Z` vs `2026-09-19`).
6. **No staging env.** Mitigation: snapshot rollback + small dry-run test (1 week, 1 session) before full import.

## Rollback

- DB: `plan_snapshots.snapshot` contains the full pre-import plan. Recovery script reads it and re-inserts.
- Code: standard `git revert` of the renderer + library + Edge Function commits.

## Tests

- **Unit:** `materialize-structure.test.ts` — new Target-type cases (10+ tests).
- **Unit:** Swift formatter tests for `formatMetric` covering each Target.type.
- **Integration:** Edge Function smoke tests (curl) — happy path, missing template, mismatched weeks, non-allowlisted user.
- **Snapshot/UI:** SessionCardView snapshots for each Target type. Manual screenshots attached to the issue.

## Out of Scope

- Strength as a first-class workout (sets×reps UI, graph). Defer to a follow-up if dogfood signal is positive.
- Generalizing `import-plan` beyond ebreard4 (drop the email allowlist) — done in a separate issue once we trust the function.
- Auto-generating `notes` from upstream markdown — payload is hand-authored for V0.
