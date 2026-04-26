# Home page session display

**Brief:** Improve how a session is presented on the Home tab — replace the current dense card-per-day stack with something that earns the premium feel.
**Generated:** 2026-04-26
**Open in browser:**
- [Option 1 — Anchor](./option-1-anchor.html)
- [Option 2 — Briefing](./option-2-briefing.html)
- [Option 3 — Arc](./option-3-arc.html)
- [Option 4 — Anchor + Shape](./option-4-anchor-shape.html) ← **leading direction after first review**

All three show the same scenario so you can compare honestly: **Tuesday 28 April, Build phase week 3 of 4, 5 weeks out from the Nimes Olympic. Today = threshold run. The week peaks Saturday with a race-pace brick.**

---

## The axis of divergence

These three options differ on **what the card believes the user needs the moment they open the app**. They are not three skins of one idea — they are three different bets about the user's mental state.

- **Anchor** bets the user wants *one clear answer*: what to do today.
- **Briefing** bets the user wants *to be coached*: prose, voice, reasoning.
- **Arc** bets the user wants *to see the shape*: where am I in the week, where does it peak.

If two of these prototypes feel interchangeable to you, I've failed — push back and I'll re-diverge.

---

## Option 1 — Anchor

**The bet:** When you open Dromos, you want to know what to do *right now*. Everything else is reassurance, not action.
**Hero:** Today's session — duration as a 56pt hero number, name above, rationale below, single primary CTA.
**Optimizes for:** Time-to-decision. Two seconds from open to "got it, go run."
**Sacrifices:** The week's narrative arc. You can see the seven days as a strip, but you don't *feel* the shape of the block — Wednesday's 2h30 ride looks the same size as Friday's 50' easy run.
**Pick this if:** Your usage data shows the user opens the app, glances at today, and closes it. The session card is for *acting*, not *understanding*.
**Reject this if:** The user actually wants to plan their week mentally on Sunday night — Anchor doesn't help with that.

This is the most conventional of the three. It looks like Apple Fitness or a clean Strava planner. It will pass `/design-critique` cleanly. It is also the safest, which means it leaves the most premium feeling on the table.

---

## Option 2 — Briefing

**The bet:** Premium isn't a dashboard. Premium is being *coached*. The card reads like a morning brief from a coach who has thought about your week.
**Hero:** A short editorial headline + two paragraphs of reasoning. The prescription (`Threshold intervals 4×8' — 1h · run`) is one quiet line at the bottom of the brief.
**Optimizes for:** Confidence-through-understanding (Stance #2 from PRODUCT.md). Every sentence is the rationale; the rationale is the content.
**Sacrifices:** Glanceability. You cannot get the answer in one second. The brief is meant to be *read*, even if just for fifteen seconds. Also: it has almost no chrome — no sport icons, no chips, no progress bar. A user used to fitness apps might initially feel "where's the data?"
**Pick this if:** You believe Dromos's wedge against Garmin Connect *is* the writing — that the coach voice is the moat. Then the home screen should *be* the coach speaking, not a dashboard with the coach's words attached.
**Reject this if:** You think the user wants to skim, not read. Or if you don't have the editorial production capacity to generate this text per athlete per day at quality (this requires the AI pipeline to ship a real coach voice, not template strings).

**This is the option that intentionally breaks current convention** — no card-per-session layout. Instead, a single editorial column. It looks unlike any fitness app on the market. That's the point — and the risk.

---

## Option 3 — Arc

**The bet:** Confidence comes from seeing the *logic* of the week — where the hard days fall, where the rest is, where the peak is. Once you see the shape, today's session makes sense without explanation.
**Hero:** A horizontal bar showing the seven days weighted by intensity × duration. Today is the accent column. Tap any day to swap the expanded panel below.
**Optimizes for:** Pattern recognition. You see at a glance: "OK, hard today, rest Thursday, peak Saturday, long Sunday, then it tapers."
**Sacrifices:** Per-session detail in the moment. The today-expanded panel works hard, but the other days are reduced to one-line summaries. Also: the arc visualization is novel — no existing iOS fitness app does this — which means it carries a small interaction-cost (users have to learn to tap the columns).
**Pick this if:** Your athletes are sophisticated enough that they think about training in *blocks*, not in *sessions*. The week's shape *is* the answer; today is just one column of it.
**Reject this if:** You think showing intensity color (even confined to today's workout-shape) drifts toward the Garmin aesthetic we've explicitly rejected. The arc bar uses monochrome, but the workout-shape inside the today card does use the intensity gradient — that's a deliberate tradeoff, and you may not want it.

---

## My recommendation

**I'd ship Option 1 (Anchor) as the default, with Option 2 (Briefing) elements grafted in.**

Specifically: Anchor's structure (today as hero, week as strip), but with Briefing's *rationale paragraph* as the centerpiece of the today block — written in Briefing's voice, not in template language. Anchor without the prose is a clean dashboard. Briefing without the structure is hard to act on. The merge is what feels like Dromos.

Option 3 (Arc) is the most distinctive of the three but the most expensive: a genuinely new visualization, novel interaction, and a small but real conflict with the "color is rare" rule. I'd file it for v2 — after we've earned the user's trust with something more conventional.

If you disagree, the most likely reason is that you believe the *coach voice* is the moat, not the layout. In that case ship Briefing as-is — but understand we're betting the home screen on the AI pipeline being able to produce real prose at scale, not template fills.

---

## What's *not* here

- **A "completed sessions feed" view.** Current SessionCardView packs three states (planned/completed/missed) into one component. None of these prototypes shows the *completed* state of today, because the home screen's job at 9am is to surface what's *next*, not to relitigate what was done. Completion belongs on the session detail screen, not the home card. This is itself a product position; flag it if you disagree.
- **A swipeable card stack** (Tinder-style, one session at a time). I considered it and rejected it — too gimmicky, fights iOS conventions, and forces the user to do work the system should do.
- **A calendar-grid view of the week.** That's the Plan tab's job. The Home tab is for *now*, not *all*.

## Open questions for the head of product

1. **What's the user's primary intent on Home?** Acting (Anchor wins), understanding (Briefing wins), or orienting (Arc wins). My instinct is acting — but you have user data, I have priors.
2. **How real is the coach voice today?** Briefing is only as good as the prose generation. If the AI pipeline can only produce template-quality text right now, Briefing degrades to bad copy in a fancy layout. Worth checking with the pipeline output before committing.
3. **Is the strict "color is rare" rule absolute, or contextual?** Option 3 uses the intensity gradient inside the today card, which DESIGN.md §1 permits ("inside workout-detail context"). But Home is borderline — is the today card "workout-detail context" or "top-level card"? You decide.
4. **Does completion state belong on Home at all?** Right now we render completed sessions in the home stack. None of these prototypes does. Confirm or push back before I scope the SwiftUI work.
