# Coach feedback — loading state

Three treatments for the moment between Strava sync completing and the AI feedback returning. The block label "COACH FEEDBACK" is constant in all three; only the body changes.

Context: VO2 intervals 5×3' just synced. The Edge Function takes ~3–8s. The actual-vs-planned table and map render normally below.

---

## Axis of divergence — reveal model

| Option | Reveal model | What animates | Voice |
|---|---|---|---|
| 1. Silent skeleton | Pure waiting → text appears (crossfade) | Three accent-tinted shimmer bars (2.6s ease-in-out, staggered) | None — silent |
| 2. Streaming prose | Progressive reveal — words fade in as the LLM streams | Words (blur-up + translate-y, 0.55s each, ~180ms apart); caret blink at write head | The actual feedback, arriving live |
| 3. Quiet label | Static micro-copy with subtle pulse | Status text opacity (2.8s) + three-dot pulse (1.8s) | "Reading your session…" |

All three: ~50–70px tall, sit inside the existing `feedback-block` (`--color-success-subtle` / `--radius-md`), honor `prefers-reduced-motion`, no bouncy easing.

---

## Option 1 — Silent skeleton

**The bet:** the label is the message. Don't say a word; just show that something is being prepared. Closest to what Apple ships in Mail summarization, Notes intelligence, and the "Summarize" affordance.

**Pros**
- Most restrained. Zero copy means zero risk of a tone-mismatch ("we are working on it…" reads like a Zendesk chat).
- Skeleton dimensions hint at the *shape* of the answer (~3 lines of prose), so when text replaces it, the layout doesn't jump.
- Works identically whether feedback takes 1s or 8s. No need for a "still working" fallback.
- Uses the accent green at low opacity — already present in the block fill — so visually it's one coherent surface.

**Cons**
- Doesn't explain *why* the user is waiting. A first-time user might not realize "the coach is thinking" — they might think the block is broken or empty.
- No surface for telling the user this is AI-generated, which we may want for trust/disclosure reasons.

**Implementation cost:** trivial. Three divs + one keyframe.

---

## Option 2 — Streaming prose

**The bet:** if the LLM is going to take 3–8 seconds anyway, fill that time with the actual answer instead of a placeholder. The wait *becomes* the reading. This is what ChatGPT, Claude, and every modern AI surface does — and the user already expects it from any product touched by AI in 2026.

**Pros**
- Strongest signal of "knowledgeable presence" — the coach is *speaking*, not loading. No abstraction between the user and the content.
- Perceived latency drops to ~zero: the user starts reading the moment the first words land.
- Makes the AI nature legible in the most honest way (you can see it think) without an "AI" badge.
- Works with our existing OpenAI streaming pipeline — Edge Function already returns SSE-able output.

**Cons**
- Requires real streaming end-to-end (Edge Function → Supabase → Swift `AsyncSequence` → SwiftUI). More backend wiring than the other two. Estimate: 0.5–1 day of client work + verifying the function streams (it should).
- Layout reservation needed: we have to reserve ~3.4em of min-height for the block, otherwise the table jumps as words arrive. Done in the prototype.
- If the network drops mid-stream, we need a graceful "feedback unavailable" fallback — extra error-state work.
- Word-by-word reveal can feel theatrical if too slow. Tuned at ~180ms/word in the prototype, which matches a fast-but-readable LLM stream. Don't go slower.

**Implementation cost:** medium. The prototype simulates with CSS `nth-child` delays; production is `AsyncStream<String>` driving a SwiftUI `Text(...)` that grows.

---

## Option 3 — Quiet label

**The bet:** be explicit and small. One short status line, almost no animation. Honest about the wait without dressing it up.

**Pros**
- Cheapest to ship — no streaming, no skeleton tuning. A static `Text` + a `.symbolEffect(.pulse, options: .repeat(...))` would do it in SwiftUI.
- Most accessible: a screen reader gets "Reading your session" naturally; the other two require an `aria-busy` + `aria-live="polite"` polite update.
- Easiest to internationalize.

**Cons**
- It's a phrase. Phrases age fast. "Reading your session" is the cleanest we found, but anything in this slot risks reading as chatter — which violates the PRODUCT.md rule "comfortable with silence — does not fill empty space with chatter."
- Harder to make *premium*. A status-with-dots is the universal bottom-of-the-barrel loading idiom; even when restrained, it can read as web-app-y (Reddit, Slack, every dashboard).
- Doesn't use the wait time productively.

**Implementation cost:** trivial.

---

## Recommendation — Option 2 (streaming prose), with Option 1 as a pragmatic v1

**Ship Option 2.** It is the only treatment that turns the latency into content. Our entire product stance — "knowledgeable presence" (PRODUCT §Voice), "performance is part of design" (PRODUCT §What Apple-level means), "always show the why" (Stance #9) — points to streaming prose. The user gets *coach speaking* instead of *app loading*. It also future-proofs us: as the AI pipeline improves, the same component carries longer/richer feedback with no UI change.

**However**, if streaming end-to-end isn't already wired through the Edge Function and Swift client, **ship Option 1 as v1** and migrate to streaming when the backend is ready. Option 1 is the only other option that respects the "comfortable with silence" rule. It's also a perfectly valid permanent choice if streaming proves flaky — Apple ships skeleton states across the OS without apology.

**Reject Option 3.** "Reading your session…" with dots is the kind of micro-copy we should be allergic to. It reads as a chatbot status, not as a coach. The dots-pulse idiom is everywhere; nothing about it says premium. Keep it as the *fallback for fallback* (e.g., when streaming fails and we fall back to non-streamed regeneration), but not as the primary loading state.

**Decision needed from you:**
- Is the OpenAI Edge Function already streaming token-by-token, or does it return one shot? If one-shot, Option 2 needs backend work first.
- Time-budget: are you OK with ~1d of streaming wiring, or do you want to ship Option 1 next sprint and iterate?
