# AGENTS.md

Read this before changing Dromos. It describes the repo as it is. If it disagrees with `.claude/context/` or an older tech spec, trust this file and the code.

Swift style lives in `.cursor/rules/development-guidalines.md` (the filename spelling is the one on disk). The product-assistant role and Linear workflow live in `.claude/CLAUDE.md`. Do not copy those into code changes.

## Product

Dromos is an iOS app that builds and follows a triathlon training plan. A new athlete signs up and talks to the coach in a fixed chat (race, metrics, which days they can swim, bike, and run, how long each of those days is, and injuries or weak spots). The backend then generates a periodized plan of concrete workouts. Home shows one day. Calendar shows one week. A workout counts as done when a synced Strava activity matches it. There is no "mark complete" control, and completion is not stored on the session.

This repo has no web app, admin UI, payments, or analytics. `docs/privacy-policy.html` is a static privacy page. The marketing site is a separate project.

Coach chat and hand-imported plans exist. Both are limited to `ebreard4@gmail.com`.

## Stack

| Layer | What |
| --- | --- |
| App | SwiftUI, deployment target iOS 18.0, bundle `com.getdromos.app`, marketing version 1.1. Project `Dromos/Dromos.xcodeproj`, scheme `Dromos`. |
| Client SDK | `supabase-swift` 2.40.0 via Swift Package Manager. |
| Backend | Hosted Supabase: Postgres, Auth, Storage, Edge Functions (Deno). Project ref is in `scripts/deploy-functions.sh`. |
| Models | OpenAI `gpt-4.1` for plan steps 1 and 3, coach chat, onboarding, and session feedback. `gpt-4o-mini` for the plan step 2 fallback. Functions use the `openai` npm package. |
| Workouts | Canonical library `ai/context/workout-library.json`. |

The app target does not use Core Data, Realm, or a third-party HTTP stack.

## Repo layout

```
Dromos/Dromos/           iOS app (App, Core, Features, Resources)
Dromos/DromosTests/      Swift tests on disk. Not an Xcode test target.
supabase/functions/      Edge functions
supabase/migrations/     SQL migrations. No supabase/config.toml.
ai/prompts/              Canonical prompt text
ai/context/              Training philosophy and workout-library.json
ai/eval/                 Promptfoo configs and the live generation eval
scripts/                 Deploy, prompt sync, storage upload, backfill
.claude/                 Product role, commands, older context notes
.cursor/rules/           Swift conventions
tech-specs/ strategy/ prototypes/   Design history, not runtime
```

iOS features under `Dromos/Dromos/Features/`: `Auth`, `Onboarding`, `Plan` (the generation screen), `Home`, `Calendar`, `Chat`, `Profile`, `Tools` (pace calculator).

| Edge function | Role |
| --- | --- |
| `generate-plan` | Builds a plan. The HTTP call returns immediately. Work continues in `EdgeRuntime.waitUntil`. |
| `session-feedback` | Writes `plan_sessions.feedback` for a matched activity. `gpt-4.1`. |
| `strava-auth` | Exchanges the Strava OAuth code and stores tokens. |
| `strava-sync` | Upserts activities, laps, and streams. |
| `chat-adjust` | Streaming advisory coach. Does not change the plan. Email-gated. |
| `onboarding-coach` | Writes the reply and, for typed answers, a structured parse. Does not write the database. Not email-gated. The app stores the row. |
| `import-plan` | Replaces a plan from a JSON body after writing `plan_snapshots`. Email-gated. |
| `delete-account` | `auth.admin.deleteUser`. Related rows cascade. Not listed in `scripts/deploy-functions.sh`. |

`supabase/functions/_shared/materialize-structure.ts` turns a library template into the `plan_sessions.structure` JSON the app renders. Swim `pace` tags become RPE. Legacy `mas_pct` becomes `vma_pct`. A range target is kept only when both the min and the max are present.

## Data model

The profile table is `public.users`, not `profiles`. `id` is the `auth.users` id. Trigger `on_auth_user_created` inserts the row on signup (`handle_new_user`).

`users` → `training_plans` (one row per user, `UNIQUE(user_id)`) → `plan_weeks` → `plan_sessions`.

Also: `strava_connections` (one per user), `strava_activities` → `strava_activity_laps`, `chat_messages`, `plan_snapshots`. Foreign keys use `ON DELETE CASCADE`. RLS is enabled. The app reads with the user JWT. Plan rows are written with the service role. Moving a session is the `reorder_sessions` RPC, which checks ownership. `import_plan_atomic` is `service_role` only.

`users` columns that matter:

