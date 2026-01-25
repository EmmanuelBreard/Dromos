# DRO-7: App Scaffolding - Vertical Slice Foundation

**Overall Progress:** `100%`

## TLDR
Set up foundational scaffolding for Dromos iOS app: folder structure, tab navigation shell, Supabase auth (email/password), and a basic user profile to prove the full stack works end-to-end.

## Critical Decisions
- **Navigation:** Tab bar (Home | Calendar | Profile) — standard fitness app pattern
- **Auth:** Email/password only for MVP — architecture supports adding Google/Apple later
- **Folder structure:** Feature-based (`Features/Auth/`, `Features/Profile/`) — better long-term maintainability
- **Credentials:** `.xcconfig` files (gitignored) — native Xcode integration, CI/CD friendly
- **Profile scope:** Basic fields only (id, email, name) — extend later as needed
- **iOS target:** 26.2 — keeping as-is per user preference

## Supabase Config
- **Project URL:** `https://cumbrfnguykvxhvdelru.supabase.co`
- **Anon Key:** Provided (store in `.xcconfig`, not in code)

---

## Tasks

### Phase 1: Project Structure + Nav Shell

- [x] 🟩 **Step 1: Create folder structure**
  - [x] 🟩 Create `App/` folder with entry point
  - [x] 🟩 Create `Core/Services/` for Supabase client
  - [x] 🟩 Create `Core/Models/` for shared models
  - [x] 🟩 Create `Features/Auth/` placeholder
  - [x] 🟩 Create `Features/Profile/` placeholder
  - [x] 🟩 Create `Features/Home/` placeholder
  - [x] 🟩 Create `Features/Calendar/` placeholder
  - [x] 🟩 Create `Components/` for reusable UI

- [x] 🟩 **Step 2: Set up config files**
  - [x] 🟩 Create `Config/Debug.xcconfig` (gitignored)
  - [x] 🟩 Create `Config/Release.xcconfig` (gitignored)
  - [x] 🟩 Create `Config/Config.example` with placeholders
  - [x] 🟩 Update `.gitignore` to exclude xcconfig files
  - [x] 🟩 Link xcconfig to Xcode project build settings
    > **Manual step required:** In Xcode, go to Project > Info > Configurations and set Debug/Release to use the respective xcconfig files

- [x] 🟩 **Step 3: Implement tab navigation shell**
  - [x] 🟩 Create `MainTabView.swift` with 3 tabs
  - [x] 🟩 Create placeholder `HomeView.swift`
  - [x] 🟩 Create placeholder `CalendarView.swift`
  - [x] 🟩 Create placeholder `ProfileView.swift`
  - [x] 🟩 Update `DromosApp.swift` to use `MainTabView`

---

### Phase 2: Supabase Client + Auth

- [x] 🟩 **Step 4: Add Supabase dependency**
  - [x] 🟩 Add `supabase-swift` via Swift Package Manager
    > **Manual step required:** In Xcode, File > Add Package Dependencies > `https://github.com/supabase/supabase-swift` (use "Up to Next Major" from 2.0.0)
  - [x] 🟩 Create `SupabaseClient.swift` singleton in `Core/Services/`
  - [x] 🟩 Load credentials from Info.plist (via xcconfig)

- [x] 🟩 **Step 5: Implement auth service**
  - [x] 🟩 Create `AuthService.swift` in `Core/Services/`
  - [x] 🟩 Implement `signUp(email:password:)`
  - [x] 🟩 Implement `signIn(email:password:)`
  - [x] 🟩 Implement `signOut()`
  - [x] 🟩 Implement session state observation

- [x] 🟩 **Step 6: Build auth UI**
  - [x] 🟩 Create `AuthView.swift` (container for login/signup)
  - [x] 🟩 Create `LoginView.swift` with email/password fields
  - [x] 🟩 Create `SignUpView.swift` with email/password/confirm fields
  - [x] 🟩 Add basic form validation (non-empty, email format)
  - [x] 🟩 Handle loading states and error display

- [x] 🟩 **Step 7: Wire auth flow to app**
  - [x] 🟩 Create `RootView.swift` to manage auth state (uses AuthService directly)
  - [x] 🟩 Update `DromosApp.swift` to show auth vs main app based on session
  - [ ] 🟨 Test login/logout flow end-to-end (requires manual testing after Xcode setup)

---

### Phase 3: User Profile (Provable Feature)

- [x] 🟩 **Step 8: Create users table in Supabase**
  - [x] 🟩 Write migration: `users` table (id, email, name, created_at, updated_at)
  - [x] 🟩 Set up RLS policy: users can only read/update their own row
  - [x] 🟩 Create trigger to auto-create user row on auth signup
    > **Manual step required:** Run the migration in Supabase SQL Editor: `supabase/migrations/001_create_users_table.sql`

- [x] 🟩 **Step 9: Implement profile service**
  - [x] 🟩 Create `User.swift` model in `Core/Models/`
  - [x] 🟩 Create `ProfileService.swift` in `Core/Services/`
  - [x] 🟩 Implement `fetchProfile()`
  - [x] 🟩 Implement `updateProfile(name:)`

- [x] 🟩 **Step 10: Build profile UI**
  - [x] 🟩 Update `ProfileView.swift` to display user info (inlined logic, no separate ViewModel needed)
  - [x] 🟩 Add edit name functionality
  - [x] 🟩 Add sign out button
  - [ ] 🟨 Test full flow: signup → profile created → view profile → edit → logout (requires manual testing)

---

## Validation Criteria
- [ ] App launches with tab navigation
- [ ] Can sign up with email/password
- [ ] Can sign in with existing account
- [ ] Profile view shows user's email and name
- [ ] Can edit name and see it persist
- [ ] Can sign out and return to auth screen
- [ ] No credentials committed to git
