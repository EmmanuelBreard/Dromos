# DRO-48 Phase 1: Clean Up Step 1 + Step 1b Prompts

## Context
We're fixing plan generation to respect user availability/duration caps (DRO-48). Phase 1 removes all `{{constraints}}` and `rest_days` references from Step 1 (macro plan) and Step 1b (MD-to-JSON). Step 1 should be volume-only — no per-day scheduling concerns.

## Branch
Create branch: `ebreard4/dro-48-plan-generation-ignores-daily-availability-and-duration-caps`

## Changes

### 1. `supabase/functions/generate-plan/prompts/step1-macro-plan-prompt.ts`

**Remove line 15** (`- Injuries / constraints: {{constraints}}`):
```
BEFORE (lines 13-16):
- Swim CSS pace: {{swim_css}} per 100m
- Limiters: {{limiters}}
- Injuries / constraints: {{constraints}}

## Task

AFTER:
- Swim CSS pace: {{swim_css}} per 100m
- Limiters: {{limiters}}

## Task
```

**Remove line 36** (`- At least 1 rest day per week`):
```
BEFORE (lines 33-37):
### Intensity distribution
- No back-to-back high-intensity days in the same sport
- Max 2 high-intensity sessions (Intervals or Tempo) per sport per week
- At least 1 rest day per week

### Limiter strategy (CRITICAL)

AFTER:
### Intensity distribution
- No back-to-back high-intensity days in the same sport
- Max 2 high-intensity sessions (Intervals or Tempo) per sport per week

### Limiter strategy (CRITICAL)
```

**Remove line 48** (`- Constraints: {{constraints}} — plan around these strictly`):
```
BEFORE (lines 44-49):
### Budget (HARD CONSTRAINT)
- The athlete has {{weekly_hours}}h per week. This is a HARD CEILING — no week may exceed it.
- Before finalizing each week, verify: swim_hours + bike_hours + run_hours ≤ {{weekly_hours}}
- If sessions don't fit, drop the lowest-priority session (usually an extra Easy)
- Constraints: {{constraints}} — plan around these strictly

## Output Format

AFTER:
### Budget (HARD CONSTRAINT)
- The athlete has {{weekly_hours}}h per week. This is a HARD CEILING — no week may exceed it.
- Before finalizing each week, verify: swim_hours + bike_hours + run_hours ≤ {{weekly_hours}}
- If sessions don't fit, drop the lowest-priority session (usually an extra Easy)

## Output Format
```

**Remove line 65** (`Rest: <day>, <day>`):
```
BEFORE (lines 62-67):
- Bike: <Type> <duration>min, <Type> <duration>min
- Run: <Type> <duration>min, <Type> <duration>min
Rest: <day>, <day>
Notes: <brief note>

AFTER:
- Bike: <Type> <duration>min, <Type> <duration>min
- Run: <Type> <duration>min, <Type> <duration>min
Notes: <brief note>
```

### 2. `ai/prompts/step1-macro-plan.txt`
Apply the EXACT same 4 removals as above. Note: this file already has lines 15 and 65 removed (check before editing). Lines 36 (rest day rule) and 48 (constraints in budget) still need removing.

### 3. `supabase/functions/generate-plan/prompts/step2-md-to-json-prompt.ts`

**Remove line 40** (`"rest_days": ["<day_name>"],`):
```
BEFORE (lines 38-42):
      "run": {
        "hours": <number>,
        "sessions": [{"type": "<Easy|Tempo|Intervals>", "duration_minutes": <number>}]
      },
      "rest_days": ["<day_name>"],
      "notes": "<string>"

AFTER:
      "run": {
        "hours": <number>,
        "sessions": [{"type": "<Easy|Tempo|Intervals>", "duration_minutes": <number>}]
      },
      "notes": "<string>"
```

### 4. `ai/prompts/step2-md-to-json.txt`
Apply the EXACT same removal as #3 (remove the `"rest_days"` line).

### 5. `supabase/functions/generate-plan/index.ts`

**Remove line 194** (`prompt = prompt.replace("{{constraints}}", "none");`) from `buildStep1Prompt`:
```
BEFORE (lines 192-196):
  prompt = prompt.replace("{{limiters}}", "none");
  prompt = prompt.replace("{{constraints}}", "none");

  return prompt;

AFTER:
  prompt = prompt.replace("{{limiters}}", "none");

  return prompt;
```

## Status Report
After completing all changes, provide:
1. List of every line removed/changed per file
2. Confirm `.ts` and `.txt` versions are now in sync for both step1 and step2
3. Confirm no remaining references to `{{constraints}}` in Step 1 or Step 1b files
4. Confirm no remaining references to `rest_days` in Step 1 or Step 1b files
