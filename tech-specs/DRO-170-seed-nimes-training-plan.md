# DRO-170 — Seed 10-Week Nîmes Training Plan

**Overall Progress:** `0%`

## TLDR

Seed an externally-built 10-week Nîmes triathlon plan into the DB for `ebreard4@gmail.com`. Requires: DB schema changes (`strength`/`race` sports, `Race` type, `reps` field), ~27 new structured workout templates, iOS rendering for strength/race/notes, enhanced `RaceDayCardView`, and a one-off SQL seed of ~99 sessions.

## Critical Decisions

- **Brick modeling:** Two separate `plan_sessions` (bike + run), each with own `template_id` and `is_brick: true`. No combined brick template.
- **Race day rendering:** `sport='race'` sessions trigger enhanced `RaceDayCardView` (not `SessionCardView`). Existing `date == raceDate` fallback preserved.
- **Marathon treatment:** Rendered as a race card (`sport='race'`, `type='Race'`), not a normal run session.
- **Session notes placement:** Above workout steps, below card header. NOT in coach feedback area.
- **Strength exercises:** New `reps` field on `WorkoutSegment` for count-based exercises. Timed exercises use existing `duration_seconds`.
- **Phase mapping:** Ramp-up→Base, Recovery→Recovery, Build 1→Build, Build 2→Peak, Pre-taper/Taper→Taper.
- **Colors:** strength=purple, race=yellow/gold.
- **Strength graph:** Show flat bars at low intensity (no `ftp_pct`/`mas_pct` → default ~50%). Steps show exercises with sets×reps.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `supabase/migrations/016_add_strength_race_types.sql` | CREATE | ALTER sport CHECK (+strength, +race), ALTER type CHECK (+Race) |
| `ai/context/workout-library.json` | MODIFY | Add ~27 new templates (8 swim, 11 bike, 5 run, 1 strength, 2 race) |
| `Dromos/Dromos/Core/Models/WorkoutTemplate.swift` | MODIFY | Add `reps` to `WorkoutSegment` + CodingKeys; add `strength`/`race` to `WorkoutLibrary` struct |
| `Dromos/Dromos/Core/Models/TrainingPlan.swift` | MODIFY | Add `strength`/`race` cases to `sportIcon`, `sportEmoji`, `typeColor` |
| `Dromos/Dromos/Core/Services/WorkoutLibraryService.swift` | MODIFY | Update `loadLibrary()` to index strength/race; update `formatMetric()` for strength; update `formatSegment()` for reps |
| `Dromos/Dromos/Features/Home/SessionCardView.swift` | MODIFY | Add notes display in `plannedWorkoutContent`; enhance `RaceDayCardView` with template-driven legs |
| `Dromos/Dromos/Features/Home/HomeView.swift` | MODIFY | Route `sport='race'` sessions to enhanced `RaceDayCardView` instead of `SessionCardView` |
| `Dromos/Dromos/Features/Home/WorkoutGraphView.swift` | MODIFY | Add `strength`/`race` cases in `formatMetric()` and `effectiveIntensity()` |
| `Dromos/Dromos/Features/Plan/DaySessionRow.swift` | MODIFY | Add `strength`/`race` to `sportColor`; handle race in `shouldShowWorkoutSteps` |
| `scripts/seed-nimes-plan.sql` | CREATE | One-off SQL: delete existing plan → insert plan + 10 weeks + ~99 sessions |

## Context Doc Updates

- `schema.md` — Updated CHECK constraints for sport/type, new `reps` field on workout segment model
- `architecture.md` — New sport colors/icons, enhanced RaceDayCardView, notes rendering in SessionCardView, WorkoutLibrary struct update

---

## Tasks

### Phase 1: Schema + Model Changes

