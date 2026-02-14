# DRO-58: Add Session Duration Caps to Step 1 Prompt

## Context
Step 1 generates sessions (e.g. 120min bike) that exceed weekday duration caps (60min). Step 3 can't split these, so it violates caps. Fix: tell Step 1 the max single-session duration so it sizes sessions appropriately.

## Branch
Create branch from main: `ebreard4/dro-58-dro-48-phase-2b-add-session-duration-caps-to-step-1-prompt`

## Changes

### 1. `supabase/functions/generate-plan/prompts/step1-macro-plan-prompt.ts`

Add one line to the Budget section. Currently (after DRO-54 cleanup):

```
### Budget (HARD CONSTRAINT)
- The athlete has {{weekly_hours}}h per week. This is a HARD CEILING — no week may exceed it.
- Before finalizing each week, verify: swim_hours + bike_hours + run_hours ≤ {{weekly_hours}}
- If sessions don't fit, drop the lowest-priority session (usually an extra Easy)
```

Add after the last bullet:
```
- Session sizing: no single session longer than {{max_weekday_minutes}}min on weekdays or {{max_weekend_minutes}}min on weekends. If a sport needs more hours than one session allows, split into multiple shorter sessions.
```

### 2. `ai/prompts/step1-macro-plan.txt`

Apply the exact same addition as #1.

### 3. `supabase/functions/generate-plan/index.ts` — `buildStep1Prompt()`

Add the following BEFORE the `return prompt;` line in `buildStep1Prompt()` (currently around line 195):

```typescript
  // Compute max session durations from daily caps
  const weekdayDurations = [
    user.mon_duration, user.tue_duration, user.wed_duration,
    user.thu_duration, user.fri_duration
  ].filter((d: number | null) => d != null);
  const weekendDurations = [
    user.sat_duration, user.sun_duration
  ].filter((d: number | null) => d != null);

  const maxWeekday = weekdayDurations.length > 0
    ? Math.min(...weekdayDurations)
    : 60;
  const maxWeekend = weekendDurations.length > 0
    ? Math.max(...weekendDurations)
    : 240;

  prompt = prompt.replace("{{max_weekday_minutes}}", maxWeekday.toString());
  prompt = prompt.replace("{{max_weekend_minutes}}", maxWeekend.toString());
```

Logic:
- `maxWeekday` = min of all weekday durations (conservative — ensures any session fits on ANY weekday)
- `maxWeekend` = max of weekend durations (permissive — allows long sessions on biggest weekend day)
- Fallback defaults: 60min weekday, 240min weekend

## DO NOT CHANGE
- Step 3 prompt — already has per-day constraint string from DRO-55
- Step 1b prompt — no changes needed
- Any other post-processing functions

## Status Report
After completing all changes, provide:
1. The exact line added to Step 1 prompt
2. The computed values for the `ebreard4` profile (should be: weekday=60, weekend=240)
3. Confirmation `.ts` and `.txt` are in sync
4. Full `buildStep1Prompt()` function after changes
