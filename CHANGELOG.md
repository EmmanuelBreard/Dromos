# Changelog

All notable changes to Dromos iOS app.

Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Changed
- **Single-week paged view moved from Home to Calendar tab** — The paged single-week view introduced in DRO-225 now lives on the Calendar tab. The previous Calendar implementation (week-by-week list with inline-expandable session rows) has been removed. The Home tab is now a placeholder ("Coming soon") reserved for an upcoming dashboard. Re-tapping the Calendar tab snaps back to the current week and refreshes Strava completion data. (DRO-230)
- **Home is now a focused, one-week view** — The (now Calendar) tab shows a single week at a time (current week by default). Navigate with chevron taps or left/right swipes. The header shows where you are in the plan ("Current Week", "Last Week", "Next Week", or "Week N / Total") plus phase + date range. Previously: a long scrolling list with a "Show next week" button and no way to look back. (DRO-225)

### Added
- **Workout sessions show concrete targets, not raw percentages** — Step lists and intensity graphs now display actionable values like `260–275 W`, `4:15–4:20/km`, `140–160 bpm`, or `RPE 6 — moderate` instead of `95% FTP` or `medium pace`. Targets remain abstract in storage so they auto-rescale when you re-test FTP / VMA / CSS. Sessions can render with HR-based, RPE-based, power-based, or pace-based prescriptions — not just the legacy bike/run percentage tags. Foundation for upcoming agent-driven session adjustments (DRO-213, DRO-215 through DRO-222).
- **Max HR and birth year** — Onboarding now collects max heart rate (with an "I don't know it" option that estimates from age via 220 − age) and birth year. Existing users can set these from Profile → Metrics. Used to render HR-zone targets as bpm ranges in the new session display (DRO-220).

### Changed
- **Workout library cleanup** — Renamed the run intensity field from `mas_pct` to `vma_pct` throughout the library and plan generator for consistency with how athletes know the metric. Behavior unchanged (DRO-215).

### Removed
- **Strength sessions removed** — Strength templates and existing strength rows have been removed from training plans. A future ticket will reintroduce strength training with proper rep-based structure. Existing plans lose their strength sessions only — all other sport sessions are unaffected (DRO-215, DRO-222).
- **Chat tab hidden** — Chat feature is disabled in production builds. Code is preserved for development; the tab and all related UI are excluded from release binaries via `#if DEBUG` (DRO-184)

### Database Migrations
- `20260425_session_structure_and_max_hr.sql` — additive: adds `plan_sessions.structure JSONB` (single source of truth for session step structure), `users.max_hr` (100–220 bpm), `users.birth_year` (1920–2030), and a top-level shape CHECK on `structure` (DRO-215)
- `20260426_remove_strength_sessions.sql` — destructive: deletes legacy strength rows from `plan_sessions` (DRO-222)

### Added
- **Planned workout compliance in coaching feedback** — Session feedback now includes the planned workout structure (intervals, intensities, warmup/cooldown) so the AI can flag incomplete sets, intensity deviations, and missing segments. Intensities shown as absolute values (watts, km/h) using athlete profile (DRO-169)
- **Lap-level coaching feedback** — Session feedback now analyzes per-lap/split data (pace, HR, power) instead of just activity averages. The AI can comment on pacing consistency, interval fade, and split execution. Strava streams (second-by-second data) also stored for future use (DRO-164)
- **AI session feedback** — Completed sessions now show auto-generated coaching feedback comparing planned vs actual execution. Feedback is phase-aware (Base/Build/Peak/Taper context), includes recovery nutrition tips, and uses GPT-4.1 for quality. Displayed as a collapsed 2-line preview with "Show more" on completed session cards. Triggers automatically after Strava sync (DRO-158)
- **Chat V0** — New Chat tab (4th, between Calendar and Profile) with AI coaching conversation agent powered by gpt-4o. Edge function (`chat-adjust`) validates JWT, fetches conversation history (last 50 messages), user profile, and active plan phase map, then returns structured coaching advice. V0 advisory mode — gathers training constraints (injury, illness, fatigue, equipment) and answers general coaching questions, but does not modify the plan. iOS UI with chat bubbles, typing indicator, optimistic send, keyboard dismiss, and clear history in Profile settings. Messages stored in `chat_messages` table (DRO-149)
- **Session completion status** — Past sessions on the Home tab now show a green left border when completed (matched to a Strava activity) or a red border with dimming when missed. Completed cards display actual performance metrics (duration, distance, power/pace/HR) and GPS route map as primary content. Planned workout details available behind a "Planned workout" collapsible disclosure. Future sessions remain unchanged. Completed sessions cannot be moved in edit mode. Status is computed client-side by matching plan sessions against synced Strava activities (same sport, same day, closest duration) (DRO-145, DRO-150)

