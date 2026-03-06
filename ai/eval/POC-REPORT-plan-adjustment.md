# Plan Adjustment PoC — Report

**Date:** 2026-02-22
**Linear:** DRO-132
**Model:** gpt-4o | Temperature: 0
**Prompt iterations:** Step 1: 5 | Step 2: 3

---

## TLDR

The 2-step pipeline (conversation → coaching brain) works. The LLM reliably classifies constraints, asks the right follow-up questions, and produces structurally sound macro diffs. The main finding: **volume ceiling math must be enforced in code, not by the LLM** — the model understands the rule but does the arithmetic wrong ~30% of the time.

---

## Results Summary

| Test Suite | Pass Rate | Scenarios | Iterations |
|---|---|---|---|
| Step 1 (Conversation) | 9/10 (90%) | 6 single-turn + 4 multi-turn | 5 |
| Step 2 (Coaching Brain) | 9/10 (90%) | 4 local + 4 structural + 2 context | 3 |
| E2E (Pipeline) | 1/3 pipeline + plan quality | 3 integration | 1 |
| E2E (Pipeline checks only) | 3/3 (100%) | — | — |
| E2E (Plan quality checks only) | 2/3 (67%) | — | — |

### Latency

| Metric | Avg | Min | Max |
|---|---|---|---|
| Step 1 alone | 3.2s | 0.7s/turn | 4.4s |
| Step 2 alone | 4.6s | 2.1s | 7.7s |
| E2E total (S1 + S2) | 7.2s | 6.1s | 9.0s |

All under the 10s target from the product spec.

---

## Key Findings

### 1. Volume ceiling: LLM understands the rule, fails the math

The LLM consistently shows ceiling calculations in its output (`current swim = 90min, ceiling = 90 × 1.15 = 103.5min, adding 22min → total 112min [OK]`) — but 112min > 103.5min. It marks violations as "OK."

**Impact:** When substituting a removed sport (e.g., run injury → add swim), the LLM adds 15-22min to a sport with only 9-14min of ceiling headroom.

**Recommendation:** Volume ceiling enforcement must be a **post-processing fixer**, not prompt logic. The fixer already exists conceptually in `fixDurationCaps()` — extend it to enforce per-sport ceiling during adjustments. The LLM should still _attempt_ ceiling compliance (it guides reasonable substitution amounts) but code must be the safety net.

### 2. Constraint classification is reliable

Step 1 correctly classifies constraints across all 4 types (equipment, fatigue, injury, illness) in 10/10 scenarios. The `life_event` type was killed during iteration — it's never the actual constraint, just the cause. Travel → equipment. Work stress → fatigue.

### 3. Required field gating works after iteration

The "act immediately when all REQUIRED fields are filled" principle took 3 iterations to land. Key anti-patterns that had to be explicitly banned:
- **Duration fishing for injuries:** the athlete doesn't know how long it'll last
- **Confirmation questions:** "Is that right?" — wastes a turn
- **HELPFUL field fishing:** asking about optional fields when REQUIRED ones are complete

These should carry into the production prompt unchanged.

### 4. Fever gate works naturally

Fever is a REQUIRED field for illness. No hard-coded safety gate needed — the LLM asks about fever as part of normal field gathering. Tested in both Step 1 standalone (A3, B3) and E2E (E2E_3). Works reliably at temp 0.

### 5. Cascading rules work in prompt

The LLM handles cascading correctly:
- **Fatigue before recovery week (D1):** correctly pushes recovery to avoid back-to-back easy weeks
- **Long injury during Build (D2):** removes affected sport, substitutes within ceiling, preserves taper timing, includes ramp-back
- **Peak illness near race (D3):** full stop, health > fitness principle, merges into taper

These are prompt-solvable and don't need post-processing fixers.

### 6. Chat history injection needs strengthening

Context continuity (E-category) is the weakest area:
- **E1 (injury recovery):** applies ramp-back correctly but doesn't always explicitly reference the previous conversation
- **E2 (repeated fatigue):** escalates response (3/4 runs) but sometimes repeats the same 25% reduction instead of going more aggressive

**Recommendation:** In production, inject a structured context summary (not raw chat history) — e.g., `Previous adjustments: [{ date, type, action_taken, outcome }]`. This gives the LLM clearer signal than free-text history.

### 7. Diff format is parseable but inconsistent

Step 2 output format varies between runs:
- Sport/type ordering: sometimes `Tempo bike`, sometimes `bike Tempo`
- Day names: sometimes included, sometimes omitted
- Volume line: consistent `Volume: Xh → Yh` format

