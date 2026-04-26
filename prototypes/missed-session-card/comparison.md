# Missed session card — option comparison

Three takes on the same slot: what does the Today card become once the session has been missed and there's no v1 CTA to recover? Each option commits to a different answer.

---

## Axes of divergence

| Axis | Option 1 — Quiet respect | Option 2 — Tag only | Option 3 — Shape survives |
|---|---|---|---|
| Dim strategy | Uniform dim (everything @ 0.55) | Title-only dim, body removed | Progressive — title bright, shape faded |
| Workout shape & steps | Both kept (full plan visible) | Both removed | Shape kept (compact), steps removed |
| Where red lives | Tag only | Tag only | Tag + 3pt left border accent |
| Rationale | Kept (dimmed) | Removed | Removed |
| Card height vs. planned | ~Same | Collapses to ~30% | ~50% |

These are real structural choices, not three skins of the same idea.

---

## Option 1 — Quiet respect

**Bet:** The plan is a record. Even when missed, it's the truth of what today *was meant to be* — show it in full, just dimmed, with status stamped on top.

- **Pick this if:** you believe athletes will look back ("what was I supposed to do?") and you want zero chance of accusing them of failure. The card is the same plan card, just labeled.
- **Reject this if:** showing the full unwalked plan feels like rubbing it in. Also: card height equals planned-state — the page doesn't visually relax when something's been skipped.

---

## Option 2 — Tag only

**Bet:** Once the day is gone, the plan is noise. Acknowledge, get out of the way, let the eye land on the week strip and tomorrow.

- **Pick this if:** you trust the user to know what they planned without re-reading it, and you want the missed-state to physically *recede* on the screen so attention naturally flows to the next day.
- **Reject this if:** you think people genuinely re-read missed plans (curiosity, regret, planning a make-up). Or if a near-empty card on the hero slot reads as "broken" rather than "respectful."

---

## Option 3 — Shape survives

**Bet:** The *shape* of a workout is its identity — keeping it (compact, faded) preserves "I see what was asked" without the operational steps that are stale after the fact. The left border is a structural marker, not decoration.

- **Pick this if:** you want a middle path that keeps a recognizable visual fingerprint of the session without the full plan-card weight, and you believe the intensity profile carries enough meaning to earn its space.
- **Reject this if:** intensity bars without labels are decorative-feeling once the session is gone, or if you find left-border accents Garmin-coded (Stance #4 risk: red appearing in two places, not one).

---

## Recommendation

**Ship Option 2 — Tag only.**

Three reasons:

1. **Voice fit.** Stance #1 (one answer per screen) and Voice ("comfortable with silence — does not fill empty space with chatter") both point here. A near-empty card is the most honest version of "session not completed, no further commentary." Anything more is the app having an opinion about a missed workout, which the product owner explicitly said it must not.
2. **Visual hierarchy.** Option 1 keeps the missed slot at full hero weight — which fights the natural read order ("look at tomorrow"). Option 2 collapses it so the week strip becomes the de-facto next focal point without us having to point at it.
3. **Future-proof for v2.** When we add the "why didn't you do it?" / "schedule a make-up" CTAs later, Option 2 has the most room to grow into them without restructuring. Option 1 is already full; Option 3 has a left-border that competes with whatever red CTA we'd add.

**Caveat / pushback:** the only reason I'd pick Option 3 over Option 2 is if user research shows people genuinely scan past missed sessions and want the visual fingerprint as a "yes, that one" anchor. Worth checking after a week of dogfood. Option 1 I'd reject — it violates the editorial principle of "the page should physically relax when there's nothing to do here."
