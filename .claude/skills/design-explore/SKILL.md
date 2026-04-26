---
name: design-explore
description: Generate 3-4 directionally distinct HTML prototypes for a new feature before any SwiftUI code is written. Each prototype is a self-contained mobile mockup the user can preview in the IDE.
argument-hint: <feature-description-in-quotes>
disable-model-invocation: true
---

# /design-explore — Diverge before you converge

You are exploring **multiple distinct directions** for a new Dromos feature, in HTML, before anyone writes SwiftUI. The user is the head of product. The output of this skill is the input to a product decision — you are not building, you are *diverging cheaply* so the user can converge confidently.

The single biggest failure mode of this skill is producing **three variations of one idea** instead of three genuinely distinct ideas. If your three options all have the same layout with different button colors, you have failed. Push for *different mental models* of the same problem.

## Input

Feature description: `$ARGUMENTS`

Examples of good inputs:
- `"a screen showing this week's overview — what's coming, what's been completed, how the week is shaping up"`
- `"the post-session feedback flow after a completed workout"`
- `"the moment a user adjusts a session because life got in the way"`

If the input is too vague (e.g. just `"home screen"`), **HALT** and ask for more context: what's the user's goal on this screen? What decision are they making?

## Step 0 — Mandatory pre-reads

Read these in order. Without them, the prototypes will be generic AI slop:

1. `.claude/context/design/PRODUCT.md` — audience, voice, stance.
2. `.claude/context/design/DESIGN.md` — tokens, components, anti-patterns.
3. Any files in `.claude/context/design/references/` (screenshots of admired/rejected designs, if present).

If `PRODUCT.md` or `DESIGN.md` don't exist, **HALT** and tell the user.

## Step 1 — Concept divergence (do this in your head, then in writing)

Before opening any HTML editor, generate 3-4 *directionally distinct* concepts. They must differ on a **structural axis**, not a cosmetic one.

Productive axes for divergence:
- **Information primacy:** What's the hero? (the next session / the week / the rationale / the metric)
- **Layout model:** card-based / editorial / list / dashboard / chronological
- **Interaction model:** tap-through-detail / swipe-between-states / scroll-rich / gesture-heavy / static-glance
- **Time orientation:** "now" / "today" / "this week" / "this phase"
- **Voice register:** instructional ("Do this") / explanatory ("Here's why") / observational ("This is where you are")

Pick 2-3 axes and generate a concept that takes a *strong* position on each. Then critique your own concepts: are they actually different, or are they the same idea with different decoration? If the latter, throw them out and try again.

**Hard rule:** at least one of your concepts must intentionally break a current convention in the app. Default-conformity-only is a failure mode.

## Step 2 — Decide output location

Generate a slug from the feature description (lowercase, kebab-case, max 4 words).
Output directory: `prototypes/<slug>/`

Structure to create:
```
prototypes/
  <slug>/
    comparison.md
    option-1-<concept-name>.html
    option-2-<concept-name>.html
    option-3-<concept-name>.html
    option-4-<concept-name>.html  (optional — only if 4th is genuinely distinct)
    shared/
      tokens.css   (copied from .claude/skills/design-explore/templates/tokens.css)
```

If `prototypes/shared/tokens.css` already exists at the project root, *symlink or relative-reference* to it instead of copying — we want a single source of truth for the design system across all prototypes.

Actually simpler approach: put `tokens.css` once at `prototypes/shared/tokens.css` (project-level, not per-feature). Each prototype references `../../shared/tokens.css`. Create the shared file if missing by copying from `.claude/skills/design-explore/templates/tokens.css`.

## Step 3 — Generate each prototype

For each option:

1. **Start from the shell** at `.claude/skills/design-explore/templates/prototype-shell.html`. Copy it, fill in the `{{FEATURE}}` and `{{OPTION_NAME}}` placeholders.
2. **Replace the `<main class="screen">` block** with the actual prototype content for that concept.
3. **Use real Dromos data, never lorem.** Examples to draw from:
   - Sport names: Run, Bike, Swim, Brick (Run+Bike sequence)
   - Real workout titles: "Threshold intervals 4×8'", "Long Z2 ride", "Recovery swim — drills", "Race-pace brick"
   - Real paces: 4:35/km, 5:10/km, 1:38/100m, 270W
   - Real durations: 1h12, 45min, 2h30
   - Real plan phases: Base / Build / Peak / Taper
   - Real days: "Today, Tue 28 Apr", "Thu", "This Sat"
