# DRO-62: Simplify Workout Library for Step 3 + Reorder Prompt

## Context
Post-DRO-59 eval shows GPT-4o still violates sport-day eligibility and duration caps. Root cause: the full workout library is ~80K chars (~20K tokens) injected into Step 3, drowning out the ~500-char constraint section. GPT-4o's "lost in the middle" problem deprioritizes rules buried in a massive prompt.

Fix: (a) build a simplified workout library at runtime containing only what Step 3 needs (template_id, sport, type, duration), (b) reorder the Step 3 prompt so Daily Availability appears first and the now-tiny library is just a reference table near the end.

## Branch
Create branch from main: `ebreard4/dro-62-dro-48-phase-5-simplify-library-reorder-prompt`

## Changes

### 1. `supabase/functions/generate-plan/index.ts` — New `buildSimplifiedLibrary()` function

Add the following two functions AFTER the `buildConstraintString()` function and BEFORE the `Deno.serve()` handler:

```typescript
// Helper: Recursively compute total duration_minutes from a segments array
// Handles nested repeats (segments within segments) and recovery blocks
function computeSegmentDuration(segments: any[]): number {
  let total = 0;
  for (const seg of segments) {
    if (seg.label === "repeat" && seg.repeats && seg.segments) {
      const innerDuration = computeSegmentDuration(seg.segments);
      total += seg.repeats * innerDuration;
      // Add recovery duration if present (once per repeat cycle, so repeats - 1 times,
      // but conservatively count repeats times since some templates use it per-rep)
      if (seg.recovery?.duration_minutes) {
        total += (seg.repeats - 1) * seg.recovery.duration_minutes;
      }
    } else if (seg.label === "rest") {
      // Rest segments between sets — counted as rest_seconds if present
      if (seg.rest_seconds) {
        total += seg.rest_seconds / 60;
      }
    } else if (seg.duration_minutes) {
      total += seg.duration_minutes;
    }
    // Segments with only distance_meters and no duration_minutes are skipped
    // (swim — handled separately via distance-based estimation)
  }
  return total;
}

// Helper: Recursively compute total distance_meters from a segments array (for swim)
function computeSegmentDistance(segments: any[]): number {
  let total = 0;
  for (const seg of segments) {
    if (seg.label === "repeat" && seg.repeats && seg.segments) {
      const innerDistance = computeSegmentDistance(seg.segments);
      total += seg.repeats * innerDistance;
      if (seg.recovery?.distance_meters) {
        total += (seg.repeats - 1) * seg.recovery.distance_meters;
      }
    } else if (seg.distance_meters) {
      total += seg.distance_meters;
    }
  }
  return total;
}

// Build a simplified workout library string for Step 3
// Strips segment details, keeps only: template_id, sport, type, duration_minutes
// Reduces prompt from ~80K chars to ~3K chars
function buildSimplifiedLibrary(workoutLibrary: any): string {
  const lines: string[] = [];

  for (const sport of ["swim", "bike", "run"]) {
    const templates = workoutLibrary[sport] || [];
    for (const tmpl of templates) {
      const tid: string = tmpl.template_id;
      // Extract type from template_id (e.g., "BIKE_Easy_01" → "Easy")
      const parts = tid.split("_");
      const type = parts.length >= 2 ? parts[1] : "Unknown";

      let durationMin: number;
      if (sport === "swim") {
        // Swim templates use distance_meters, not duration_minutes
        // Estimate duration at ~2min per 100m (reasonable amateur pace)
        const totalDistance = computeSegmentDistance(tmpl.segments || []);
        durationMin = Math.round(totalDistance / 100 * 2);
      } else {
        // Bike and run templates have duration_minutes in segments
        durationMin = Math.round(computeSegmentDuration(tmpl.segments || []));
      }

      lines.push(`${tid} | ${sport} | ${type} | ${durationMin}min`);
    }
  }

  return "template_id | sport | type | duration\n" + lines.join("\n");
}
```

### 2. `supabase/functions/generate-plan/index.ts` — Use simplified library in Step 3 block loop

In the Step 3 block loop (around line 604-639), make these changes:

**BEFORE** the `for (let b = 0; b < blocks.length; b++)` loop, add:
```typescript
    // Build simplified library for Step 3 (strips segment details, keeps only template matching info)
    const simplifiedLibrary = buildSimplifiedLibrary(workoutLibrary);
```

**CHANGE** the library injection line from:
```typescript
      finalPrompt = finalPrompt.replace("{{workout_library}}", WORKOUT_LIBRARY_STR);
```
to:
```typescript
      finalPrompt = finalPrompt.replace("{{workout_library}}", simplifiedLibrary);
```

Note: keep `WORKOUT_LIBRARY_STR` and `workoutLibrary` — they're still used by `fixConsecutiveRepeats(allBlockWeeks, workoutLibrary)` later.

### 3. `supabase/functions/generate-plan/prompts/step3-workout-block-prompt.ts` — Reorder prompt

Replace the ENTIRE prompt content with this reordered version. The key changes:
- Daily Availability moved to the TOP (right after the system message) so constraints are the first thing the LLM sees
- Workout Library moved to AFTER the matching rules (now a tiny reference table, not a 80K dump)
- All rules and constraints are concentrated in the middle, close to the output format

```typescript
export default `You are an expert triathlon coach selecting specific workouts from a template library for a 4-week training block.

## Daily Availability (HARD CONSTRAINTS — read this first)
{{constraints}}

## Athlete Context
- Limiters: {{limiters}}

## This Block's Weeks (from the macro plan)
{{block_weeks_json}}

## Previously Used Templates (from earlier blocks)
{{previously_used}}

