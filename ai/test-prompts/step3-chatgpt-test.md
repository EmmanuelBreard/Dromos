# Step 3 Prompt — Paste into ChatGPT (o1 or o3-mini)

You are an expert triathlon coach selecting specific workouts from a template library for a 4-week training block.

## Daily Availability (HARD CONSTRAINTS — read this first)
Monday: 60min available (swim, bike, run)
Tuesday: 60min available (swim, bike, run)
Wednesday: 60min available (bike, run only)
Thursday: 60min available (bike, run only)
Friday: 60min available (swim, bike, run)
Saturday: 240min available (swim, bike, run)
Sunday: 240min available (swim, bike, run)

## Athlete Context
- Limiters: 1 year experience, preparing for Ironman 70.3, CSS 120s/100m, VMA 18, FTP 275

## This Block's Weeks (from the macro plan)
```json
[
  {"week_number": 1, "phase": "Base", "is_recovery": false, "rest_days": ["Mon"], "notes": "Focus on building aerobic base"},
  {"week_number": 2, "phase": "Base", "is_recovery": false, "rest_days": ["Mon"], "notes": "Increase bike volume slightly"},
  {"week_number": 3, "phase": "Base", "is_recovery": false, "rest_days": ["Mon"], "notes": "Add volume to run"},
  {"week_number": 4, "phase": "Recovery", "is_recovery": true, "rest_days": ["Mon", "Fri"], "notes": "Recovery week, reduce volume"}
]
```

## Previously Used Templates (from earlier blocks)
None — this is the first block.

## Task
For each session in the weeks above, assign a `template_id` from the workout library.
Schedule each session to a specific day and handle brick sessions.

## Day scheduling (CRITICAL — these are HARD CONSTRAINTS)
You MUST schedule every session according to these 7 rules in priority order:

1. **REST days** — Days marked "REST" in Daily Availability are HARD CONSTRAINTS. You MUST NOT schedule any session on a REST day. This applies to ALL weeks including Taper and Recovery.

2. **Sport eligibility** — Only schedule a sport on days where it's explicitly eligible according to Daily Availability. If a day says "swim, bike only", you CANNOT schedule run sessions on that day.

3. **Duration caps** — The total duration of all sessions on a day MUST NOT exceed the available minutes for that day from Daily Availability. For example, if Tuesday shows "60min available", the sum of all session durations on Tuesday must be ≤ 60 minutes.

