---
name: research
description: Fire a research agent on any topic. Dispatches `researcher` workers (serially when visual, in parallel when text-only), captures real screenshots, and writes a synthesized analysis file + (conditionally) a comparison matrix. Outputs to research/<descriptive-slug>/.
argument-hint: <topic-in-quotes>
disable-model-invocation: true
---

# /research — Fire-and-forget research agent

You orchestrate research on a single topic. You stay in the main context. You dispatch `researcher` subagents (one per source). You synthesize their results into a report.

## Input

Topic: `$ARGUMENTS`

Examples of good inputs:
- `"how do top triathlon apps onboard a new user — first 60 seconds"`
- `"current state of HRV-based recovery scoring — research consensus 2025"`
- `"pricing pages of subscription fitness apps under $20/mo"`
- `"design language of Linear, Height, and Attio — what's the shared aesthetic"`

If the topic is too vague (e.g. just `"competitors"` or `"AI coaching"`), **HALT** and ask one sharp clarifying question. Do not guess scope.

## Step 0 — Classify the topic

Decide two things and write them down for yourself before doing anything else:

**A. Is this visual?**
- `is_visual: true` → topic is about UI, UX, design, layouts, copy, onboarding flows. Sources have screens worth capturing.
- `is_visual: false` → topic is about ideas, research, science, business model, pricing-only. WebFetch is enough.
- `is_visual: mixed` → some sources need screenshots, some don't. Decide per source in Step 2.

**B. Is this comparative?**
- Comparative → research will surface ≥3 entities of the same type (apps, products, papers, brands) that can be lined up against each other.
- Single-subject → deep-dive on one thing or one question, no apples-to-apples comparison.

The **matrix file is built ONLY if comparative**. State the decision now and don't revisit it.

## Step 1 — Pick the folder slug + synthesis filename

Both names must be **self-explanatory at a glance**. A reader scrolling `research/` should know what each folder is about without opening it.

**Folder slug** — descriptive kebab-case, ≤50 chars. Describe the topic, not the date (date lives inside the synthesis file). Examples:
- `triathlon-app-pricing-comparison`
- `hrv-recovery-scoring-research`
- `triathlon-app-onboarding-flows`
- `linear-height-attio-design-language`

❌ Avoid: `2026-05-01-research-1`, `competitor-analysis`, `topic-1` — these are not self-explanatory.

If `research/<slug>/` already exists, append `-2`, `-3`, etc. Never overwrite.

**Synthesis filename** — pick a 2–4 word descriptive name + `-analysis.md`. Examples:
- `pricing-comparison-analysis.md`
- `onboarding-flow-analysis.md`
- `hrv-research-analysis.md`
- `design-language-analysis.md`

Use this filename in Step 3 and Step 5. **Never use generic `README.md`.**

## Step 2 — Identify sources

Use `WebSearch` to find 3–10 sources. Quality bar:
- Comparative topics → aim for the top 5–8 entities in the space.
- Single-subject topics → 4–6 strong sources (papers, primary docs, established blogs).
- Skip: SEO spam, listicles older than 18 months, AI-generated content farms.

For each source, decide its `source_slug` (kebab-case, ≤30 chars) and whether it needs visual capture.

Show the user the source list **before dispatching workers** so they can prune. Format:

```
Sources for "<topic>":
1. <source_slug> — <url> — visual:yes/no — <one-line why>
2. ...
Reply "go" to dispatch, or edit the list.
```

Wait for confirmation. If the user says "go", proceed. If they edit, accept changes and re-confirm.

## Step 3 — Create folder structure (with pre-created files)

Create the topic folder, per-source folders, and **pre-create empty placeholder files** for `analysis.md` and `raw.json`. Pre-creating these files prevents fresh-path permission prompts when subagents go to write into them. Use Bash:

```bash
mkdir -p research/<topic-slug>/sources
for src in <source-slug-1> <source-slug-2> ...; do
  mkdir -p "research/<topic-slug>/sources/$src/screenshots"
  : > "research/<topic-slug>/sources/$src/analysis.md"
  : > "research/<topic-slug>/sources/$src/raw.json"
done
```

The resulting structure:

```
research/<topic-slug>/
  <synthesis-filename>.md      ← stub now, filled in Step 5
  sources/
    <source-slug-1>/
      analysis.md                (empty placeholder)
      raw.json                   (empty placeholder)
      screenshots/               (empty dir)
    <source-slug-2>/
      ...
```

Then write a stub at `research/<topic-slug>/<synthesis-filename>` with the topic, classification, source list, timestamp, and a `_workers dispatched, synthesis pending_` note.

## Step 4 — Dispatch workers

**Dispatch rule depends on visual mode:**

- **`is_visual: true` (or `mixed` with any visual sources):** dispatch workers **SERIALLY** — one Task call, wait for it to return, then dispatch the next. The Playwright MCP exposes one shared browser session; parallel workers collide on `browser_navigate` and overwrite each other's pages. Serial keeps screenshots clean.
- **`is_visual: false` for all sources:** dispatch in parallel — single message with all Task calls. WebFetch is concurrency-safe.

For each source, the prompt to the worker MUST be the strict contract from `.claude/agents/researcher.md`:

```
{
  "source_url": "<url>",
  "source_slug": "<slug>",
  "topic_slug": "<topic-slug>",
  "topic_question": "<the original topic>",
  "focus_areas": ["<area-1>", "<area-2>", ...],
  "is_visual": true|false
}
```

`focus_areas` should be 3–5 specific things tied to the topic. For onboarding research: `["first screen", "signup friction", "value prop placement", "time to first action"]`. Don't pass generic areas like `"general analysis"`.

Collect all worker summaries. After the last worker returns, **verify on disk** that each source folder contains a non-empty `analysis.md` and `raw.json`. If a worker returned `STATUS: ok` but the files are empty, downgrade its status to `partial` and note it in the synthesis.

## Step 5 — Synthesize the analysis file

Write the final report at `research/<topic-slug>/<synthesis-filename>` (the descriptive `*-analysis.md` you picked in Step 1):

```markdown
# <Clear human-readable title — e.g. "Pricing comparison: TrainingPeaks, TriDot, Humango">

**Date:** YYYY-MM-DD
**Classification:** visual | textual | mixed · comparative | single-subject
**Sources:** <count> (<count_ok> ok, <count_partial> partial, <count_failed> failed)

## TL;DR
3–5 bullets — the answer to the topic question. No hedging.

## What's worth stealing
3–5 patterns / ideas / approaches that came up across multiple sources.

## What surprised us
2–3 non-obvious findings.

## Per-source findings
For each source: 1-paragraph summary + link to `sources/<slug>/analysis.md`.

## Open questions
Things the research couldn't answer. Suggest follow-up topics.
```

Quality bar: every claim in TL;DR must be traceable to at least one `sources/<slug>/analysis.md`. No vibes.

## Step 6 — (Conditional) Write `matrix.md`

**Only if** Step 0 said comparative AND ≥3 workers returned `STATUS: ok` with the same `ENTITY_TYPE`.

Otherwise skip — do not force a matrix.

Format:

```markdown
# Comparison matrix — <topic>

| | <source-1> | <source-2> | <source-3> | ... |
|---|---|---|---|---|
| <focus_area_1> | ... | ... | ... | ... |
| <focus_area_2> | ... | ... | ... | ... |
| Verdict (1-line) | ... | ... | ... | ... |
```

Each cell must be independently verifiable from that source's `raw.json` (Exa Websets pattern — verification per cell, not per row).

## Step 7 — Report back to user

Final message to user, ≤150 words:
- Topic + classification
- Path: `research/<topic-slug>/<synthesis-filename>`
- Source count + any failures
- TL;DR (3 bullets, copy from synthesis file)
- Whether matrix was built and why/why-not
- Suggest 1 follow-up if obvious

## Hard rules

- Never skip Step 2's user confirmation — sources are the most expensive thing to get wrong.
- Never write outside `research/<topic-slug>/`.
- Never commit. Never push.
- When `is_visual: true`, dispatch workers SERIALLY (one at a time). Parallel only for text-only runs.
- Never name the synthesis file `README.md` — always use a descriptive `*-analysis.md` filename.
- Pre-create per-source `analysis.md` + `raw.json` as empty files in Step 3 to avoid subagent write-permission prompts.
- Screenshots can get heavy. Mention to user at the end if total `research/` exceeds ~50MB; suggest gitignoring `research/*/sources/*/screenshots/`.