- [ ] 🟥 **Step 1: DB Migration — Add strength/race sport + Race type**
  - [ ] 🟥 Create `supabase/migrations/016_add_strength_race_types.sql`
    ```sql
    -- UP
    ALTER TABLE plan_sessions DROP CONSTRAINT plan_sessions_sport_check;
    ALTER TABLE plan_sessions ADD CONSTRAINT plan_sessions_sport_check
      CHECK (sport IN ('swim', 'bike', 'run', 'strength', 'race'));

    ALTER TABLE plan_sessions DROP CONSTRAINT plan_sessions_type_check;
    ALTER TABLE plan_sessions ADD CONSTRAINT plan_sessions_type_check
      CHECK (type IN ('Easy', 'Tempo', 'Intervals', 'Race'));

    -- DOWN
    -- ALTER TABLE plan_sessions DROP CONSTRAINT plan_sessions_sport_check;
    -- ALTER TABLE plan_sessions ADD CONSTRAINT plan_sessions_sport_check
    --   CHECK (sport IN ('swim', 'bike', 'run'));
    -- ALTER TABLE plan_sessions DROP CONSTRAINT plan_sessions_type_check;
    -- ALTER TABLE plan_sessions ADD CONSTRAINT plan_sessions_type_check
    --   CHECK (type IN ('Easy', 'Tempo', 'Intervals'));
    ```
  - [ ] 🟥 Apply migration via Supabase MCP (`mcp__supabase__apply_migration`)

- [ ] 🟥 **Step 2: WorkoutSegment — Add `reps` field**
  - [ ] 🟥 `Dromos/Dromos/Core/Models/WorkoutTemplate.swift` line ~44: Add `var reps: Int?` after `restSeconds`
  - [ ] 🟥 Same file, CodingKeys enum line ~62: Add `case reps` after `case restSeconds`
  - [ ] 🟥 Same file, convenience init (line ~72): Add `reps: Int? = nil` parameter + `self.reps = reps`

- [ ] 🟥 **Step 3: WorkoutLibrary — Add strength + race arrays**
  - [ ] 🟥 `Dromos/Dromos/Core/Models/WorkoutTemplate.swift` lines 171-175: Add to `WorkoutLibrary` struct:
    ```swift
    struct WorkoutLibrary: Codable {
        let swim: [WorkoutTemplate]
        let bike: [WorkoutTemplate]
        let run: [WorkoutTemplate]
        let strength: [WorkoutTemplate]?  // Optional for backward compat with existing JSON
        let race: [WorkoutTemplate]?      // Optional for backward compat
    }
    ```
  - [ ] 🟥 `Dromos/Dromos/Core/Services/WorkoutLibraryService.swift` `loadLibrary()` (lines 91-116): Index strength + race templates into the `[String: WorkoutTemplate]` dictionary:
    ```swift
    // After existing swim/bike/run indexing:
    for t in library.strength ?? [] { templates[t.templateId] = t }
    for t in library.race ?? [] { templates[t.templateId] = t }
    ```

- [ ] 🟥 **Step 4: TrainingPlan — Add strength/race sport properties**
  - [ ] 🟥 `Dromos/Dromos/Core/Models/TrainingPlan.swift` `sportIcon` (lines 131-142): Add cases:
    ```swift
    case "strength": return "figure.strengthtraining.traditional"
    case "race":     return "flag.checkered"
    ```
  - [ ] 🟥 Same file, `sportEmoji` (lines 155-162): Add cases:
    ```swift
    case "strength": return "💪"
    case "race":     return "🏁"
    ```
  - [ ] 🟥 Same file, `typeColor` (lines 145-152): Add case:
    ```swift
    case "Race": return .yellow
    ```

- [ ] 🟥 **Step 5: DaySessionRow — Add sportColor for strength/race**
  - [ ] 🟥 `Dromos/Dromos/Features/Plan/DaySessionRow.swift` `sportColor` (lines 277-285): Add cases:
    ```swift
    case "strength": return .purple
    case "race":     return .yellow
    ```

---

### Phase 2: iOS View Updates

- [ ] 🟥 **Step 6: SessionCardView — Display notes above workout steps**
  - [ ] 🟥 `Dromos/Dromos/Features/Home/SessionCardView.swift` `plannedWorkoutContent` (line ~203): Insert at the top of the ViewBuilder, before the `if let template` block:
    ```swift
    // Coaching notes (if present)
    if let notes = session.notes, !notes.isEmpty {
        Text(notes)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.bottom, 4)
    }
    ```