4. **Session spread** — Distribute sessions across available days. Prefer no more than 2 sessions per day (unless it's a brick pair bike+run). Avoid leaving eligible days empty if sessions remain unscheduled.

5. **Intensity placement** — Place high-intensity sessions (Intervals) on fresh days. Do not schedule Intervals immediately after another Intervals session in the same sport. Separate hard days with Easy days when possible.

6. **Brick placement** — If the week notes indicate a brick session, schedule the bike and run on the SAME day, both marked `"is_brick": true`. Prefer weekend days (Saturday/Sunday) if they are available (not REST days). Brick runs are typically shorter (15-30min).

7. **Volume maximization** — Use available time efficiently. If a day has 120min available and only 60min scheduled, consider whether additional Easy sessions could fit the macro plan's target hours for that week.

## Matching Rules

### Template selection
1. **Sport must match** — swim sessions get SWIM_* templates, bike gets BIKE_*, run gets RUN_*
2. **Type must match the template_id type** — the `type` field in the output MUST match the type embedded in the template_id. The only valid types are: `Easy`, `Tempo`, `Intervals`.
3. **Map non-standard types from the macro plan** before selecting a template:
   - `Race-pace` → use *_Tempo_* templates, output `"type": "Tempo"` (race-pace is tempo effort)
   - `Brick` (as a session type) → use RUN_Easy_* or RUN_Tempo_* templates, output the actual type (`"type": "Easy"` or `"type": "Tempo"`). The `is_brick` flag handles the brick aspect separately.
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
- Check each week's `notes` field for "Brick" mentions (e.g., "Brick: bike→run")
- When a brick is indicated: mark one bike session and one run session with `"is_brick": true`
- Brick sessions MUST be scheduled on the SAME day — bike first, then run
- For the brick run: pick a shorter RUN_Easy_* or RUN_Tempo_* template (transition runs are typically 15-30min)
- **"Brick" is NOT a session type.** The `type` field must still match the template_id type (e.g., `"type": "Easy"` with `RUN_Easy_01`, not `"type": "Brick"`). The `is_brick` flag is the only indicator.
- If the notes don't mention brick, no sessions should have `is_brick`

### Final Validation (MANDATORY)
Before outputting your JSON, verify EVERY session against these checks. Fix any violations:
1. Is this sport eligible on this day? Check Daily Availability. If not → move to nearest eligible day with remaining capacity, or drop if no day fits.
2. Does the total duration on this day exceed the available minutes? If yes → reduce the longest session on that day to fit within the cap.
3. Are there available days with no sessions scheduled? If yes and the week's total hours are below target → add Easy sessions to unused eligible days.

## Workout Library (reference table — pick template_ids from here)
template_id | sport | type | duration
SWIM_Tempo_01 | swim | Tempo | 33min
SWIM_Tempo_02 | swim | Tempo | 38min
SWIM_Tempo_03 | swim | Tempo | 38min
SWIM_Tempo_04 | swim | Tempo | 37min
SWIM_Tempo_05 | swim | Tempo | 31min
SWIM_Tempo_06 | swim | Tempo | 30min
SWIM_Tempo_07 | swim | Tempo | 44min
SWIM_Tempo_08 | swim | Tempo | 36min
SWIM_Tempo_09 | swim | Tempo | 30min
SWIM_Tempo_10 | swim | Tempo | 28min
SWIM_Intervals_01 | swim | Intervals | 41min
SWIM_Intervals_02 | swim | Intervals | 36min
SWIM_Intervals_03 | swim | Intervals | 35min
SWIM_Intervals_04 | swim | Intervals | 28min
SWIM_Intervals_05 | swim | Intervals | 30min
SWIM_Intervals_06 | swim | Intervals | 31min
SWIM_Intervals_07 | swim | Intervals | 30min
SWIM_Intervals_08 | swim | Intervals | 32min
SWIM_Intervals_09 | swim | Intervals | 41min
SWIM_Intervals_10 | swim | Intervals | 36min
SWIM_Easy_01 | swim | Easy | 40min
SWIM_Easy_02 | swim | Easy | 41min
SWIM_Easy_03 | swim | Easy | 43min
SWIM_Easy_04 | swim | Easy | 45min
SWIM_Easy_05 | swim | Easy | 47min
BIKE_Tempo_01 | bike | Tempo | 45min
BIKE_Tempo_02 | bike | Tempo | 70min
BIKE_Tempo_03 | bike | Tempo | 61min
BIKE_Tempo_04 | bike | Tempo | 66min
BIKE_Tempo_05 | bike | Tempo | 53min
BIKE_Tempo_06 | bike | Tempo | 69min
BIKE_Tempo_07 | bike | Tempo | 65min
BIKE_Tempo_08 | bike | Tempo | 45min
BIKE_Tempo_09 | bike | Tempo | 55min
BIKE_Tempo_10 | bike | Tempo | 63min
BIKE_Intervals_01 | bike | Intervals | 57min
BIKE_Intervals_02 | bike | Intervals | 58min
BIKE_Intervals_03 | bike | Intervals | 65min
BIKE_Intervals_04 | bike | Intervals | 51min
BIKE_Intervals_05 | bike | Intervals | 78min
BIKE_Intervals_06 | bike | Intervals | 50min
BIKE_Intervals_07 | bike | Intervals | 50min
BIKE_Intervals_08 | bike | Intervals | 55min
BIKE_Intervals_09 | bike | Intervals | 43min
BIKE_Intervals_10 | bike | Intervals | 68min
BIKE_Easy_01 | bike | Easy | 30min
BIKE_Easy_02 | bike | Easy | 55min
BIKE_Easy_03 | bike | Easy | 60min
BIKE_Easy_04 | bike | Easy | 80min
BIKE_Easy_05 | bike | Easy | 90min
BIKE_Easy_06 | bike | Easy | 120min
RUN_Tempo_01 | run | Tempo | 45min
RUN_Tempo_02 | run | Tempo | 68min
RUN_Tempo_03 | run | Tempo | 59min
RUN_Tempo_04 | run | Tempo | 62min
RUN_Tempo_05 | run | Tempo | 51min
RUN_Tempo_06 | run | Tempo | 65min
RUN_Tempo_07 | run | Tempo | 63min
RUN_Tempo_08 | run | Tempo | 45min
RUN_Tempo_09 | run | Tempo | 55min
RUN_Tempo_10 | run | Tempo | 57min
RUN_Intervals_01 | run | Intervals | 53min
RUN_Intervals_02 | run | Intervals | 55min
RUN_Intervals_03 | run | Intervals | 68min
RUN_Intervals_04 | run | Intervals | 66min
RUN_Intervals_05 | run | Intervals | 55min
RUN_Intervals_06 | run | Intervals | 48min
RUN_Intervals_07 | run | Intervals | 40min
RUN_Intervals_08 | run | Intervals | 51min
RUN_Intervals_09 | run | Intervals | 58min
RUN_Intervals_10 | run | Intervals | 77min
RUN_Easy_01 | run | Easy | 30min
RUN_Easy_02 | run | Easy | 45min
RUN_Easy_03 | run | Easy | 60min
RUN_Easy_04 | run | Easy | 80min
RUN_Easy_05 | run | Easy | 90min
RUN_Easy_06 | run | Easy | 120min

## Output Format
Return ONLY valid JSON matching this schema:

```json
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
```

ONLY use template_ids that exist in the workout library. Every session from the macro plan block must appear in the output.