- Identity: `email`, `name`, `onboarding_completed`.
- Race: `race_objective` (`Sprint`, `Olympic`, `Ironman 70.3`, `Ironman`, or null), `race_date`, `time_objective_minutes`.
- Metrics: `vma` (10–25), `css_seconds_per100m` (25–300), `ftp` (50–500), `experience_years` (≥ 0), `current_weekly_hours` (0–25), `max_hr` (100–220), `birth_year` (1920–2030).
- Availability: `swim_days`, `bike_days`, `run_days`. JSON arrays of full English day names (`"Monday"`).
- Time: `mon_duration` through `sun_duration`. Null, or an integer from 30 to 420. Null means that day is not available. `0` fails the check.
- Onboarding extras: `limiters` (text, nullable; the word `none` means the athlete reported none; null means not asked yet) and `metrics_source` (jsonb object, or null). `metrics_source` records `entered`, `estimated_from_race`, `estimated_from_experience`, or `estimated_from_age` for `vma`, `css`, `ftp`, and `max_hr`.
- Strava: `strava_athlete_id`.

The app only offers Olympic and Ironman 70.3. The check constraint still allows Sprint and full Ironman so older rows still load. `User` decodes an unknown `race_objective` as nil instead of failing the whole profile.

`training_plans.status` is `generating`, `active`, or `failed`. A failure also sets `error_message` and `failed_at` (migration `20260715_allow_failed_plan_status.sql`). `race_date`, `race_objective`, `total_weeks`, and `start_date` are copied onto the plan at creation.

`plan_weeks`: `week_number`, `phase` (`Base`, `Build`, `Peak`, `Taper`, `Recovery`), `is_recovery`, `rest_days`, `notes`, `start_date`. Unique on `(plan_id, week_number)`.

`plan_sessions`: `day`, `sport`, `type`, `template_id`, `duration_minutes`, `is_brick`, `order_in_day`, `notes`, `feedback`, `matched_activity_id`, `structure`. The check allows sports `swim`, `bike`, `run`, `strength`, `race` and types `Easy`, `Tempo`, `Intervals`, `Race`. Generation only writes `swim`, `bike`, and `run`, and only `Easy`, `Tempo`, or `Intervals`. `structure` is what the cards render. A null `structure` falls back to `template_id` in the bundled library.

`users.limiters` is read by `toAthletePlanInput`. Null becomes the prompt word `none`. The column is sliced to 200 characters in the prompt; that cap was already there and this change does not raise it.

## User flows

`RootView` routes: splash while `AuthService.isInitializing` → `AuthView` → `OnboardingFlowView` until `users.onboarding_completed` → `PlanGenerationView` until a plan with `status = active` exists → `MainTabView` (Home, Calendar, Profile, and Coach only for the allowlisted email).

1. **Auth.** Email and password (`AuthService`). The client maps an "Email not confirmed" API error when the project returns one. There is no Apple or Google sign-in.
2. **Onboarding.** New users only (`onboarding_completed` is false). `OnboardingFlowView` hosts `OnboardingChatView`. A scripted state machine in `Dromos/Dromos/Core/Onboarding/` chooses the step, the quick replies, and what may be stored. `onboarding-coach` only writes the reaction and parses free text. Each accepted answer is saved with `ProfileService.saveOnboardingPatch`, so a closed app resumes at the next unanswered step. "Get my plan" calls `markOnboardingComplete` and `PlanGenerationView` starts generation on appear. Availability and daily durations are not editable afterward. Profile edit writes name, race, time objective, VMA, CSS, FTP, experience, max HR, and birth year only.
3. **Generate.** `PlanService.generatePlan` invokes `generate-plan` with the session JWT and no body, then polls `training_plans` every 3 seconds for up to 8 minutes (`160` iterations) until `active` or `failed`. The function loads `users` and builds `AthletePlanInput` in `supabase/functions/generate-plan/lib/input.ts`. The prompt text is unchanged.
4. **Pipeline inside `buildScheduledPlan`.** Step 1 (`gpt-4.1`, temperature 0.2, 16,384 tokens) writes a markdown macro plan. If that markdown matches the expected shape, it is parsed in process and step 2 is skipped. Otherwise `gpt-4o-mini` converts it, splitting the markdown when a reply is cut off. Step 3 assigns templates in parallel 4-week blocks (`gpt-4.1`, 16,384 tokens). A block that still fails is scheduled from the macro plan so the other blocks survive. `preparePlanWeeks` repairs phase, sport, type, day, duration, and template to values Postgres accepts. The fixer chain in `buildScheduledPlan` then runs (bricks, rest days, duration caps, intensity spread, volume, and the rest). `preparePlanWeeks` runs again with `preserveDays` so a fixer-chosen day is kept and a stray label cannot fail the insert. Each session is inserted with `materialize(template)`. A template that will not materialize is saved with `structure` null. A session insert error fails the plan. Success sets `status = active` and clears `error_message`.
5. **Follow the plan.** Home is the selected day in the current week: planned, completed, missed, rest, race, or an unscheduled Strava activity. Calendar pages one week and can reorder sessions. Strava sync runs on launch, return to foreground, pull-to-refresh, and tapping the active tab again. `SessionMatcher` pairs a non-manual activity to a session with the same sport and the same local calendar day, picking the closest duration. Each activity is used once. A past session with no match is missed. Today and future days stay planned. After sync, `PlanService.generatePendingFeedback` calls `session-feedback` for completed sessions that have no feedback yet.
6. **Delete account** is on Profile and calls `delete-account`.