The diff applier handles this with flexible regex, but for production, the output should be structured JSON (not markdown). Markdown is fine for human review during the PoC but not for programmatic application.

---

## Known Failures (Accepted)

| Scenario | Failure | Root Cause | Decision |
|---|---|---|---|
| Step 1 A4 | JSON emission ~80% reliable | LLM says "I'll note this" but doesn't emit JSON | Known formatting issue. Will resolve with structured output/function calling in production. |
| Step 2 E2 | Root cause flag ~75% reliable | LLM sometimes omits overtraining/sleep investigation | Borderline — passes most runs. Acceptable for V1. |
| E2E equipment | Equipment acknowledgment flaky | LLM sometimes omits "treadmill/spin bike" mention | Cosmetic — substitution is correct regardless. |

---

## Architectural Recommendations

### For V1 Implementation

1. **Step 1 (Conversation) → Keep as prompt-only LLM call**
   - Conversation agent works well with prompt logic alone
   - Use function calling / structured output for the terminal JSON (fixes A4 reliability)
   - Inject structured context summary for chat history (fixes E-category weakness)

2. **Step 2 (Coaching Brain) → Prompt + post-processing fixer**
   - Prompt handles rule selection, cascading, and ramp-back correctly
   - **Add a volume ceiling fixer** that runs after the LLM output:
     - Parse ADD lines, compute actual ceiling per sport
     - Cap any ADD that exceeds 15% of original sport volume
     - Log the correction for transparency
   - Output as structured JSON (not markdown diff) for programmatic application

3. **Steps 3-4 (JSON format + template selection) → Skip for PoC**
   - The existing `generate-plan` pipeline's Steps 3-4 can be reused
   - The macro diff from Step 2 maps directly to session-level changes
   - No separate PoC needed — proceed to implementation

4. **Post-processing fixers to extend for adjustments:**
   - `fixDurationCaps()` → add per-sport ceiling enforcement
   - `fixIntensitySpread()` → run on modified weeks to prevent new intensity conflicts
   - `fixBrickPairs()` → ensure brick sessions aren't broken by substitutions

### Model Choice

gpt-4o at temp 0 works for both steps. For production:
- Step 1: gpt-4o-mini may suffice (simpler task, lower latency)
- Step 2: keep gpt-4o (needs strong reasoning for cascading rules)

---

## Files Created

| File | Purpose |
|---|---|
| `ai/prompts/adjust-step1-conversation.txt` | Step 1 conversation agent prompt (138 lines) |
| `ai/prompts/adjust-step2-coaching-brain.txt` | Step 2 coaching brain prompt (167 lines) |
| `ai/eval/vars/adjust-step1-scenarios.yaml` | 10 Step 1 test scenarios |
| `ai/eval/vars/adjust-step2-scenarios.yaml` | 10 Step 2 test scenarios |
| `ai/eval/poc-adjust-step1.js` | Step 1 PoC runner |
| `ai/eval/poc-adjust-step2.js` | Step 2 PoC runner |
| `ai/eval/poc-adjust-e2e.js` | E2E integration runner (S1 → S2 → diff apply → plan validate) |

---

## Decisions Made During PoC

| Decision | Rationale |
|---|---|
| Kill `life_event` constraint type | Life events are causes, not constraints. Travel = equipment. Work stress = fatigue. 4 types: equipment, fatigue, injury, illness. |
| JSON only at terminal states | Plain English during conversation, JSON only when ready/no_action/escalate. Simpler for both LLM and parsing. |
| Phase map in Step 1 | Cheap context (~20 rows). Helps LLM ask smarter questions (e.g., aware next week is recovery). |
| Temperature 0 | Temp 0.4 caused inconsistent behavior (regressions between runs). Zero gives deterministic results. |
| Don't hard-code fever safety gate | Fever is REQUIRED for illness like any other required field. No special treatment needed. |
| Accept moderate severity for illness with fever | Don't overfit severity classification — coaching engine handles downstream decisions. |
| No duration fishing for injuries/illness | Athletes don't know how long it'll last. Start by removing sessions, ask again later. |

---

## Next Steps

1. Create full tech spec for V1 implementation (DRO-XXX)
2. Design structured output schema for Step 1 (replace free-text JSON with function calling)
3. Design structured output schema for Step 2 (replace markdown diff with JSON diff)
4. Extend `fixDurationCaps()` for per-sport volume ceiling enforcement
5. Design chat storage schema (`chat_messages` table)
6. Design adjustment tracking schema (which sessions were modified, why, when)
