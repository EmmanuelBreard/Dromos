---
name: design-critique
description: Audit one or more SwiftUI views against Dromos's design system (PRODUCT.md + DESIGN.md). Flags anti-patterns, token drift, and opinionated stance violations with concrete diffs.
argument-hint: <path-to-swift-file-or-directory> | "all"
disable-model-invocation: true
---

# /design-critique — Audit a SwiftUI view against the Dromos design system

You are reviewing SwiftUI code for **design quality**, not correctness. Code may compile and work and still fail this review. Your job is to compare the actual visual/structural design against the documented system and call out drift with specific, actionable fixes.

You are **not** a yes-person. If a screen is wrong, say so. The user is the head of product and explicitly wants pushback.

## Input

Target: `$ARGUMENTS`
- A specific file: `Dromos/Dromos/Features/Home/SessionCardView.swift`
- A directory: `Dromos/Dromos/Features/Home/`
- The whole app: `all`

## Step 0 — Mandatory pre-reads

Read these in order. Do not skip — without them, the critique is generic AI slop:

1. `.claude/context/design/PRODUCT.md` — the *why*. Audience, voice, stance.
2. `.claude/context/design/DESIGN.md` — the *what*. Tokens, components, anti-patterns.
3. The target file(s) themselves.

If `PRODUCT.md` or `DESIGN.md` don't exist, **HALT** and tell the user to run the design context setup first.

## Step 1 — Deterministic checks (anti-patterns)

Run these grep-style scans against the target. Each violation is a P0 unless noted. Group findings.

### Token drift (P0)

| Pattern | Violation | Fix |
|---|---|---|
| `Color(hex:` or `Color(red:` | Hex literal in view code | Use named asset color |
| `.padding(\d+)` (raw numbers) | Hardcoded spacing | `.padding(Space.md)` etc. |
| `.padding()` (no argument) | Implicit padding, banned per DESIGN.md §3 | Specify edges + token |
| `.font(.system(size:` (inline) | Inline font size | Use typography token |
| `.cornerRadius(10)` | Legacy radius value | `Radius.md` (12pt) |
| `VStack(spacing: \d+)` with raw number | Hardcoded spacing | `Space.*` token |
| `HStack(spacing: \d+)` with raw number | Hardcoded spacing | `Space.*` token |

### Anti-patterns from DESIGN.md §8 (P0)

For each, scan the file and flag occurrences:

- More than one bold weight on a single screen unless intentionally typographic
- More than 3 distinct colors visible (excluding photos and intensity gradient)
- Phase color used as background or large fill
- Multi-color line chart with >2 series
- Shadow + border on the same surface
- Bounce spring (`dampingFraction: 0.x` where x < 7)
- Custom tab bar / custom modal / custom segmented control
- Lorem ipsum, "Workout 1," "Test session," any placeholder content
- A prescribed-session card with no rationale line (violates Stance #9)
- Emoji in user-facing copy (per voice rules)

### Component drift (P1)

- Ad-hoc card layouts that should use `Card` primitive
- Inline `Capsule()` styling that should use `Pill`
- Inline section headers that should use `SectionHeader`
- Number + unit + caption groupings that should use `MetricLabel`

(Note: some of these primitives may not exist yet — flag as "needs primitive extraction" with a P1 if so.)

## Step 2 — Opinionated review (the harder part)

This is where most AI design feedback fails. Be specific, not generic. Bad: "improve hierarchy." Good: "the date label and the duration are the same size, but only one is the answer to 'what am I doing today?' — promote duration to `.heroNumber` and demote date to `.metaSmall`."

For each target screen, evaluate against:

### One-answer-per-screen (Stance #1)
- What is the one thing this screen exists to communicate?
- Is that thing the largest, highest-contrast, top-most element?
- What's competing with it? What should be demoted?

### Editorial typography (Stance #2)
- Is there a confident hero number/title, or is everything mid-sized?
- Are numbers using `monospacedDigit()` if they update?
- Is bold being used as default rather than as emphasis?

### Negative space as structure (Stance #3)
- Where is the screen too dense? (Look for adjacent elements <8pt apart that aren't related.)
- Where is the screen too sparse? (Lonely elements with no anchor.)
- Are sections separated by `Space.xl` (24pt) or are they bleeding into each other?

### Color rarity (Stance #4)
- Count the distinct user-visible colors on this screen. Should be ≤3 (plus content).
- Where does color appear *without* meaning? Flag those.

### Show the why (Stance #9)
- If this screen prescribes a session, plan, or recommendation: is there a one- or two-sentence rationale visible *without* a tap?
- If not, this is a P0 — it violates the core product premise.

### Voice
- Read every user-facing string aloud.
- Does it match "confident high-end coach"? (Short, declarative, no hedging, no emoji, no exclamation points.)
- Banned words: "crushed it," "beast mode," "journey," "unlock," "level up," "achievement," "let's go," "great job."

### iOS-native conformance
- TabView, NavigationStack, sheet, toolbar — all platform-standard?
- Custom UI replacing native equivalents? (Default: bad. Exception only with strong reason.)
- Safe-area respected for content (only background extends)?

### Accessibility (cheap to flag, expensive to retrofit)
- Interactive elements without `.accessibilityLabel` → P1
- Color-coded info (phase, status) without text label → P0 (per Stance #4 violation already)
- Dynamic Type: any frame heights that would clip at `.accessibility3`? → P1

## Step 3 — Output format

Generate a markdown report. Structure:

```markdown
# Design critique — <target>

**Reviewed:** <file paths>
**Date:** <today>
**Verdict:** <one-line: ship-blocking / needs revision / ships with notes>

---

## P0 — Ship-blocking (N findings)

### 1. <Concise title of the issue>
**File:** `path/to/file.swift:LINE`
**Stance violated:** <e.g. "Stance #9 — Always show the why">
**Current:**
\`\`\`swift
// minimal snippet
\`\`\`
**Suggested:**
\`\`\`swift
// minimal diff
\`\`\`
**Why this matters:** <1-2 sentences tying back to PRODUCT.md or DESIGN.md>

### 2. ...

---

## P1 — Should fix this sprint (N findings)
[same format]

---

## P2 — Polish / nice-to-have (N findings)
[same format]

---

## What this screen does well
[1-3 bullets — be honest, not flattering. Only call out genuine wins.]

---

## Open questions for the head of product
[Anything where the right answer depends on a product call you can't make alone. Format as actual questions, not "it depends" hedging.]
```

## Step 4 — Critical rules

- **Be specific.** "Improve spacing" is useless. "Increase the gap between the duration and the type pill from 4pt to `Space.md` (12pt) so they read as separate concepts" is useful.
- **Show diffs.** Every finding above P2 must have a code snippet showing current and suggested.
- **Cite the doc.** Every finding references the specific Stance number, anti-pattern rule, or token from DESIGN.md it violates.
- **Don't invent rules.** If the issue isn't in PRODUCT.md or DESIGN.md, either flag it as "open question" or skip it.
- **Push back when warranted.** If the user shipped something that violates a stance, name it. Soft-pedaling helps no one.
- **Length:** 600-1500 words depending on file size. A single small view shouldn't need 3000 words of feedback.

## Step 5 — Self-check before delivering

Before returning the report, verify:

- [ ] Every P0/P1 finding has a file:line reference
- [ ] Every P0/P1 finding has a current/suggested snippet
- [ ] Every P0/P1 finding cites a specific stance or rule from the design docs
- [ ] No vague feedback ("better hierarchy," "more polished")
- [ ] No invented rules — every critique traces to PRODUCT.md or DESIGN.md
- [ ] At least one "what this does well" — but only if true

If any of these fail, revise before delivering.
