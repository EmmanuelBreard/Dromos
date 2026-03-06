# DRO-132 PoC: Chat Plan Adjustment — 4-Step Pipeline Validation

**Overall Progress:** `100%`

## TLDR

Standalone Node.js scripts (same stack as existing eval framework — PromptFoo + OpenAI SDK) that validate the 4-step adjustment pipeline against real plan data. Tests each step independently: (1) conversation agent gathers info and outputs a structured constraint summary, (2) coaching brain produces a macro-level adjustment diff for affected weeks only, (3) format conversion to JSON session changes, (4) template selection for new sessions (reuses existing Step 3). Focus is on Steps 1-2 (new, risky). Steps 3-4 reuse existing infrastructure. Run locally, no iOS or edge function needed.

## Pipeline Architecture Being Validated

```
Step 1: Conversation Agent
  Input:  user message + chat history + constraint rules
  Output: structured constraint summary (type, affected sports, duration, severity)
  Notes:  multi-turn — asks follow-ups until it has enough info, then emits summary
          no hard follow-up cap — prompt defines required fields per constraint type,
          LLM decides when it has enough

Step 2: Coaching Brain (mirrors generate-plan Step 1)
  Input:  constraint summary + full phase map (all weeks) + session detail (affected weeks only) + user profile
  Output: markdown macro diff — what changes per affected week (sport/type/duration per session, week restructuring)
  Notes:  rewrites ONLY impacted weeks. must be periodization-aware (recovery week conflicts, phase compression)

Step 3: Format Conversion (mirrors generate-plan Step 2)
  Input:  macro diff from Step 2
  Output: structured JSON — array of {action: delete|update|insert, session fields}
  Notes:  uses gpt-4o-mini. pure conversion, no reasoning.

Step 4: Template Selection (mirrors generate-plan Step 3)
  Input:  JSON session changes + workout library
  Output: template_id + final session fields for each insert/update
  Notes:  reuses existing Step 3 prompt pattern + post-processing fixers
```

## What This PoC Answers

| Question | Risk Level | Step | How We Test |
|---|---|---|---|
| **Does the conversation agent gather info correctly and know when to stop?** | Highest | 1 | 10 scenarios at varying info completeness — validate constraint summary output |
| **Does the coaching brain make correct periodization decisions?** | Highest | 2 | 10 scenarios with hardcoded constraints — validate macro diff respects rules |
| **Does the coaching brain handle cascading changes?** | High | 2 | Scenarios where local changes force structural ripple effects (recovery week conflict, phase compression) |
| **Does the end-to-end pipeline produce coherent results?** | High | 1→2 | 3 integration scenarios — Step 1 output feeds into Step 2, validate final macro diff |
| **Is the scoped context (affected weeks + full phase map) sufficient?** | Medium | 2 | Compare output quality with scoped vs. full plan context |
| **Is post-conversation latency acceptable?** | Medium | 2+3+4 | Measure wall-clock time for Steps 2-4 sequentially (target: <15s total) |

## Success Criteria

- **Step 1 — Conversation flow:** ≥90% of scenarios produce correct behavior (ask when info missing, act when info complete, constraint summary matches expected fields)
- **Step 2 — Coaching decisions:** ≥90% of scenarios produce correct macro adjustments (volume ceiling respected, cascading handled, phase rules followed)
- **Step 2 — Cascading:** 100% of recovery-week-conflict scenarios correctly push/swap the recovery week
- **End-to-end:** ≥80% of integration scenarios produce coherent results across Step 1 → Step 2
- **Latency:** Steps 2+3+4 sequential < 15s p95
- **If any criteria fails:** iterate on the relevant prompt. 3 iterations max per step. If still failing, flag to product.

## Critical Decisions

