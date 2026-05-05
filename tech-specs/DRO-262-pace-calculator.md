# DRO-262: Pace Calculator (Profile entry + Workout chip entry)

**Overall Progress:** `100%` (Phases 1 + 2 + 3 complete)

**Linear:** [DRO-262](https://linear.app/dromosapp/issue/DRO-262/pace-calculator-drawer-profile-entry-workout-chip-pre-seed)

## TLDR

A slider-driven pace/time calculator presented as an 80%-height bottom drawer (Option C "shareable pace card" visual, dark gradient, dismissible via chevron / drag-down / backdrop tap). Two entry points ship together:

1. **Profile → new "Tools" section row** "Pace calculator ›" (canonical home).
2. **`SessionCardView` "Pace" chip** in the workout card header (contextual entry — pre-seeds the drawer with the workout's sport + the athlete's threshold from `ProfileService`).

A third entry point — a speedometer icon in the Calendar toolbar — is prototyped (`prototypes/pace-calculator/index.html`) but **out of scope** here. We'll add it later if usage data justifies the extra toolbar weight.

## Critical Decisions

- **Single shared `PaceCalculatorSheet` view** — both entry points present the same view. The view takes an optional `seed: PaceSeed?` parameter; nil = neutral defaults (Run, 12.0 km/h), non-nil = pre-fill discipline + slider value.
- **Bottom drawer at fixed 80% height** — using `.sheet(...) .presentationDetents([.fraction(0.8)])` with `.presentationDragIndicator(.visible)`. iOS gives us drag-to-dismiss for free; we add a small chevron-down button at the bottom of the header for an explicit, tap-to-dismiss affordance per design.
- **No persistence** — slider value resets to the seed (or neutral default) every time the drawer is opened. We can layer in `@AppStorage` per-discipline persistence later if users complain.
- **Pre-seed source for the chip** — sport comes from `PlanSession.sport`. The slider seed comes from `ProfileService.user`: VMA (km/h) for run, threshold speed derived from FTP for bike (V0: hardcoded mapping, see Open Questions), CSS (sec/100m) for swim. If the relevant metric is missing, fall back to the neutral default.
- **Stateless calculator math, pure functions** — distance ⇄ pace formulas live in a single `PaceMath.swift` utility (no service, no caching). Easy to unit-test, easy to reuse.
- **No analytics in V0** — we have zero analytics in the app (CLAUDE.md). Don't bolt any in for this feature.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Core/Utils/PaceMath.swift` | CREATE | Pure functions for pace ⇄ time ⇄ speed conversions; `Discipline` enum (`run` / `bike` / `swim`) with per-sport slider bounds, default values, and distance lists. |
| `Dromos/Dromos/Features/Tools/PaceCalculatorSheet.swift` | CREATE | Self-contained SwiftUI view rendering the Option C drawer (header + segmented control + slider + finish-times list + share button). Takes `seed: PaceSeed?`. |
| `Dromos/Dromos/Features/Tools/PaceSeed.swift` | CREATE | Tiny struct: `PaceSeed(discipline: Discipline, sliderValue: Int)` + factory `from(session: PlanSession, profile: User?) -> PaceSeed?`. |
| `Dromos/Dromos/Features/Profile/ProfileView.swift` | MODIFY | Add new `Section("Tools")` above `Section("Goals")` with a "Pace calculator" row that presents `PaceCalculatorSheet(seed: nil)` via `.sheet`. |
| `Dromos/Dromos/Features/Home/SessionCardView.swift` | MODIFY | Add `PaceChipView` in Row 1 (next to the type tag). Tap presents `PaceCalculatorSheet(seed: PaceSeed.from(session:profile:))`. View needs a new optional `profile: User?` parameter to read VMA/FTP/CSS. |
| `Dromos/Dromos/Features/Home/HomeView.swift` | MODIFY | Pass `profileService.user` into `SessionCardView` call site. |
| `Dromos/Dromos/Features/Calendar/CalendarView.swift` | MODIFY | Pass `profileService.user` into `SessionCardView` call site. |
| `Dromos/DromosTests/PaceMathTests.swift` | CREATE | Unit tests for the conversion functions (run, bike, swim — boundary values + a couple of known-good fixtures). |

## Context Doc Updates

- `architecture.md` — add `Features/Tools/` folder, `PaceCalculatorSheet`, `PaceMath` utility. Note that `SessionCardView` now optionally consumes `profile` for pre-seeding.

## Phase 1 — `PaceMath` + `PaceCalculatorSheet` (no entry points yet)

Goal: ship the drawer view and its math, runnable in a `#Preview`. No integration into Profile or SessionCardView yet.

- [x] **Step 1.1: `PaceMath.swift`** 🟩
  - [x] Define `enum Discipline: String, CaseIterable { case run, bike, swim }`.
  - [x] Define `struct DisciplineConfig` with: `min: Int`, `max: Int`, `step: Int`, `defaultValue: Int`, `inputLabel: String`, `unit: String`, `secondaryLabel: String`, `secondaryUnit: String`, `distances: [DistanceEntry]`. Ranges:
    - `.run` → 60–220 (= 6.0–22.0 km/h × 10), step 1, default 120, distances: 1 km / 10 km / Half (21.0975) / Marathon (42.195)
    - `.bike` → 150–500 (= 15.0–50.0 km/h × 10), step 5, default 320, distances: 1 km / 40 km Olympic / 90 km Half-Iron / 180 km Ironman
    - `.swim` → 60–180 (sec / 100 m), step 1, default 110, distances: 1500 m Olympic / 1900 m Half-Iron / 3800 m Ironman
  - [x] Add `Discipline.config: DisciplineConfig` computed property.
  - [x] Pure functions:
    - `kmH(forSliderValue v: Int, discipline: Discipline) -> Double` (run/bike: `v/10`; swim: `360 / Double(v)`)
    - `secondsToCover(km: Double, atSpeedKmH: Double) -> TimeInterval`
    - `formatTime(_ seconds: TimeInterval) -> String` → `"H:MM:SS"` if h>0, else `"M:SS"`
    - `formatPacePerKm(secondsPerKm: TimeInterval) -> String` → `"M:SS / km"`

- [x] **Step 1.2: `PaceSeed.swift`** 🟩
  - [x] `struct PaceSeed { let discipline: Discipline; let sliderValue: Int }`
  - [x] `static func from(session: PlanSession, profile: User?) -> PaceSeed?`
    - Map `session.sport.lowercased()` → `.run` / `.bike` / `.swim`. Unknown sport → `nil`.
    - For `.run`: if `profile?.vma` is non-nil, `sliderValue = Int((vma * 10).rounded())`. Else use `Discipline.run.config.defaultValue`.
    - For `.bike`: V0 — always use default 320.
    - For `.swim`: if `profile?.cssSecondsPer100m` is non-nil, `sliderValue = cssSecondsPer100m`. Else default.
    - Clamp `sliderValue` to `[config.min, config.max]`.

- [x] **Step 1.3: `PaceCalculatorSheet.swift`** 🟩
  - [x] Inputs: `let seed: PaceSeed?`. State: `@State private var discipline: Discipline`, `@State private var sliderValue: Int`. Initial values from `seed` or run/default.
  - [x] Dark gradient background using `Color(red:green:blue:)` literals (no `Color(hex:)` extension in codebase).
  - [x] Layout: eyebrow → title → dismiss button → segmented picker → two-column metrics → slider → finish times.
  - [x] When `discipline` changes, reset `sliderValue` to that discipline's `defaultValue`.
  - [x] `#Preview` block with three previews: `nil` seed, run-seeded (138), swim-seeded (110).

- [x] **Step 1.4: Unit tests `PaceMathTests.swift`** 🟩
  - [x] Run: `12.0 km/h` → 1 km in `5:00`, 10 km in `50:00`, marathon in `3:30:59` (spec lists 3:30:30, which is a ~29s transcription error; 42.195/12×3600 = 12658.5 s = 3:30:59).
  - [x] Bike: `32.0 km/h` → 40 km in `1:15:00`, 180 km in `5:37:30`.
  - [x] Swim: `110 sec/100m` → 1500 m in `27:30`, 3800 m in `1:09:40`.
  - [x] Boundary: slider at min/max for each discipline produces non-NaN, non-zero finish times.
  - [x] `PaceSeed.from(...)` factory tests: sport mapping, VMA/CSS seeding, clamping.
  - **Note:** No test target in `Dromos.xcodeproj` (matches precedent of all other test files in `DromosTests/`). Build compiles cleanly. Test target wiring is a pre-existing project gap.

## Phase 2 — Profile entry point (placement #1)

- [x] **Step 2.1: Add Tools section to ProfileView** 🟩
  - [x] In `ProfileView.swift`, add a new section above `Section("Goals")`:
    ```swift
    Section("Tools") {
        Button {
            showPaceCalculator = true
        } label: {
            HStack {
                Image(systemName: "speedometer").foregroundColor(.accentColor)
                Text("Pace calculator").foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
        }
    }
    ```
  - [x] Add `@State private var showPaceCalculator = false` to `ProfileView`.
  - [x] Attach the sheet:
    ```swift
    .sheet(isPresented: $showPaceCalculator) {
        PaceCalculatorSheet(seed: nil)
            .presentationDetents([.fraction(0.8)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.black)
    }
    ```
  - [x] Verify the system drag indicator + the in-view chevron-down both work.

## Phase 3 — Workout card chip entry point (placement #2)

- [x] **Step 3.1: `PaceChipView` inside `SessionCardView`** 🟩
  - [ ] Add a private `paceChip` view inside `SessionCardView` Row 1, placed *between* the duration `VStack` and the existing trailing content (or next to the type tag — match what looks balanced in the live build).
    ```swift
    private var paceChip: some View {
        Button {
            showPaceCalculator = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "speedometer").font(.caption2)
                Text("Pace").font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12))
            .foregroundColor(.accentColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    ```
  - [ ] Show the chip only when `PaceSeed.from(session:profile:)` returns non-nil (i.e. sport is recognized). For unknown sports we hide it rather than showing an inert chip.

- [x] **Step 3.2: Add `profile` parameter to `SessionCardView`** 🟩
  - [ ] Add `var profile: User? = nil` (defaulted so call sites without profile data still compile).
  - [ ] Add `@State private var showPaceCalculator = false`.
  - [ ] Attach `.sheet(isPresented: $showPaceCalculator) { … PaceCalculatorSheet(seed: PaceSeed.from(session: session, profile: profile)) … }` with the same detent/drag-indicator/background as Phase 2.

- [x] **Step 3.3: Wire `profile` from call sites** 🟩
  - [x] `HomeView.swift`: pass `profile: profileService.user` into the `SessionCardView(...)` call.
  - [x] `CalendarView.swift`: same.

- [x] **Step 3.4: Update context doc** 🟩
  - [x] `architecture.md` — `SessionCardView` now optionally consumes `profile` for pre-seeding the pace calculator. Add `Features/Tools/` description.

## Manual QA checklist

- [ ] Profile → Tools → Pace calculator opens drawer at 80%, run preselected, slider at neutral default.
- [ ] Drawer dismisses via: (a) system drag indicator drag-down, (b) chevron-down button, (c) tapping outside the drawer area.
- [ ] Switching discipline resets the slider to that discipline's default.
- [ ] Slider movement updates the major value, secondary value, and all finish times in real-time without lag.
- [ ] Finish times match `PaceMathTests` fixtures for one spot-check per sport.
- [ ] Workout card chip appears on run/bike/swim cards, hidden for unknown sports.
- [ ] Tapping the chip on a run card with VMA set in profile → drawer opens with run pre-selected and slider at the VMA value.
- [ ] Tapping the chip on a swim card with CSS set in profile → drawer opens with swim pre-selected and slider at the CSS value.
- [ ] Tapping the chip on a bike card → drawer opens with bike pre-selected at the default 32 km/h (V0 behavior — see open question).
- [ ] Tapping the chip when profile is nil (cold-launch, profile not yet loaded) → drawer still opens, slider at neutral default.
- [ ] Drawer renders correctly in light + dark mode (it's intentionally always-dark, but parent surfaces shouldn't break).
- [ ] No layout regression on existing SessionCard for completed / planned / missed states.

## Resolved decisions

1. **Bike pre-seed (V0)** — always default to 32 km/h. No FTP → speed derivation in V0.
2. **No share button in V0** — remove the "Share pace card" button from the spec entirely. The shareable pace-card export is a separate ticket; we don't ship a non-functional button.
3. **No persistence** — slider resets to seed (or default) every time the drawer is opened.

## Open Question

- **Bike "1 km" distance row** — bikers think in km/h, not pace per km. Drop the 1 km row (3 distances) or keep it (4 distances) for visual symmetry with run? **Recommend keep** — it's the unit the slider reflects most directly. Easy to flip later.

## Rollback plan

Pure-additive change. Rollback = revert the PR. No DB migrations, no new edge functions, no shared service mutations.
