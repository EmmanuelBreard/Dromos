# Changelog

All notable changes to Dromos iOS app.

Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Initial app scaffolding with SwiftUI and Supabase
- Email/password authentication (sign up, sign in, sign out)
- Tab navigation shell (Profile, Calendar, Home)
- Basic profile view with edit mode and validation
- RLS policies for user data access
- Environment-based configuration (Secrets.swift)
- **3-screen onboarding flow** collecting user profile data
  - Screen 1: Basic info (sex, birth date, weight)
  - Screen 2: Race goals (triathlon type, race date, time target)
  - Screen 3: Performance metrics (VMA, CSS, FTP, experience)
- Form validation with user-friendly error messages
- Book-like page transitions (directional swipe animations)
- Sign out button in onboarding (escape hatch for incomplete flow)
- Fallback mechanism when profile save succeeds but status check fails

### Fixed
- Transition directions now slide naturally (forward→right to left, back→left to right)
- Users no longer stuck on onboarding after successful save
- Race objective picker now defaults to Sprint correctly
- Invalid text input no longer clears previously valid data
- Profile view safety: removed force unwraps, added comprehensive validation

### Changed
- Database: `birth_date` and `race_date` converted from DATE to TIMESTAMPTZ for ISO-8601 compatibility
- Navigation: RootView now handles 3-way routing (auth → onboarding → main)

### Database Migrations
- `002_add_onboarding_fields.sql`: Add user profile fields (sex, birth_date, weight_kg, race_objective, race_date, time_objective_hours/minutes, vma, css_minutes/seconds, ftp, experience_years, onboarding_completed)
- `003_convert_date_to_timestamptz.sql`: Convert DATE columns to TIMESTAMPTZ

---

**Note:** No releases have been tagged yet. All changes above are in `main` branch but not deployed.
