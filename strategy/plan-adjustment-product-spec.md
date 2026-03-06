# Plan Adjustment via Chat — Product Specification

> **Date:** 2026-02-21
> **Author:** Porco (CPO)
> **Status:** Product Spec — Ready for Engineering Feasibility Review
> **Research:** [plan-adjustment-research.md](plan-adjustment-research.md)
> **Strategy ref:** [ai-differentiation.md](ai-differentiation.md) — Priority 2: Natural Language Plan Adaptation

---

## 1. Overview

Dromos adds a **Chat tab** where users describe training disruptions in natural language. The AI gathers enough context through conversation, adjusts the plan, and explains what changed and why — directly in the chat. No approval flow. The chat history persists and serves as both UX and data for future adjustments.

**Core user need:** "When life throws a curveball, I need my training to adapt without me figuring out the ripple effects."

**What makes this different from competitors:** Every competitor either fakes adaptation (TriDot), hides it in a black box (TrainerRoad, Humango), or delegates to manual drag-and-drop (Mottiv). Dromos explains every change in plain English, asks the right follow-up questions, and remembers past conversations for context.

---

## 2. User Experience

### 2.1 Entry Point

New tab in `MainTabView`: **Chat** (speech bubble icon), positioned between Calendar and Profile.

```
[Home]  [Calendar]  [Chat]  [Profile]
```

### 2.2 Chat Interface

- Standard chat UI: user messages on right, AI messages on left
- Persistent conversation history (scrollable, chronological)
- Text input field at bottom with send button
- No quick-reply buttons in V1 (may add later as acceleration, not as a crutch)

### 2.3 Conversation Flow

The AI drives the conversation through 3 stages:

**Stage 1 — User describes the issue (free text)**

User sends a message describing their situation. Examples:
- "My knee has been hurting since Tuesday"
- "I'm traveling to London next week, no pool access"
- "I'm exhausted, can't face another interval session"
- "I've had a fever since yesterday"
- "Work is insane this month, I can barely fit anything in"

**Stage 2 — AI classifies and gathers missing info (1-2 follow-ups max)**

The AI:
1. Classifies the constraint type (equipment, fatigue, injury, life event, illness)
2. Checks which required fields are filled vs. missing (see Section 4)
3. Asks only for what's missing — most users provide 60-70% of needed info in message 1

Examples of follow-ups:
- (Injury) "Can you still bike and swim without pain?"
- (Equipment) "How long will you be without pool access?"
- (Illness) "Do you have a fever or is it more of a head cold?"
- (Life event) "What dates are affected, and will you have access to a gym?"

**Stage 3 — AI adjusts the plan and explains what changed**

Once the AI has sufficient information, it:
1. Modifies the plan (affected weeks, potentially including ramp-back)
2. Explains what changed and why, directly in the chat

Example AI response:
> Here's what I've done to your plan for this week and next:
>
> **This week (Week 8 — Build):**
> - Removed Thursday's tempo run and Saturday's long run (knee needs rest from impact)
> - Kept Wednesday's swim intervals and Tuesday's easy bike
> - Added an easy swim on Friday to keep aerobic load up (you had headroom in swim volume)
> - Total volume: 6h → 4.2h
>
> **Next week (Week 9 — Build):**
> - Shifted your threshold run to a threshold bike instead
> - Kept all swim sessions unchanged
>
> Your bike and swim fitness won't skip a beat. When the knee improves, let me know and I'll ramp running back in gradually — we won't jump straight to where you were.

No approval button. The plan is updated. If the user disagrees, they can say so in chat and the AI adjusts further.

### 2.4 Persistent History & Context

- Chat history is stored server-side and loaded when the user opens the Chat tab
- The AI has access to previous conversations when processing new messages
- This enables continuity: "My knee is better now" → AI knows about the knee conversation from 10 days ago and triggers a run ramp-back protocol
- History also serves as an audit trail: the user can scroll back to see what changed and when

### 2.5 Proactive Check-In (V1.1 — not V1)

If the system detects 3+ consecutive missed sessions with no chat message, it surfaces a nudge (e.g., push notification or in-app banner): "You've missed a few sessions — is everything okay? Tell me what's going on and I'll adjust your plan."

This is NOT in V1 scope. Noting it here because the chat architecture should support system-initiated messages from day one.

---

## 3. What the AI Can and Cannot Do

### 3.1 Can Do (V1 Scope)

