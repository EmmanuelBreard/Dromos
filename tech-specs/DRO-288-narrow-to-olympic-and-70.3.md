# DRO-288 — Narrow Dromos to Olympic + Ironman 70.3

**Overall Progress:** `100%` — Shipped 2026-06-06. Edge function deployed to production at version 36. All sub-issues (DRO-290 / DRO-291 / DRO-292 / DRO-293) merged and closed. Follow-ups filed as [DRO-294](https://linear.app/dromosapp/issue/DRO-294) (re-entry custom-time clobber) and [DRO-295](https://linear.app/dromosapp/issue/DRO-295) (pre-existing eval drift from gpt-4o → gpt-4.1 model upgrade — not a DRO-288 regression).

## TLDR

Reduce the supported race-distance surface from 4 (Sprint / Olympic / 70.3 / Ironman) to 2 (Olympic / 70.3) across the iOS app, AI pipeline context, workout library, and eval fixtures. No DB schema change — the CHECK constraint stays loose so existing non-70.3/Olympic users keep their data. One piece of net-new work: author an Olympic race-day template in `workout-library.json` (currently absent — without it Olympic athletes would inherit the 70.3 race template).

## Critical Decisions

- **DB CHECK constraint stays untouched.** Keep `('Sprint','Olympic','Ironman 70.3','Ironman')` in `users.race_objective`. Existing Sprint/Ironman users (1 Sprint per audit) keep their data. Avoids a destructive migration for a 1-user edge case.
- **Author a new Olympic RACE template (`RACE_Race_02`, reusing the freed slot).** Library has no Olympic race template today. Without one, Step 3 would force-pick the 70.3 template for Olympic athletes' race week. Replace the deleted full-IM marathon stub at `RACE_Race_02` rather than introducing `RACE_Race_03` — keeps the ID sequence tidy.
- **Time-objective default becomes distance-aware** (Olympic = 150 min, 70.3 = 360 min). Default to 70.3 path when distance unset. Today it's a static 120-min default (`selectedHours = 2`) — clearly wrong for 70.3, marginal for Olympic.
- **No prompt edits in `step1-macro-plan.txt` / `step2-md-to-json.txt` / `step3-workout-block.txt`.** Distance guidance lives in `training-philosophy-content.ts` (Section 5) which is interpolated into Step 1 — that's the only LLM-injected place per `ai-pipeline.md:43-51`. The Step 3 simplified library already iterates only `["swim","bike","run"]` (see `ai-pipeline.md:93`), but the `race[]` array is still served at runtime to the post-processing race-week logic — that part needs the curated 2 templates.
- **iOS picker stays as a 2-option segmented control**, not a static label. Two distances on a segmented picker reads better than a single static label and supports future widening (e.g., adding Sprint back) with a 1-line change.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `supabase/functions/generate-plan/context/training-philosophy-content.ts` | MODIFY | Delete Sprint + Ironman rows from volume-split table (L64, L67). Delete "Sprint Triathlon" (L121-126) and "Ironman" (L142-148) subsections. Keep Olympic + 70.3 sections + the Olympic example week (L103). |
| `supabase/functions/generate-plan/index.ts` | MODIFY | `expandRaceObjective()` (L99-109): drop Sprint + Ironman entries from `mapping`, keep Olympic + Ironman 70.3. |
| `ai/context/workout-library.json` | MODIFY | Keep `RACE_Race_01` (70.3) as-is. Replace `RACE_Race_02` (currently marathon-only full-IM stub) with a new Olympic race template (1.5km swim / 40km bike / 10km run with T1/T2). |
| `Dromos/Dromos/Resources/workout-library.json` | NO ACTION | Symlink → `ai/context/workout-library.json`, auto-updates. Per `architecture.md:79`. |
| Storage upload: `static-assets/workout-library.json` | RE-UPLOAD | Edge function fetches library at runtime from Supabase Storage (per `ai-pipeline.md:160`). Run `scripts/upload-static-assets.sh` after JSON edits. |
| `Dromos/Dromos/Core/Models/User.swift` | MODIFY | `RaceObjective` enum (L14-19): delete `.sprint` + `.ironman`. Keep `.olympic` + `.ironman703`. |
| `Dromos/Dromos/Core/Models/OnboardingData.swift` | MODIFY | Update doc comment at L15 from "Sprint, Olympic, 70.3, Ironman" → "Olympic, Ironman 70.3". |
| `Dromos/Dromos/Features/Onboarding/OnboardingScreen2View.swift` | MODIFY | Picker (L69-82): `.sprint` defaults → `.ironman703` at L70 + L80. Time-objective defaults (L20-21): make distance-aware via `onChange(of: data.raceObjective)` → Olympic = 150 min (`selectedHours=2, selectedMinutes=30`), 70.3 = 360 min (`selectedHours=6, selectedMinutes=0`). Default to 70.3 path when `raceObjective` unset on appear. |
| `Dromos/Dromos/Features/Profile/ProfileView.swift` | MODIFY | L43 `editRaceObjective: RaceObjective = .sprint` → `.ironman703`. L344-347 Picker iterates `RaceObjective.allCases` — no code change, picker auto-shrinks to 2. L622 `?? .sprint` fallback → `?? .ironman703`. |
| `Dromos/Dromos/Core/Utils/PaceMath.swift` | MODIFY | Bike `distances` (L99-104): drop `"180 km · Ironman"`. Swim `distances` (L117-121): drop `"3800 m · Ironman"`. Keep Olympic + Half-Iron entries on both. |
| `ai/eval/vars/athletes.yaml` | MODIFY | Remove Sam (Sprint, L82-120). Keep Alex (Olympic), Jordan (70.3), Emmanuel (70.3). |
| `ai/eval/vars/step2-inputs.yaml` | MODIFY | Remove Sam block (L318-404). Keep Alex/Jordan/Emmanuel blocks intact. |
| `ai/eval/vars/adjust-step2-scenarios.yaml` | NO ACTION | Comment at L7 references Alex (Olympic) — still valid. |
| `ai/eval/generate-for-jeanne.js` | MODIFY | Mapping at L75-78: drop Sprint + Ironman entries. L32 `race_objective: "Olympic"` stays valid. |
| `ai/eval/benchmark-timing.js` | MODIFY | L24 `race_objective: "olympic"` (lowercase, fails DB CHECK) → `"Olympic"`. |

## Context Doc Updates

- `ai-pipeline.md` — Update Step 1 template variables section (L51) noting `{{race_distance}}` now has 2 possible values. Update the file-locations table or add a note to the workout-library section (L158-162) that `race[]` now holds 2 curated templates (RACE_Race_01 = 70.3, RACE_Race_02 = Olympic).
- `schema.md` — No change. The `users.race_objective` CHECK constraint is unchanged per the locked decision.
- `architecture.md` — No change. No new files, no new patterns.

## Phases

Four sequential phases. Each phase is self-contained and shippable behind a single PR. Phases 1 + 3 can run in parallel (different sub-trees) but Phase 4 must wait for both.

---

### Phase 1: AI pipeline narrowing (edge function + workout library)

- [x] 🟩 **Step 1.1: Trim `training-philosophy-content.ts`**
  - [x] 🟩 Delete Sprint row from volume-split table (L64).
  - [x] 🟩 Delete Ironman row from volume-split table (L67).
  - [x] 🟩 Delete the entire "Sprint Triathlon" subsection (L121-126).
  - [x] 🟩 Delete the entire "Ironman" subsection (L142-148).
  - [x] 🟩 Keep Olympic + 70.3 subsections verbatim. Keep the "Olympic distance focus" example week (L103).

- [x] 🟩 **Step 1.2: Collapse `expandRaceObjective()`**
  - [x] 🟩 In `supabase/functions/generate-plan/index.ts:100-108`, reduce the `mapping` object to:
    ```ts
    const mapping: Record<string, string> = {
      Olympic: "Olympic (1.5km swim / 40km bike / 10km run)",
      "Ironman 70.3": "Half-Ironman (1.9km swim / 90km bike / 21.1km run)",
    };
    ```
  - [x] 🟩 Leave the fallback `return mapping[raceObjective] || raceObjective;` so legacy Sprint/Ironman strings degrade to a literal echo instead of crashing.

- [x] 🟩 **Step 1.3: Curate `workout-library.json` race[] array**
  - [x] 🟩 Keep `RACE_Race_01` (70.3) unchanged (L5078-5114).
  - [x] 🟩 **Replace** `RACE_Race_02` (currently full-IM marathon stub at L5115-5127) with an Olympic race template:
    - `template_id: "RACE_Race_02"`
    - `duration_minutes: ~150` (matches Olympic time-objective default — author tunes to a realistic finish profile)
    - Segments: swim 1500m work → recovery (T1) → bike 40000m work → recovery (T2) → run 10000m work
    - Match the structure of `RACE_Race_01` (label/distance_meters/duration_minutes/pace OR ftp_pct/vma_pct/cue).
    - Cues should reference Olympic-specific pacing (e.g. swim "stay smooth, 200m race effort", bike "Z3/upper Z2 sustainable", run "negative split").
  - [x] 🟩 Run `scripts/upload-static-assets.sh` to push the updated library to Supabase Storage (`static-assets/workout-library.json`).

- [x] 🟩 **Step 1.4: Sync prompts + redeploy edge function**
  - [x] 🟩 Run `scripts/sync-prompts.sh` (regenerates `.ts` wrappers from canonical `ai/prompts/*.txt`). No prompt-text changes in this ticket, but the context-file edit doesn't go through sync-prompts — verify no other regeneration is needed.
  - [x] 🟩 Deploy via `scripts/deploy-functions.sh generate-plan`.

---

### Phase 2: iOS UI narrowing

- [x] 🟩 **Step 2.1: Shrink `RaceObjective` enum**
  - [x] 🟩 In `Dromos/Dromos/Core/Models/User.swift:14-19`, delete `.sprint` + `.ironman` cases. Final state:
    ```swift
    enum RaceObjective: String, Codable, CaseIterable {
        case olympic = "Olympic"
        case ironman703 = "Ironman 70.3"
    }
    ```
  - [x] 🟩 Fix the doc comment at L12-13 to match.

- [x] 🟩 **Step 2.2: Update OnboardingData doc**
  - [x] 🟩 `Dromos/Dromos/Core/Models/OnboardingData.swift:15` — rewrite comment: `/// Target triathlon race distance (Olympic, Ironman 70.3)`.

- [x] 🟩 **Step 2.3: Update `OnboardingScreen2View.swift`**
  - [x] 🟩 L70 + L80: replace `.sprint` defaults with `.ironman703`.
  - [x] 🟩 L20-21: keep `@State private var selectedHours: Int = 6` and `selectedMinutes: Int = 0` as the **default** (70.3 path; matches the new "default to 70.3 when distance unset" decision).
  - [x] 🟩 Add an `onChange(of: data.raceObjective)` to the form `VStack` that resets `(selectedHours, selectedMinutes)` and `data.timeObjectiveMinutes` to `(2, 30, 150)` when distance becomes Olympic and `(6, 0, 360)` when distance becomes 70.3, **only if the user hasn't yet manually edited the time picker this session**. Track manual edits with a `@State private var timeObjectiveManuallyEdited = false` flag that flips in the existing `onChange(of: selectedHours/selectedMinutes)` handlers.
  - [x] 🟩 Verify the segmented `Picker` (L69-77) auto-shrinks to 2 options because it iterates `RaceObjective.allCases`. No code change required there beyond what Step 2.1 enables.

- [x] 🟩 **Step 2.4: Update `ProfileView.swift`**
  - [x] 🟩 L43: `editRaceObjective: RaceObjective = .sprint` → `.ironman703`.
  - [x] 🟩 L622: `editRaceObjective = user.raceObjective ?? .sprint` → `.ironman703`.
  - [x] 🟩 L344-347 Picker: no code change (auto-shrinks via `RaceObjective.allCases`). Confirm visually that the segmented appearance is acceptable for 2 options inside a `Form` row — if it renders poorly, switch to `.pickerStyle(.menu)` or keep default wheel.
  - [x] 🟩 Verify `mapSaveError` does not need updating — DB CHECK is unchanged so existing error paths still apply.

- [x] 🟩 **Step 2.5: Update `PaceMath.swift`**
  - [x] 🟩 Bike `distances` (L99-104): drop `DistanceEntry(name: "180 km · Ironman", km: 180.0)`.
  - [x] 🟩 Swim `distances` (L117-121): drop `DistanceEntry(name: "3800 m · Ironman", km: 3.8)`.
  - [x] 🟩 Keep Olympic + Half-Iron entries on both disciplines + the 1km / 10km / half marathon / marathon entries on run (run distances are not race-distance-specific in the calculator — they're educational reference values).

---

### Phase 3: Eval fixture cleanup

- [x] 🟩 **Step 3.1: Remove Sam (Sprint) from athletes.yaml**
  - [x] 🟩 Delete lines L82-120 (`athlete_name: "Sam - Time-Crunched Sprint"` block). Renumber remaining athletes if YAML uses ordinal keys — confirm during execution.

- [x] 🟩 **Step 3.2: Remove Sam block from step2-inputs.yaml**
  - [x] 🟩 Delete L318-404. Keep Alex, Jordan, Emmanuel blocks unchanged.

- [x] 🟩 **Step 3.3: Trim `generate-for-jeanne.js` mapping**
  - [x] 🟩 L75-78: drop Sprint + Ironman entries. Final:
    ```js
    Olympic: "Olympic (1.5km swim / 40km bike / 10km run)",
    "Ironman 70.3": "Half-Ironman (1.9km swim / 90km bike / 21.1km run)",
    ```
  - [x] 🟩 L32 `race_objective: "Olympic"` stays valid — no change.

- [x] 🟩 **Step 3.4: Fix benchmark-timing.js casing**
  - [x] 🟩 L24: `race_objective: "olympic"` → `"Olympic"` (proper case for DB CHECK constraint).

---

### Phase 4: Validation + context-doc updates

- [x] 🟩 **Step 4.1: Run AI eval batch**
  - [x] 🟩 `bash ai/eval/batch-eval.sh` (default settings) targeting Alex (Olympic) + Jordan/Emmanuel (70.3).
  - [x] 🟩 Verify 0 violations across all 8 metrics from `ai/eval/check-step3-violations.js`.
  - [x] 🟩 Spot-check one Olympic plan + one 70.3 plan: race-week session uses the correct RACE_Race_0X template.

- [x] 🟩 **Step 4.2: Manual iOS QA**
  - [x] 🟩 Fresh onboarding flow: picker shows 2 options. Selecting Olympic → time picker shows 2h30 by default. Selecting 70.3 → 6h00. Manual edit then switching distance must NOT overwrite the user's typed value.
  - [x] 🟩 Profile → Edit: picker shows 2 options. Existing Olympic user (Emmanuel test account if available, else simulate) loads correctly. Existing legacy Sprint user (the 1 audit-flagged production user) — verify Profile renders without crash and the picker falls back gracefully (selection will not match → defaults via `?? .ironman703`).
  - [x] 🟩 Generate a fresh plan end-to-end from the iOS client for both distances. Confirm plan persists and renders.

- [x] 🟩 **Step 4.3: Update `.claude/context/ai-pipeline.md`**
  - [x] 🟩 Add a note under "Step 1" or "Workout Library" that `{{race_distance}}` is now Olympic or Ironman 70.3 only, and that `race[]` holds 2 curated templates.

---

## Tests / Rollback

**Automated tests:** AI eval batch (`batch-eval.sh`) is the primary gate — 0 violations + correct race-week template.

**Manual tests:** Listed in Step 4.2.

**Rollback plan:** Pure code revert. No DB state changed, no migrations. `git revert` the 3-4 PRs (one per phase) and `scripts/deploy-functions.sh generate-plan` + `scripts/upload-static-assets.sh` to restore prior state. Existing user data is untouched throughout.

**Risk: legacy users.** 1 Sprint + 0 (no Ironman) audited production users. On next profile fetch, their `raceObjective` decodes as `nil` (string `"Sprint"` no longer maps to any enum case). UI falls back to `.ironman703` defaults; their existing plan is unaffected (`training_plans.race_objective` is a snapshot TEXT field). If we ever ship a "regenerate plan" flow that re-reads `users.race_objective`, that user would get a 70.3 plan — acceptable for V0.
