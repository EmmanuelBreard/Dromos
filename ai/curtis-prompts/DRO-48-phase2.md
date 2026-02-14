# DRO-48 Phase 2: Constraint-Aware Scheduling (Step 3 + index.ts)

## Context
Phase 1 removed constraints/rest_days from Step 1 and Step 1b. Now we inject real user availability into Step 3 and update `index.ts` to build the constraint string, remove `fixRestDays()`, and compute rest_days from actual sessions at DB write time.

## Branch
Same branch as Phase 1: `ebreard4/dro-48-plan-generation-ignores-daily-availability-and-duration-caps`

## Changes

### 1. New function `buildConstraintString(user)` in `index.ts`

Add this function after `buildStep2Prompt` (after line 203). It reads user profile fields and builds a structured constraint string for the LLM.

**User profile fields available:**
- `user.swim_days`: `string[]` e.g. `["Tuesday", "Friday", "Saturday", "Sunday"]`
- `user.bike_days`: `string[]` e.g. `["Monday", "Wednesday", "Saturday", "Sunday"]`
- `user.run_days`: `string[]` e.g. `["Tuesday", "Thursday", "Saturday", "Sunday"]`
- `user.mon_duration` through `user.sun_duration`: `number | null` (minutes, null = rest day)

**Function logic:**
```typescript
function buildConstraintString(user: any): string {
  const dayMap: Record<string, { key: string }> = {
    Monday: { key: "mon_duration" },
    Tuesday: { key: "tue_duration" },
    Wednesday: { key: "wed_duration" },
    Thursday: { key: "thu_duration" },
    Friday: { key: "fri_duration" },
    Saturday: { key: "sat_duration" },
    Sunday: { key: "sun_duration" },
  };

  const swimDays = new Set(user.swim_days || []);
  const bikeDays = new Set(user.bike_days || []);
  const runDays = new Set(user.run_days || []);

  const lines: string[] = [];
  for (const [day, { key }] of Object.entries(dayMap)) {
    const duration = user[key];
    if (duration == null) {
      lines.push(`- ${day}: REST`);
    } else {
      const sports: string[] = [];
      if (swimDays.has(day)) sports.push("swim");
      if (bikeDays.has(day)) sports.push("bike");
      if (runDays.has(day)) sports.push("run");
      const sportStr = sports.length > 0 ? sports.join(", ") : "none";
      lines.push(`- ${day}: ${duration}min — ${sportStr}`);
    }
  }

  return lines.join("\n");
}
```

**Example output:**
```
- Monday: REST
- Tuesday: 60min — swim, run
- Wednesday: 60min — bike
- Thursday: 60min — run
- Friday: 60min — swim, bike
- Saturday: 180min — swim, bike, run
- Sunday: REST
```

### 2. Rewrite Step 3 prompt — Day scheduling section

Replace the ENTIRE `### Day scheduling (CRITICAL)` section (lines 55-59) AND the `## Athlete Context` section (lines 9-11) in **both** `step3-workout-block-prompt.ts` and `step3-workout-block.txt`.

**Replace lines 9-11:**
```
BEFORE:
## Athlete Context
- Limiters: {{limiters}}
- Constraints: {{constraints}}

AFTER:
## Athlete Context
- Limiters: {{limiters}}

## Daily Availability (HARD CONSTRAINTS)
{{constraints}}
```

**Replace lines 55-59:**
```
BEFORE:
### Day scheduling (CRITICAL)
- **Rest days are HARD CONSTRAINTS** — before assigning a day to any session, check the week's `rest_days` array. If the day appears in `rest_days`, you MUST NOT schedule anything on that day. This applies to ALL weeks including Taper and Recovery.
- Spread sessions across available (non-rest) days — no more than 2 sessions per day (unless one is a brick pair)
- Place high-intensity sessions (Intervals) on fresh days, not after another hard session
- Brick sessions go on weekend days when possible (if those days are not rest days)

AFTER:
### Day scheduling (CRITICAL)
The "Daily Availability" section above defines HARD CONSTRAINTS for every day of the week. You MUST obey ALL of the following rules:

1. **REST days** — if a day says "REST", you MUST NOT schedule any session on that day. This applies to ALL weeks including Taper and Recovery.
2. **Sport eligibility** — a session for a sport may ONLY be placed on a day that lists that sport. For example, if Tuesday allows "swim, run", you cannot place a bike session on Tuesday.
3. **Duration cap** — the total duration of ALL sessions on a given day MUST NOT exceed that day's minute cap. For example, if Wednesday is "60min", you cannot schedule a 45min bike + 30min run on Wednesday (75min > 60min).
4. **Spread sessions** across available days — no more than 2 sessions per day (unless one is a brick pair).
5. Place high-intensity sessions (Intervals) on fresh days, not after another hard session.
6. Brick sessions go on weekend days when possible (if those days are not REST days).
7. **Maximize weekly volume** — use all available days to approach the weekly hour budget from the macro plan. Do not leave available days empty unless the week's volume is already met.
```