4. **Per Stance #9, every prescribed thing must show its rationale** in 1-2 sentences. Example: "Threshold work — sharpens your top sustainable pace before next week's race-pace brick." This is non-negotiable; a prototype that omits this is broken.
5. **Use only the typography utilities and components from the shell** (`.t-hero`, `.t-title`, `.card`, `.pill`, `.btn-primary`, etc.). Do not invent new styles inline. If you need something new, ask whether it should be added to the shell.
6. **Respect every anti-pattern in DESIGN.md §8.** Specifically: ≤3 visible colors per screen, no emoji in copy, no bouncy motion, monochrome phase metadata.
7. **Show the same scenario in each option.** Example: if the feature is "this week overview," every option shows *the same week's* sessions. This is what makes them genuinely comparable.

### Pre-flight check before writing each HTML

Ask yourself for each option:
- Could a user tell what this concept *believes* about how the user thinks? (Strong concepts have an opinion.)
- Is the hero the right thing? (Per Stance #1: one answer per screen.)
- Does it look like Dromos and not like a generic fitness app?
- If the user picked this option and we shipped it, would they later regret it for a *specific* reason? (Surface that tradeoff in `comparison.md`.)

## Step 4 — Generate `comparison.md`

This file is what the user reads first. It is the converge tool. Without it, they're staring at 4 HTML files with no decision frame.

Format:

```markdown
# <Feature title>

**Brief:** <one-sentence restatement of what was asked>
**Generated:** <date>
**Open in browser:**
- [Option 1 — <name>](./option-1-<name>.html)
- [Option 2 — <name>](./option-2-<name>.html)
- [Option 3 — <name>](./option-3-<name>.html)

---

## The axis of divergence

These options differ primarily on **<the structural axis you chose>**. They are not variations of one idea; they are different bets about <what the user actually needs / wants / will do>.

---

## Option 1 — <Concept name>

**The bet:** <one sentence — what this option believes about the user>
**Hero:** <what's the biggest thing on screen and why>
**Optimizes for:** <the one thing this is best at>
**Sacrifices:** <what you give up to get that — be honest>
**Pick this if:** <the user-belief that would make this the right answer>
**Reject this if:** <the user-belief that would make this wrong>

[Optional: 2-3 sentences of additional reasoning]

---

## Option 2 — <Concept name>
[same structure]

---

## Option 3 — <Concept name>
[same structure]

---

## My recommendation

[1-3 sentences. Be opinionated — "I'd ship Option 2 because <reason>." If you have low conviction, say so explicitly: "I don't have a strong recommendation here; the choice depends on <X>." Never hedge.]

## What's *not* here

[Briefly: 1-3 directions you considered and rejected, and why. This proves the divergence was real, not lazy.]

## Open questions for the head of product

[Things the user needs to decide that you couldn't make a call on alone. Format as actual questions.]
```

## Step 5 — Final report to the user

Once files are written, return a tight summary in chat:

```
Generated <N> prototypes for "<feature>" at prototypes/<slug>/.

Open comparison.md first: prototypes/<slug>/comparison.md
Then preview each option in VS Code (right-click → Open Preview, or use Live Server).

The three concepts are:
1. <Name> — <one-line bet>
2. <Name> — <one-line bet>
3. <Name> — <one-line bet>

My recommendation: Option <N> because <reason>.

Once you pick a direction, run /create-tech-spec to scope the SwiftUI implementation.
```

## Critical rules

- **Distinctness over polish.** Three rough concepts that differ are infinitely more useful than three polished concepts that are the same.
- **Real data only.** No "Workout 1," no lorem, no "User A." Real workout names, real paces, real dates.
- **Show the why on every prescribed thing.** Stance #9 is non-negotiable.
- **One hero per screen.** Stance #1 — every option must commit to one answer.
- **No invented colors or fonts.** Everything from `tokens.css`. If you reach for something not in tokens, stop and ask.
- **No emoji in user-facing copy.** Voice rules from PRODUCT.md.
- **Tab bar visible by default.** Remove it only for full-screen modals (onboarding, focused capture flows).
- **Don't skip `comparison.md`.** The HTML files without the comparison framing are useless.
- **Push back if the brief is bad.** If the feature description doesn't define a clear user goal, halt and ask.

## Self-check before delivering

- [ ] All concepts differ on a *structural* axis, not just decoration
- [ ] At least one concept intentionally breaks a current app convention
- [ ] Every prototype uses real Dromos data
- [ ] Every prescribed session/recommendation shows its rationale
- [ ] All HTML files reference `../../shared/tokens.css`
- [ ] `comparison.md` exists and is opinionated
- [ ] No invented styles; all styling uses tokens/utilities from shell
- [ ] At most 3 user-visible colors on each screen (excluding intensity gradient)
- [ ] No banned words in any user-facing copy

If any of these fail, fix before returning.