- **4-step pipeline, not single LLM call** — mirrors generate-plan architecture. Each step has a bounded responsibility. Steps can be tested independently.
- **No hard follow-up cap** — the conversation prompt defines required fields per constraint type. The LLM decides when it has enough info based on those requirements. No arbitrary "max 2 questions" limit.
- **LLM does NOT pick templates** — Step 1-2 focus on coaching reasoning. Template selection is Step 4, reusing existing infrastructure. The coaching prompt never sees the workout library.
- **Step 2 rewrites only affected weeks** — if the constraint impacts weeks 5-7, Step 2 outputs a macro plan for just those weeks. All other weeks are untouched.
- **Full phase map as context** — Step 2 receives the phase skeleton for ALL weeks (week_number, phase, is_recovery — ~20 rows of metadata) so it can detect cascading conflicts. Session detail is scoped to affected weeks only.
- **PoC tests Steps 1-2 deeply, Steps 3-4 lightly** — Steps 3-4 reuse existing patterns. The risk is in the new coaching logic.
- **4 constraint types, not 5** — `life_event` killed during PoC. Life events are causes, not constraints: travel → equipment, work stress → fatigue.
- **Temperature 0** — temp 0.4 caused inconsistent behavior between runs. Zero gives deterministic results.
- **Volume ceiling = post-processing fixer** — LLM understands the rule but fails arithmetic ~30% of the time. Code must enforce.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `ai/eval/poc-adjust-step1.js` | CREATE | Step 1 PoC — conversation agent scenarios |
| `ai/eval/poc-adjust-step2.js` | CREATE | Step 2 PoC — coaching brain scenarios |
| `ai/eval/poc-adjust-e2e.js` | CREATE | End-to-end integration (Step 1 → Step 2, 3 scenarios) |
| `ai/prompts/adjust-step1-conversation.txt` | CREATE | Step 1 prompt — conversation rules, required fields per constraint, output schema |
| `ai/prompts/adjust-step2-coaching-brain.txt` | CREATE | Step 2 prompt — adjustment rules, volume ceilings, phase logic, ramp-back, output format |
| `ai/eval/vars/adjust-step1-scenarios.yaml` | CREATE | 10 conversation scenarios |
| `ai/eval/vars/adjust-step2-scenarios.yaml` | CREATE | 10 coaching decision scenarios (with hardcoded constraint summaries) |
| `ai/eval/assertions/validate-adjustment.js` | SKIPPED | Validators inline in PoC scripts instead (simpler) |

## Tasks

