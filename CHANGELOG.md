# Changelog

All notable changes to Dromos iOS app.

Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
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

---

**Note:** No releases have been tagged yet. All changes above are in `main` branch but not deployed.