| Capability | Description |
|---|---|
| Modify sessions in current + future weeks | Swap, remove, add, or reschedule sessions within the plan |
| Substitute sports | Replace one sport with another, respecting volume ceilings |
| Reduce volume/intensity | Scale down sessions for fatigue, illness, time constraints |
| Adjust across multiple weeks | Handle "I'm traveling in 3 weeks" or "out for the next month" |
| Explain changes | Every modification comes with plain-English rationale |
| Remember past context | Use chat history to inform future adjustments |
| Apply ramp-back protocols | After injury/illness, gradually reintroduce the affected sport |

### 3.2 Cannot Do (V1)

| Limitation | Reason |
|---|---|
| Undo a previous adjustment | No snapshot/revert mechanism in V1. User can ask for further changes instead. |
| Regenerate the entire plan | Full plan regen is a separate flow (PlanGenerationView). Chat handles modifications, not rebuilds. |
| Change user profile data | FTP, VMA, CSS, race date, availability — these are profile settings, not chat concerns. |
| Prescribe medical advice | Injury/illness responses follow codified coaching rules, but always include "consult a professional" for severity >= moderate. |
| Add sessions beyond the current plan's end date | Plan has a fixed total_weeks. Chat can't extend the plan. |

### 3.3 Escalation to Plan Regeneration

If the disruption is severe enough that modification is insufficient (e.g., 4+ weeks complete rest, missed an entire phase, race date changed), the AI should recommend regenerating the plan rather than patching it:

> "Given the time you've been off, modifying the current plan won't give you a solid Build phase before your race. I'd recommend generating a fresh plan that accounts for your current fitness. You can do that from your Profile."

---

## 4. Constraint Classification & Required Information

The AI must gather specific information depending on the constraint type before making changes. This is the "enough info" check.

### 4.1 Equipment / Facility Unavailability

| Field | Required? | Example |
|---|---|---|
| Which sport(s) affected | Yes | "No pool", "bike is in the shop" |
| Duration or dates | Yes | "Next 2 weeks", "until Friday" |
| What's still available | Helpful | "I have a hotel gym with treadmill and spin bike" |

### 4.2 Physical Fatigue

| Field | Required? | Example |
|---|---|---|
| Severity signal | Yes | "Just today" vs. "all week" vs. "for weeks" |
| Specific symptoms | Helpful | "Bad sleep", "legs feel dead", "no motivation" |

No duration needed — the AI infers severity from the description and applies the appropriate protocol. Fatigue is always "starting now."

### 4.3 Injury

| Field | Required? | Example |
|---|---|---|
| Body location | Yes | "Knee", "shoulder", "achilles" |
| Which sports are painful | Yes | "Can't run, biking is ok" |
| Duration estimate | Helpful | "Doc says 2 weeks" or "don't know" |
| Severity signal | Helpful | "Slight discomfort" vs. "can't walk" |

### 4.4 Life Event

| Field | Required? | Example |
|---|---|---|
| Dates affected | Yes | "March 3-10", "next week" |
| What training is possible | Helpful | "Can run but nothing else", "no training at all" |
| Type of event | Helpful | Travel vs. work deadline (affects stress modeling) |

### 4.5 Illness

| Field | Required? | Example |
|---|---|---|
| Above or below neck | Yes | "Head cold" vs. "fever and body aches" |
| Fever present | Yes (critical) | "Yes 38.5" or "no fever" |
| When it started | Helpful | "Since Tuesday" |

---

## 5. Adjustment Rules (Summary)

Full rules with decision trees are in [plan-adjustment-research.md](plan-adjustment-research.md). Key rules the engineering team must understand:

### 5.1 Volume Ceiling Per Sport

When substituting one sport for another, the substitute volume is capped:

```
max_additional_volume_in_substitute = current_weekly_volume_in_substitute × 0.15
```

Cannot dump 4h of missing bike onto 3h of existing run. Accept the volume deficit.

**Per-sport volume** can be derived from `plan_sessions` for the affected week — no schema change needed for V1.

### 5.2 Never Double Up

Missed sessions are never made up by adding extra sessions later. Skip and move on. This is a hard rule — the AI must never propose "let's do two sessions tomorrow to catch up."

### 5.3 Constraint-Specific Phase Rules

| Constraint | Base | Build | Peak | Taper |
|---|---|---|---|---|
| Equipment | Substitute within ceilings | Same | Same | Same |
| Fatigue | Yellow flag (investigate) | Protect 1 quality session | 1-2 days extra rest is free | Extend taper if not resolving |
| Injury | Cross-train within ceilings, accept lower volume | Return to Base 3 intensity if key sport lost >2 weeks | Reassess race goal | Forced rest partially aligns with taper |
| Life event | Align with recovery week if possible | Protect brick/threshold | Race-sim session priority | Nearly free |
| Illness (above neck) | Z1-2 only | Z1-2 only | Z1-2 + strides | Z1 + strides |
| Illness (below neck) | Full stop → Base 1 on return | Full stop → Base 3 for 1 week before Build | Merge into extended taper | Full rest, accept performance hit |

