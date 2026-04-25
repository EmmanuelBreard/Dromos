# DRO-213 — Phase 1: Generalize session display for agent-generated sessions

**Linear:** [DRO-213](https://linear.app/dromosapp/issue/DRO-213/phase-1-generalize-session-display-for-agent-generated-sessions)
**Overall Progress:** `0%`

## TLDR

Replace the rigid template-driven session display with a generic structured-session schema (`structure` JSONB on `plan_sessions`). Any session — template-based or agent-generated — renders with notes + steps + graph view, always showing concrete actionable values (pace / watts / HR / RPE) instead of raw percentages. Foundation for Phase 2 (rebuild-session agent) and Phase 3 (chat menu).

## Critical Decisions

- **Storage abstract, display concrete.** Targets stored as references (`ftp_pct: 95-100`, `vma_pct: 95-100`, `rpe: 6`) so saved sessions auto-rescale on FTP/VMA/CSS re-test. Display layer always resolves to actionable values.
- **Single primary measure per segment.** A segment has *exactly one* of `duration_minutes` or `distance_meters` — author decides (long run = duration, intervals = distance, swim = always distance).
- **Renderer reads `structure` first with `template_id` fallback** for one release cycle. After verification, retire the bundled JSON loader in a follow-up release.
- **Strength removed entirely.** Templates deleted from JSON, existing `plan_sessions` rows deleted in a *separate, second migration* (run only after additive changes prove stable). Generation pipeline strips strength generation. `sport` CHECK keeps `'strength'` for future re-introduction.
- **`mas_pct` renamed to `vma_pct`** in `workout-library.json` for consistency. Same field, clearer name. Affects Step 3 LLM prompt and post-processing.
- **HR zones use % max HR (standard 5-zone)** — not Karvonen (avoids requiring resting HR field).
- **No staging Supabase project — production is the only target.** Migrations apply directly to prod via `mcp__supabase__apply_migration`. Risk mitigated by (a) splitting destructive strength deletion into a second migration that runs after additive changes prove stable, and (b) the renderer's `template_id` fallback path that survives a partial backfill.
- **Backfill via Deno script in `scripts/`** that imports the shared materializer from `supabase/functions/_shared/materialize-structure.ts` via relative path. Materializer is a pure function (no Supabase client / env deps) so it works in both runtimes.
- **Materializer runs at the single insert site only.** Post-processing fixers mutate `template_id` upstream of insert; insert picks up the resolved template and materializes once. Fixers do not re-materialize.
- **`maxHr` stays nullable for existing users.** New users get it via onboarding. Existing users update via Settings on their own. No modal prompt — Phase 1 templates don't use HR targets so nothing breaks.
- **Tests written within each phase**, not deferred. Phase 7 is integration QA + snapshot baselines, not the first time tests get written.
- **CSS swim pace resolution stays deferred.** Phase 1 swim ships RPE-only (per existing FIX #7). Closed properly in Phase 2 when agent emits `css_pct` directly.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `supabase/migrations/20260425_session_structure_and_max_hr.sql` | CREATE | **Additive only:** add `plan_sessions.structure` JSONB; add `users.max_hr`, `users.birth_year` |
| `supabase/migrations/20260426_remove_strength_sessions.sql` | CREATE | **Destructive (Phase 8 only):** `DELETE FROM plan_sessions WHERE sport = 'strength'`. Runs after additive migration + backfill prove stable |
| `ai/context/workout-library.json` | MODIFY | Remove `strength` array; rename `mas_pct` → `vma_pct` everywhere |
| `Dromos/Dromos/Core/Models/TrainingPlan.swift` | MODIFY | Add `structure: SessionStructure?` to `PlanSession` (line 109); keep `templateId` |
| `Dromos/Dromos/Core/Models/WorkoutTemplate.swift` | MODIFY | Add new types: `SessionStructure`, `StructureSegment`, `Target` (enum with associated values), `Constraint`. Keep existing `WorkoutTemplate`/`WorkoutSegment` (used by backfill input + transitional fallback) |
| `Dromos/Dromos/Core/Models/User.swift` | MODIFY | Add `maxHr: Int?`, `birthYear: Int?` (lines 46-52 area); update Codable keys |
| `Dromos/Dromos/Core/Services/WorkoutLibraryService.swift` | MODIFY | Add `flattenedSegments(structure:)` and `stepSummaries(structure:sport:user:)` operating on the new types. Keep existing template-based methods as transitional fallback. Add `materialize(template:) -> SessionStructure` for server/backfill reuse |
| `Dromos/Dromos/Features/Home/IntensityColorHelper.swift` | MODIFY | Add `Color.intensity(forTarget:isRecovery:)` overload that accepts new `Target` enum |
| `Dromos/Dromos/Features/Home/WorkoutStepsView.swift` | MODIFY | Polymorphic display per `target.type` via formatter |
| `Dromos/Dromos/Features/Home/WorkoutGraphView.swift` | MODIFY | Accept `css` parameter (currently missing); polymorphic intensity normalization across target types |
| `Dromos/Dromos/Features/Home/SessionCardView.swift` | MODIFY | Read `session.structure` first; fall back to `template` lookup if nil |
| `Dromos/Dromos/Features/Plan/DaySessionRow.swift` | MODIFY | Same dual-path read; align gating with `SessionCardView` (steps + graph use the same guard) |
| `Dromos/Dromos/Features/Onboarding/OnboardingScreen3View.swift` | MODIFY | Add `maxHr` and `birthYear` fields. "Use formula (220 − age)" affordance pre-fills `maxHr` from `birthYear`; manual override allowed |
| `Dromos/Dromos/Core/Services/ProfileService.swift` | MODIFY | Persist `maxHr` and `birthYear` to `users` table |
| `supabase/functions/generate-plan/index.ts` | MODIFY | Insert path (~line 2006-2016): materialize `structure` from template via shared TS helper; write both `template_id` and `structure`. Remove strength session generation entirely |
| `supabase/functions/generate-plan/prompts/step3-workout-block-prompt.ts` | MODIFY | Remove strength templates from prompt context |
| `supabase/functions/_shared/materialize-structure.ts` | CREATE | Shared TS helper that reads a template and produces a `SessionStructure` JSON (mirrors iOS `materialize(template:)`). Reused by `generate-plan` insert path and backfill script |
| `scripts/backfill-session-structure.ts` | CREATE | One-time Deno script. Reads `workout-library.json`, walks all `plan_sessions` rows, calls shared materializer, writes `structure` via `service_role`. Idempotent. Logs per-row outcome |
| `Dromos/DromosTests/SessionStructureTests.swift` | CREATE | Unit tests: each `Target` type × sport → expected display string + intensity %; range vs single-value handling; fallback chain |
| `Dromos/DromosTests/StructureRenderSnapshotTests.swift` | CREATE | Snapshot tests: a representative set of templates pre-backfill (legacy renderer) vs post-backfill (new renderer). Output must match. |

## Schema Reference (for implementation)

### `SessionStructure` JSON

```json
{
  "segments": [
    {
      "label": "warmup" | "work" | "recovery" | "cooldown" | "repeat" | "rest" | "drill",
      "duration_minutes": 10,
      "distance_meters": 400,
      "target": { "type": "...", "value": ..., "min": ..., "max": ... },
      "cadence_rpm": 90,
      "constraints": [{ "type": "hr_max", "value": 145 }],
      "cue": "rolling OK",
      "drill": "pull",
      "repeats": 4,
      "rest_seconds": 30,
      "recovery": { "...nested segment..." },
      "segments": [ { "...nested..." } ]
    }
  ]
}
```

**Rules enforced by the materializer + agent:**
- `duration_minutes` XOR `distance_meters` per segment (never both)
- `target` may be omitted (drill / skill work / strength-style with no intensity)
- A segment with `repeats` has `segments` (and either `rest_seconds` or `recovery`); leaf segments have `target`/`duration`/`distance`/`cue`

### Target types

```ts
type Target =
  | { type: "ftp_pct"; min: number; max: number }
  | { type: "ftp_pct"; value: number }
  | { type: "vma_pct"; min: number; max: number }
  | { type: "vma_pct"; value: number }
  | { type: "css_pct"; min: number; max: number }   // Phase 2
  | { type: "css_pct"; value: number }              // Phase 2
  | { type: "rpe"; value: number }                  // 1-10
  | { type: "hr_zone"; value: 1 | 2 | 3 | 4 | 5 }
  | { type: "hr_pct_max"; min: number; max: number }
  | { type: "hr_pct_max"; value: number }
  | { type: "power_watts"; min: number; max: number }
  | { type: "power_watts"; value: number }
  | { type: "pace_per_km"; value: string }    // "5:30"
  | { type: "pace_per_100m"; value: string }; // "1:50"
```

### HR zones (% max HR)

| Zone | % max HR |
|---|---|
| Z1 | 50–60% |
| Z2 | 60–70% |
| Z3 | 70–80% |
| Z4 | 80–90% |
| Z5 | 90–100% |

### Display priority by sport

- **Run:** `vma_pct`/`pace_per_km` → `hr_zone`/`hr_pct_max` → `rpe`
- **Swim:** `pace_per_100m`/`css_pct` (Phase 2) → `rpe`
- **Bike:** `ftp_pct`/`power_watts` → `hr_zone`/`hr_pct_max` → `rpe` *(never speed)*

If primary target's required metric is unset on the user (e.g. `vma_pct` with VMA = nil), formatter falls back to displaying `RPE N — descriptor` using the calibration table.

### Backfill swim pace → RPE

| pace tag | rpe |
|---|---|
| `slow`, `easy` | 3 |
| `medium` | 6 |
| `quick`, `threshold` | 7 |
| `fast` | 8 |
| `very_quick` | 9 |

### Intensity → 0-100% normalization (graph bars)

Used only for visual bar height; approximate.

| target | intensity % |
|---|---|
| `ftp_pct.value` | value (clamped 30-110) |
| `vma_pct.value` | value (clamped 30-110) |
| `css_pct.value` | value (clamped 30-110) |
| `hr_zone` | Z1=55, Z2=65, Z3=75, Z4=85, Z5=95 |
| `hr_pct_max.value` | value (clamped 30-110) |
| `rpe.value` | value × 10 (1→10, 10→100) |
| `power_watts.value` | value / FTP × 100 (if FTP set), else 70 |
| `pace_per_km`/`pace_per_100m` | value / target_pace × 100 (if VMA/CSS set), else 70 |

Recovery segments always render as the recovery green regardless of target.

## Context Doc Updates

- `schema.md` — document `plan_sessions.structure` JSONB shape + `users.max_hr` + `users.birth_year`
- `architecture.md` — document the new `SessionStructure` types, polymorphic display formatter, `_shared/materialize-structure.ts` shared helper, dual-path renderer (transitional)
- `ai-pipeline.md` — note the change in `generate-plan` insert path (writes both `template_id` and `structure`); document strength removal

## Tasks

- [ ] 🟥 **Phase 1 — Additive DB migration & shared materializer**
  - [ ] 🟥 Write migration `20260425_session_structure_and_max_hr.sql` (additive only: `structure`, `max_hr`, `birth_year`; **no strength deletion here**)
  - [ ] 🟥 Apply migration directly to production via `mcp__supabase__apply_migration` (no staging exists)
  - [ ] 🟥 Verify with `mcp__supabase__list_tables` that the new columns are present and nullable
  - [ ] 🟥 Create `supabase/functions/_shared/materialize-structure.ts` — pure function `materialize(template) -> SessionStructure`. **No Supabase client / `Deno.env` deps** — must be importable by both Edge Functions and Deno CLI scripts via relative path
  - [ ] 🟥 Encode swim pace → RPE table inside the materializer
  - [ ] 🟥 Encode `mas_pct` → `vma_pct` rename inside the materializer (translates legacy JSON keys to new schema)
  - [ ] 🟥 Strip `strength` array from `ai/context/workout-library.json`; rename `mas_pct` → `vma_pct` keys throughout the JSON
  - [ ] 🟥 Update `step3-workout-block-prompt.ts` to drop strength entries; verify the prompt no longer references `mas_pct` (use `vma_pct`)
  - [ ] 🟥 Unit-test the materializer for: `ftp_pct` template, `vma_pct` template, swim pace tags → RPE, nested repeats (3 levels), `cadence_rpm` preservation, `cue` preservation, `RUN_Easy_07`-style duration+distance dedup (prefer duration)

- [ ] 🟥 **Phase 2 — Server (`generate-plan`) writes both columns**
  - [ ] 🟥 Import shared materializer in `supabase/functions/generate-plan/index.ts`
  - [ ] 🟥 At the single insert site (~line 2006-2016), call materializer with the resolved template and pass result as the `structure` insert field. Insert site is the only materialization point — fixers do **not** re-materialize
  - [ ] 🟥 Remove strength session generation throughout the pipeline (Step 1/2/3 prompts + post-processing fixers)
  - [ ] 🟥 Tests: unit-test that `generate-plan`'s insert payload has non-null `structure` matching the template; integration test that strength is never produced
  - [ ] 🟥 Generate a fresh test plan against production (test user); verify rows have non-null `structure`

- [ ] 🟥 **Phase 3 — Backfill script**
  - [ ] 🟥 Create `scripts/backfill-session-structure.ts` (Deno). Imports the shared materializer from `../supabase/functions/_shared/materialize-structure.ts` via relative path
  - [ ] 🟥 Script iterates `plan_sessions` rows in batches of 100 ordered by `id`
  - [ ] 🟥 For each row, call materializer; write `structure` if currently null (idempotent — skip already-populated rows). Log + skip orphaned `template_id`s without erroring
  - [ ] 🟥 Final summary log: `populated`, `skipped`, `orphaned`, `failed`. Exit non-zero on `failed > 0`
  - [ ] 🟥 Tests: unit-test the script's row-mapping logic against fixture rows
  - [ ] 🟥 Run in production via `service_role` key; archive log; spot-check rendering parity for 5 sample sessions in the iOS app pre-Phase-5 (raw JSON inspection via Supabase dashboard)

- [ ] 🟥 **Phase 4 — Swift model layer**
  - [ ] 🟥 Add `SessionStructure`, `StructureSegment`, `Target` (enum), `Constraint` types in `WorkoutTemplate.swift`
  - [ ] 🟥 Implement `Codable` for `Target` enum with a custom decoder switching on the `type` discriminator key (test all 9 target types decode correctly)
  - [ ] 🟥 Add `structure: SessionStructure?` to `PlanSession` in `TrainingPlan.swift:109` with snake_case CodingKey
  - [ ] 🟥 Add `maxHr: Int?` and `birthYear: Int?` to `User.swift` with snake_case CodingKeys
  - [ ] 🟥 Tests: unit-test Codable round-trip for each `Target` variant (single value + range), nested segments, full session structure
  - [ ] 🟥 Verify Supabase decoding with a backfilled production row (read-only)

- [ ] 🟥 **Phase 5 — Display layer (services + views)**
  - [ ] 🟥 In `WorkoutLibraryService.swift`, add `flattenedSegments(structure:)`, `stepSummaries(structure:sport:ftp:vma:css:maxHr:)`, and a Swift port of `materialize(template:)` for transitional fallback
  - [ ] 🟥 Implement polymorphic `displayString(for: Target, sport:, ftp:, vma:, css:, maxHr:) -> String` returning concrete ranges/values per the spec table (specific per-metric args, not a whole `User`)
  - [ ] 🟥 Implement `intensityPct(for: Target, ftp:, vma:, css:, maxHr:) -> Int` per the normalization table. Note: pace-based targets invert (faster pace = higher intensity)
  - [ ] 🟥 Define rendering for `Target = none` (drill / skill work): no intensity dot color (use neutral), no graph bar height boost (default 30%)
  - [ ] 🟥 Update `WorkoutStepsView.swift` to consume new `StepSummary` shape (text + intensityPct unchanged)
  - [ ] 🟥 Update `WorkoutGraphView.swift`: accept `css: Int?` and `maxHr: Int?`; replace `effectiveIntensity` with new `intensityPct` function; tooltip shows new display strings
  - [ ] 🟥 In `SessionCardView.swift` and `DaySessionRow.swift`: prefer `session.structure` when present; fall back to `template` lookup + `materialize(template:)` if nil
  - [ ] 🟥 Align `DaySessionRow` and `SessionCardView` gating: steps + graph use the same `shouldShow` predicate (drop the inconsistency surfaced in discovery)
  - [ ] 🟥 Tests: unit-test `displayString` for each `Target` × sport combination; unit-test `intensityPct`; snapshot test `WorkoutStepsView` / `WorkoutGraphView` for representative sessions

- [ ] 🟥 **Phase 6 — Onboarding (max HR + birth year, new users only)**
  - [ ] 🟥 In `OnboardingScreen3View.swift`, add a `birthYear` picker and a `maxHr` numeric input
  - [ ] 🟥 Add a "Use formula (220 − age)" button that fills `maxHr` based on `birthYear`; manual edit allowed afterward
  - [ ] 🟥 Wire `maxHr`/`birthYear` through `OnboardingFlowView` → `ProfileService` → `users` row (snake_case keys)
  - [ ] 🟥 Existing users keep `maxHr = NULL` until they update via Settings (deferred to a future ticket — Phase 1 templates don't use HR targets so nothing breaks for them)
  - [ ] 🟥 Tests: unit-test the formula button (`birthYear = 1990` → `maxHr = 220 - 36 = 184` for 2026); integration test the onboarding flow end-to-end

- [ ] 🟥 **Phase 7 — Integration QA & snapshot baselines**
  - [ ] 🟥 Add `Dromos/DromosTests/StructureRenderSnapshotTests.swift`: 5+ representative templates rendered via legacy path (read template, render via old code path) vs new path (materialize + render via new code path) — outputs must match exactly
  - [ ] 🟥 Edge cases: athlete missing FTP/VMA/maxHr; row with `structure = null` (template fallback path); deeply nested repeat (e.g. `SWIM_Tempo_02` 3-level); session with `Target = none`
  - [ ] 🟥 Manual QA in simulator with backfilled production data: open Home + Plan tabs; verify steps + graph render correctly across run/bike/swim and across Easy/Tempo/Intervals types
  - [ ] 🟥 Manual QA: regression check on completed sessions (`SessionCardView` "Planned workout" disclosure) and on race day (`RaceDayCardView`)

- [ ] 🟥 **Phase 8 — Strength removal & ship**
  - [ ] 🟥 Write second migration `20260426_remove_strength_sessions.sql`: `DELETE FROM plan_sessions WHERE sport = 'strength'`. Apply directly to production via `mcp__supabase__apply_migration`
  - [ ] 🟥 Verify count of remaining strength rows is 0 via `mcp__supabase__execute_sql`
  - [ ] 🟥 Deploy updated `generate-plan` Edge Function (already strength-stripped from Phase 2 — this step ships it)
  - [ ] 🟥 Submit iOS build (renderer with `template_id` fallback path enabled)
  - [ ] 🟥 Verify in production over one release cycle (~1 week of usage telemetry / no error reports)
  - [ ] 🟥 Open follow-up issue to retire the bundled-JSON runtime loader + `template_id` fallback path