- [ ] 🟥 **Step 7: Enhanced RaceDayCardView — Template-driven race legs**
  - [ ] 🟥 `Dromos/Dromos/Features/Home/SessionCardView.swift` `RaceDayCardView` (lines 263-298): Refactor to accept optional template + notes:
    ```swift
    struct RaceDayCardView: View {
        let raceObjective: String?
        var template: WorkoutTemplate? = nil
        var notes: String? = nil
        // ... existing body + new leg rendering when template is present
    }
    ```
  - [ ] 🟥 When `template` is present, render structured legs below the header:
    - Each top-level segment = one leg row
    - Row format: `label` (Swim/Bike/Run/T1/T2) | duration | metric (pace/speed/power)
    - Use `cue` field for transition notes
    - `notes` from session displayed below legs as target/strategy text
  - [ ] 🟥 When `template` is nil, keep existing static rendering (backward compat)

- [ ] 🟥 **Step 8: HomeView — Route race sessions to RaceDayCardView**
  - [ ] 🟥 `Dromos/Dromos/Features/Home/HomeView.swift` in `daySectionView` (around line 259-283): In the `ForEach sessions` loop, check if `session.sport == "race"`:
    - If race: render `RaceDayCardView(raceObjective: plan.raceObjective, template: template, notes: session.notes)` instead of `SessionCardView`
    - If not race: render `SessionCardView` as before
  - [ ] 🟥 Keep existing `date == raceDate` `RaceDayCardView` below sessions as fallback (but skip it if a race session already rendered one on that day to avoid duplicate)

- [ ] 🟥 **Step 9: WorkoutGraphView — Handle strength/race in tooltips**
  - [ ] 🟥 `Dromos/Dromos/Features/Home/WorkoutGraphView.swift` `formatMetric()` (lines 150-187): Add cases:
    ```swift
    case "strength":
        if let reps = segment.reps {
            return "\(reps) reps"
        }
        return nil
    case "race":
        return nil  // Race cards don't use the graph
    ```
  - [ ] 🟥 Same file, `effectiveIntensity()` (lines 273-285): Add strength default:
    ```swift
    // For strength segments without intensity, default to low
    if sport == "strength" { return 50 }
    ```

- [ ] 🟥 **Step 10: WorkoutLibraryService — Format strength segments with reps**
  - [ ] 🟥 `Dromos/Dromos/Core/Services/WorkoutLibraryService.swift` `formatMetric()` (lines 382-416): Add case:
    ```swift
    case "strength":
        if let reps = segment.reps {
            return "\(reps) reps"
        }
        if let secs = segment.durationSeconds {
            return "\(secs)s"
        }
        return nil
    ```
  - [ ] 🟥 Same file, `formatDuration()`: Handle reps-based segments — if `segment.reps != nil` and no duration/distance, format as sets×reps from the parent repeat context
  - [ ] 🟥 Same file, `createFlatSegment()`: For strength segments, use `durationSeconds` or estimate 30s per rep if only `reps` is set

---

### Phase 3: Workout Templates