- [x] 🟩 **Phase 1: Step 1 Prompt + Scenarios (Conversation Agent)**

  - [x] 🟩 Create `ai/prompts/adjust-step1-conversation.txt`
    - Role: "You are the intake agent for Dromos training plan adjustments..."
    - Define 5 constraint types with required fields per type (from product spec Section 4)
    - Instructions: "Classify the constraint from the user's message. Check which required fields are present vs. missing. If critical info is missing, ask ONE targeted follow-up question. When you have enough information to make an adjustment, output a structured constraint summary."
    - Illness safety gate: "If illness is mentioned and fever status is unknown, you MUST ask about fever before proceeding. This is a safety-critical question."
    - No hard follow-up cap — the LLM reads the required fields and decides
    - Output schema when ready to act:
      ```json
      {
        "status": "ready" | "need_info" | "no_action" | "escalate",
        "response_text": "Plain English response to user",
        "constraint_summary": {
          "type": "equipment | fatigue | injury | illness",
          "affected_sports": ["run"],
          "available_sports": ["swim", "bike"],
          "duration": "2 weeks",
          "severity": "moderate",
          "details": "Knee pain, can't run, biking OK if easy, swim fine",
          "phase_impact": "structural"
        }
      }
      ```
    - `phase_impact`: `"local"` (only current/next week) vs. `"structural"` (multi-week ripple expected) — guides Step 2's scope

  - [x] 🟩 Create `ai/eval/vars/adjust-step1-scenarios.yaml` — 10 scenarios:

  **Category A: Single-Turn Info Completeness (6 scenarios)**

  ```yaml
  - id: A1_injury_vague
    constraint: injury
    messages:
      - role: user
        content: "Something hurts"
    expected_status: need_info
    expected_follow_up_targets: [body_location, which_sports_painful]
    notes: "Extremely vague — must ask for body part AND sport impact"

  - id: A2_injury_almost_complete
    constraint: injury
    messages:
      - role: user
        content: "My knee has been hurting since Tuesday, I can't run but biking is fine"
    expected_status: ready
    expected_constraint_summary:
      type: injury
      affected_sports: [run]
      available_sports: [bike, swim]
    notes: "Has body part + sport eligibility + implicit duration. Should act."

  - id: A3_illness_must_ask_fever
    constraint: illness
    messages:
      - role: user
        content: "I've got a cold, runny nose and sneezing"
    expected_status: need_info
    expected_follow_up_targets: [fever]
    notes: "CRITICAL: must ask about fever even though above-neck symptoms are clear"

  - id: A4_illness_complete_severe
    constraint: illness
    messages:
      - role: user
        content: "I've had a fever of 38.5 since yesterday with body aches and chest congestion"
    expected_status: ready
    expected_constraint_summary:
      type: illness
      severity: severe
    notes: "Below neck + fever = full stop. Must act immediately."

  - id: A5_equipment_travel
    constraint: equipment
    messages:
      - role: user
        content: "I'm traveling to London March 3-10. Hotel has a gym with treadmill and spin bike but no pool."
    expected_status: ready
    expected_constraint_summary:
      type: equipment
      affected_sports: [swim]
      available_sports: [run, bike]
      duration: "March 3-10"
    notes: "All info provided. Should act. (life_event killed — travel = equipment)"

  - id: A6_not_a_disruption
    messages:
      - role: user
        content: "Thanks for adjusting my plan last week, it felt great!"
    expected_status: no_action
    notes: "Should respond conversationally, NOT classify as constraint"
  ```

  **Category B: Multi-Turn Conversations (4 scenarios)**

  ```yaml
  - id: B1_injury_converge
    constraint: injury
    messages:
      - role: user
        content: "I hurt myself"
      - role: assistant
        content: null  # AI generates — validate it asks about body part
      - role: user
        content: "It's my shoulder"
      - role: assistant
        content: null  # AI generates — should ask about sport impact
      - role: user
        content: "I can bike and run fine but swimming is painful"
    expected_final_status: ready
    expected_constraint_summary:
      type: injury
      affected_sports: [swim]
      available_sports: [bike, run]
    notes: "Must converge naturally — no hard cap, but should resolve efficiently"

  - id: B2_fatigue_one_turn
    constraint: fatigue
    messages:
      - role: user
        content: "I'm feeling really tired"
      - role: assistant
        content: null  # Should ask: just today or ongoing?
      - role: user
        content: "All week, my legs feel like lead and I'm sleeping badly"
    expected_final_status: ready
    expected_constraint_summary:
      type: fatigue
      severity: accumulated
    notes: "Severity now clear. Should act."

  - id: B3_illness_fever_gate
    constraint: illness
    messages:
      - role: user
        content: "I've got a cold"
      - role: assistant
        content: null  # MUST ask about fever
      - role: user
        content: "No fever, just runny nose and sneezing"
    expected_final_status: ready
    expected_constraint_summary:
      type: illness
      severity: mild
    notes: "Above-neck, no fever → Z1-2 only. Critical that it asks fever question."

  - id: B4_escalation
    messages:
      - role: user
        content: "I broke my leg and I'll be in a cast for 8 weeks"
    expected_final_status: escalate
    notes: "8 weeks = beyond modification scope. Should recommend plan regen."
  ```

