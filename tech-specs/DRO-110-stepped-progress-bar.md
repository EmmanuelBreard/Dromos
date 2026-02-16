# DRO-110: Stepped Progress Bar on Plan Generation Screen

**Overall Progress:** `100%`

## TLDR
Replace the rotating text phrases in `PlanGenerationView` with a 3-step progress bar that gives users visual forward motion during the ~50-65s plan generation wait. Client-side timer only — no backend changes.

## Critical Decisions
- **Client-side timer, not real pipeline status** — The bar is driven by a local timer (0→20→40→65s), not SSE/polling from the edge function. Simpler, no backend work, good enough for a screen seen once.
- **Cap at 90% until real response** — Prevents the bar from completing before the API call returns. If generation exceeds 65s, label switches to "Finalizing..." and bar holds at ~90%.
- **Remove rotating phrases** — The stepped labels replace them entirely. No need for both.

## Files to Touch
| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Plan/PlanGenerationView.swift` | MODIFY | Replace `generatingView`, replace Timer logic, add progress bar + step labels |

## Context Doc Updates
None — no new files, no schema changes, no pipeline changes.

## Tasks

- [x] 🟩 **Step 1: Replace state and timer logic**
  - [x] 🟩 Remove `currentProgressPhraseIndex`, `progressPhraseTimer`, `progressPhrases` array
  - [x] 🟩 Add new state: `@State private var generationStartTime: Date?` and `@State private var elapsedSeconds: Double = 0`
  - [x] 🟩 Add `@State private var generationCompleted = false` to track when the API response has arrived (so bar can snap to 100%)
  - [x] 🟩 Replace `Timer.scheduledTimer` with a `TimelineView(.periodic(from:by:))` or a `Timer.publish(every: 0.5)` that updates `elapsedSeconds` from `generationStartTime`
  - [x] 🟩 Remove `startProgressPhraseRotation()` / `stopProgressPhraseRotation()` methods; replace with start/stop logic for the new timer

- [x] 🟩 **Step 2: Add progress bar and step labels**
  - [x] 🟩 Define step thresholds as a constant array: `[(threshold: 0, label: "Periodizing your plan", step: 1), (threshold: 20, label: "Structuring your weeks", step: 2), (threshold: 40, label: "Selecting your workouts", step: 3)]`
  - [x] 🟩 Compute `currentStep` and `currentLabel` from `elapsedSeconds` against thresholds
  - [x] 🟩 Compute `progress: Double` (0.0–1.0): linearly interpolate within each step range (0-20s → 0.0-0.33, 20-40s → 0.33-0.66, 40-65s → 0.66-0.90). Cap at 0.90 until `generationCompleted` is true, then snap to 1.0
  - [x] 🟩 If `elapsedSeconds > 65 && !generationCompleted`, override label to `"Finalizing..."`
  - [x] 🟩 Replace the `generatingView` body: keep `ProgressView()` spinner (or replace with the bar — designer's call), add a `ProgressView(value: progress)` bar styled with `.tint(.blue)` and rounded track, add `Text("Step \(currentStep) of 3 — \(currentLabel)")` below the bar
  - [x] 🟩 Remove the old `"This may take a few minutes..."` text — the step labels replace it

- [x] 🟩 **Step 3: Wire completion signal**
  - [x] 🟩 In `generatePlan()`, set `generationCompleted = true` immediately after `planService.generatePlan()` returns (before `checkPlanStatus`)
  - [x] 🟩 Add a brief delay (~0.6s) between setting `generationCompleted = true` and triggering the `authService` transition, so the user sees the bar hit 100% before the screen changes
  - [x] 🟩 On error, stop the timer and reset state (existing error flow handles the view switch)

- [x] 🟩 **Step 4: Polish and edge cases**
  - [x] 🟩 Animate progress bar changes with `.animation(.easeInOut(duration: 0.5), value: progress)`
  - [x] 🟩 Ensure the bar looks correct in both light and dark mode (use semantic colors for track background)
  - [x] 🟩 Test on iPhone SE width (375pt) — step label text must not truncate
  - [x] 🟩 Verify the `.onDisappear` cleanup stops the new timer correctly