- [ ] 🟥 **Step 11: Add ~27 new templates to workout-library.json**

  All templates in `ai/context/workout-library.json` with full structured segments following existing schema patterns.

  #### Swim (8 new)
  - [ ] 🟥 `SWIM_Easy_06` — 35min, 1.5k easy @2:15/100m: 200m wu (slow) + 1100m work (slow) + 200m cd (slow)
  - [ ] 🟥 `SWIM_Easy_07` — 30min, 1.2k drills only: 4×100m drill segments (catch_up, fingertip_drag, fist_drill, side_kick) + 2×100m slow with `cue`
  - [ ] 🟥 `SWIM_Easy_08` — 35min, taper opener: 400m wu (slow) + 4×100m (medium, 15s rest) + 300m cd (slow)
  - [ ] 🟥 `SWIM_Tempo_11` — 50min, 400m wu + 6×150m (medium, 20s rest) + 200m cd
  - [ ] 🟥 `SWIM_Tempo_12` — 55min, 400m wu + 5×200m (medium, 20s rest) + 200m cd
  - [ ] 🟥 `SWIM_Tempo_13` — 50min, 400m wu + 4×200m (medium, 20s rest) + 200m cd. `cue: "sight_every_6_strokes"` on work segments
  - [ ] 🟥 `SWIM_Intervals_11` — 60min, 400m wu + 8×150m (quick, 15s rest) + 300m cd
  - [ ] 🟥 `SWIM_Intervals_12` — 60min, 400m wu + 6×200m (quick, 15s rest) + 200m cd

  #### Bike (11 new)
  - [ ] 🟥 `BIKE_Easy_07` — 150min: 150min work @65% FTP
  - [ ] 🟥 `BIKE_Easy_08` — 180min: 180min work @65% FTP
  - [ ] 🟥 `BIKE_Easy_09` — 210min: 210min work @65% FTP
  - [ ] 🟥 `BIKE_Easy_10` — 240min: 240min work @65% FTP
  - [ ] 🟥 `BIKE_Easy_11` — 40min, taper opener: 15min wu @60% + 2×5min @84% (3min recovery @60%) + 10min cd @58%
  - [ ] 🟥 `BIKE_Intervals_11` — 60min: 10min wu @60% + 5×4min @110% (3min recovery @51%) + 10min cd @60%
  - [ ] 🟥 `BIKE_Tempo_11` — 45min, brick bike: 25min @65% + 20min @88%
  - [ ] 🟥 `BIKE_Tempo_12` — 50min, brick bike: 30min @65% + 20min @91%
  - [ ] 🟥 `BIKE_Tempo_13` — 40min, brick bike: 15min @65% + 25min @91%
  - [ ] 🟥 `BIKE_Tempo_14` — 30min, brick bike: 10min @65% + 20min @90%
  - [ ] 🟥 `BIKE_Tempo_15` — 180min, long + threshold: 80min @65% + 2×8min @96% (5min recovery @60%) + 64min @65% + 10min cd @58%

  #### Run (5 new)
  - [ ] 🟥 `RUN_Intervals_19` — 60min: 10min wu @70% + 6×3min @100% (2min recovery @65%) + 10min cd @70%
  - [ ] 🟥 `RUN_Intervals_20` — 65min: 10min wu @70% + 5×4min @100% (3min recovery @65%) + 10min cd @70%
  - [ ] 🟥 `RUN_Tempo_18` — 87min, long run w/ threshold finish: 65min @68% + 22min @85%
  - [ ] 🟥 `RUN_Tempo_19` — 55min, brick run w/ threshold: 38min @65% + 17min @85%
  - [ ] 🟥 `RUN_Tempo_20` — 75min, brick run w/ threshold: 52min @65% + 23min @85%

  #### Strength (1 new)
  - [ ] 🟥 `STRENGTH_Easy_01` — 30min: Uses `reps` field for count-based exercises and `duration_seconds` for timed holds. Structure:
    ```
    Block 1 (Core — repeat block):
      - Plank: 3×45s (duration_seconds: 45, rest_seconds: 30)
      - Side plank L: 2×30s
      - Side plank R: 2×30s
      - Dead bug: 3×8 reps/side (reps: 8, rest_seconds: 20)
      - Bird dog: 3×8 reps/side
      - Pallof press: 2×10 reps/side
    Block 2 (Strength — repeat block):
      - SL Romanian deadlift: 3×8 reps/side
      - Bulgarian split squat: 3×8 reps/side
      - Calf raises: 3×12 reps
      - Single-leg glute bridge: 2×10 reps/side
      - Band pull-apart: 2×15 reps
    ```

  #### Race (2 new)
  - [ ] 🟥 `RACE_Race_01` — 300min, Nîmes triathlon. Segments as race legs:
    ```json
    [
      {"label": "work", "distance_meters": 1900, "duration_minutes": 37, "pace": "medium", "cue": "Swim 1.9km — draft, stay calm in Gardon river current"},
      {"label": "recovery", "duration_minutes": 4, "cue": "T1 — wetsuit off → helmet on → go"},
      {"label": "work", "distance_meters": 90000, "duration_minutes": 162, "ftp_pct": 69, "cue": "Bike 90km — negative split, 190W avg, eat 60-80g carbs/h"},
      {"label": "recovery", "duration_minutes": 3, "cue": "T2 — caffeine gel"},
      {"label": "work", "distance_meters": 21000, "duration_minutes": 93, "mas_pct": 75, "cue": "Run 21km — start 4:35/km, build to 4:20/km if legs allow"}
    ]
    ```
  - [ ] 🟥 `RACE_Race_02` — 220min, Paris Marathon:
    ```json
    [
      {"label": "work", "distance_meters": 42195, "duration_minutes": 220, "mas_pct": 63, "cue": "Marathon — 5:20-5:40/km Z2, HR <145. Walk aid stations if needed. Practice 60g carbs/h."}
    ]
    ```

  #### JSON structure note
  - [ ] 🟥 Add top-level `"strength"` and `"race"` arrays to the JSON alongside existing `"swim"`, `"bike"`, `"run"`

