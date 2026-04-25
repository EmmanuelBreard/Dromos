# DRO-212 — Replace ebreard4@gmail.com plan sessions (Apr 22 → May 31) with Yupa-reviewed plan

**Overall Progress:** `0%`

## TLDR

One-off data update: replace `plan_sessions` rows for wks 5–10 of Emmanuel Breard's active 70.3 plan with a coach-reviewed schedule biased toward race-pace specificity. Append any missing session templates to `ai/context/workout-library.json`. Silent swap — iOS picks up the change on next foreground refresh. No Edge Function, no iOS code, no migrations.

- Plan: `448c70ee-e2b2-480f-9ba0-7fbbee9ec82f`
- User: `6a7ac10d-82f6-4a9b-9a8f-93fb49c0bd6a` (`ebreard4@gmail.com`)
- Scope: wks 5–10 sessions starting Wed Apr 22. Wks 1–4 and Mon/Tue of wk 5 are untouched.

## Critical Decisions

- **Template library is a symlink, not two files.** Architecture doc (`.claude/context/architecture.md:57`) and `ls -la` confirm `Dromos/Dromos/Resources/workout-library.json` is a symlink → `ai/context/workout-library.json`. Edit one file; iOS bundle picks up the change. _Corrects the original ticket description._
- **Execution path: direct SQL via Supabase MCP with `service_role`.** No new Edge Function, no script artifact. The `reorder_sessions` RPC cannot DELETE rows (per `supabase/migrations/011_plan_sessions_user_update.sql`), so RPC is not an option. MCP writes bypass RLS — this is expected for a one-off admin op.
- **Destructive replace, no snapshot.** Per user decision, we discard current wk 5–10 rows. Informal backup = the SELECT-before-DELETE output in the chat transcript.
- **Template strategy: reuse where segments match exactly, otherwise append new.** Numbering continues the existing sequence (e.g. next bike tempo → `BIKE_Tempo_18`). Segment `ftp_pct` / `mas_pct` values are derived from Emmanuel's thresholds (FTP 275W, VMA 18 km/h → 3:20/km at 100% MAS, CSS 2:00/100m). Notes on each `plan_sessions` row mirror the prescription word-for-word so iOS renders the same prescription whether it reads the template's `segments` or the session's `notes` field.
- **Silent swap, no athlete signal.** No notification, no chat message, no `feedback` field text. The new plan just appears on next foreground refresh via `MainTabView.scenePhase` (`Dromos/Dromos/App/MainTabView.swift:93`).
- **Tue Apr 21 row stays as-is.** The original generator's run-intervals row for that day remains in the DB even though the athlete did a 33-min easy bike. Per user decision: "We don't care about today or tomorrow."

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `ai/context/workout-library.json` | MODIFY | Append new templates for sessions without an exact existing match (bike race-pace, short-VO2 run, race-week openers, progressive tempo runs). |
| `plan_sessions` (DB) | DELETE + INSERT | Destructive replace of wks 5–10 rows (except wk 5 Mon + Tue). |
| `plan_weeks` (DB) | UPDATE | Wk 5: `phase='Recovery'`, new `notes`. Wks 6–10: `notes` only (phase already correct). |

No Swift, no Edge Function, no migration file, no new table.

## Context Doc Updates

None. This is a data operation with one library append; no schema, architecture, or pipeline changes.

## Tasks

- [ ] 🟥 **Step 1: Pre-flight snapshot & template audit**
  - [ ] 🟥 Run `SELECT ... FROM plan_sessions JOIN plan_weeks ... WHERE plan_id = '448c70ee...' AND week_number BETWEEN 5 AND 10 ORDER BY week_number, day, order_in_day` and paste the raw JSON into the chat transcript as an informal backup.
  - [ ] 🟥 Read `ai/context/workout-library.json` fully and build a map of existing `{sport → type → duration → structure}` → `template_id`.
  - [ ] 🟥 For each of the 58 new sessions in the ticket's day-by-day tables, decide: REUSE existing `template_id`, or CREATE new. Produce a decision table (session → template_id) and share inline before proceeding.

- [ ] 🟥 **Step 2: Append new templates to the library**
  - [ ] 🟥 Draft new template JSON entries. Segment schema per sport:
    - Bike: `{label, duration_minutes, ftp_pct, cadence_rpm?}`, with repeats via `{label: "repeat", repeats, segments, recovery}`.
    - Run: `{label, duration_minutes, mas_pct}` with same repeat pattern.
    - Swim: `{label, distance_meters, pace}` (existing convention in `SWIM_*` templates).
  - [ ] 🟥 Derive `ftp_pct` / `mas_pct` from athlete thresholds:
    - FTP 275W → 240W = 87%, 245W = 89%, 260W = 94%, 280W = 102%, 230W = 84%, 235W = 85%.
    - VMA 18 km/h (3:20/km) → 3:30/km = 95% MAS, 4:30/km = 74% MAS, 4:45/km = 70% MAS, 5:15/km = 64% MAS, 5:30/km = 60% MAS.
  - [ ] 🟥 Append entries using next-sequence IDs (e.g. `BIKE_Tempo_18`, `BIKE_Intervals_13`, `RUN_Intervals_23`, `RUN_Tempo_22`…). Preserve existing file formatting (2-space indent, trailing newline).
  - [ ] 🟥 Validate JSON is parseable: `jq . ai/context/workout-library.json > /dev/null`.
  - [ ] 🟥 Commit the library diff as its own commit: `chore(DRO-212): add workout templates for coach-reviewed plan`.