`AthletePlanInput` is `race_objective`, `race_date`, `experience_years`, `current_weekly_hours`, `ftp`, `vma`, `css_seconds_per100m`, `limiters`, `swim_days`, `bike_days`, `run_days`, and the seven duration columns. `time_objective_minutes`, `max_hr`, and `birth_year` are stored and used on screen (max HR turns heart-rate targets into bpm). They are not generation inputs. Prompt `weekly_hours` is the sum of the duration columns divided by 60, rounded to one decimal. `current_weekly_hours` is a separate prompt variable and the baseline for `fixVolumeRamp`. Experience becomes `beginner` (null or ≤ 1 year), `intermediate` (≤ 4), or `experienced`. Olympic and Ironman 70.3 expand to the 1.5/40/10 km and 1.9/90/21.1 km descriptions. Any other stored distance is passed through as text.

The plan starts tomorrow, as a UTC date, so today is never scheduled. `total_weeks` is `ceil(days / 7)` from that date through the race's UTC date, and it must be at least 1. A race dated today or on the start date is rejected. A race on the day after the start date is one week and is accepted. The 400 text says "at least a week away", which is stricter than the check.

## Conventions

- No view-model types. Services are `@MainActor final class` `ObservableObject`s with `@Published` state. The owner view uses `@StateObject`. Children take `@ObservedObject`. There is no `@EnvironmentObject`. `SupabaseClientProvider` is the only singleton.
- Database columns are snake_case. Swift properties are camelCase. `SupabaseClientProvider` sets `.convertToSnakeCase` and `.convertFromSnakeCase` on the shared PostgREST encoder and decoder. Do not add `CodingKeys` only to rename snake_case. `cssSecondsPer100m` encodes as `css_seconds_per100m` on purpose (migration 008). `User` declares keys so an unknown race distance can decode as nil. Those raw values are still camelCase.
- Files are PascalCase and match the type. Views are `{Feature}View.swift`. Enum raw values match the database strings (`"Olympic"`, `"Monday"`, `"Easy"`).
- `async`/`await`. Pass UUIDs to PostgREST as `.uuidString`. Call functions with `client.functions.invoke`.
- Services set `errorMessage` to a short string and throw. Views show that string. Domain failures use a `LocalizedError` enum such as `PlanGenerationError`.
- Keep a change local. Do not add a protocol or a new layer for one caller.
- Author prompts in `ai/prompts/*.txt`. `scripts/sync-prompts.sh` regenerates the TypeScript modules under `supabase/functions/*/prompts/`. The next sync overwrites a hand edit to those modules.
- Migrations are SQL files with an UP section and a commented DOWN. Existing names are `001`–`018` plus dated files such as `20260715_allow_failed_plan_status.sql`. Apply a new file to the hosted database. Do not edit a migration that has already been applied. This repo has no `supabase/config.toml` and no checked-in local stack.
- User-visible changes go in `CHANGELOG.md` under `[Unreleased]`.

## Build, run, deploy

Copy `Dromos/Dromos/Core/Secrets.example` to `Secrets.swift` (gitignored). Fill `supabaseURL`, `supabaseAnonKey`, and `stravaClientId`. Open the Xcode project and run scheme `Dromos`. A compile used in past reviews, from the `Dromos/` directory:

```
xcodebuild -scheme Dromos -configuration Debug -destination 'generic/platform=iOS Simulator'
```

There is no Fastlane config and no GitHub Actions workflow. A release is an Xcode archive. Put notes in `CHANGELOG.md`. `.claude/commands/document.md` describes moving `[Unreleased]` into a version section and tagging `vX.Y.Z`.

Put the legacy JWT anon key in `Secrets.swift`. A publishable `sb_publishable_` key made the Supabase gateway return 401 (DRO-195). Functions check the bearer token with `auth.getUser()` and are deployed with `--no-verify-jwt`.

From the repo root:

```
./scripts/deploy-functions.sh                 # every function except delete-account
./scripts/deploy-functions.sh generate-plan   # one function
supabase functions deploy delete-account --no-verify-jwt --project-ref cumbrfnguykvxhvdelru
```

`generate-plan` still needs `OPENAI_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` in the function environment. PR #140 added no new name.

After a library edit, upload it. Generation fetches Storage, not the git file:

```
./scripts/upload-static-assets.sh
```

That copies `ai/context/workout-library.json` to the public object `static-assets/workout-library.json`. The app reads the symlink `Dromos/Dromos/Resources/workout-library.json`.

Environment variable names only. Never commit values.

| Where | Names |
| --- | --- |
| Every edge function (set by Supabase) | `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` |
| OpenAI functions (`generate-plan`, `chat-adjust`, `session-feedback`, `onboarding-coach`) | `OPENAI_API_KEY` |
| Strava functions | `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET` |
| Local evals and scripts (`.env`, see `.env.example`) | `OPENAI_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`. `SUPABASE_SECRET_KEY` is accepted as an alias of the service-role key. `ANTHROPIC_API_KEY` is optional and only referenced by a commented promptfoo provider. |

Deno, from the repo root:

```
deno check supabase/functions/generate-plan/index.ts
deno test supabase/functions/generate-plan/__tests__/plan-generation.test.ts
deno test supabase/functions/onboarding-coach/__tests__/parse.test.ts
deno check supabase/functions/onboarding-coach/index.ts
deno test supabase/functions/generate-plan/__tests__/insert-payload.test.ts
deno test supabase/functions/_shared/__tests__/materialize-structure.test.ts
deno test scripts/__tests__/backfill-session-structure.test.ts
```

`Dromos/DromosTests/` is not a target in the Xcode project, so `xcodebuild test` has nothing to run. `ai/eval/run-eval.sh` calls the deployed `generate-plan` and spends OpenAI quota. Do not run it unless that cost is intended. It is separate from the promptfoo configs, which exercise prompts without the deployed function.

## Gotchas

- **Bad input fails before any delete. Model noise does not fail the plan** (PR #140). `assertGeneratable` returns 400, and leaves the current plan in place, when race distance or race date is missing or every duration is null. The same is true when the race is on or before the plan start date. A second tap while `status` is still `generating` and `created_at` is under 8 minutes reuses that row (`shouldRestartPlan` returns `attach`). A failed, active, or stale row is deleted and replaced. Two creates that hit the unique `user_id` constraint share the winning row. If the isolate dies mid-run, `beforeunload` sets `failed` and a short `error_message`. The app shows that string. The chat onboarding will not save a race the generator rejects. The old form used to accept today on the local calendar. The check matches `computePlanHorizon`: the plan starts tomorrow UTC, and the race must fall on a later UTC date, which counts as one week. The coach still says "at least a week" because that is the generator's own error string.
- **Parsing and retries.** `fillTemplate` replaces every `{{placeholder}}`, including repeats. A single `String.replace` used to leave later copies of `{{total_weeks}}` and `{{weekly_hours}}` literal. `parseModelJson` accepts fenced JSON. Calls retry rate limits, 5xx, timeouts, and empty or invalid JSON, and they raise the token budget when a reply is cut off (`gpt-4o-mini` caps at 16,384, `gpt-4.1` at 32,768). Step 3 blocks run in parallel, so the prompt's `previously_used` value is the literal `None — blocks are processed in parallel.`
- **Do not mark a half-written plan active.** A failed `plan_sessions` insert throws. An unknown `template_id` is a warning and a null `structure`, not a failed plan.
- **A 0-minute day is rest.** `toAthletePlanInput` turns `0` into null so the model is not told the athlete can train for zero minutes. The column check would reject `0` anyway.
- **One plan per user.** Replacing a plan deletes its weeks and sessions. `plan_snapshots` is written by `import-plan`, not by `generate-plan`.
- **Completion is recomputed.** Moving a missed session onto a future day makes it planned again, because status is not a column. Manual Strava entries are not matched onto planned sessions. They show up as unscheduled activities.
- **The Coach tab is an email gate, not a `#if DEBUG` gate.** `CHANGELOG.md` still mentions a compile-out from DRO-184. Current `MainTabView` and `chat-adjust` both allow only `ebreard4@gmail.com`. `import-plan` uses the same address.
- **`delete-account` is easy to skip.** `scripts/deploy-functions.sh` does not deploy it.
- **The cursor rule says iOS 17+.** The Xcode deployment target is 18.0.
- **`.claude/context/schema.md`, `architecture.md`, and `ai-pipeline.md` are older notes.** They still describe a status check without `failed`, a required step 2, and a 4,096-token step 3. Use this file.
