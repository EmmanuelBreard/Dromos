# DRO-169: Inject Planned Workout Structure into Session Feedback Prompt

**Overall Progress:** `100%`

## TLDR
Add the planned workout steps (from the workout template library) to the session-feedback prompt so the AI can compare planned vs actual execution — flagging incomplete intervals, skipped sets, and intensity deviations.

## Critical Decisions
- **Fetch library at runtime (Option A)** — Fetch `workout-library.json` from Supabase Storage on each call (~50KB, CDN-cached). Same pattern as `generate-plan`. Avoids migration/backfill.
- **Compact single-line format** — `Warmup 15min @156W → 4×8min @240W / 3min recovery @156W → Cooldown 10min @156W`. Saves tokens while giving the AI enough to count intervals.
- **Absolute values** — Convert percentage-based intensities to real numbers using athlete profile (FTP for bike, VMA for run, pace labels for swim).

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `ai/prompts/session-feedback-v0.txt` | MODIFY | Add `{{planned_workout}}` to `## Planned` section, add compliance rule to `## Rules` |
| `supabase/functions/session-feedback/index.ts` | MODIFY | Fetch workout library, lookup template, add `formatPlannedWorkout()`, replace `{{planned_workout}}` |
| `supabase/functions/session-feedback/prompts/session-feedback-v0-prompt.ts` | REGENERATED | Auto-generated via `scripts/sync-prompts.sh` |

## Context Doc Updates
- `ai-pipeline.md` — Add `{{planned_workout}}` to session-feedback template variables list

## Tasks

### Phase 1: Prompt + Edge Function (single phase, no dependencies)

- [x] **Step 1: Update canonical prompt**

  Edit `ai/prompts/session-feedback-v0.txt`:

  - [x] Expand `## Planned` section from:
    ```
    ## Planned
    {{sport}} {{type}} — {{planned_duration}} min
    ```
    to:
    ```
    ## Planned
    {{sport}} {{type}} — {{planned_duration}} min
    {{planned_workout}}
    ```

  - [x] Add new rule in `## Rules` section:
    ```
    - If planned workout structure is provided, compare actual laps against it. Flag incomplete intervals (e.g., 3 of 4 completed), significant intensity deviations from prescribed targets, or missing warmup/cooldown. This is the most important coaching signal when both planned structure and lap data are available.
    ```

  - [x] Run `scripts/sync-prompts.sh` to regenerate the `.ts` file

- [x] **Step 2: Add workout library fetch and template lookup**

  In `supabase/functions/session-feedback/index.ts`:

  - [x] Add `template_id` to the `PlanSessionRow` interface and the `.select()` query (line 301)

  - [x] Add workout library types:
    ```typescript
    interface WorkoutSegment {
      label: string;
      duration_minutes?: number;
      distance_meters?: number;
      ftp_pct?: number;
      mas_pct?: number;
      pace?: string;
      repeats?: number;
      segments?: WorkoutSegment[];
      recovery?: WorkoutSegment;
      rest_seconds?: number;
    }

    interface WorkoutTemplate {
      template_id: string;
      duration_minutes: number;
      segments: WorkoutSegment[];
    }
    ```

  - [x] Add `fetchWorkoutLibrary()` function — same pattern as `generate-plan/index.ts` line 18:
    ```typescript
    async function fetchWorkoutLibrary(): Promise<Map<string, WorkoutTemplate>> {
      const supabaseUrl = Deno.env.get("SUPABASE_URL");
      const url = `${supabaseUrl}/storage/v1/object/public/static-assets/workout-library.json`;
      const res = await fetch(url);
      if (!res.ok) return new Map();
      const lib = await res.json();
      const map = new Map<string, WorkoutTemplate>();
      for (const sport of ["swim", "bike", "run"]) {
        for (const t of lib[sport] ?? []) {
          map.set(t.template_id, t);
        }
      }
      return map;
    }
    ```

- [x] **Step 3: Add `formatPlannedWorkout()` function**

  New function that takes a `WorkoutTemplate`, `sport` string, and `UserProfileRow`, returns compact single-line string.

  Logic per segment:
  - **`warmup` / `cooldown` / `work`** (non-repeat):
    - Bike: `{label} {duration}min @{round(ftp_pct/100 * profile.ftp)}W`
    - Run: `{label} {duration}min @{round(mas_pct/100 * profile.vma * 10) / 10} km/h ({formatPace("run", mas_pct/100 * profile.vma / 3.6)})`
    - Swim (duration): `{label} {duration}min {pace} pace`
    - Swim (distance): `{label} {distance}m {pace} pace`

  - **`repeat`**:
    - Work segment: `{repeats}×{work.duration or work.distance}{unit} @{intensity}`
    - Recovery (bike/run, `recovery` key): `/ {recovery.duration}min recovery @{intensity}`
    - Recovery (swim, `rest_seconds` key): `/ {rest_seconds}s rest`

  Join all top-level segments with ` → `.

  Fallbacks:
  - If `profile.ftp` is null for bike: use `{ftp_pct}% FTP` (relative)
  - If `profile.vma` is null for run: use `{mas_pct}% VMA` (relative)
  - If template not found: return empty string

  Example outputs:
  - Bike: `Warmup 15min @156W → 4×8min @240W / 3min recovery @156W → Cooldown 10min @156W`
  - Run: `Warmup 15min @12.0 km/h (5:00/km) → 2×20min @14.4 km/h (4:10/km) / 3min recovery @11.2 km/h (5:21/km) → Cooldown 10min @11.2 km/h (5:21/km)`
  - Swim: `Warmup 300m slow pace → 10×100m medium pace / 20s rest → Cooldown 200m slow pace`

- [x] **Step 4: Integrate into main handler**

  In the main handler, after fetching profile and session (around line 323):

  - [x] Add `fetchWorkoutLibrary()` to the `Promise.all` (5th parallel query)
  - [x] After `Promise.all`, look up template:
    ```typescript
    const templateId = session.template_id;
    const template = templateId ? workoutLibrary.get(templateId) : null;
    const plannedWorkout = template
      ? formatPlannedWorkout(template, session.sport, profile)
      : "";
    ```
  - [x] Add `.replace("{{planned_workout}}", plannedWorkout)` to the prompt rendering chain (after line 423)

- [x] **Step 5: Update context docs + deploy**

  - [x] Update `ai-pipeline.md` — add `{{planned_workout}}` to session-feedback template variables list
  - [x] Deploy: `scripts/deploy-functions.sh session-feedback`
  - [x] Manual test: trigger sync, verify feedback for a completed interval session references the planned structure (e.g., mentions "3 of 4 intervals")