### Fixed
- **Plan generation 401** — `generate-plan` edge function now validates the JWT via `auth.getUser()` internally (same as `strava-sync`) and is deployed with `verify_jwt: false`. Previously it relied solely on the Supabase gateway's JWT check, which was incompatible with the iOS SDK's `sb_publishable_` key format. Also switched `Secrets.swift` to the legacy JWT anon key for SDK compatibility, and improved the 401 error message to "Your session has expired. Please sign in again." (DRO-195)

### Changed
- **Workout graph tooltip is now press-and-hold** — Touching a segment bar shows its details (duration, speed/pace/watts) in a floating tooltip above the bar. The tooltip disappears when you lift your finger. Previously, tapping toggled a persistent label below the graph (DRO-193)

### Fixed
- **App launch flash** — Opening the app while already logged in no longer flashes through the login, onboarding, and home screens before landing. A brief splash screen (logo + spinner) is shown while auth state resolves, then the app navigates directly to the correct screen (DRO-178)
- **Strava OAuth** — Use web authorize endpoint (`/oauth/authorize`) instead of mobile endpoint which broke callback interception when native Strava app was installed (DRO-145)
- **Current week detection** — Fixed off-by-one in `currentWeekIndex()` where the last day of a training week could fall through to the next week (DRO-145)
- **Strava integration** — Connect your Strava account to import activities. OAuth connection in Profile, auto-sync on app open, 90-day lookback on first sync. Activities synced with sport normalization (swim/bike/run) (DRO-139)
- **Expandable sessions in Calendar Plan** — Tap any session in the Calendar tab to expand workout steps and intensity graph inline. Tap again to collapse. All sessions reset to collapsed when switching tabs (DRO-122)

### Changed
- **Swim distance in session header** — Planned swim sessions now show estimated distance inline with duration (e.g., "45 min · 1.8 km") instead of a separate line. Works for all swim workout types including intervals (DRO-157)
- **Redesigned login and sign-up screens** — New mobile-friendly auth UI with large typography, icon-prefixed input fields, custom full-width buttons, and brand-colored accent links. Content vertically centered (DRO-126)
- **Lighter onboarding** — Removed the demographics screen (sex, age, weight) from onboarding, reducing the flow from 7 screens to 6. Race Goals is now the first screen (DRO-125)

### Removed
- Sex, age, and weight fields removed from onboarding, profile edit, and database (DRO-125)

### Database Migrations
- `015_strava_laps_and_streams.sql` — Creates `strava_activity_laps` table for per-lap activity data, adds `streams_data` JSONB column to `strava_activities` for raw time-series data (DRO-164)
- `014_session_feedback.sql` — Adds `feedback TEXT` and `matched_activity_id UUID` columns to `plan_sessions` for AI-generated coaching feedback (DRO-158)
- `013_create_chat_messages.sql` — Creates `chat_messages` table for AI coaching conversation history with RLS (user SELECT + DELETE, service_role INSERT) (DRO-149)
- `20260222_add_summary_polyline.sql` — Adds `summary_polyline TEXT` column to `strava_activities` for GPS route data from Strava (DRO-145)
- `010_drop_demographic_columns.sql` — Drops `sex`, `birth_date`, `weight_kg` columns and `check_weight_kg` constraint from `public.users` (DRO-125)
- **Plan generation loading screen** — Replaced rotating text phrases with a 3-step progress bar showing pipeline stages (Periodizing → Structuring → Selecting), capped at 90% until the real response arrives (DRO-110)
- **Onboarding inputs replaced with wheel Pickers** — All numeric TextFields across onboarding screens 1-3 replaced with native iOS wheel pickers, eliminating the keyboard entirely. All metrics mandatory with sensible defaults (DRO-103)
  - Weight: wheel picker (30-150 kg, default 70)
  - Race time objective: dual hour/minute pickers (default 2h 0min)
  - VMA, CSS, FTP, experience: always-visible pickers with hint text above each
  - All screens use consistent ScrollView layout with non-sticky navigation buttons