- [x] 🟩 **Phase 2: Step 2 Prompt + Scenarios (Coaching Brain)**

  - [x] 🟩 Create `ai/prompts/adjust-step2-coaching-brain.txt`
    - Role: "You are the coaching engine for Dromos plan adjustments. Given a constraint summary and the current plan state, produce a macro-level adjustment plan for the affected weeks..."
    - Input context:
      - Constraint summary (from Step 1)
      - Full phase map: `[{ week: 1, phase: "Base", is_recovery: false }, ...]` for ALL weeks
      - Session detail for affected weeks: `[{ week: 5, sessions: [{day, sport, type, duration_minutes}] }]`
      - Per-sport weekly volumes for affected weeks
      - User profile (availability, metrics)
    - Rules (from product spec Section 5):
      - Volume ceiling formula: `max_additional = current_weekly_volume_in_sport × 0.15`
      - Never double up (missed sessions are NOT made up)
      - Phase-specific rules table (Section 5.3)
      - Duration thresholds (Section 5.4)
      - Ramp-back protocols for injury and illness (Section 5.5)
      - Cascading rules:
        - "If reducing this week and the NEXT week is already a recovery week, push the recovery week later to avoid two consecutive easy weeks"
        - "If a constraint removes a key sport for 2+ weeks during Build, consider compressing remaining Build and protecting Peak timing"
        - "Race date is fixed. Taper timing is sacred. All cascading must preserve taper start."
    - Output format: markdown macro diff per affected week
      ```
      ## Week 5 (Build W2) — MODIFIED
      - REMOVE: Thursday tempo run (knee injury)
      - REMOVE: Saturday long run (knee injury)
      - KEEP: Wednesday swim intervals (unchanged)
      - KEEP: Tuesday easy bike (unchanged)
      - ADD: Friday easy swim, ~45min (substitute within ceiling: current swim = 3h, ceiling = 3h27m, adding 45m → 3h45m OK)
      - Volume: 6h → 4.2h (deficit accepted)

      ## Week 6 (Build W3 — was Recovery) — RESTRUCTURED
      - SWAP: Recovery week pushed to Week 7 (avoid back-to-back easy weeks after injury reduction)
      - Sessions: normal Build W3 load, minus running
      ```
    - `phase_impact` from Step 1 guides scope:
      - `"local"` → Step 2 receives affected week ± 1 week of sessions
      - `"structural"` → Step 2 receives affected weeks + all downstream weeks until end of current phase (or plan end)

  - [x] 🟩 Create `ai/eval/vars/adjust-step2-scenarios.yaml` — 10 scenarios:

  **Category C: Local Adjustments (4 scenarios)**
  Input: hardcoded constraint summaries (no conversation needed)

  ```yaml
  - id: C1_volume_ceiling
    constraint_summary:
      type: equipment
      affected_sports: [bike]
      available_sports: [swim, run]
      duration: "2 weeks"
      severity: moderate
      phase_impact: local
    plan_context:
      current_week: { phase: "Build", week_in_block: 2, is_recovery: false }
      current_volumes: { swim: 180, bike: 240, run: 150 }  # minutes
    validation:
      - "Run volume increase ≤ 15% of 150min (≤ 22min additional)"
      - "Swim volume increase ≤ 15% of 180min (≤ 27min additional)"
      - "Total volume will be lower than planned — deficit accepted, not filled"
    notes: "Volume ceiling is the key rule. Must NOT dump 240min bike onto run/swim."

  - id: C2_illness_full_stop
    constraint_summary:
      type: illness
      severity: severe
      details: "Fever 39°C, chest congestion"
      phase_impact: structural
    plan_context:
      current_week: { phase: "Build", week_in_block: 3, is_recovery: false }
    validation:
      - "ALL sessions removed for remaining days this week"
      - "No sessions added as substitute"
      - "Macro diff mentions ramp-back protocol for return"
      - "Next week sessions reduced or removed depending on recovery"
    notes: "Below-neck illness = zero training. No substitution."

  - id: C3_no_double_up
    constraint_summary:
      type: fatigue
      duration: "this week (already passed)"
      details: "All sessions this week were missed — the week is over. Athlete is asking about next week."
      phase_impact: local
    plan_context:
      current_week: { phase: "Build", week_in_block: 2, is_recovery: false }
    validation:
      - "Does NOT add missed sessions to next week"
      - "Macro diff explicitly states: skip and move on"
    notes: "Never double up rule — Friel's principle"

  - id: C4_phase_awareness_build_fatigue
    constraint_summary:
      type: fatigue
      severity: accumulated
      details: "Exhausted all week, legs like lead, poor sleep"
      phase_impact: local
    plan_context:
      current_week: { phase: "Build", week_in_block: 2, is_recovery: false }
    validation:
      - "Keeps exactly 1 quality session (brick or threshold)"
      - "Converts other quality sessions to Easy"
      - "Volume reduced by ~20-30%"
    notes: "Build phase fatigue: protect 1 quality session"
  ```

  **Category D: Structural / Cascading Adjustments (4 scenarios)**

  ```yaml
  - id: D1_fatigue_before_recovery_week
    constraint_summary:
      type: fatigue
      severity: accumulated
      details: "Exhausted, everything feels hard"
      phase_impact: structural
    plan_context:
      current_week: { week: 5, phase: "Build", week_in_block: 3, is_recovery: false }
      next_week: { week: 6, phase: "Build", week_in_block: 4, is_recovery: true }
      phase_map: [
        { week: 5, phase: "Build", is_recovery: false },
        { week: 6, phase: "Build", is_recovery: true },
        { week: 7, phase: "Build", is_recovery: false },
        { week: 8, phase: "Build", is_recovery: false }
      ]
    validation:
      - "Current week reduced (easy + shorter sessions)"
      - "Recovery week (W6) pushed to W7 or kept but W7 becomes loading"
      - "Must NOT have two consecutive easy/recovery weeks"
      - "Reasoning explains why recovery was moved"
    notes: "KEY SCENARIO: fatigue + next week is recovery = must cascade to avoid 2 easy weeks back-to-back"

  - id: D2_long_injury_compress_build
    constraint_summary:
      type: injury
      affected_sports: [run]
      available_sports: [swim, bike]
      duration: "3 weeks"
      severity: moderate
      phase_impact: structural
    plan_context:
      current_week: { week: 8, phase: "Build", week_in_block: 2, is_recovery: false }
      phase_map: [
        { week: 8, phase: "Build", is_recovery: false },
        { week: 9, phase: "Build", is_recovery: false },
        { week: 10, phase: "Build", is_recovery: true },
        { week: 11, phase: "Peak", is_recovery: false },
        { week: 12, phase: "Peak", is_recovery: false },
        { week: 13, phase: "Taper", is_recovery: false },
        { week: 14, phase: "Race", is_recovery: false }
      ]
    validation:
      - "Removes run sessions for weeks 8-10"
      - "Substitutes within volume ceiling (swim/bike ≤ +15%)"
      - "Does NOT shift taper/race timing"
      - "Includes run ramp-back protocol starting week 11"
      - "May suggest compressing remaining Build or simplifying Peak"
    notes: "3-week injury during Build — must protect Peak/Taper timing, accept fitness deficit"

  - id: D3_peak_illness
    constraint_summary:
      type: illness
      severity: severe
      details: "Fever 38.2, body aches, race in 12 days"
      phase_impact: structural
    plan_context:
      current_week: { week: 12, phase: "Peak", week_in_block: 1, is_recovery: false }
      phase_map: [
        { week: 12, phase: "Peak", is_recovery: false },
        { week: 13, phase: "Taper", is_recovery: false },
        { week: 14, phase: "Race", is_recovery: false }
      ]
    validation:
      - "Full stop on all training"
      - "Macro diff mentions merging into taper or extended taper"
      - "Macro diff mentions 'arriving healthy > arriving sharp' or equivalent"
      - "Ramp-back protocol respects illness severity — no intensity before race"
    notes: "Peak + severe illness = merge into taper. Race goal may need adjustment."

  - id: D4_travel_with_equipment_change
    constraint_summary:
      type: equipment
      affected_sports: [swim]
      available_sports: [run, bike]
      duration: "March 3-10"
      details: "Hotel gym: treadmill + spin bike, no pool"
      phase_impact: local
    plan_context:
      current_week: { week: 7, phase: "Build", week_in_block: 1, is_recovery: false }
      current_volumes: { swim: 150, bike: 210, run: 120 }
    validation:
      - "Removes swim sessions for affected dates only"
      - "Substitution within volume ceiling"
      - "Swim resumes immediately after return (no ramp-back — equipment, not injury)"
      - "Accounts for available equipment (treadmill + spin bike)"
    notes: "Equipment-based life event — clean substitution, no cascading needed"
  ```

  **Category E: Context Continuity (2 scenarios)**

  ```yaml
  - id: E1_context_recovery_from_injury
    constraint_summary:
      type: injury
      details: "Knee is better now"
      affected_sports: []  # no longer affected
      phase_impact: local
    chat_history:
      - role: user
        content: "My knee has been hurting, can't run"
        created_at: "2026-02-11"
      - role: assistant
        content: "I've removed your run sessions for this week and next..."
        created_at: "2026-02-11"
    plan_context:
      current_week: { week: 9, phase: "Build", week_in_block: 3 }
    validation:
      - "Reintroduces running with ramp-back (not at full volume)"
      - "References the previous knee conversation"
      - "Run ramp-back: starts at <20min Z1"
    notes: "Tests chat history context — AI must know about the previous injury"

  - id: E2_repeated_fatigue
    constraint_summary:
      type: fatigue
      severity: accumulated
      details: "Still tired, last week's reduction didn't help"
      phase_impact: structural
    chat_history:
      - role: user
        content: "I'm exhausted all week"
        created_at: "2026-02-15"
      - role: assistant
        content: "I've reduced your volume by 25% this week, keeping your threshold bike..."
        created_at: "2026-02-15"
    plan_context:
      current_week: { week: 10, phase: "Build", week_in_block: 4 }
    validation:
      - "More aggressive reduction than first time (previous 25% wasn't enough)"
      - "May convert current week to full recovery"
      - "References previous fatigue conversation"
      - "May suggest investigating root cause (overtraining, life stress)"
    notes: "Recurring fatigue — AI must escalate response, not repeat same reduction"
  ```

