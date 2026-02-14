# DRO-59: Sport Availability in Step 1 + Step 3 Self-Validation

## Context
Post-DRO-58 eval shows the LLM still violates sport-day eligibility (e.g. swim on non-swim days) and duration caps (90min on 60min days). Root causes: Step 1 doesn't know per-sport day counts, Step 3 doesn't self-validate before outputting.

## Branch
Create branch from main: `ebreard4/dro-59-dro-48-phase-4-sport-availability-in-step-1-step-3-self`

## Changes

### 1. `supabase/functions/generate-plan/prompts/step1-macro-plan-prompt.ts`

Add a new section **between the Athlete Profile section (line 14) and the Task section (line 16)**. Insert after `- Limiters: {{limiters}}`:

```
### Sport Day Availability
- Swim: {{swim_weekday_count}} weekdays + {{swim_weekend_count}} weekend days
- Bike: {{bike_weekday_count}} weekdays + {{bike_weekend_count}} weekend days
- Run: {{run_weekday_count}} weekdays + {{run_weekend_count}} weekend days
Plan session counts per sport accordingly — a sport with fewer available days should have fewer sessions. Use all available days to maximize volume toward the weekly budget.
```

### 2. `ai/prompts/step1-macro-plan.txt`

Apply the exact same addition as #1.

### 3. `supabase/functions/generate-plan/index.ts` — `buildStep1Prompt()`

Add the following AFTER the session duration caps block (after `prompt = prompt.replace("{{max_weekend_minutes}}", ...)`) and BEFORE the `return prompt;` line:

```typescript
  // Sport day availability counts for Step 1 volume shaping
  const weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"];
  const weekendDays = ["Saturday", "Sunday"];
  const swimDays = new Set(user.swim_days || []);
  const bikeDays = new Set(user.bike_days || []);
  const runDays = new Set(user.run_days || []);

  prompt = prompt.replace("{{swim_weekday_count}}", weekdays.filter(d => swimDays.has(d)).length.toString());
  prompt = prompt.replace("{{swim_weekend_count}}", weekendDays.filter(d => swimDays.has(d)).length.toString());
  prompt = prompt.replace("{{bike_weekday_count}}", weekdays.filter(d => bikeDays.has(d)).length.toString());
  prompt = prompt.replace("{{bike_weekend_count}}", weekendDays.filter(d => bikeDays.has(d)).length.toString());
  prompt = prompt.replace("{{run_weekday_count}}", weekdays.filter(d => runDays.has(d)).length.toString());
  prompt = prompt.replace("{{run_weekend_count}}", weekendDays.filter(d => runDays.has(d)).length.toString());
```

### 4. `supabase/functions/generate-plan/prompts/step3-workout-block-prompt.ts`

Add a new section **immediately before** the `## Output Format` section (currently around line 74). Insert:

```
### Final Validation (MANDATORY)
Before outputting your JSON, verify EVERY session against these checks. Fix any violations:
1. Is this sport eligible on this day? Check Daily Availability. If not → move to nearest eligible day with remaining capacity, or drop if no day fits.
2. Does the total duration on this day exceed the available minutes? If yes → reduce the longest session on that day to fit within the cap.
3. Are there available days with no sessions scheduled? If yes and the week's total hours are below target → add Easy sessions to unused eligible days.
```

### 5. `ai/prompts/step3-workout-block.txt`

Apply the exact same addition as #4.

## DO NOT CHANGE
- Step 1b prompt — no changes needed
- Post-processing functions — no changes
- Any other files

## Status Report
After completing all changes, provide:
1. The sport availability section as it would render for a user with swim_days=["Monday","Tuesday","Friday","Saturday","Sunday"], bike_days=all 7, run_days=all 7 (expected: swim 3+2, bike 5+2, run 5+2)
2. The full Final Validation section added to Step 3
3. Confirmation `.ts` and `.txt` are in sync for both Step 1 and Step 3
4. Full `buildStep1Prompt()` function after changes