- [ ] 🟥 **Step 3: Update `plan_weeks` metadata (phase + notes)**
  - [ ] 🟥 UPDATE wk 5 → `phase='Recovery'`, `notes='REBUILD: post-marathon + wk-4 overreach recovery. Z1–Z2 only from Wed.'`.
  - [ ] 🟥 UPDATE wk 6 → `notes='BUILD: reintroduce 1 VO2 + 1 race-pace per discipline. 80/20 polarized.'`.
  - [ ] 🟥 UPDATE wk 7 → `notes='PEAK BUILD: 1 VO2 + 2 race-pace blocks. First brick with race-pace finish.'`.
  - [ ] 🟥 UPDATE wk 8 → `notes='PEAK SPECIFICITY: race-sim bike, race-pace run. Short VO2 touch only.'`.
  - [ ] 🟥 UPDATE wk 9 → `notes='PRE-TAPER: volume −30%, no VO2, preserve race-pace touches.'`.
  - [ ] 🟥 UPDATE wk 10 → `notes='TAPER + RACE: openers, rest, execute Nîmes 70.3.'`.

- [ ] 🟥 **Step 4: Delete obsolete sessions**
  - [ ] 🟥 Build the DELETE WHERE clause carefully — preserve wk 5 Mon 20 + Tue 21:
    ```sql
    DELETE FROM plan_sessions
    WHERE week_id IN (
      SELECT id FROM plan_weeks
      WHERE plan_id = '448c70ee-e2b2-480f-9ba0-7fbbee9ec82f'
        AND week_number BETWEEN 5 AND 10
    )
    AND NOT (
      week_id = (SELECT id FROM plan_weeks WHERE plan_id = '448c70ee-e2b2-480f-9ba0-7fbbee9ec82f' AND week_number = 5)
      AND day IN ('Mon', 'Tue')
    );
    ```
  - [ ] 🟥 Confirm rowcount matches expectation (original wk 5–10 session count minus wk 5 Mon+Tue rows).

- [ ] 🟥 **Step 5: Insert new sessions**
  - [ ] 🟥 Build INSERT statements from the day-by-day table in DRO-212, one row per session. Fields: `week_id`, `day` (Mon/Tue/…/Sun abbreviated), `sport`, `type`, `template_id`, `duration_minutes`, `is_brick`, `order_in_day`, `notes`.
  - [ ] 🟥 Validate CHECK constraints: `sport ∈ {swim,bike,run,strength,race}`, `type ∈ {Easy,Tempo,Intervals,Race}`, `duration_minutes > 0`.
  - [ ] 🟥 Execute INSERT in one batch per week.

- [ ] 🟥 **Step 6: Post-flight verification**
  - [ ] 🟥 Run session count + total minutes per week:
    ```sql
    SELECT pw.week_number, pw.phase, COUNT(ps.*) AS sessions, SUM(ps.duration_minutes) AS total_min
    FROM plan_weeks pw LEFT JOIN plan_sessions ps ON ps.week_id = pw.id
    WHERE pw.plan_id = '448c70ee-e2b2-480f-9ba0-7fbbee9ec82f'
    GROUP BY pw.week_number, pw.phase ORDER BY pw.week_number;
    ```
    Expected: wk 5 ≈ 390min (6.5h incl. Tue row), wk 6 ≈ 630min, wk 7 ≈ 675min, wk 8 ≈ 670min, wk 9 ≈ 485min, wk 10 ≈ 240min (race row excluded) or ~570min (race row included — depends on existing RACE row).
  - [ ] 🟥 Confirm every `template_id` in `plan_sessions` resolves to a key in `workout-library.json`:
    ```sql
    SELECT DISTINCT template_id FROM plan_sessions
    WHERE week_id IN (SELECT id FROM plan_weeks WHERE plan_id = '448c70ee...' AND week_number BETWEEN 5 AND 10);
    ```
    Manually cross-check each against the JSON.
  - [ ] 🟥 Open the iOS app on-device (trigger `scenePhase = .active` refetch). Confirm Wed Apr 22 shows the new run-easy session and wk 5 phase badge shows **Recovery**. Spot-check wk 6 and wk 8 peaks.

- [ ] 🟥 **Step 7: Close the loop**
  - [ ] 🟥 Update the Linear ticket with an execution-complete comment + a link to the library-diff commit.
  - [ ] 🟥 Move DRO-212 to `Done`.

## Risks

- **Destructive, no rollback.** Snapshot is a raw SELECT in chat — if that's lost, recovery is manual from memory. Accepted.
- **Template-to-note fidelity.** The athlete self-paces from the `notes` string; the template `segments` only drive iOS's workout-step graph. If notes and segments drift, the step-by-step render may not match the note text. Mitigation: Step 2's derivation rubric keeps them in sync by construction.
- **iOS refetch timing.** The athlete must foreground the app for `MainTabView.scenePhase` to trigger. If he doesn't open it Wed morning, he sees stale data. Mitigation: none needed — same behavior as all other plan updates today.
- **FTP/VMA interpretation.** If Emmanuel's real FTP is below 275W or VMA above 18 km/h, the derived `ftp_pct` / `mas_pct` values in the new templates will slightly mis-scale. Acceptable — the notes carry absolute targets (W and /km) which override the percentages for the self-paced athlete.