- [x] 🟩 **Phase 3: PoC Scripts + Validators**

  - [x] 🟩 Create `ai/eval/poc-adjust-step1.js` (Node.js script, uses OpenAI SDK + dotenv)
    - Load test plan from `ai/eval/vars/step2-inputs.yaml` (reuse existing Emmanuel Half-Ironman plan)
    - Load scenarios from `ai/eval/vars/adjust-step1-scenarios.yaml`
    - For each scenario:
      1. Build Step 1 prompt with constraint rules + plan phase summary
      2. Loop: send user message → get AI response → if `need_info`, continue with next user message → if `ready`/`no_action`/`escalate`, stop
      3. Validate: does the output `constraint_summary` match expected fields?
      4. Record: number of AI turns, final status, constraint summary, follow-up quality, wall-clock latency per turn
    - Output: results table per scenario + pass/fail per check
    - Use `OPENAI_API_KEY` from `.env`, model: gpt-4o

  - [x] 🟩 Create `ai/eval/poc-adjust-step2.js` (Node.js script)
    - Load test plan from `ai/eval/vars/step2-inputs.yaml`
    - Load scenarios from `ai/eval/vars/adjust-step2-scenarios.yaml`
    - For each scenario:
      1. Build Step 2 prompt with: hardcoded constraint summary + phase map + scoped session detail + user profile
      2. Single LLM call (gpt-4o, temp 0)
      3. Parse macro diff output
      4. Run validation checks per scenario
      5. Record: macro diff text, validation pass/fail, wall-clock latency
    - Output: results table + validation details

  - [x] 🟩 Create `ai/eval/poc-adjust-e2e.js` (Node.js script)
    - 3 integration scenarios: run Step 1 → feed constraint_summary into Step 2 → validate final macro diff
    - Measures total latency (Step 1 final turn + Step 2)
    - Validates that the contract between steps works (Step 1 output is valid Step 2 input)

  - [x] 🟩 Create `ai/eval/assertions/validate-adjustment.js`
    - `validateConstraintSummary(output, expected)` — checks type, affected_sports, severity match
    - `checkFollowUpTarget(responseText, expectedTargets)` — keyword matching for follow-up quality
    - `validateVolumeCeiling(macroDiff, currentVolumes)` — parses volume numbers from macro diff, checks ≤ 15% increase
    - `validateNoCascadingViolation(macroDiff, phaseMap)` — checks no back-to-back recovery/easy weeks
    - `validateTaperPreserved(macroDiff, phaseMap)` — taper and race weeks are never moved
    - `checkRampBack(macroDiff, constraintType)` — if injury/illness, ramp-back protocol mentioned

