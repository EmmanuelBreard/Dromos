# Plan Adjustment Based on User Message — Product Research Document

> **Date:** 2026-02-21
> **Author:** Fio, CTO — Dromos
> **Status:** Research / Pre-Discovery

---

## Table of Contents

1. [Purpose and Scope](#1-purpose-and-scope)
2. [Core Architectural Principle: Constraint-First Decision Model](#2-core-architectural-principle-constraint-first-decision-model)
3. [Critical Rule: Volume Ceiling Per Sport](#3-critical-rule-volume-ceiling-per-sport)
4. [Constraint Type 1: Facility / Equipment Unavailability](#4-constraint-type-1-facility--equipment-unavailability)
5. [Constraint Type 2: Physical Fatigue](#5-constraint-type-2-physical-fatigue)
6. [Constraint Type 3: Injury](#6-constraint-type-3-injury)
7. [Constraint Type 4: Life Event (Travel, Work, Family)](#7-constraint-type-4-life-event-travel-work-family)
8. [Constraint Type 5: Illness](#8-constraint-type-5-illness)
9. [Cross-Cutting Rules](#9-cross-cutting-rules)
10. [Sport Substitution Matrix](#10-sport-substitution-matrix)
11. [Detraining Thresholds](#11-detraining-thresholds)
12. [Competitive Landscape](#12-competitive-landscape)
13. [Five Exploitable Gaps for Dromos](#13-five-exploitable-gaps-for-dromos)
14. [Dromos Pipeline Integration Notes](#14-dromos-pipeline-integration-notes)
15. [Sources](#15-sources)

---

## 1. Purpose and Scope

This document synthesizes the research and decision logic needed to implement intelligent, constraint-aware plan adaptation when a Dromos user reports a disruption via natural language message. It is intended to serve as the authoritative product-level reference before a tech spec is written.

The core user need: "When life throws a curveball, I need my training to adapt without me figuring out the ripple effects."

Scope:
- Classification of disruption types and sub-types
- Substitution and reduction logic with volume ceilings
- Duration and phase-sensitive handling
- Week-within-block positioning
- Ramp-back rules where relevant
- Codifiable decision trees for each constraint type

Out of scope for this document:
- UI/UX design of the message input
- Prompt engineering specifics for the adaptation LLM call
- Specific DB schema changes (see tech spec stage)

---

## 2. Core Architectural Principle: Constraint-First Decision Model

The decision hierarchy is always constraint-first. Duration and phase are nested inside constraint type — they modify the constraint response, they do not sit at the same level.

```
User message → classify constraint_type
  → constraint_type determines:
      available_sports
      intensity_ceiling
      response_mode: substitution | reduction | full_stop
    → duration (1-3d, 4-7d, 8-14d, 14+d) determines:
        action scope: swap | reframe | rollback | regen
      → phase (Base | Build | Peak | Taper) determines:
          what to protect
          where to resume
          compression rules
            → week_within_block determines:
                risk flags and opportunity windows
```

This ordering matters: a knee injury does not become "just a duration problem" because it lasts 5 days. The constraint type (injury) governs available sports first. Duration then determines whether to substitute for a window, restructure a block, or regenerate the plan.

---

## 3. Critical Rule: Volume Ceiling Per Sport

**This rule applies to ALL constraint types involving sport substitution.**

When a sport is unavailable or restricted, the system cannot dump the missing volume onto another sport beyond the athlete's current capacity.

```
substitute_volume_in_sport <= athlete.current_weekly_volume_in_that_sport × 1.15
```

**Worked example — Injury (lost bike, 4h/week):**
- Athlete runs 3h/week currently
- Maximum additional run volume: 3h × 1.15 = 3h 27min → headroom = 27min extra
- Remaining gap (3h 33min of the lost 4h bike): absorb partially in swim (also capped at swim volume × 1.15), then accept reduced total volume
- Do NOT schedule 7h of running. Accept the volume deficit.

**Headroom formula:**

```
headroom_in_sport = (athlete.current_weekly_volume_in_sport × 1.15) - already_scheduled_in_sport_this_week
```

**Why this rule matters:**
- The cardiovascular system adapts faster than connective tissue (tendons, ligaments, bones)
- Rapid volume spikes in an unaccustomed sport cause overuse injury — the exact opposite of the goal
- "Don't fill the gap" is a first-class rule, not a fallback

**Ordering of substitute sports by injury risk:**
1. Bike (lowest impact, most forgiving volume ceiling)
2. Swim (non-weight-bearing, but technique-dependent)
3. Run (highest injury risk — apply volume ceiling most strictly)

---

## 4. Constraint Type 1: Facility / Equipment Unavailability

### 4.1 Core Question

Which sessions can be substituted with available equipment, and what is the equivalent intensity and duration in the substitute sport — without exceeding the athlete's current capacity in that sport?

### 4.2 Sub-Types

| Sub-Type | Sports Affected | Available Alternatives |
|---|---|---|
| No pool | Swim | Rowing erg, bike, run |
| No bike / indoor trainer | Bike | Spin bike, run, elliptical |
| No run surface (weather, terrain) | Run | Treadmill, bike, elliptical, aqua jog |
| Hotel gym only | All (typically) | Treadmill, spin bike, or nothing; volume likely drops |
| Outdoors only (travel, camping) | Indoor trainer, pool | Outdoor bike/run; swim may fully drop |

### 4.3 What Changes (Substitution Rules)

Sessions are SUBSTITUTED within volume ceilings — they are not simply moved or cancelled without replacement.

1. Identify the missing sport for the disruption window
2. Identify available substitute sports from sub-type mapping
3. Calculate current weekly volume per available substitute sport
4. Calculate headroom: `(current_weekly_volume × 1.15) - already_scheduled`
5. Substitute up to headroom using duration multiplier from the [Sport Substitution Matrix](#10-sport-substitution-matrix)
6. If headroom is zero or near-zero in all substitute sports → DROP the session entirely; do not force it
7. Match intensity zone, not just sport: a threshold bike session maps to threshold in the substitute sport (not Easy)

**Race-specific intensity exception:** Intensity sessions (Tempo, Intervals) should always map to the equivalent intensity zone in the substitute sport, not be downgraded to Easy simply because the sport is unfamiliar.

### 4.4 Duration Impact

| Window | Action |
|---|---|
| 1–7 days | Swap only: substitute sessions within volume ceilings for the window; resume original plan after |
| 8–14 days | Swap + consider adding sport-specific dryland / gym work to maintain neuromuscular patterns |
| 14+ days | Warn about sport-specific fitness loss; re-evaluate whether block restructure is needed |

Note: 14+ days of swim unavailability → technique regression risk (swim is the most skill-dependent discipline). Flag to user.

### 4.5 Phase Impact

Equipment unavailability has minimal impact on training goals — the goal of each phase (Base = aerobic base, Build = threshold, Peak = race pace) is maintained through the substitute sport. Phase logic does not change which sessions to protect; the substitution matrix handles the translation.

Exception: Base phase long aerobic sessions should remain long and easy in the substitute sport. Do not use the swap as an excuse to shorten duration beyond what the volume ceiling requires.

### 4.6 Week-Within-Block Impact

- Week 1–2 of block: low concern; fitness adaptations are early
- Week 3 (highest load): if an intensity session must be dropped due to zero headroom, note it as a gap but do not double up when back
- Week 4 (recovery week): facility issues during recovery week = lowest risk scenario; reduce further if needed

### 4.7 Codifiable Decision Tree

```
INPUT: facility_type_unavailable, window_days, user.current_weekly_volumes

→ map facility_type → affected_sport(s)
→ map affected_sport → candidate_substitute_sports (ordered by preference)
→ FOR EACH session in window:
    → IF session.sport IN affected_sports:
        → FOR EACH substitute_sport IN candidates:
            → headroom = (weekly_volume[substitute_sport] × 1.15) - already_scheduled[substitute_sport]
            → converted_duration = session.duration_minutes × multiplier[session.sport → substitute_sport]
            → IF converted_duration <= headroom:
                → SUBSTITUTE session with substitute_sport, converted_duration, same intensity_zone
                → already_scheduled[substitute_sport] += converted_duration
                → BREAK
        → IF no substitute has headroom:
            → DROP session
            → add note: "Session dropped — no headroom in substitute sports"
→ IF window_days >= 14:
    → FLAG: "Sport-specific fitness may decline. Consider block review."
→ RESUME original plan after window
```

---

## 5. Constraint Type 2: Physical Fatigue

### 5.1 Core Question

How overloaded is the athlete, and how much do we reduce intensity and/or volume — while protecting the minimum training stimulus needed for the current phase?

### 5.2 Sub-Types and Severity Ladder

| Level | Definition | Signs |
|---|---|---|
| Acute fatigue | Normal post-hard-session tiredness | Heavy legs, mild DOMS, resolved after one easy day |
| Accumulated fatigue | Carried fatigue from consecutive hard weeks | Persistent heaviness, performance plateau, poor sleep |
| Non-functional overreaching (NFOR) | Chronic, multi-week overload | Mood disturbances, HR elevation, performance decline over 2+ weeks |

### 5.3 What Changes

**Acute fatigue:**
- Today only: swap current session to Easy / Zone 1
- No volume reduction; no ripple to rest of week
- Add note: "Listen to your body; proceed tomorrow as planned unless symptoms persist"

**Accumulated fatigue:**
- Reduce weekly volume by 20–30%
- Keep exactly 1 quality (Tempo or Intervals) session this week — the single best session for the phase
- Convert remaining quality sessions to Easy
- Do not skip all sessions; complete rest is not the right signal here

**Non-functional overreaching (NFOR):**
- Reduce weekly volume by 50–60%
- Zero intensity sessions for 2–4 weeks
- All sessions Easy / Zone 1 only
- Monitor: if no improvement in 2 weeks, flag possible medical evaluation

Volume ceiling rule applies to substitutions if any sports are swapped, but fatigue primarily calls for reduction, not substitution.

### 5.4 Duration Impact

| Window | Action |
|---|---|
| 1 day | Acute protocol: swap today's session to Easy |
| 2–5 days | Accumulated protocol: -20-30% volume, 1 quality session protected |
| 6–21 days | NFOR protocol: -50-60%, zero intensity |
| 21+ days | Consider plan regeneration with reduced target volume for the remainder of the block |

### 5.5 Phase Impact

Phase is the primary modifier of how to interpret fatigue:

**Base phase:**
- Fatigue in Base is a yellow flag — Base training should not be producing significant fatigue
- If fatigued in Base, investigate: volume too high, sleep/nutrition issues, or underlying illness
- Protocol: Acute or Accumulated as appropriate; do NOT flag NFOR prematurely

**Build phase (most common):**
- Normal for accumulated fatigue to appear in Build
- Protect the single best session: brick (if available) or threshold run/bike
- NFOR in Build = serious risk; do not push through

**Peak phase:**
- 1–2 extra rest days for acute/accumulated fatigue is nearly free — fitness is not lost in 2 days
- NFOR in Peak = race risk; consider race goal re-evaluation
- Compress or extend taper to absorb the recovery

**Taper phase:**
- Fatigue should be resolving naturally during taper
- If fatigue persists into taper, extend taper by 3–5 days
- NFOR in taper = clinical concern; recommend medical evaluation

### 5.6 Week-Within-Block Impact

| Week in Block | Fatigue Signal | Interpretation |
|---|---|---|
| Week 1 | Fatigue | Yellow flag: abnormal. Check if preceding block recovery was adequate. Potential NFOR. |
| Week 2 | Fatigue | Monitor. Could be adjustment to new block load. |
| Week 3 (peak load) | Fatigue | Expected and normal. Convert to early recovery week if severe. |
| Week 4 (recovery) | Fatigue | Fatigue should be resolving. If not, something is wrong upstream. |

**Key rule:** Week 3 fatigue → convert to early recovery week (effectively move recovery week up by a few days). Week 1 fatigue → flag as potential NFOR, investigate before reducing.

### 5.7 Codifiable Decision Tree

```
INPUT: fatigue_report, current_week_number_in_block, phase, user.weekly_volume

→ classify_severity:
    IF single_day AND normal_prior_week → ACUTE
    IF multiple_days AND prior_week_was_hard → ACCUMULATED
    IF multi_week_trend OR mood/HR changes → NFOR

→ IF ACUTE:
    → swap today's session → Easy (Zone 1)
    → rest of week: unchanged

→ IF ACCUMULATED:
    → identify best_quality_session_this_week (brick > threshold run > threshold bike)
    → convert all other quality sessions → Easy
    → reduce total weekly volume × 0.75 (drop easiest/shortest sessions first)

→ IF NFOR:
    → convert ALL sessions → Easy (Zone 1)
    → reduce total weekly volume × 0.45
    → set intensity_ceiling = Zone1 for min(2_weeks, until_symptoms_resolve)
    → FLAG: "If no improvement in 2 weeks, seek medical evaluation"

→ IF phase = Taper AND fatigue persists:
    → extend taper by 3-5 days
    → FLAG: "Taper fatigue is unusual — check for NFOR or illness"

→ IF week_in_block = 3 AND ACCUMULATED:
    → convert to early recovery week (treat as week 4)
```

---

## 6. Constraint Type 3: Injury

### 6.1 Core Question

Which sports are safe to continue, and at what volume and intensity — given the injured body part and severity — while respecting the volume ceiling rule in substitute sports?

### 6.2 Sub-Types: Body Part → Sport Eligibility

| Body Part | Swim | Bike | Run | Notes |
|---|---|---|---|---|
| Knee | Caution (kick) | Caution (low cadence) | No (severity ≥ moderate) | Aqua jog OK if no knee flex pain |
| Ankle | No (push-off) | Caution (cleat tension) | No | Swimming and stationary bike (cleat-free) may be OK |
| Shin / shin splints | Yes | Yes | No | Excellent bike substitution window |
| Hip flexor | Caution | Caution | No | Depends on ROM and severity |
| Shoulder | Caution or No | Yes | Yes | Freestyle compromised; bike/run unaffected |
| Lower back | Caution | Caution (TT position) | Caution | Upright bike preferred; no run if pain with gait |
| Achilles | Yes | Yes (clipless caution) | No | Critical: do NOT run through Achilles pain |

### 6.3 Severity Ladder

| Level | Definition | Protocol |
|---|---|---|
| Discomfort | Mild sensation, no performance impact | Reduce intensity in affected sport; monitor |
| Mild | Noticeable, slight performance impact | Substitute affected sport with eligible alternatives; volume ceiling applies |
| Moderate | Clear performance impairment | Remove affected sport; substitute within ceilings; reduce total volume |
| Severe | Cannot perform affected sport without pain | Full stop of affected sport; medical evaluation recommended |
| Medical stop | Pain with daily activity or physician directive | Full rest; follow medical guidance |

### 6.4 What Changes (Substitution Rules with Volume Ceiling)

**This is the constraint type where the volume ceiling rule is most critical.**

A cyclist who loses 4h/week of bike due to a knee injury cannot replace it with 4h of running if their current run volume is 3h/week. The deficit must be accepted.

Substitution headroom calculation:

```
headroom_in_sport = (current_weekly_volume_in_sport × 1.15) - already_scheduled_in_sport_this_week
```

Steps:
1. Determine injured sport(s) from body-part eligibility table
2. Identify eligible substitute sports (from table above)
3. Calculate headroom in each eligible sport
4. Substitute up to headroom; accept the remaining volume deficit
5. Do not schedule any intensity in the injured sport unless severity = discomfort and sport is listed as "caution" (not removed)

**"Don't fill the gap" rule:** More rest is better than overcompensating in substitute sports. Extra recovery time is training load, not wasted time.

### 6.5 Duration Impact

| Window | Action |
|---|---|
| Known window (e.g., "I'll be out 10 days") | Substitute for the window; plan ramp-back after |
| Indefinite | Substitute + flag for weekly re-evaluation; do not restructure yet |
| 15–21 days | Restructure the current block; adjust volume and progression for remainder |
| 22+ days | Consider plan regeneration with injury constraint; resumption phase depends on what was missed |

### 6.6 Phase Impact

**Base phase:**
- Cross-training IS possible within volume ceilings
- May need to accept lower total volume — do not compensate by overloading other sports
- Extend Base phase if needed to preserve the aerobic foundation before progressing to Build

**Build phase (most dangerous):**
- If the key discipline is lost for more than 2 weeks, do NOT return to Build intensity when resuming
- Return to Base 3 intensity (aerobic threshold, not race-pace) for minimum 1 week
- Protecting single-sport fitness is more important than maintaining multi-sport balance during injury

**Peak phase:**
- Loss of any discipline for 2+ weeks in Peak = race goal re-evaluation, not just plan adjustment
- Flag: "Depending on recovery timeline, race completion > race performance may be the appropriate goal"
- Do not attempt to compress Peak work into a shorter window after return; proceed to taper

**Taper phase:**
- Forced rest partially aligns with taper goals (reduce volume, maintain freshness)
- If injured sport is safe for low-intensity efforts, allow Zone 1-2 only
- Do not introduce intensity in taper, even if the athlete feels "recovered"

### 6.7 Ramp-Back Rules (Unique to Injury)

Connective tissue heals slower than cardiovascular fitness returns. This is the most common source of re-injury.

```
Week 1 (return):  < 20min, Zone 1 only, in injured sport. Pain-free required to proceed.
Week 2:           +10% of pre-injury volume. Zone 1 only. If pain returns, drop back to Week 1.
Week 3:           +10% again. Zone 1-2 allowed.
Week 4+:          Continue +10%/week. Intensity (Tempo) only after:
                    (a) pain-free for full week AND
                    (b) current volume >= 80% of pre-injury weekly volume
```

Intervals (Zone 4+) only after full return to pre-injury volume with no pain.

### 6.8 Week-Within-Block Impact

| Week in Block | Injury Timing | Priority |
|---|---|---|
| Week 1 | Injury at start of block | Restructure block immediately; substitute within ceilings |
| Week 2-3 | Mid-block injury | Salvage remaining key sessions; protect best available |
| Week 4 (recovery) | Injury during recovery week | Lower stakes; rest aligns with recovery goals |

### 6.9 Codifiable Decision Tree

```
INPUT: body_part, severity, sport_eligibility_map, window_type, window_days, phase, user.weekly_volumes

→ eligible_sports = sport_eligibility_map[body_part][severity]
→ injured_sports = ALL_SPORTS - eligible_sports

→ FOR EACH session in window WHERE session.sport IN injured_sports:
    → DROP session OR substitute with eligible sport:
        → FOR EACH eligible_sport IN eligible_sports (ordered: bike > swim > run):
            → headroom = (weekly_volume[eligible_sport] × 1.15) - already_scheduled[eligible_sport]
            → converted_duration = session.duration × multiplier[session.sport → eligible_sport]
            → IF converted_duration <= headroom AND converted_duration > 0:
                → substitute; already_scheduled[eligible_sport] += converted_duration
                → BREAK
        → IF no eligible sport has headroom:
            → DROP session; add note: "Volume ceiling reached — rest is better than overcompensation"

→ IF window_days > 21:
    → trigger block restructure
→ IF window_days > 35:
    → trigger plan regeneration with injury_constraint

→ IF phase = Build AND injured_sport = primary_discipline AND window_days > 14:
    → FLAG: "Race goal re-evaluation recommended"

→ ON RETURN:
    → apply ramp-back: Week 1 <20min Z1; +10%/week; intensity only after pain-free at 80% pre-injury volume
```

---

## 7. Constraint Type 4: Life Event (Travel, Work, Family)

### 7.1 Core Question

Given a reduced time or availability window, which sessions deliver the highest training value per minute — and can the gap be converted to a recovery benefit rather than a loss?

### 7.2 Sub-Types

| Sub-Type | Typical Time Available | Key Constraint |
|---|---|---|
| Business travel | 30–45 min/day, hotel gym | Equipment limited; schedule compressed |
| Vacation | Variable (0 to normal) | Often near normal if planned; family obligation variable |
| Work deadline / crunch | Fatigue + time crunch | Life stress = training stress (see rule below) |
| Major life change | Highly variable, often prolonged | May require plan restructure or regeneration |

### 7.3 What Changes

**Key insight: Intensity > Volume when time-constrained.**

A 25-minute threshold run delivers more training stimulus than a 60-minute easy walk. When total time is limited, compress volume aggressively but protect intensity.

**Front-loading rule:** Unlike injury or illness, it is safe to front-load sessions before a life event window. Complete 2–3 sessions in the days before the disruption begins. This does not apply to injury (overcompensation risk) or illness (immune system risk).

**Life stress = training stress:** The body does not distinguish between cortisol from a board presentation and cortisol from a hard workout. During high-stress work events, reduce training intensity even if time is technically available. An easy session is better than forcing a hard session on a stressed body.

**Align with recovery week when possible:** If a life event falls within 1–2 days of a scheduled recovery week, shift the recovery week to overlap with the event. Net cost: zero.

### 7.4 Duration Impact

| Window | Action |
|---|---|
| 1–3 days | Skip; do not reschedule. Never make up missed sessions. Resume plan. |
| 4–7 days | 2–3 short (25–40 min) high-intensity sessions; skip long sessions; use remaining time for rest |
| 8–14 days | Sandwich strategy: compressed training before + after the disruption; reduced maintenance mode during |
| 14+ days | Maintenance mode: 2 sessions/week/discipline at Zone 1-2 minimum; preserves most fitness (see detraining thresholds) |

### 7.5 Phase Impact

**General rule across all phases:** Protect highest-value session. If only 2 sessions possible in a week, prioritize: brick/threshold + long session in the priority discipline for that phase.

| Phase | Priority Session to Protect | What to Drop First |
|---|---|---|
| Base | Long aerobic (swim, bike, or run) | Extra easy sessions |
| Build | Brick or threshold session | Volume sessions |
| Peak | Race-pace/race-simulation session | Easy fillers |
| Taper | Do less anyway; life event during taper is nearly free | Most sessions already short |

### 7.6 Week-Within-Block Impact

| Week | Life Event Impact |
|---|---|
| Week 1 (base load) | Low stakes; early block; skip without concern |
| Week 2-3 (peak load) | Protect 1–2 key sessions. High-intensity short sessions over skipping entirely. |
| Week 4 (recovery) | Natural alignment; convert to recovery + life event; net cost near zero |

### 7.7 Ramp-Back

No formal ramp-back required for life events (no tissue damage, no illness). Resume from where the plan left off the day after the event ends. Do not double up or compensate.

### 7.8 Codifiable Decision Tree

```
INPUT: event_type, window_days, phase, available_minutes_per_day, current_week_in_block

→ IF window_days <= 3:
    → skip sessions cleanly; add note: "Resume plan on [date]. Do not make up missed sessions."

→ IF window_days 4-7:
    → identify 2-3 highest-value sessions for the phase (brick > threshold > long)
    → compress to 25-40 min each
    → drop all volume-only sessions
    → front_load: IF event starts in >2 days AND no injury/illness: schedule 1-2 extra sessions before event

→ IF window_days 8-14:
    → pre-event: front-load 2-3 key sessions in days before
    → during event: maintenance mode (2 sessions/week, Zone 1-2, 30-45 min each)
    → post-event: resume plan from current position

→ IF window_days 14+:
    → maintenance mode throughout
    → check detraining thresholds; flag if >21 days

→ IF event_type = work_deadline:
    → apply life_stress_modifier: downgrade intensity by 1 zone across all sessions during window
    → note: "High life stress period — keeping sessions easy to avoid accumulated overload"

→ IF week_in_block = 4 OR distance_to_recovery_week <= 2 days:
    → convert gap to recovery week; note: "Timing aligns with recovery — no fitness cost"
```

---

## 8. Constraint Type 5: Illness

### 8.1 Core Question

Is the illness above or below the neck — and is there fever? These two questions determine whether any training is permitted at all.

### 8.2 The Neck Check

This is the single most important rule for illness:

```
IF symptoms ABOVE neck only (runny nose, sore throat, mild congestion) AND no fever:
    → Zone 1-2 allowed; no intensity
ELSE (fever, chest, lungs, GI, muscle aches, fatigue):
    → FULL REST until fever-free for 24 hours minimum
```

**Medical rationale:** Training through below-neck illness or fever risks myocarditis (viral inflammation of the heart muscle), immune suppression, and prolonged recovery. This is not conservative caution — it is genuine medical risk. The system must not be talked out of this rule.

### 8.3 Sub-Types

| Type | Neck Check | Protocol |
|---|---|---|
| Upper respiratory (cold, mild) | Above neck, no fever | Zone 1-2 only |
| Flu / influenza | Below neck, fever | Full rest |
| GI illness | Below neck | Full rest |
| COVID / similar respiratory | Below neck or fever | Full rest; extended graduated return |
| Post-illness lingering fatigue | Resolved, no fever | Graduated return protocol |

### 8.4 What Changes

**Above-neck, no fever:**
- Reduce all sessions to Zone 1-2 (easy aerobic only)
- No Tempo or Intervals
- Shorten duration by 20-30% if feeling suboptimal
- No substitution needed — all three sports available at low intensity

**Below-neck or fever:**
- Full stop: zero training
- Rest until fever-free for 24+ hours
- Then: graduated return protocol (see ramp-back below)
- Volume ceiling is irrelevant — no training is the ceiling

**"1 day sick = 2 days easy-only" rule (below-neck):**

```
days_of_below_neck_illness = N
mandatory_easy_days_on_return = N × 2
```

This applies after the fever-free threshold is crossed. N days sick = N×2 days of Zone 1-2 only before resuming normal intensity.

### 8.5 Duration Impact

| Scenario | Action |
|---|---|
| Above-neck, 1–3 days | Reduce to Zone 1-2 for duration; resume normal intensity when symptom-free |
| Below-neck, any duration | Full rest until fever-free 24h; then graduated return |
| Extended illness (>7 days) | Below-neck protocol + return to earlier plan point (see ramp-back) |

### 8.6 Phase Impact

**Base phase:**
- Return to Base 1 (lowest Zone 1) until HR and RPE normalize
- Do not rush to Base 2 or 3 intensity post-illness

**Build phase:**
- Do NOT return to Build intensity immediately after illness
- Mandatory Base 3 intensity for minimum 1 week before resuming any Tempo/Intervals
- Build intensity = threshold work that stresses the cardiac system = elevated risk post-illness

**Peak phase:**
- No race-pace work during or immediately after illness
- Merge recovery period into an extended taper
- Flag: if illness extends within 10 days of race, "arriving healthy > arriving sharp"

**Taper phase:**
- Above-neck: Zone 1 + strides only; maintain movement without stress
- Below-neck: complete rest; accept possible performance hit on race day; do not train into sickness to "save" the taper

### 8.7 Ramp-Back Rules (Graduated Return)

Return protocol after below-neck illness (starting from fever-free for 24h):

```
Stage 1: Walking / casual movement only (1-2 days)
Stage 2: Easy aerobic — Zone 1-2 (running, cycling, swimming at conversation pace) (2-3 days)
Stage 3: Normal aerobic — Zone 2-3 (moderate intensity, no threshold work) (3-5 days)
Stage 4: Resume plan from 1-2 weeks prior to illness (not from current week)

REGRESSION RULE: If symptoms return at ANY stage → drop back ONE stage, wait 24h, reassess
```

Resuming from 1–2 weeks prior to illness is critical: the plan was built for a healthy athlete with accumulated fitness. Post-illness, the athlete is temporarily deconditioned even if they feel recovered.

### 8.8 Week-Within-Block Impact

| Week | Illness Timing | Impact |
|---|---|---|
| Week 1 | Illness at block start | Convert week to rest; delay block start |
| Week 3 (peak load) | Most dangerous: heaviest week during illness = highest immune suppression risk | Full rest immediately; reassess block goals |
| Week 4 (recovery) | Recovery week partially protects; illness may resolve with rest anyway | Low training load = lower risk; full rest if below-neck |

### 8.9 Codifiable Decision Tree

```
INPUT: symptoms, fever_present, days_ill, phase, race_days_remaining

→ neck_check:
    IF fever OR chest_symptoms OR GI OR systemic_fatigue OR muscle_aches:
        → BELOW_NECK → FULL_STOP
    ELSE:
        → ABOVE_NECK → REDUCE

→ IF FULL_STOP:
    → zero sessions until fever_free_24h
    → after fever_free: apply graduated return (Walk → Z1-2 → Z2-3 → resume from 2wks prior)
    → mandatory_easy_days = days_ill × 2 after fever_free
    → REGRESSION: IF symptoms return → drop_one_stage, wait 24h

→ IF REDUCE:
    → convert all sessions → Zone 1-2
    → reduce duration × 0.8
    → when symptom_free: resume normal plan (no ramp-back needed for above-neck)

→ IF phase = Build AND returning from FULL_STOP:
    → set intensity_ceiling = Base_3 for min(7_days, until_HR_RPE_normalize)
    → then resume Build

→ IF phase = Peak AND days_ill >= 5:
    → merge into extended taper
    → FLAG: "Race performance may be compromised. Prioritize arriving healthy."

→ IF race_days_remaining <= 10 AND FULL_STOP:
    → FLAG: "Full rest + stay healthy. Do not train. A healthy start > a compromised peak."
```

---

## 9. Cross-Cutting Rules

These rules apply regardless of constraint type.

| Rule | Source | Application |
|---|---|---|
| Never make up missed workouts by doubling up | Friel, Training Bible | Applies to all 5 constraint types. Skip and move on. |
| Life stress = training stress | Friel; HRV research | During high-stress life events: reduce intensity as if physically fatigued |
| Connective tissue lags cardiovascular fitness | Sports medicine (Dye, Kibler) | Applies to injury and illness ramp-back: cardiovascular readiness returns before tissue is safe |
| Injury risk peaks in weeks 2–4 of return | Incidence data (Nielsen, 2012) | Build ramp-back conservatively through this window |
| Maintenance mode minimum | Hickson et al., 1981 | 2 sessions/week/discipline at Zone 1-2 preserves most fitness for 4+ weeks |
| Do not fill the gap | Friel; Noakes | Extra rest > overcompensation via substitute sports. Accept volume deficit. |
| Intensity > volume when time-constrained | Burke, Coggan | High-intensity short sessions over long easy sessions during time-limited windows |

---

## 10. Sport Substitution Matrix

Volume ceiling rule applies to ALL substitutions. "Less risky" does not mean unlimited — apply the formula.

| Missing Sport | Best Substitute (Ordered) | Duration Multiplier | Volume Ceiling Severity | Notes |
|---|---|---|---|---|
| **Swim** | 1. Rowing erg | 1:1 | Medium | Full-body aerobic; closest to swim stimulus |
| | 2. Bike | 1:1 | Low | Low injury risk; volume ceiling less critical |
| | 3. Run | 1:1 | High | Run volume ceiling especially strict |
| **Bike** | 1. Spin bike / indoor trainer | 1:1 | Negligible | Same sport, different equipment |
| | 2. Run | 0.7× bike duration (i.e., 1h bike → 42min run) | CRITICAL | Run has highest overuse injury risk; apply ceiling strictly |
| | 3. Elliptical | 0.9× bike duration | Low | Non-weight-bearing; lower ceiling risk |
| **Run** | 1. Aqua jog | 1:1 | Low | Closest neuromuscular pattern; non-impact |
| | 2. Elliptical | 1:1 | Low | Good run substitute; non-impact |
| | 3. Bike | 1.5× run duration (i.e., 1h run → 90min bike) | Low | Less risky to over-substitute with bike; low impact |

**Notes on multipliers:**
- Multipliers convert training stimulus equivalency, not calorie burn
- When in doubt, err on the shorter side — under-substitute rather than over-substitute
- For intensity sessions: maintain same zone, do not downgrade to Easy in the substitute sport

---

## 11. Detraining Thresholds

Reference data for communicating fitness preservation to users and for determining whether plan restructure is warranted.

| Detraining Window | Estimated Fitness Loss | Recommendation |
|---|---|---|
| 0–5 days | 0% | No concern; resume normally |
| 5–10 days | 0–2% | Minor; resume at slightly reduced intensity for 1–2 days |
| 10–14 days | 2–5% | Resume plan 1 week prior; rebuild over 5–7 days |
| 14–21 days | 5–10% | Restructure current block; do not jump back to prior load |
| 21–28 days | 10–15% | Consider block rebuild; reassess phase and progression |
| 28+ days | 15–25% | Plan regeneration warranted; injury or illness constraint should be embedded |

Source: Mujika & Padilla (2000), Coyle et al. (1984), Hickson et al. (1981).

These thresholds apply to aerobic (VO2max / cardiac output) detraining. Neuromuscular adaptations (economy, power at threshold) may degrade faster or slower depending on sport.

---

## 12. Competitive Landscape

How existing competitors handle plan disruption and adaptation.

| App | Disruption Feature | What It Actually Does | Key Weakness |
|---|---|---|---|
| **Athletica.ai** | Workout Wizard (4 tabs: Reschedule, Modify, Skip, Change) + nightly HRV/readiness scan | Genuine adaptation using load metrics; reschedule is smart | Injury tab is generic — no body-part specificity; HRV requires wearable |
| **Humango** | "Chat with Hugo" (ChatGPT-backed) | Conversational modification; theoretically flexible | Black box: no explanations for changes; quality degrades with complex requests; users can't verify the adaptation is correct |
| **TriDot** | Volume sliders | Manual volume adjustments per sport | Reports indicate it does not actually adapt the plan structure; feels cosmetic |
| **TrainerRoad** | Post-workout survey (thumbs up/down) + calendar annotations | Adaptive Training adjusts next workout difficulty | Never explains WHY a workout is easier/harder; annotation system is clunky; triathlon swim/run integration is weak |
| **Mottiv** | Manual drag-and-drop of workouts | Zero adaptation; pure calendar rearrangement | Not adaptation at all; user must understand the implications themselves |
| **Runna** | Best disruption taxonomy in market: 5 modes (injury, illness, travel, fatigue, missed session) | Clean classification UI; clear outcome per mode | Running-only; no triathlon multi-sport complexity; no volume ceiling logic |

**Pattern across all competitors:** Every app that attempts adaptation either (a) doesn't explain why the change was made, (b) fakes it with sliders, or (c) delegates to a generic chatbot. None implement triathlon-specific multi-sport substitution with volume ceiling awareness.

---

## 13. Five Exploitable Gaps for Dromos

Ranked by user value × competitive whitespace.

### Gap 1: Explainable Adaptation — "Here's Why Your Plan Changed"

**The gap:** Zero apps consistently explain the reasoning behind an adaptation. TrainerRoad lowers your next workout's intensity but never says "because your last 3 sessions showed declining power output." Humango makes changes through Hugo with no audit trail.

**Dromos opportunity:** Every adaptation outputs a natural-language explanation tied to the athlete's specific situation: phase, previous load, injury type, remaining time to race. This is architecturally native to an LLM pipeline — we generate the explanation alongside the change.

**User statement:** "I want to understand WHY my plan changed, not just accept that it did."

### Gap 2: Meaningful Injury Handling — Body Part × Sport Eligibility

**The gap:** Athletica's injury tab is a single generic "injury" toggle. TriDot has no injury-aware adaptation. Humango claims it adapts to injury but delivers generic reduction. No app implements the body-part → sport eligibility mapping or the volume ceiling rule for injury substitution.

**Dromos opportunity:** Body-part-specific eligibility matrix. Volume ceiling applied to substitutes. "Don't fill the gap" rule surfaced to the user with explanation. Ramp-back protocol codified and tracked.

**User statement:** "I hurt my knee — the app didn't even ask me what kind of injury before removing all my run sessions."

### Gap 3: Proactive Disruption Detection — Before the User Reports It

**The gap:** Only Athletica attempts this via HRV, but it requires wearable integration and only covers fatigue. No app detects life events or illness early.

**Dromos opportunity (medium-term):** Detect signals from session completion patterns (skipped sessions cluster = possible life event or illness) and prompt the user proactively. "You've missed 3 sessions this week — is everything okay? Tell us what's happening and we'll adjust." No wearable required.

**User statement:** "I went through a rough week and when I came back the plan was already stale. No one asked."

### Gap 4: Feedback Loop After Adaptation — Did It Work?

**The gap:** Zero apps close the loop after an adaptation. TrainerRoad asks how your workout felt. No app asks "how did the adapted week feel?" and uses that to calibrate the next adaptation.

**Dromos opportunity:** Post-adaptation check-in. One question at the end of the adapted week: "How did last week feel given the changes we made?" This trains the system (and the user's trust) over time.

**User statement:** "I'll never know if the adaptation the app made was any good."

### Gap 5: Granular Disruption Taxonomy — Triathlon-Specific

**The gap:** Runna has the best classification UI (5 modes), but it is running-only. No app combines Runna's taxonomic clarity with triathlon multi-sport complexity. Athletica's wizard is 4 generic tabs. TriDot has sliders.

**Dromos opportunity:** A clean 5-type classification (Facility, Fatigue, Injury, Life Event, Illness) with sub-types and natural language input as the primary entry point. The classification drives a constraint-aware multi-sport adaptation rather than a single-sport reduction.

**User statement:** "There's no option that matches what actually happened to me."

---

## 14. Dromos Pipeline Integration Notes

These are observations about how the adaptation feature fits the current architecture. Not prescriptive — tech spec stage will firm these up.

**Current pipeline:** 3-step LLM generation (Step 1: macro plan markdown → Step 2: JSON → Step 3: template selection) + 15 post-processing fixers → DB writes.

**Adaptation approach options:**

| Option | Description | Cost | Risk |
|---|---|---|---|
| A. Surgical DB mutation | Classify constraint, compute changes in code, mutate `plan_sessions` / `plan_weeks` directly | ~$0 LLM cost | Complex logic in code; harder to explain changes |
| B. Re-run Step 3 on affected block | Feed constraint + current block JSON to Step 3 with new constraints | ~$0.02-0.05/call | Step 3 produces template selection only; phase reasoning not included |
| C. Re-run Step 1 from current week | Regenerate macro plan from current week forward with constraint embedded | ~$0.15-0.30/call | Full pipeline latency (50-60s); highest quality; best explanation output |
| D. New adaptation-specific LLM call | Separate prompt that takes current week JSON + constraint + rules → outputs mutated week JSON | ~$0.02-0.05/call | New prompt to develop and eval; cleanest separation of concerns |

**Recommendation for research stage:** Option D (new adaptation LLM call) is the most architecturally clean. Option A (surgical mutation) is fastest to ship but hardest to explain to users. The constraint logic in this document maps naturally to Option D: classify the constraint type, build the rule-constrained prompt, let the LLM apply the rules and produce explanation text alongside the adjusted sessions.

**Data needed at adaptation time (from existing schema):**
- `plan_sessions` for the affected window (current week + N weeks)
- `plan_weeks.phase` for affected weeks
- `users.current_weekly_hours` (for volume ceiling calculation, per-sport breakdown not currently stored)
- `users.{sport}_days` (availability)
- `users.{day}_duration` (per-day availability in minutes)

**Gap in current schema:** Volume ceiling calculation requires `current_weekly_volume_per_sport` (e.g., current swim hours, current bike hours, current run hours). This is not stored separately from `current_weekly_hours`. Will need to be either (a) derived from current plan sessions, (b) asked during onboarding, or (c) inferred from the macro plan structure. This is a non-trivial schema/product decision.

---

## 15. Sources

### Sports Science

- Mujika, I., & Padilla, S. (2000). "Detraining: Loss of training-induced physiological and performance adaptations." *Sports Medicine*, 30(2), 79–87.
- Coyle, E.F., Martin, W.H., Sinacore, D.R., et al. (1984). "Time course of loss of adaptations after stopping prolonged intense endurance training." *Journal of Applied Physiology*, 57(6), 1857–1864.
- Hickson, R.C., Kanakis, C., Davis, J.R., et al. (1981). "Reduced training duration effects on aerobic power, endurance, and cardiac growth." *Journal of Applied Physiology*, 53(1), 225–229.
- Nielsen, R.O., Buist, I., Sørensen, H., et al. (2012). "Training errors and running related injuries: a systematic review." *International Journal of Sports Physical Therapy*, 7(1), 58–75.
- Friel, J. (2009). *The Triathlete's Training Bible* (3rd ed.). VeloPress.
- Friel, J. (2016). *Fast After 50*. VeloPress. [Life stress = training stress; recovery adaptation principles]
- Dye, S.F. (2005). "The pathophysiology of patellofemoral pain." *Clinical Orthopaedics and Related Research*, 436, 100–110.

### Competitive Research

- [Triathlete.com — We Hands-On Review 8 AI Triathlon Training Apps](https://www.triathlete.com/gear/tech-wearables/ai-triathlon-training-apps/)
- [TriLaunchpad — AI Training Apps: Honest Reviews from Age Groupers](https://triathlon.mx/blogs/triathlon-news/ai-training-apps-for-triathletes-put-to-the-test-honest-reviews-from-age-groupers)
- [220 Triathlon — Best Triathlon Training Apps 2026](https://www.220triathlon.com/gear/tri-tech/best-triathlon-training-apps-review)
- [Athletica.ai — Workout Wizard documentation](https://support.athletica.ai/)
- [Runna — Disruption handling (iOS App Store reviews, 2025)](https://apps.apple.com/us/app/runna-running-training-plans/id1594910326)
- [TrainerRoad — Adaptive Training overview](https://www.trainerroad.com/blog/adaptive-training/)
- [Humango — AI Coach Hugo](https://humango.ai/)
- [TriDot — Adaptive Training claims](https://www.tridot.com/)

### Internal Dromos References

- `/Users/emmanuel/Documents/ClaudeLife/App_Projects/Dromos-iOS App/strategy/ai-differentiation.md` — Competitive landscape and differentiation framework
- `/Users/emmanuel/Documents/ClaudeLife/App_Projects/Dromos-iOS App/.claude/context/ai-pipeline.md` — Current 3-step generation pipeline
- `/Users/emmanuel/Documents/ClaudeLife/App_Projects/Dromos-iOS App/.claude/context/schema.md` — Database schema (training_plans, plan_weeks, plan_sessions)
- `/Users/emmanuel/Documents/ClaudeLife/App_Projects/Dromos-iOS App/.claude/context/architecture.md` — App architecture reference
