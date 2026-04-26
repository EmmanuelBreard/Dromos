# PRODUCT.md — Dromos design context

This file is the source of truth for *who Dromos is for* and *how it should feel*. Both `/design-critique` and `/design-explore` read it before generating anything. If something here is wrong, fix it here — don't argue with the skill.

---

## Audience

**The Dromos user is a high-income, time-poor age-group triathlete.**

They earn well, train 6–12h/week around a demanding job, and have trained themselves to expect *premium* in everything they touch. They drive a Porsche or a Tesla, fly business when they can, and judge software the way they judge a watch movement — by precision, restraint, and finish. They already own a Garmin (top-tier — Fenix, Forerunner 965, Epix). They tolerate Garmin Connect because the hardware is essential; they actively dislike the software.

They do not need to be taught what a threshold workout is. They need to be told *theirs is right* and shown *exactly what to do today.*

**They are not:**
- Beginners discovering triathlon.
- Pros who already have a human coach.
- Strava-style social athletes who train for kudos.
- Gamification-driven (rings, streaks, badges).

---

## Emotional job-to-be-done

> "I am training the best way possible given the life I actually have, and a coach I trust is one tap away when I need them."

Two feelings to deliver, in this order:

1. **Confidence through understanding.** The plan is right *for me*, and I understand *why* this session is what I'm doing today. Confidence is not built by being told what to do — it's built by being shown the logic and trusting it.
2. **Presence.** The coach is here. Not a chatbot — a knowledgeable presence that explains as much as it prescribes.

Everything we ship should reinforce one of these. If a screen reinforces neither, it's noise.

---

## Voice

**A confident, high-end coach.**

- Speaks in short, declarative sentences. No hedging, no emoji, no exclamation points.
- Tells you what to do today **and why it matters**. The user is intelligent and earns trust through understanding, not blind compliance. Every prescribed session has a one- or two-sentence rationale visible without a tap (e.g. *"Threshold work — sharpens your top sustainable pace before next week's race-effort brick."*). Deeper explanation lives one tap away.
- Comfortable with silence — does not fill empty space with chatter. The "why" is signal, not chatter.
- Never congratulates effort that didn't happen. Never scolds.
- Tone reference: a former pro who now coaches — quietly authoritative, never loud. Teaches by explaining the system, not by issuing orders.

**Words we use:** session, effort, threshold, recovery, build, taper, today.
**Words we avoid:** workout buddy, crushed it, beast mode, journey, unlock, level up, achievement.

---

## References — what we admire and why

### Revolut
- **What:** Confident use of black, gradients used with restraint, financial-grade typographic hierarchy, dense data made calm.
- **Steal:** Treating numbers as the hero of the screen. Generous type sizes for the metric that matters; everything else recedes.

### Instagram
- **What:** Content-first, chrome-minimal, gestural. The product disappears around the content.
- **Steal:** Edge-to-edge content, thin chrome, trust the user to know where to tap.

### Spotify
- **What:** Bold editorial typography, controlled motion, premium dark surfaces, hierarchy that makes "what to play next" obvious.
- **Steal:** The "what now" answer is always visible without scrolling. Album-art-scale visual moments for things that matter (next session as the hero card).

---

## Anti-references — what we reject and why

### Garmin Connect
- **Why we reject it:** Every metric, everywhere, all the time. No editorial judgment about what matters today. Industrial 1990s data-dump aesthetic. Charts that look like SCADA dashboards.
- **Specifically never:** Multi-color line charts with 6+ series. Tiny labels. Tabs three deep. "Stats" pages that show 40 numbers without ranking them.

### Google Calendar
- **Why we reject it:** Chrome-heavy. Color-coded chaos as a substitute for hierarchy. UI takes more space than content. Designed for committees, not individuals.
- **Specifically never:** Heavy nav bars, dense toolbars, color used to differentiate categories rather than to draw attention.

### Reddit
- **Why we reject it:** Information density without curation. Treats the user as a forager, not a guest. Visual noise everywhere.
- **Specifically never:** Lists that go on forever. Up/down indicators. Comment-thread hierarchy. Anything that says "more, more, more" instead of "this, now."

---

## Stance — opinionated principles

These are non-negotiable. The skills enforce them.

1. **One answer per screen.** Every screen leads with the single most important thing. Secondary content recedes — physically smaller, lower contrast, lower in the visual stack.
2. **Editorial typography over UI typography.** Big confident headlines. Restrained body. Numbers as design elements. Inter/SF Pro at editorial sizes (40pt+ for hero metrics).
3. **Negative space is structural, not decorative.** Whitespace is how we say "this is important." Cramming kills the premium feel.
4. **Color is rare and meaningful.** Mostly neutrals (deep black, off-white, a few grays). Accent color appears sparingly — and when it does, it means something.
5. **Motion is restrained and purposeful.** No bouncy, no springy-for-its-own-sake. iOS-native easing. Motion confirms an action; it does not entertain.
6. **Real data, always.** No "Workout 1." No lorem. Sessions are named, paces are real, weeks are dated.
7. **Apple-native, not Apple-imitating.** SF Pro, system materials, native gestures, iOS HIG conformance. We do not invent UI patterns that fight the platform.
8. **Restraint over feature display.** Just because a metric exists doesn't mean it shows. The user trusts us to filter — that's the job.
9. **Always show the why.** Every prescribed session, plan adjustment, or recommendation carries a one- or two-sentence rationale visible by default — not buried behind a tap. Rationale is *content*, not chatter; it's what makes the confidence real. Deeper explanation lives one tap away for users who want more.

---

## Brand mode vs. product mode

Dromos operates almost exclusively in **product mode** — design *serves* the experience of training. We are a tool, not a marketing site. There is no "look at our beautiful design" moment inside the app; the design's job is to be invisibly correct.

The exception: onboarding and the marketing site, where brand mode applies — bigger gestures, hero typography, more deliberate first-impression decisions allowed.

---

## What "Apple-level" means here

Concrete, not aspirational:

- A naive user would not be surprised by any interaction. Everything behaves the way iOS taught them it should.
- A design-literate user notices the *restraint* before they notice anything else.
- Every screen would survive a pixel-level review — alignment, spacing, type hierarchy, contrast.
- Nothing is there because "it might be useful." Everything earns its place.
- Performance is part of design — no jank, no layout shift, no "loading…" without intent.

---

## How to use this file

- `/design-explore` reads this to ground prototype directions in our voice and references.
- `/design-critique` reads this to score current screens against our stance.
- When you (the user) reject a generated design, update this file with what was wrong before re-generating. The skill compounds.
- When in doubt, the **Stance** section wins.