## Task
For each session in the weeks above, assign a \`template_id\` from the workout library.
Schedule each session to a specific day and handle brick sessions.

## Day scheduling (CRITICAL — these are HARD CONSTRAINTS)
You MUST schedule every session according to these 7 rules in priority order:

1. **REST days** — Days marked "REST" in Daily Availability are HARD CONSTRAINTS. You MUST NOT schedule any session on a REST day. This applies to ALL weeks including Taper and Recovery.

2. **Sport eligibility** — Only schedule a sport on days where it's explicitly eligible according to Daily Availability. If a day says "swim, bike only", you CANNOT schedule run sessions on that day.

3. **Duration caps** — The total duration of all sessions on a day MUST NOT exceed the available minutes for that day from Daily Availability. For example, if Tuesday shows "60min available", the sum of all session durations on Tuesday must be ≤ 60 minutes.

4. **Session spread** — Distribute sessions across available days. Prefer no more than 2 sessions per day (unless it's a brick pair bike+run). Avoid leaving eligible days empty if sessions remain unscheduled.

5. **Intensity placement** — Place high-intensity sessions (Intervals) on fresh days. Do not schedule Intervals immediately after another Intervals session in the same sport. Separate hard days with Easy days when possible.

6. **Brick placement** — If the week notes indicate a brick session, schedule the bike and run on the SAME day, both marked \`"is_brick": true\`. Prefer weekend days (Saturday/Sunday) if they are available (not REST days). Brick runs are typically shorter (15-30min).

7. **Volume maximization** — Use available time efficiently. If a day has 120min available and only 60min scheduled, consider whether additional Easy sessions could fit the macro plan's target hours for that week.

## Matching Rules

### Template selection
1. **Sport must match** — swim sessions get SWIM_* templates, bike gets BIKE_*, run gets RUN_*
2. **Type must match the template_id type** — the \`type\` field in the output MUST match the type embedded in the template_id. The only valid types are: \`Easy\`, \`Tempo\`, \`Intervals\`.
3. **Map non-standard types from the macro plan** before selecting a template:
   - \`Race-pace\` → use *_Tempo_* templates, output \`"type": "Tempo"\` (race-pace is tempo effort)
   - \`Brick\` (as a session type) → use RUN_Easy_* or RUN_Tempo_* templates, output the actual type (\`"type": "Easy"\` or \`"type": "Tempo"\`). The \`is_brick\` flag handles the brick aspect separately.
   - Any other non-standard type → map to the closest valid type (Easy/Tempo/Intervals)
4. **Duration** — pick a template whose duration range fits the planned duration_minutes. If no exact match, pick the closest.

### Variety (CRITICAL — this is non-negotiable)
The library has multiple templates per sport/type. You MUST rotate through them:
- BIKE_Easy has 6 templates (01-06), RUN_Easy has 6 (01-06), SWIM_Easy has 5 (01-05)
- Each Tempo category has 10 templates, each Intervals category has 10 templates

**Rules:**
- NEVER use the same template_id in two consecutive weeks for the same sport/type slot
- Over this 4-week block, use at least 3 different templates per sport/type
- Check the "Previously Used Templates" list — do NOT start this block with the same template that ended the previous block for the same sport/type
- Cycle through ALL available templates in the category before repeating any

### Phase-appropriate difficulty
- **Base phase**: prefer lower-numbered templates (simpler structure, longer intervals)
- **Build/Peak phase**: prefer higher-numbered templates (more complex, shorter/harder intervals)
- **Recovery/Taper**: use Easy templates or low-numbered Tempo templates

### Brick sessions (CRITICAL)
- Check each week's \`notes\` field for "Brick" mentions (e.g., "Brick: bike→run")
- When a brick is indicated: mark one bike session and one run session with \`"is_brick": true\`
- Brick sessions MUST be scheduled on the SAME day — bike first, then run
- For the brick run: pick a shorter RUN_Easy_* or RUN_Tempo_* template (transition runs are typically 15-30min)
- **"Brick" is NOT a session type.** The \`type\` field must still match the template_id type (e.g., \`"type": "Easy"\` with \`RUN_Easy_01\`, not \`"type": "Brick"\`). The \`is_brick\` flag is the only indicator.
- If the notes don't mention brick, no sessions should have \`is_brick\`

### Final Validation (MANDATORY)
Before outputting your JSON, verify EVERY session against these checks. Fix any violations:
1. Is this sport eligible on this day? Check Daily Availability. If not → move to nearest eligible day with remaining capacity, or drop if no day fits.
2. Does the total duration on this day exceed the available minutes? If yes → reduce the longest session on that day to fit within the cap.
3. Are there available days with no sessions scheduled? If yes and the week's total hours are below target → add Easy sessions to unused eligible days.

## Workout Library (reference table — pick template_ids from here)
{{workout_library}}

## Output Format
Return ONLY valid JSON matching this schema:

{
  "weeks": [
    {
      "week_number": <number>,
      "phase": "<Base|Build|Peak|Taper|Recovery>",
      "sessions": [
        {
          "sport": "<swim|bike|run>",
          "type": "<Easy|Tempo|Intervals>",
          "template_id": "<e.g. RUN_Tempo_03>",
          "duration_minutes": <number>,
          "day": "<Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday>",
          "is_brick": <true|false>
        }
      ]
    }
  ]
}

ONLY use template_ids that exist in the workout library. Every session from the macro plan block must appear in the output.
`;
```

### 4. `ai/prompts/step3-workout-block.txt`

Apply the EXACT same reordered prompt content as #3, but as plain text (no `export default \`` wrapper, no trailing `` `; ``).

### 5. `supabase/functions/generate-plan/prompts/step3-workout-block.txt`

Apply the EXACT same reordered prompt content as #3, but as plain text (no `export default \`` wrapper, no trailing `` `; ``).

## DO NOT CHANGE
- Step 1, Step 1b, Step 2 prompts — no changes
- Post-processing functions (`fixTypes`, `fixBrickPairs`, `fixConsecutiveRepeats`) — no changes
- Any other files not listed above

## Status Report
After completing all changes, provide:
1. The full `buildSimplifiedLibrary()` function as written
2. The full `computeSegmentDuration()` and `computeSegmentDistance()` functions as written
3. Confirmation of the prompt reorder — list the section headings in order as they appear in the new Step 3 prompt
4. A sample of what the simplified library output looks like for the first 5 swim templates and first 5 bike templates (just show the lines)
5. Confirmation that all three Step 3 files are in sync: `.ts`, `supabase/.../step3-workout-block.txt`, `ai/prompts/step3-workout-block.txt`
6. The injection line change in `index.ts` (old line vs new line)