### Fixed
- **Onboarding transition direction** — Back/Next screen transitions now always slide in the correct direction (DRO-103)
- **Graph final time label** — Time axis now displays exact session duration (e.g., 45', 1h30) with hour formatting and overlap prevention (DRO-100)
- **Easy intensity differentiation** — Easy sessions now show different intensity based on duration for run and bike (DRO-102)
- **Simplified day headers** — Day headers now show "Today" / "Tomorrow" instead of full date (DRO-107)

## [1.0.0] - 2026-02-15

### Changed
- **15-fixer post-processing chain** — Complete overhaul of training plan quality enforcement. 7 rounds of eval iteration achieved 0 violations across all 8 metrics on 5 consecutive batch runs (DRO-85)
- **Same-day sport rules** — Max 1 bike + 1 run per day (brick counts). No dual hard (Tempo/Intervals) bike/run sessions on same day. Swim exempt (DRO-85)
- **Improved intensity spread** — `fixIntensitySpread` now tries both days of a consecutive hard pair, uses post-swap adjacency simulation, and checks same-sport conflicts on swap targets. Swim excluded from hard-day tracking (DRO-85)
- **Density-aware intensity checker** — Consecutive different-sport hard days accepted for high-volume athletes when `available_days / hard_sessions < 2` (DRO-85)
- **Brick sessions guaranteed and isolated** — Bike-to-run transition sessions guaranteed (Base biweekly, Build/Peak weekly). Brick day cleared to 2 sessions: bike + RUN_Easy_01 (30min). `fixBrickRunDuration` catches informal bricks. `fixBrickOrder` enforces bike-before-run in sessions array (DRO-85)
- **Sport clustering skip for high-volume** — `fixSportClustering` disabled for athletes with ≥8h/week (consecutive same-sport expected with 3 sports over 7 days) (DRO-85)
- **Volume gap filler** — Empty available days in non-Recovery/Taper weeks filled with Easy sessions based on macro plan sport targets and neighbor alternation (DRO-85)
- **Removed fixLongRun** — Long run placement now handled by improved prompt rules + volume gap filler (DRO-85)
- **Step 3 prompt rules 9-11** — Added explicit LLM rules for same-sport doubling, dual hard sessions, and brick ordering (DRO-85)

### Added
- **Batch eval pipeline** — `ai/eval/batch-eval.sh` runs N parallel eval runs, produces per-run plans + violation reports, aggregates scores. Used for iterating on fixer quality (DRO-85)
- **8-metric violation checker** — `check-step3-violations.js` validates duration caps, sport eligibility, rest days, missing bricks, sport clustering, same-day conflicts, intensity clustering, and brick order (DRO-85)
- **Rich session card data foundation** — Workout segment flattening and step summary generation with sport-specific formatting (DRO-82)
  - ProfileService shared from MainTabView for athlete metrics (FTP, VMA, CSS)
  - FlatSegment model for graph rendering (expands nested repeats into individual segments)
  - StepSummary model for text display (bike: watts, run: speed/pace, swim: distance/label)
- **Workout steps and intensity graph** — Session cards now display step-by-step workout breakdown with intensity-colored dots and a visual bar chart (DRO-83)
  - WorkoutStepsView: compact step list with green→red intensity dots and sport-specific metrics
  - WorkoutGraphView: horizontal bar chart with proportional widths, normalized heights, and 15-min time axis
  - IntensityColorHelper: shared HSL gradient function for consistent color across dots and bars
  - Simple swims show distance only; complex workouts show full steps + graph
- **Tap-to-reveal graph popovers** — Tap any intensity bar to see sport-specific segment details (DRO-84)
  - Bike: duration + label + watts (e.g., "15 min warmup — 156 W")
  - Run: duration + label + speed/pace (e.g., "10 min tempo — 12.0 km/h (5:00/km)")
  - Swim: distance + pace label (e.g., "100m — medium pace")
  - Adaptive time axis intervals (15/30/60 min based on workout duration)
  - Smooth show/dismiss animation with tap-outside-to-close

### Changed
- **Sport emojis** — Session cards use 🏊‍♂️🚴‍♂️🏃‍♂️ emojis instead of SF Symbol icons (DRO-81)
- **Type-based badge colors** — Easy=green, Tempo=orange, Intervals=red across all sports (DRO-81)
- **Brighter intensity colors** — Graph bars and step dots use lighter, more vibrant HSB palette (DRO-81)
- **Swim graph height** — Swim bar heights now derived from pace label (easy→short, hard→tall) instead of flat minimum (DRO-81)
- **Easy session steps** — Single-segment workouts now show a step description above the graph (DRO-81)
- **Home tab background inversion** — Gray background with white session cards for better visual hierarchy (DRO-82)
- **Shared ProfileService** — Profile data now shared between Home and Profile tabs, keeping athlete metrics in sync (DRO-82)

- **Rolling weeks Home dashboard** — Home tab now shows current + next week with progressive "Show next week" CTA to reveal future weeks (DRO-74)
  - Week section headers with "Current Week" / "Next Week" labels, date ranges with ordinal suffixes, and phase badges
  - Race Day indicator card shown on the race date with trophy icon and race objective
  - Auto-scroll to today on initial load; scroll-to-top reset on tab return
- Initial app scaffolding with SwiftUI and Supabase
- Email/password authentication (sign up, sign in, sign out)
- Tab navigation shell (Profile, Calendar, Home)
- Basic profile view with edit mode and validation
- RLS policies for user data access
- Environment-based configuration (Secrets.swift)
- **7-screen onboarding flow** collecting full athlete profile
  - Screen 1: Basic info (sex, birth date, weight)
  - Screen 2: Race goals (triathlon type, race date, time target)
  - Screen 3: Performance metrics (VMA, CSS, FTP, experience, current weekly training volume)
  - Screens 4-6: Sport-specific weekly availability (swim, bike, run day selection)
  - Screen 7: Per-day training duration (30–420 min per available day)
- Form validation with user-friendly error messages
- Book-like page transitions (directional swipe animations)
- Sign out button in onboarding (escape hatch for incomplete flow)
- Fallback mechanism when profile save succeeds but status check fails
- **Plan generation system** — 3-step LLM pipeline via Supabase Edge Function
  - Step 1: GPT-4o macro plan (weekly volume/phase/session breakdown)
  - Step 2: GPT-4o-mini Markdown → JSON parsing
  - Step 3: GPT-4o workout assignment from library (constraint-aware, 4-week blocks)
- Plan generation trigger and loading UX post-onboarding
- **Calendar tab** — week-by-week plan overview with phase colors and volume tracking
- **Home tab** — detailed current week view with session cards and workout segments
- Current training volume slider on Screen 3 (required, 0–25h, 0.5h steps) — injected into Step 1 prompt so week 1 starts near athlete's baseline (DRO-65)
- Sport day availability counts passed to Step 1 prompt (weekday/weekend per sport) (DRO-59)
- Session duration caps derived from per-day availability, passed to Step 1 prompt (DRO-58)
- Constraint-aware scheduling in Step 3 (respects day availability + duration ceilings) (DRO-55)
- Workout library with swim, bike, run templates bundled as JSON in Supabase Storage
- **15 classic interval running sessions** added to workout library (DRO-69)
  - 8 Intervals (Bernard Brun, Pyramide, Billat, Super-10K, Fartlek, 1000, Colline, Zatopek)
  - 7 Tempo (Viktor Röthlin, Pierre Morath, Progressive Marathon, Endurance Kényane, 10 Miles, 3x3, Demi-10K)
  - Distance-based main sets (`distance_meters`) with time-based warmup/cooldown
  - `name` field added to new templates for future UI display
- Shared post-processing helpers: `parseConstraints()`, `sessionPriority()`, `buildTemplateDurationMap()` in eval and production (DRO-70)

### Fixed
- Improved plan generation accuracy: Step 3 workout selection now enforces ±20% duration flexibility, exempts Easy sessions from forced rotation, and includes violation examples for the AI (DRO-64)
- Transition directions now slide naturally (forward→right to left, back→left to right)
- Users no longer stuck on onboarding after successful save
- Race objective picker now defaults to Sprint correctly
- Invalid text input no longer clears previously valid data
- Profile view safety: removed force unwraps, added comprehensive validation
- 9 broken swim templates rewritten with correct distances (DRO-51)
- iOS URLSession timeout set to 180s for plan generation (DRO-57)
- `fixConsecutiveRepeats` now duration-aware — swaps to closest-duration template instead of random (DRO-71)
- `fixRestDays` now cap-aware — checks remaining day capacity and sport eligibility before placing sessions (DRO-71)
- `fixRestDays` ported to production (was missing from `index.ts`, only ran 3 of 4 fixers) (DRO-71)

### Changed
- Workout library and prompt files consolidated to single source of truth with automated sync scripts (DRO-64)
- Database: `birth_date` and `race_date` converted from DATE to TIMESTAMPTZ for ISO-8601 compatibility
- Database: `time_objective_hours` + `time_objective_minutes` consolidated into single `time_objective_minutes` INT; `css_minutes` + `css_seconds` consolidated into `css_seconds_per100m` (DRO-24)
- Navigation: RootView now handles 3-way routing (auth → onboarding → main)
- Prompt naming: `step1b` renamed to `step2`; dead workout-selection prompt removed (DRO-60)
- Workout library simplified for Step 3 + prompt reordered (DRO-62)
- Step 1 prompt cleaned up: constraints and rest_days removed (now handled by Step 3) (DRO-54)

### Database Migrations
- `002_add_onboarding_fields.sql`: Add user profile fields
- `003_convert_date_to_timestamptz.sql`: Convert DATE columns to TIMESTAMPTZ
- `004_add_availability_columns.sql`: Add swim_days, bike_days, run_days JSONB arrays
- `005_add_daily_duration_columns.sql`: Add mon_duration through sun_duration INT columns
- `006_create_training_plan_tables.sql`: Create training_plans, plan_weeks, plan_sessions tables
- `007_consolidate_time_fields.sql`: Merge split time fields into single integers
- `008_rename_css_column.sql`: Rename css_seconds_per_100m → css_seconds_per100m
- `009_add_current_weekly_hours.sql`: Add current_weekly_hours DECIMAL(3,1) with CHECK 0–25

