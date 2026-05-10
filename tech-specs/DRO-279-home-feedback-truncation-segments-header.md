# DRO-279 — Home: truncate coach feedback to 2 lines + remove "Segments" header

**Linear:** [DRO-279](https://linear.app/dromosapp/issue/DRO-279/home-truncate-coach-feedback-to-2-lines-remove-segments-header)
**Branch:** `ebreard4/dro-279-home-truncate-coach-feedback-to-2-lines-remove-segments`

**Overall Progress:** `100%`

## TLDR

Two UI polish tweaks on the Home tab's completed-session card (`TodayCompletedCard`):

1. Add 2-line truncation + Show more / Show less toggle to the coach feedback block. The toggle is rendered **only when the feedback would actually overflow 2 lines** (no dead affordance for short feedback).
2. Delete the redundant `Text("Segments")` header above the per-lap segment graph.

## Critical Decisions

- **Visual treatment of `CoachFeedbackBlock` is unchanged** — keep the tinted accent container, uppercase `"COACH FEEDBACK"` label, and `.body` body font. Only the truncation+toggle is added. Calendar's flat secondary-colored styling is *not* adopted (confirmed in discovery).
- **State is local (`@State` inside `CoachFeedbackBlock`)** — expanded state resets on day swipe / card re-render. Same as calendar's `SessionCardView`.
- **Show more is gated on actual truncation** — measure full intrinsic text height vs the 2-line clamped height and only render the button when the former exceeds the latter. Calendar today always renders the button; we go one notch better here.
- **`CompletedSegmentGraphView` header removal is safe** — only one production caller (`TodayCompletedCard`); the inner `VStack(spacing: 8)` becomes a single-child container so spacing is moot. Vertical rhythm to neighbouring sections is owned by the parent `VStack(spacing: 16)`.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `Dromos/Dromos/Features/Home/CoachFeedbackBlock.swift` | MODIFY | Add `@State` for `showFeedback` + `isTruncated`. Modify `filledBody(_:)` to apply `lineLimit(showFeedback ? nil : 2)` and append a Show more / Show less button gated on `isTruncated`. Use a hidden ghost-text overlay with `PreferenceKey` height capture to compute `isTruncated`. Update accessibility labels. |
| `Dromos/Dromos/Features/Home/CompletedSegmentGraphView.swift` | MODIFY | Delete the `Text("Segments")` header block (lines ~87–90). Leave the `VStack(alignment: .leading, spacing: 8)` in place (single-child, harmless). |

## Context Doc Updates

None. UI-only change: no schema, no edge functions, no new services, no new architectural patterns.

## Tasks

- [ ] 🟩 **Step 1: Add truncation + Show more/less to `CoachFeedbackBlock`**
  - [ ] 🟩 Add `@State private var showFeedback: Bool = false` and `@State private var isTruncated: Bool = false` to the `CoachFeedbackBlock` struct.
  - [ ] 🟩 Define a private `PreferenceKey` (e.g. `FullTextHeightKey` and `ClampedTextHeightKey`) for capturing rendered heights from `GeometryReader` backgrounds.
  - [ ] 🟩 Refactor `filledBody(_:)` to:
    - Render the visible `Text(text)` with `.lineLimit(showFeedback ? nil : 2)` and a `GeometryReader` background that emits `ClampedTextHeightKey`.
    - Add a hidden ghost overlay (`Text(text).lineLimit(nil).fixedSize(horizontal: false, vertical: true).hidden()`) wrapped in a `GeometryReader` background that emits `FullTextHeightKey`. The ghost must sit inside the same width context as the visible text so layout-derived heights match.
    - Wire `.onPreferenceChange` for both keys to update local state vars and recompute `isTruncated = fullHeight > clampedHeight + 0.5` (epsilon avoids float jitter).
  - [ ] 🟩 Append a Show more / Show less `Button` below the body **only when `isTruncated == true`**. Style: `.font(.caption)`, `.foregroundColor(.accentColor)`, `.buttonStyle(.plain)`, label toggles between `"Show more"` and `"Show less"`. Tap action toggles `showFeedback` inside `withAnimation(.easeInOut(duration: 0.2))`.
  - [ ] 🟩 Add accessibility labels: keep the body label as `"Coach feedback: \(text)"`; set the button's `.accessibilityLabel` to `"Show full feedback"` when collapsed and `"Show less feedback"` when expanded.
  - [ ] 🟩 Verify the loading and missing branches are untouched: skeleton renders no toggle (gated by `if let feedback`), missing returns `EmptyView()`.

- [ ] 🟩 **Step 2: Remove "Segments" header from `CompletedSegmentGraphView`**
  - [ ] 🟩 Delete lines ~87–90 (the `// Section header` comment and the `Text("Segments")` block).
  - [ ] 🟩 Leave the surrounding `VStack(alignment: .leading, spacing: 8)` unchanged — its single remaining child (the `GeometryReader`) is fine, and the parent `TodayCompletedCard` controls outer spacing via its own `VStack(spacing: 16)`.

- [ ] 🟩 **Step 3: Update / verify previews**
  - [ ] 🟩 In `CoachFeedbackBlock`'s `#Preview("All three states")`, confirm the existing long-form filled sample exercises the truncation + Show more flow. Add (or reuse) a *short-feedback* sample (≤ 2 lines) to visually verify the button does **not** render.
  - [ ] 🟩 In `CompletedSegmentGraphView`'s 4 previews, confirm the graph still lays out cleanly without the header. No layout adjustments expected.

- [ ] 🟩 **Step 4: Manual QA on Home tab (frontend / e2e)**
  - [ ] 🟩 Build & run on simulator. Open Home tab. Force a completed session with long feedback and confirm: 2-line truncation by default, "Show more" present, tap expands smoothly, "Show less" collapses, day swipe resets to collapsed.
  - [ ] 🟩 Force a completed session with short feedback (≤ 2 lines) and confirm the Show more button is **absent**.
  - [ ] 🟩 Force a completed session with feedback still loading (skeleton) and confirm no toggle appears.
  - [ ] 🟩 Force a completed session with no feedback and confirm the entire block is absent.
  - [ ] 🟩 Open a completed run/bike with ≥ 2 laps and confirm the "Segments" header no longer appears above the graph.
  - [ ] 🟩 Verify swim / brick / single-lap sessions are unchanged (graph stays absent).

## Risk & rollback

- **Rollback:** revert this branch. Both files are isolated to the Home completed card; no DB / edge-function / schema changes.
- **Risk surface:** the ghost-text measurement pattern can produce a 1-frame flicker (button appears late) on first render. Mitigation: initialize `isTruncated = false` so the button defaults to hidden until measurement settles — first-render path shows the truncated text without a button, then the button fades in if needed. Acceptable for this surface.
- **Cross-platform:** Dromos is iOS-only; no Catalyst / iPad split-view edge cases to worry about beyond standard Dynamic Type response (which `lineLimit` already honors).