---

### Phase 4: Data Seed

- [ ] 🟥 **Step 12: Create seed SQL script**
  - [ ] 🟥 Create `scripts/seed-nimes-plan.sql` with:
    1. Look up user ID: `SELECT id FROM auth.users WHERE email = 'ebreard4@gmail.com'`
    2. Delete existing plan: `DELETE FROM training_plans WHERE user_id = <user_id>` (CASCADE handles weeks + sessions)
    3. Insert `training_plans`: status='active', total_weeks=10, start_date='2026-03-23', race_date='2026-05-31', race_objective='Ironman 70.3'
    4. Insert 10 `plan_weeks` with:

       | Week | week_number | phase | is_recovery | start_date | notes |
       |------|-------------|-------|-------------|------------|-------|
       | 1 | 1 | Base | false | 2026-03-23 | Ramp-up: introduce doubles, build easy volume |
       | 2 | 2 | Base | false | 2026-03-30 | Ramp-up: first brick, push long bike to 80km |
       | 3 | 3 | Base | false | 2026-04-06 | Pre-marathon: front-load quality Mon-Thu, marathon Sunday |
       | 4 | 4 | Recovery | true | 2026-04-13 | Post-marathon recovery + restart. 3:1 cycle. |
       | 5 | 5 | Build | false | 2026-04-20 | Build 1: rebuild volume, reintroduce bricks |
       | 6 | 6 | Build | false | 2026-04-27 | Build 1: push bike to 90km, race nutrition test |
       | 7 | 7 | Peak | false | 2026-05-04 | KEY WEEK: biggest volume, first 100km ride, race-pace brick |
       | 8 | 8 | Peak | false | 2026-05-11 | PEAK VOLUME: full 90km race sim, longest brick run |
       | 9 | 9 | Taper | false | 2026-05-18 | Pre-taper: reduce volume 30%, keep sharp hard touches |
       | 10 | 10 | Taper | false | 2026-05-25 | TAPER + RACE: rest, sharpen, execute |

    5. Insert all `plan_sessions` (~99 rows). Each row: `week_id`, `day`, `sport`, `type`, `template_id`, `duration_minutes`, `is_brick`, `order_in_day`, `notes`
    6. Rest days derived from sessions: days with no sessions in each week → populate `plan_weeks.rest_days` JSONB

  - [ ] 🟥 Session-to-template mapping follows the full mapping from discovery (14 existing templates reused + 27 new templates). Key mappings:
    - Easy swims 1.5k (12+ occurrences) → `SWIM_Easy_06`
    - Bike VO2max 5×4min → `BIKE_Intervals_11`
    - Bike VO2max 4×4min → `BIKE_Intervals_02` (existing)
    - 5×3min run VO2max → `RUN_Intervals_01` (existing)
    - 6×3min run VO2max → `RUN_Intervals_19`
    - 5×4min run VO2max → `RUN_Intervals_20`
    - All brick bike legs → `BIKE_Tempo_11` through `BIKE_Tempo_14` (matched by duration/intensity)
    - All brick run legs → `RUN_Tempo_19` or `RUN_Tempo_20` (matched by distance/threshold portion)
    - Strength sessions → `STRENGTH_Easy_01`
    - Marathon → `RACE_Race_02` (sport='race', type='Race')
    - Nîmes race → `RACE_Race_01` (sport='race', type='Race')

- [ ] 🟥 **Step 13: Execute seed script**
  - [ ] 🟥 Run via Supabase MCP (`mcp__supabase__execute_sql`) against production
  - [ ] 🟥 Verify: query plan_sessions count for user, spot-check W1/W7/W10 sessions

---

### Phase 5: Context Doc Updates

- [ ] 🟥 **Step 14: Update context docs**
  - [ ] 🟥 `.claude/context/schema.md`: Update CHECK constraints for sport (add strength, race) and type (add Race). Note `reps` field on WorkoutSegment model.
  - [ ] 🟥 `.claude/context/architecture.md`: Update sport colors/icons/emojis table. Note enhanced RaceDayCardView, notes rendering, WorkoutLibrary struct change (strength/race arrays).