### 5.4 Duration Thresholds (Across All Constraints)

| Duration | General Action |
|---|---|
| 1-3 days | Skip, resume normally |
| 4-7 days | Reframe as recovery week or reduce volume |
| 8-14 days | Roll back 1 week in plan progression |
| 14-21 days | Return to start of current phase |
| 21+ days | Consider recommending plan regeneration |

These are modified by constraint type — e.g., illness has stricter ramp-back than life events for the same duration.

### 5.5 Ramp-Back (Injury & Illness Only)

After injury:
```
Week 1: <20min, Z1, pain-free required
Week 2: +10% volume, Z1
Week 3: +10%, Z1-2
Week 4+: +10%/week, intensity only after pain-free at ≥80% pre-injury volume
```

After below-neck illness:
```
Days 1-2: Walking only
Days 3-4: Easy aerobic, 20-30min, Z1
Days 5-7: Normal aerobic, no intensity
Day 7+: Resume plan from 1-2 weeks prior
Rule: if symptoms return → drop back 1 stage, wait 24h
```

---

## 6. Architecture Considerations (For Engineering Discussion)

These are product-level observations, not prescriptions. Engineering decides the approach.

### 6.1 Chat Storage

- Messages need server-side persistence (user_id, role, content, timestamp)
- Metadata per message may be useful: constraint type detected, sessions modified, etc.
- History must be retrievable for context injection into future LLM calls

### 6.2 Plan Modification Path

The chat AI needs write access to `plan_sessions` and potentially `plan_weeks`. Today, only the `generate-plan` edge function writes to these tables (via `service_role`). The adjustment feature introduces a second write path.

Options for how the LLM produces plan changes (engineering to evaluate):
- Structured function calling (LLM outputs a JSON diff, code applies it)
- Direct DB mutation computed in code (no LLM for the actual change, only for classification + explanation)
- New LLM call with current plan state → outputs modified plan state
- Re-run parts of the existing pipeline with new constraints

### 6.3 Context Window

The LLM call needs:
- Current plan state (affected weeks — sessions, phases, volumes)
- Chat history (or a summary of it for long histories)
- Adjustment rules (system prompt with constraint-specific logic)
- User profile (availability, sport days, metrics)

For a 20-week plan, injecting the full plan may be too large. The system should scope to affected weeks + surrounding context (e.g., current week ± 4 weeks, plus phase metadata for the full plan).

### 6.4 Latency

Users expect chat to feel responsive. Plan generation takes 50-65s — that's unacceptable for chat. The adjustment call should target <10s. This likely means:
- Smaller model or fewer tokens than full plan generation
- Scoped context (not the full plan)
- Possibly a faster model for classification + a reasoning model for the actual adjustment

### 6.5 Per-Sport Volume Derivation

The volume ceiling rule requires per-sport weekly volume. This can be derived from existing `plan_sessions` data:

```sql
SELECT sport, SUM(duration_minutes) as weekly_minutes
FROM plan_sessions
WHERE week_id = [current_week_id]
GROUP BY sport
```

No schema change needed for V1.

---

## 7. Scope & Phasing

### V1 (Ship First)

- Chat tab with persistent history
- Free-text input, AI-driven conversation
- 5 constraint types handled (equipment, fatigue, injury, life event, illness)
- Plan modification for current week + future weeks (no limit on how far ahead)
- Plain-English explanation of every change
- Ramp-back protocols for injury and illness
- Volume ceiling enforcement on substitutions

### V1.1 (Fast Follow)

- Quick-reply buttons for common scenarios (accelerator, not replacement for free text)
- Proactive check-in when sessions are missed
- Post-adaptation feedback ("How did last week feel given the changes?")

### V2 (Later)

- Wearable data integration (HRV, resting HR) feeding into fatigue detection
- Undo/revert mechanism (plan state snapshots)
- Session completion tracking feeding back into adaptation quality
- Plan regeneration triggered from chat when modification isn't enough

---

## 8. Success Metrics

| Metric | Target | Why |
|---|---|---|
| Chat adoption | >40% of active users send at least 1 message within first month | Validates the entry point is discoverable and useful |
| Messages to resolution | ≤3 messages per adjustment (user message + 1 follow-up + confirmation) | Validates the AI is gathering info efficiently |
| Plan modification accuracy | <5% of adjustments require user correction via follow-up | Validates the rules are correct |
| Retention impact | Users who use chat retain at 2x rate of those who don't | Validates the "feels like a coach" hypothesis |
| Response latency | <10s for plan modification response | Chat must feel conversational |

---