- [x] 🟩 **Phase 4: Run + Iterate**
  - [x] 🟩 Run Step 1 scenarios (10). Score conversation quality.
  - [x] 🟩 Run Step 2 scenarios (10). Score coaching decision quality.
  - [x] 🟩 Run E2E scenarios (3). Score pipeline coherence.
  - [x] 🟩 If Step 1 fails: iterate on conversation prompt (required fields, follow-up instructions)
  - [x] 🟩 If Step 2 fails: iterate on coaching brain prompt (rules, cascading logic, phase awareness)
  - [x] 🟩 If cascading scenarios fail consistently: flag to product — cascading rules may need to be post-processing fixers, not prompt logic
  - [x] 🟩 Measure latency: Step 2 alone, Steps 2+3+4 sequentially (if Steps 3-4 are implemented)
  - [x] 🟩 Target: 3 prompt iterations max per step.

- [x] 🟩 **Phase 5: Report**
  - [x] 🟩 Results summary: pass rates per category, latency stats, prompt iteration count
  - [x] 🟩 Document final prompt versions for Step 1 and Step 2
  - [x] 🟩 Flag rules the LLM consistently struggles with — candidates for post-processing fixers
  - [x] 🟩 Architectural recommendation: should Steps 3-4 be tested in a follow-up PoC or proceed directly to implementation?
  - [x] 🟩 Update DRO-132 with PoC findings before proceeding to full tech spec