### 3. Update `index.ts` Step 3 block loop (around line 565)

**Replace line 565** (`finalPrompt = finalPrompt.replace("{{constraints}}", "none");`):
```
BEFORE (line 565):
      finalPrompt = finalPrompt.replace("{{constraints}}", "none");

AFTER:
      finalPrompt = finalPrompt.replace("{{constraints}}", buildConstraintString(user));
```

Note: `user` is already in scope — it's the user profile object fetched at the top of the handler. Verify variable name matches (it's `user` from the `.single()` call around line 400).

### 4. Remove `fixRestDays()` call (line 596)

```
BEFORE (lines 592-596):
    // Post-processing
    fixTypes(allBlockWeeks);
    fixBrickPairs(allBlockWeeks);
    fixConsecutiveRepeats(allBlockWeeks, workoutLibrary);
    fixRestDays(allBlockWeeks, weeks);

AFTER:
    // Post-processing
    fixTypes(allBlockWeeks);
    fixBrickPairs(allBlockWeeks);
    fixConsecutiveRepeats(allBlockWeeks, workoutLibrary);
```

Also **delete the entire `fixRestDays` function** (lines 326-361) and the `ALL_DAYS` constant it depends on (search for it — it's likely defined near line 55-60).

### 5. Compute `rest_days` from actual sessions at DB write time (line 633)

**Replace line 633** (`rest_days: macroWeek?.rest_days || [],`):
```
BEFORE (lines 626-638):
      const { data: weekRow, error: weekError } = await dbClient
        .from("plan_weeks")
        .insert({
          plan_id: planId,
          week_number: week.week_number,
          phase: week.phase,
          is_recovery: week.phase === "Recovery",
          rest_days: macroWeek?.rest_days || [],
          notes: macroWeek?.notes || null,
          start_date: formatDate(weekStartDate),
        })
        .select()
        .single();

AFTER:
      // Compute rest_days from actual sessions: days with no sessions = rest days
      const ALL_DAYS_OF_WEEK = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
      const daysWithSessions = new Set((week.sessions || []).map((s: any) => normDay(s.day)));
      const computedRestDays = ALL_DAYS_OF_WEEK.filter((d) => !daysWithSessions.has(d));

      const { data: weekRow, error: weekError } = await dbClient
        .from("plan_weeks")
        .insert({
          plan_id: planId,
          week_number: week.week_number,
          phase: week.phase,
          is_recovery: week.phase === "Recovery",
          rest_days: computedRestDays,
          notes: macroWeek?.notes || null,
          start_date: formatDate(weekStartDate),
        })
        .select()
        .single();
```

### 6. Sync `.ts` and `.txt` for Step 3

Ensure `ai/prompts/step3-workout-block.txt` matches the content of `supabase/functions/generate-plan/prompts/step3-workout-block-prompt.ts` exactly (minus the `export default` wrapper and backticks).

## DO NOT CHANGE
- `fixTypes()`, `fixBrickPairs()`, `fixConsecutiveRepeats()` — keep as-is
- `{{limiters}}` — stays `"none"` (out of scope)
- `plan_weeks.rest_days` column — no DB migration, just computed differently
- Step 1 and Step 1b prompts — already done in Phase 1

## Status Report
After completing all changes, provide:
1. Full content of the new `buildConstraintString()` function
2. Full content of the new Day scheduling section in Step 3 prompt
3. Confirmation that `fixRestDays()` function AND its call are both removed
4. Confirmation that `ALL_DAYS` constant (if it was only used by fixRestDays) is removed
5. Confirmation that rest_days is now computed from sessions at DB write time
6. Confirmation `.ts` and `.txt` are in sync for Step 3
7. Any variable scoping issues encountered (e.g. `user` not accessible in Step 3 loop)