## 9. Open Questions for Engineering

1. **LLM model selection for chat** — Do we use the same GPT-4o as plan generation, or a faster/cheaper model? Classification could use a small model; adjustment reasoning may need GPT-4o.

2. **Write path for plan modifications** — How do we handle the second write path to `plan_sessions`? New edge function? Extend existing one? Client-side with service role?

3. **Chat history context management** — How much history do we inject per call? Full history, last N messages, or a running summary?

4. **Offline/sync** — What happens if the user sends a chat message with no connectivity? Queue and process later, or require connectivity?

5. **Rate limiting** — Should we limit how many plan modifications per day/week? Users could theoretically re-adjust every day, which could destabilize the plan.

6. **Testing/eval framework** — How do we validate that adjustments are correct? Can we extend the existing eval framework (batch-eval) with adjustment scenarios?

---

## 10. Competitive Deep-Dive: Humango's Hugo (Lessons Learned)

Hugo is the closest competitor to what we're building — a ChatGPT-powered conversational AI coach. Understanding its architecture and failure modes directly informs our design.

### 10.1 How Hugo Works

- **Architecture:** ChatGPT with a system prompt + user plan context injected. Not function-calling or agentic — a thin conversational wrapper on top of Humango's pre-existing algorithmic replanning engine.
- **Flow:** User says something ("I need a day off") → Hugo extracts intent → fires Humango's backend algorithm → confirms back. Mostly single-turn.
- **No structured ask-vs-act decision tree.** Hugo does not have follow-up logic. It acts on whatever info it gets.

### 10.2 Hugo's Failure Mode: Under-Asking

Hugo's critical failure is **acting on insufficient information without asking for clarification:**
- User says "I'm not feeling great" → Hugo adjusts without asking if it's fatigue, illness, or injury
- No follow-up questions about severity, affected sports, or duration
- Changes happen silently — user must check the calendar to discover what changed
- No explanation of reasoning or what was modified

This is the opposite of the over-asking problem. Users get **actions without understanding**, not interrogation without action.

### 10.3 User Feedback on Hugo

| Signal | Source |
|---|---|
| "Hugo was laughably bad and pretty much useless" | Athletica Forum user (switched away) |
| "The AI doesn't seem to respond to changes or failures in performance anymore" | Google Play review (post-2024 update) |
| "It's not THAT smart but it's the best thing until I can find an actual coach" | App Store review |
| "Less of a coach, more of a triathlon-savvy scheduling assistant" | Review consensus |
| Hugo cannot provide technical support — users expected coaching, got logistics | App Store complaint |

### 10.4 What We Learn for Dromos

| Hugo's Weakness | Our Design Response |
|---|---|
| Acts on ambiguous input without clarifying | **90% rule:** act when ≥90% of required info is present, ask when less. Never act on <60% info. |
| No follow-up questions | **Targeted follow-ups:** 1-2 max, asking for the most critical missing field (e.g., fever check for illness) |
| No explanation of what changed | **Every adjustment includes plain-English rationale** in the chat, with before/after volume numbers |
| Changes are silent — user checks calendar | **Changes are communicated in-chat** with specific session-level detail |
| Conversation quality degraded after updates | **Codified rules in system prompt + eval framework** — regression-testable, not a fragile system prompt |
| Stateless context — doesn't remember past issues | **Persistent chat history** fed into every LLM call — "my knee is better" triggers ramp-back from the previous conversation |
| No structured safety gates | **Fever/illness safety gate** — always asks about fever if not mentioned. Hard rule, not LLM judgment. |

### 10.5 The Conversation Design Principle

Hugo proves that **the risk is under-asking, not over-asking.** Users will tolerate 1-2 quick clarifying questions if it means the plan change is correct and explained. They will NOT tolerate a silent wrong adjustment.

Our design: **ask precisely, act confidently, explain thoroughly.**

---

## 11. Competitive Positioning

This feature, if executed well, makes Dromos the **only triathlon app where the plan adjustment is transparent, conversational, and sport-aware**:

- **vs. Athletica:** We explain why. They don't. We handle injury by body part. They have a generic tab.
- **vs. Humango:** Hugo acts without asking or explaining. We ask the right questions, then explain every change. Hugo is a scheduling wrapper — we're a coaching engine.
- **vs. TriDot:** We actually adapt. They claim to but users report otherwise.
- **vs. TrainerRoad:** We cover all 3 sports with equal depth. They're cycling-first.
- **vs. Mottiv:** We're AI-driven. They're manual drag-and-drop.

The moat is that this requires an LLM-native architecture (which we have) combined with sport-specific coaching rules (which we've codified). Template-based competitors can't replicate this without rebuilding their engines.
