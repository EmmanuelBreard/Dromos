// Step 3 Block Orchestrator
// Splits each athlete's macro plan into 4-week blocks, processes sequentially
// with OpenAI, carries previously_used_templates between blocks, then
// concatenates results and applies post-processing fixes.

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
require('dotenv').config({ path: path.join(__dirname, '..', '..', '.env') });

const BLOCK_SIZE = 4;
const MODEL = 'gpt-4.1';
const TEMPERATURE = 0.2;
const MAX_TOKENS = 4096; // Much smaller per block — only 4 weeks

// ── Load assets ──────────────────────────────────────────────────────────────

const promptTemplate = fs.readFileSync(
  path.join(__dirname, '..', 'prompts', 'step3-workout-block.txt'), 'utf8'
);
const workoutLibraryRaw = fs.readFileSync(
  path.join(__dirname, '..', 'context', 'workout-library.json'), 'utf8'
);
const workoutLibrary = JSON.parse(workoutLibraryRaw);

// Build simplified library string (matches production buildSimplifiedLibrary)
function buildSimplifiedLibrary(lib) {
  const lines = [];
  for (const sport of ['swim', 'bike', 'run']) {
    for (const tmpl of lib[sport] || []) {
      const tid = tmpl.template_id;
      const type = tid.split('_')[1];
      lines.push(`${tid} | ${sport} | ${type} | ${tmpl.duration_minutes}min`);
    }
  }
  return 'template_id | sport | type | duration\n' + lines.join('\n');
}

const simplifiedLibrary = buildSimplifiedLibrary(workoutLibrary);

// Load athletes.yaml for per-day availability
const athletesRaw = fs.readFileSync(path.join(__dirname, 'vars', 'athletes.yaml'), 'utf8');
const athleteProfiles = yaml.load(athletesRaw);

// Build per-day constraint string from athlete profile (matches production buildConstraintString)
function buildConstraintString(vars) {
  const dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const durationFields = ['mon_duration', 'tue_duration', 'wed_duration', 'thu_duration', 'fri_duration', 'sat_duration', 'sun_duration'];

  // Parse sport days from comma-separated string
  const parseDays = (s) => new Set((s || '').split(',').map(d => d.trim()).filter(Boolean));
  const swimDays = parseDays(vars.swim_days);
  const bikeDays = parseDays(vars.bike_days);
  const runDays = parseDays(vars.run_days);

  const lines = [];
  for (let i = 0; i < dayNames.length; i++) {
    const day = dayNames[i];
    const duration = parseInt(vars[durationFields[i]] || '0', 10);

    if (!duration) {
      lines.push(`${day}: REST`);
    } else {
      const eligible = [];
      if (swimDays.has(day)) eligible.push('swim');
      if (bikeDays.has(day)) eligible.push('bike');
      if (runDays.has(day)) eligible.push('run');

      if (eligible.length === 0) {
        lines.push(`${day}: ${duration}min available (no sports eligible)`);
      } else if (eligible.length === 3) {
        lines.push(`${day}: ${duration}min available (all sports)`);
      } else {
        lines.push(`${day}: ${duration}min available (${eligible.join(', ')} only)`);
      }
    }
  }
  return lines.join('\n');
}

// Parse athlete profile into structured constraint objects for post-processing fixers.
// Returns { dayCaps: { Monday: 60, ... }, sportEligibility: { Monday: ['swim','run'], ... } }
function parseConstraints(vars) {
  const dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const durationFields = ['mon_duration', 'tue_duration', 'wed_duration', 'thu_duration', 'fri_duration', 'sat_duration', 'sun_duration'];

  const parseDays = (s) => new Set((s || '').split(',').map(d => d.trim()).filter(Boolean));
  const swimDays = parseDays(vars.swim_days);
  const bikeDays = parseDays(vars.bike_days);
  const runDays = parseDays(vars.run_days);

  const dayCaps = {};
  const sportEligibility = {};

  for (let i = 0; i < dayNames.length; i++) {
    const day = dayNames[i];
    const duration = parseInt(vars[durationFields[i]] || '0', 10);
    dayCaps[day] = duration;

    const eligible = [];
    if (swimDays.has(day)) eligible.push('swim');
    if (bikeDays.has(day)) eligible.push('bike');
    if (runDays.has(day)) eligible.push('run');
    sportEligibility[day] = eligible;
  }

  return { dayCaps, sportEligibility, weeklyHours: parseInt(vars.weekly_hours || '0', 10) };
}

// Compute session priority for eviction ordering.
// Intervals(3) > Tempo(2) > Easy(1), +0.5 if is_brick.
function sessionPriority(session) {
  const typeScores = { Intervals: 3, Tempo: 2, Easy: 1 };
  return (typeScores[session.type] || 1) + (session.is_brick ? 0.5 : 0);
}

// Build template_id → duration_minutes lookup from workout library.
// e.g. { SWIM_Easy_01: 40, BIKE_Tempo_01: 45, ... }
function buildTemplateDurationMap(lib) {
  const map = {};
  for (const sport of ['swim', 'bike', 'run']) {
    for (const tmpl of lib[sport] || []) {
      map[tmpl.template_id] = tmpl.duration_minutes;
    }
  }
  return map;
}

const templateDurationMap = buildTemplateDurationMap(workoutLibrary);

// Build constraint map: athlete_name -> constraint string (for prompt)
const constraintMap = {};
// Build parsed constraints map: athlete_name -> { dayCaps, sportEligibility } (for fixers)
const parsedConstraintsMap = {};
for (const a of athleteProfiles) {
  constraintMap[a.vars.athlete_name] = buildConstraintString(a.vars);
  parsedConstraintsMap[a.vars.athlete_name] = parseConstraints(a.vars);
}

const step2ResultsPath = path.join(__dirname, 'results', 'step2.json');
const step1ResultsPath = path.join(__dirname, 'results', 'step1.json');
const outputPath = path.join(__dirname, 'results', 'step3-blocks.json');

if (!fs.existsSync(step2ResultsPath)) {
  console.error('No step 2 results found. Run step 2 first.');
  process.exit(1);
}

const step2Data = JSON.parse(fs.readFileSync(step2ResultsPath, 'utf8'));
const step2Results = step2Data.results?.results || step2Data.results || [];

let step1Results = [];
if (fs.existsSync(step1ResultsPath)) {
  const step1Data = JSON.parse(fs.readFileSync(step1ResultsPath, 'utf8'));
  step1Results = step1Data.results?.results || step1Data.results || [];
}

// ── Day normalization (for post-processing) ──────────────────────────────────

const DAY_NORM = {
  'mon': 'Monday', 'monday': 'Monday',
  'tue': 'Tuesday', 'tues': 'Tuesday', 'tuesday': 'Tuesday',
  'wed': 'Wednesday', 'wednesday': 'Wednesday',
  'thu': 'Thursday', 'thur': 'Thursday', 'thurs': 'Thursday', 'thursday': 'Thursday',
  'fri': 'Friday', 'friday': 'Friday',
  'sat': 'Saturday', 'saturday': 'Saturday',
  'sun': 'Sunday', 'sunday': 'Sunday'
};
const ALL_DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
function normDay(d) { return DAY_NORM[(d || '').toLowerCase()] || d; }

// ── OpenAI call ──────────────────────────────────────────────────────────────

async function callOpenAI(prompt) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error('OPENAI_API_KEY not set');

  const resp = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`
    },
    body: JSON.stringify({
      model: MODEL,
      temperature: TEMPERATURE,
      max_tokens: MAX_TOKENS,
      response_format: { type: 'json_object' },
      messages: [{ role: 'user', content: prompt }]
    })
  });

  if (!resp.ok) {
    const err = await resp.text();
    throw new Error(`OpenAI API error ${resp.status}: ${err}`);
  }

  const data = await resp.json();
  return data.choices[0].message.content;
}

// ── Build prompt for a block ─────────────────────────────────────────────────

function buildPrompt(blockWeeks, athleteName, limiters, constraints, previouslyUsed) {
  let prompt = promptTemplate;
  prompt = prompt.replace('{{workout_library}}', simplifiedLibrary);
  prompt = prompt.replace('{{block_weeks_json}}', JSON.stringify(blockWeeks, null, 2));
  prompt = prompt.replace('{{athlete_name}}', athleteName);
  prompt = prompt.replace('{{limiters}}', limiters);
  prompt = prompt.replace('{{constraints}}', constraints);

  const prevStr = previouslyUsed.length > 0
    ? previouslyUsed.map(p => `- ${p.sport} ${p.type}: last used ${p.template_id} in W${p.week}`).join('\n')
    : 'None — this is the first block.';
  prompt = prompt.replace('{{previously_used}}', prevStr);

  return prompt;
}

// ── Extract last-used templates from a block result ──────────────────────────

function extractLastUsed(blockResult) {
  const lastUsed = {};
  for (const week of (blockResult.weeks || [])) {
    for (const session of (week.sessions || [])) {
      const key = `${session.sport}_${session.type}`;
      lastUsed[key] = {
        sport: session.sport,
        type: session.type,
        template_id: session.template_id,
        week: week.week_number
      };
    }
  }
  return Object.values(lastUsed);
}

// ── Post-processing: fix type from template_id (source of truth) ─────────────

function fixTypes(planWeeks) {
  let fixes = 0;
  for (const week of planWeeks) {
    for (const session of (week.sessions || [])) {
      const tid = session.template_id;
      if (!tid) continue;
      // Extract type from template_id: e.g. "SWIM_Easy_01" → "Easy"
      const tidType = tid.split('_')[1];
      if (tidType && session.type !== tidType) {
        console.log(`  Fix: W${week.week_number} ${tid} type "${session.type}" → "${tidType}"`);
        session.type = tidType;
        fixes++;
      }
    }
  }
  return fixes;
}

// ── Post-processing: fix brick pairs (both sessions on same day must have is_brick) ──

function fixBrickPairs(planWeeks) {
  let fixes = 0;
  for (const week of planWeeks) {
    // Group sessions by day
    const byDay = {};
    for (const session of (week.sessions || [])) {
      const d = normDay(session.day);
      byDay[d] = byDay[d] || [];
      byDay[d].push(session);
    }
    // If any session on a day has is_brick, ensure the bike+run pair both have it
    for (const [day, sessions] of Object.entries(byDay)) {
      const hasBrick = sessions.some(s => s.is_brick);
      if (!hasBrick) continue;
      const bike = sessions.find(s => s.sport === 'bike');
      const run = sessions.find(s => s.sport === 'run');
      if (bike && run) {
        if (!bike.is_brick) { bike.is_brick = true; fixes++; console.log(`  Fix: W${week.week_number} ${day} ${bike.template_id} marked is_brick`); }
        if (!run.is_brick) { run.is_brick = true; fixes++; console.log(`  Fix: W${week.week_number} ${day} ${run.template_id} marked is_brick`); }
        // Enforce bike→run ordering in the sessions array
        const bikeIdx = (week.sessions || []).indexOf(bike);
        const runIdx = (week.sessions || []).indexOf(run);
        if (bikeIdx >= 0 && runIdx >= 0 && runIdx < bikeIdx) {
          week.sessions[runIdx] = bike;
          week.sessions[bikeIdx] = run;
        }
      }
    }
    // Also fix "type": "Brick" → derive from template_id (handled by fixTypes)
  }
  return fixes;
}

// ── Post-processing: fix consecutive-week template repeats ───────────────────

function fixConsecutiveRepeats(planWeeks) {
  // Build catalog of available templates per category from the library
  const lib = workoutLibrary;
  const catalog = {}; // "swim_Easy" -> ["SWIM_Easy_01", "SWIM_Easy_02", ...]
  for (const sport of ['swim', 'bike', 'run']) {
    if (lib[sport]) {
      for (const w of lib[sport]) {
        const type = w.template_id.split('_')[1];
        const cat = `${sport}_${type}`;
        if (!catalog[cat]) catalog[cat] = [];
        catalog[cat].push(w.template_id);
      }
    }
  }

  let fixes = 0;
  const sorted = [...planWeeks].sort((a, b) => a.week_number - b.week_number);

  for (let i = 1; i < sorted.length; i++) {
    const prevWeek = sorted[i - 1];
    const currWeek = sorted[i];

    // Build map of previous week's templates per sport/type
    const prevMap = {};
    for (const s of (prevWeek.sessions || [])) {
      const key = `${s.sport}_${s.type}`;
      if (!prevMap[key]) prevMap[key] = new Set();
      prevMap[key].add(s.template_id);
    }

    // Check current week for repeats and swap with closest-duration alternative
    for (const session of (currWeek.sessions || [])) {
      const key = `${session.sport}_${session.type}`;
      if (prevMap[key] && prevMap[key].has(session.template_id)) {
        const options = (catalog[key] || []).filter(t => t !== session.template_id);
        if (options.length > 0) {
          const originalDuration = templateDurationMap[session.template_id] || 0;
          // Sort by closest duration to avoid introducing cap violations downstream
          options.sort((a, b) =>
            Math.abs((templateDurationMap[a] || 0) - originalDuration) -
            Math.abs((templateDurationMap[b] || 0) - originalDuration)
          );
          const alt = options[0];
          console.log(`  Fix: W${currWeek.week_number} ${session.template_id} (${originalDuration}min) → ${alt} (${templateDurationMap[alt]}min) (consecutive repeat)`);
          session.template_id = alt;
          session.duration_minutes = templateDurationMap[alt] || session.duration_minutes;
          fixes++;
        }
      }
    }
  }
  return fixes;
}

// ── Post-processing: fix rest day violations (cap-aware + sport-eligibility-aware) ──
// Moves sessions off rest days to eligible days that have remaining capacity.
// Falls back to priority-based eviction when no day has room.

function fixRestDays(planWeeks, macroWeeks, dayCaps, sportEligibility) {
  let fixes = 0;
  for (const week of planWeeks) {
    const macroWeek = macroWeeks.find(w => w.week_number === week.week_number);
    if (!macroWeek || !macroWeek.rest_days) continue;

    const restDays = new Set(macroWeek.rest_days.map(normDay));
    if (restDays.size === 0) continue;

    // Track used minutes per day for cap checking
    const usedMinutes = {};
    for (const s of (week.sessions || [])) {
      const d = normDay(s.day);
      usedMinutes[d] = (usedMinutes[d] || 0) + (s.duration_minutes || 0);
    }

    // Snapshot sessions on rest days to avoid splice-during-iteration bugs
    const restSessions = (week.sessions || []).filter(s => restDays.has(normDay(s.day)));

    for (const session of restSessions) {
      const d = normDay(session.day);
      const dur = session.duration_minutes || 0;

      // Find eligible days: not a rest day, sport is allowed, and has remaining capacity
      const candidates = ALL_DAYS.filter(day => {
        if (restDays.has(day)) return false;
        const eligible = sportEligibility[day] || [];
        if (!eligible.includes(session.sport)) return false;
        const remaining = (dayCaps[day] || 0) - (usedMinutes[day] || 0);
        return remaining >= dur;
      });

      if (candidates.length > 0) {
        // Pick the day with the most remaining capacity
        candidates.sort((a, b) =>
          ((dayCaps[b] || 0) - (usedMinutes[b] || 0)) -
          ((dayCaps[a] || 0) - (usedMinutes[a] || 0))
        );
        const newDay = candidates[0];
        console.log(`  Fix: W${week.week_number} ${session.template_id} ${d} → ${newDay} (rest day, ${dur}min fits)`);
        usedMinutes[d] = (usedMinutes[d] || 0) - dur;
        session.day = newDay;
        usedMinutes[newDay] = (usedMinutes[newDay] || 0) + dur;
        fixes++;
      } else {
        // No day has capacity — evict lowest-priority session in the week if current outranks
        const currentPriority = sessionPriority(session);
        let lowestSession = null;
        let lowestPriority = Infinity;

        for (const other of (week.sessions || [])) {
          if (other === session) continue;
          const otherDay = normDay(other.day);
          if (restDays.has(otherDay)) continue;
          const p = sessionPriority(other);
          if (p < lowestPriority) {
            lowestPriority = p;
            lowestSession = other;
          }
        }

        if (lowestSession && currentPriority > lowestPriority) {
          const evictDay = normDay(lowestSession.day);
          const evictDur = lowestSession.duration_minutes || 0;
          console.log(`  Fix: W${week.week_number} evict ${lowestSession.template_id} (priority ${lowestPriority}) from ${evictDay}, move ${session.template_id} (priority ${currentPriority}) ${d} → ${evictDay}`);
          usedMinutes[evictDay] = (usedMinutes[evictDay] || 0) - evictDur;
          usedMinutes[d] = (usedMinutes[d] || 0) - dur;
          const idx = week.sessions.indexOf(lowestSession);
          if (idx >= 0) week.sessions.splice(idx, 1);
          session.day = evictDay;
          usedMinutes[evictDay] = (usedMinutes[evictDay] || 0) + dur;
          fixes++;
        }
      }
    }
  }
  return fixes;
}

// ── Post-processing: fix duration cap violations ─────────────────────────────
// When total session minutes on a day exceed dayCaps[day], apply cascading fixes:
//   1. Swap longest session to shorter template (same sport/type, within 20% margin)
//   2. Move session to eligible day with remaining capacity
//   3. Evict lowest-priority session in the week (if target outranks)
//   4. Last resort: drop lowest-priority session on the day

function fixDurationCaps(planWeeks, dayCaps, sportEligibility) {
  // Build template catalog per sport/type for swapping
  const catalog = {}; // "swim_Easy" -> ["SWIM_Easy_01", ...]
  for (const sport of ['swim', 'bike', 'run']) {
    for (const w of (workoutLibrary[sport] || [])) {
      const type = w.template_id.split('_')[1];
      const cat = `${sport}_${type}`;
      if (!catalog[cat]) catalog[cat] = [];
      catalog[cat].push(w.template_id);
    }
  }

  const MARGIN = 1.2; // Accept templates within 20% of remaining cap
  const TRIGGER_MARGIN = 1.1; // Only fix days exceeding 10% over cap
  let fixes = 0;

  for (const week of planWeeks) {
    // Compute used minutes per day
    const usedMinutes = {};
    for (const s of (week.sessions || [])) {
      const d = normDay(s.day);
      usedMinutes[d] = (usedMinutes[d] || 0) + (s.duration_minutes || 0);
    }

    for (const day of ALL_DAYS) {
      const cap = dayCaps[day] || 0;
      if (cap === 0) continue; // REST day — handled by fixRestDays

      let iterations = 0;
      const MAX_ITER = 10; // Safety guard against infinite loops

      while ((usedMinutes[day] || 0) > cap * TRIGGER_MARGIN && iterations < MAX_ITER) {
        iterations++;
        const daySessions = (week.sessions || []).filter(s => normDay(s.day) === day);
        if (daySessions.length === 0) break;

        // Target the longest session on the overflowing day
        daySessions.sort((a, b) => (b.duration_minutes || 0) - (a.duration_minutes || 0));
        const target = daySessions[0];
        const targetDur = target.duration_minutes || 0;

        // Remaining cap for this slot = cap minus all OTHER sessions on this day
        const othersTotal = (usedMinutes[day] || 0) - targetDur;
        const slotCap = cap - othersTotal;

        // Strategy 1: Swap to shorter template (same sport/type, fits within margin)
        const key = `${target.sport}_${target.type}`;
        const swapCandidates = (catalog[key] || []).filter(tid => {
          const dur = templateDurationMap[tid] || 0;
          return dur < targetDur && dur <= slotCap * MARGIN;
        });

        if (swapCandidates.length > 0) {
          // Pick the largest that still fits (closest to original)
          swapCandidates.sort((a, b) => (templateDurationMap[b] || 0) - (templateDurationMap[a] || 0));
          const alt = swapCandidates[0];
          const altDur = templateDurationMap[alt] || 0;
          console.log(`  Fix: W${week.week_number} ${day} swap ${target.template_id} (${targetDur}min) → ${alt} (${altDur}min) (cap: ${usedMinutes[day]}/${cap}min)`);
          usedMinutes[day] = usedMinutes[day] - targetDur + altDur;
          target.template_id = alt;
          target.duration_minutes = altDur;
          fixes++;
          continue;
        }

        // Strategy 2: Move session to eligible day with remaining capacity
        const moveCandidates = ALL_DAYS.filter(d => {
          if (d === day) return false;
          const eligible = sportEligibility[d] || [];
          if (!eligible.includes(target.sport)) return false;
          const remaining = (dayCaps[d] || 0) - (usedMinutes[d] || 0);
          return remaining >= targetDur;
        });

        if (moveCandidates.length > 0) {
          // Pick day with most remaining capacity
          moveCandidates.sort((a, b) =>
            ((dayCaps[b] || 0) - (usedMinutes[b] || 0)) -
            ((dayCaps[a] || 0) - (usedMinutes[a] || 0))
          );
          const newDay = moveCandidates[0];
          console.log(`  Fix: W${week.week_number} move ${target.template_id} (${targetDur}min) ${day} → ${newDay} (cap: ${usedMinutes[day]}/${cap}min)`);
          usedMinutes[day] -= targetDur;
          target.day = newDay;
          usedMinutes[newDay] = (usedMinutes[newDay] || 0) + targetDur;
          fixes++;
          continue;
        }

        // Strategy 3: Evict lowest-priority session in the week if target outranks
        const targetPriority = sessionPriority(target);
        let lowestSession = null;
        let lowestPriority = Infinity;

        for (const other of (week.sessions || [])) {
          if (other === target) continue;
          const p = sessionPriority(other);
          if (p < lowestPriority) {
            lowestPriority = p;
            lowestSession = other;
          }
        }

        if (lowestSession && targetPriority > lowestPriority) {
          const evictDay = normDay(lowestSession.day);
          const evictDur = lowestSession.duration_minutes || 0;
          console.log(`  Fix: W${week.week_number} evict ${lowestSession.template_id} (pri ${lowestPriority}) from ${evictDay} for ${target.template_id} (pri ${targetPriority}) on ${day} (cap: ${usedMinutes[day]}/${cap}min)`);
          usedMinutes[evictDay] = (usedMinutes[evictDay] || 0) - evictDur;
          const idx = week.sessions.indexOf(lowestSession);
          if (idx >= 0) week.sessions.splice(idx, 1);
          fixes++;
          continue; // Re-check: eviction may have freed this day or enabled a move
        }

        // Strategy 4: Last resort — drop lowest-priority session on this day
        const dayByPriority = [...daySessions].sort((a, b) => sessionPriority(a) - sessionPriority(b));
        const toDrop = dayByPriority[0];
        const dropDur = toDrop.duration_minutes || 0;
        console.log(`  Fix: W${week.week_number} DROP ${toDrop.template_id} (${dropDur}min, pri ${sessionPriority(toDrop)}) from ${day} (last resort, cap: ${usedMinutes[day]}/${cap}min)`);
        usedMinutes[day] -= dropDur;
        const dropIdx = week.sessions.indexOf(toDrop);
        if (dropIdx >= 0) week.sessions.splice(dropIdx, 1);
        fixes++;
      }
    }
  }

  return fixes;
}

// ── Post-processing: ensure brick sessions in Build/Peak weeks ───────────────
// Creates bike+run brick pairs when missing (weekly in Build/Peak, biweekly in Base)

function fixMissingBricks(planWeeks, dayCaps, sportEligibility) {
  // Preferred brick days - weekends first
  const BRICK_PREFERRED_DAYS = ['Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
  let fixes = 0;

  for (const week of planWeeks) {
    const phase = week.phase;
    // Skip Taper and Recovery weeks
    if (phase === 'Taper' || phase === 'Recovery') continue;
    // Base: biweekly bricks (even-numbered weeks only)
    if (phase === 'Base' && week.week_number % 2 === 1) continue;
    // Check if week already has brick sessions
    if ((week.sessions || []).some(s => s.is_brick)) continue;

    // Group sessions by day
    const byDay = {};
    for (const session of (week.sessions || [])) {
      const d = normDay(session.day);
      byDay[d] = byDay[d] || [];
      byDay[d].push(session);
    }

    // Find brick-eligible day
    let brickDay = null;
    for (const day of BRICK_PREFERRED_DAYS) {
      const eligible = sportEligibility[day] || [];
      if (!eligible.includes('bike') || !eligible.includes('run')) continue;
      if ((dayCaps[day] || 0) < 90) continue; // need enough capacity for bike+run

      // Prefer day that already has a bike session
      if ((byDay[normDay(day)] || []).some(s => s.sport === 'bike')) {
        brickDay = day;
        break;
      }

      // Otherwise take first eligible day
      if (brickDay === null) {
        brickDay = day;
      }
    }

    if (brickDay === null) continue;

    // STEP 1: Clear non-bike sessions off brickDay BEFORE placing brick pair
    const brickDaySessions = [...(byDay[normDay(brickDay)] || [])];
    for (const session of brickDaySessions) {
      if (session.sport === 'bike') continue; // keep bikes

      // Find best alternative day for this session
      const sessionDur = session.duration_minutes || 0;

      // Build list of alternative days: eligible for sport and NOT brickDay
      const candidates = ALL_DAYS.filter(day => {
        if (day === brickDay) return false;
        const eligible = sportEligibility[day] || [];
        if (!eligible.includes(session.sport)) return false;
        return true;
      });

      // Sort candidates: prefer empty days, then days with fewest sessions that have room
      candidates.sort((a, b) => {
        const aSessions = byDay[normDay(a)] || [];
        const bSessions = byDay[normDay(b)] || [];
        const aUsed = aSessions.reduce((sum, s) => sum + (s.duration_minutes || 0), 0);
        const bUsed = bSessions.reduce((sum, s) => sum + (s.duration_minutes || 0), 0);
        const aRemaining = (dayCaps[a] || 0) - aUsed;
        const bRemaining = (dayCaps[b] || 0) - bUsed;

        // Prioritize: empty days first (0 sessions)
        if (aSessions.length === 0 && bSessions.length > 0) return -1;
        if (bSessions.length === 0 && aSessions.length > 0) return 1;

        // Then by fewest sessions
        if (aSessions.length !== bSessions.length) {
          return aSessions.length - bSessions.length;
        }

        // Then by most remaining capacity
        return bRemaining - aRemaining;
      });

      // Find first candidate with enough room
      for (const newDay of candidates) {
        const newDaySessions = byDay[normDay(newDay)] || [];
        const newDayUsed = newDaySessions.reduce((sum, s) => sum + (s.duration_minutes || 0), 0);
        const newDayRemaining = (dayCaps[newDay] || 0) - newDayUsed;

        if (newDayRemaining >= sessionDur) {
          // Move session
          const oldDay = normDay(session.day);
          byDay[oldDay] = (byDay[oldDay] || []).filter(s => s !== session);
          session.day = newDay;
          byDay[normDay(newDay)] = byDay[normDay(newDay)] || [];
          byDay[normDay(newDay)].push(session);
          console.log(`  Fix: W${week.week_number} moved ${session.template_id} off brick day ${brickDay} → ${newDay}`);
          break;
        }
      }
      // If no alternative found, leave it (don't break the plan)
    }

    // STEP 2: Ensure a bike session is on brickDay
    let bikeSession = (byDay[normDay(brickDay)] || []).find(s => s.sport === 'bike');
    if (!bikeSession) {
      // Find a bike from another day and move it
      const allBikes = (week.sessions || []).filter(s => s.sport === 'bike' && !s.is_brick);
      for (const bike of allBikes) {
        const brickDayUsed = (byDay[normDay(brickDay)] || []).reduce(
          (sum, s) => sum + (s.duration_minutes || 0), 0
        );
        const brickDayRemaining = (dayCaps[brickDay] || 0) - brickDayUsed;
        if ((bike.duration_minutes || 0) <= brickDayRemaining) {
          // Move bike to brickDay
          const bikeOrigDay = normDay(bike.day);
          byDay[bikeOrigDay] = (byDay[bikeOrigDay] || []).filter(s => s !== bike);
          bike.day = brickDay;
          byDay[normDay(brickDay)] = byDay[normDay(brickDay)] || [];
          byDay[normDay(brickDay)].push(bike);
          bikeSession = bike;
          break;
        }
      }
    }

    if (!bikeSession) continue;

    // STEP 3: Always use RUN_Easy_01 (30min) for brick run
    const brickRunTemplate = (workoutLibrary.run || []).find(t => t.template_id === 'RUN_Easy_01');
    if (!brickRunTemplate) continue; // Safety check

    // Check if brick run fits on brickDay
    const brickDayUsed = (byDay[normDay(brickDay)] || []).reduce(
      (sum, s) => sum + (s.duration_minutes || 0), 0
    );
    const brickDayRemaining = (dayCaps[brickDay] || 0) - brickDayUsed;

    if (brickRunTemplate.duration_minutes > brickDayRemaining) continue; // Can't fit 30min run

    // Find any run in the week (non-brick) and move it to brickDay with RUN_Easy_01 template
    const allRuns = (week.sessions || []).filter(s => s.sport === 'run' && !s.is_brick);
    // Prefer shortest Easy run to minimize disruption to quality workouts
    allRuns.sort((a, b) => {
      if (a.type === 'Easy' && b.type !== 'Easy') return -1;
      if (a.type !== 'Easy' && b.type === 'Easy') return 1;
      return (a.duration_minutes || 0) - (b.duration_minutes || 0);
    });

    if (allRuns.length > 0) {
      const run = allRuns[0];
      const runOrigDay = normDay(run.day);
      byDay[runOrigDay] = (byDay[runOrigDay] || []).filter(s => s !== run);

      // Swap to RUN_Easy_01 (30min)
      run.template_id = brickRunTemplate.template_id;
      run.duration_minutes = brickRunTemplate.duration_minutes;
      run.type = 'Easy';
      run.day = brickDay;
      run.is_brick = true;

      byDay[normDay(brickDay)] = byDay[normDay(brickDay)] || [];
      byDay[normDay(brickDay)].push(run);

      bikeSession.is_brick = true;
      fixes++;
      console.log(`  Fix: W${week.week_number} created brick pair on ${brickDay} (${bikeSession.template_id} + RUN_Easy_01)`);
    } else {
      // No existing run to repurpose — create a new brick run
      const newRun = {
        sport: 'run',
        type: 'Easy',
        template_id: brickRunTemplate.template_id,
        duration_minutes: brickRunTemplate.duration_minutes,
        day: brickDay,
        is_brick: true,
      };
      week.sessions = week.sessions || [];
      week.sessions.push(newRun);
      byDay[normDay(brickDay)] = byDay[normDay(brickDay)] || [];
      byDay[normDay(brickDay)].push(newRun);
      bikeSession.is_brick = true;
      fixes++;
      console.log(`  Fix: W${week.week_number} created NEW brick run on ${brickDay} (no existing run to repurpose)`);
    }
  }

  return fixes;
}

// ── Post-processing: fix brick ordering (bike before run in sessions array) ───

function fixBrickOrder(planWeeks) {
  let fixes = 0;
  for (const week of planWeeks) {
    const byDay = {};
    for (const session of (week.sessions || [])) {
      const d = normDay(session.day);
      byDay[d] = byDay[d] || [];
      byDay[d].push(session);
    }
    for (const [day, sessions] of Object.entries(byDay)) {
      const brickBike = sessions.find(s => s.is_brick && s.sport === 'bike');
      const brickRun = sessions.find(s => s.is_brick && s.sport === 'run');
      if (!brickBike || !brickRun) continue;
      const bikeIdx = (week.sessions || []).indexOf(brickBike);
      const runIdx = (week.sessions || []).indexOf(brickRun);
      if (bikeIdx >= 0 && runIdx >= 0 && runIdx < bikeIdx) {
        week.sessions[runIdx] = brickBike;
        week.sessions[bikeIdx] = brickRun;
        fixes++;
        console.log(`  Fix: W${week.week_number} ${day} brick order → bike before run`);
      }
    }
  }
  return fixes;
}

// ── Post-processing: fix same-day hard session conflicts ──────────────────────
// Rule 1: Hard bike/run + another session of the SAME sport on same day → move one away
//         (no hard run + any run, no hard bike + any bike on the same day)
// Rule 2: Two hard sessions (bike/run) on same day → move one away
//         (no bike hard + run hard, no bike hard + bike hard, no run hard + run hard)
// Exception: brick pairs (bike + run 30min, both is_brick) are always OK — different sports
// Swim is exempt from both rules.

function fixSameDayHardConflicts(planWeeks, dayCaps, sportEligibility) {
  const HARD_TYPES = ['Tempo', 'Intervals'];
  let fixes = 0;

  for (const week of planWeeks) {
    const byDay = {};
    for (const session of (week.sessions || [])) {
      const d = normDay(session.day);
      byDay[d] = byDay[d] || [];
      byDay[d].push(session);
    }

    for (const day of ALL_DAYS) {
      // Rule 1: Max 1 bike and max 1 run per day (brick sessions count)
      for (const sport of ['bike', 'run']) {
        const sportSessions = (byDay[normDay(day)] || []).filter(s => s.sport === sport);
        if (sportSessions.length < 2) continue;

        // Keep: brick session first, then hard session, then longest
        const keeper = sportSessions.find(s => s.is_brick)
          || sportSessions.find(s => HARD_TYPES.includes(s.type))
          || [...sportSessions].sort((a, b) => (b.duration_minutes || 0) - (a.duration_minutes || 0))[0];

        const toMove = sportSessions.filter(s => s !== keeper);
        for (const session of toMove) {
          if (tryRelocateSession(session, day, week, byDay, dayCaps, sportEligibility)) {
            fixes++;
          }
        }
      }

      // Rule 2: No two hard (bike/run) sessions on same day (brick hard sessions count)
      const currentSessions = byDay[normDay(day)] || [];
      const hardBikeRun = currentSessions.filter(s =>
        HARD_TYPES.includes(s.type) && ['bike', 'run'].includes(s.sport)
      );

      if (hardBikeRun.length >= 2) {
        // Prefer moving non-brick session
        const nonBrick = hardBikeRun.filter(s => !s.is_brick);
        const toMove = nonBrick.length > 0
          ? nonBrick.sort((a, b) => (a.duration_minutes || 0) - (b.duration_minutes || 0))[0]
          : hardBikeRun.sort((a, b) => (a.duration_minutes || 0) - (b.duration_minutes || 0))[0];
        if (tryRelocateSession(toMove, day, week, byDay, dayCaps, sportEligibility)) {
          fixes++;
        }
      }
    }
  }

  return fixes;
}

// Helper: try to move a session from sourceDay to another day
// Strategy 1: direct move, Strategy 2: swap with Easy of different sport, Strategy 3: downsize + move
function tryRelocateSession(session, sourceDay, week, byDay, dayCaps, sportEligibility) {
  const HARD_TYPES = ['Tempo', 'Intervals'];
  const dur = session.duration_minutes || 0;
  const sport = session.sport;
  const isHard = HARD_TYPES.includes(session.type);

  // Strategy 1: Direct move to day with capacity (no new conflicts)
  for (const targetDay of ALL_DAYS) {
    if (targetDay === sourceDay) continue;
    if (!(sportEligibility[targetDay] || []).includes(sport)) continue;
    const targetSessions = byDay[normDay(targetDay)] || [];

    // No same-sport on target day (bike/run only — max 1 per sport per day)
    if (['bike', 'run'].includes(sport) && targetSessions.some(s => s.sport === sport)) continue;
    // No dual hard on target day
    if (isHard && targetSessions.some(s => HARD_TYPES.includes(s.type) && ['bike', 'run'].includes(s.sport))) continue;

    const targetUsed = targetSessions.reduce((sum, s) => sum + (s.duration_minutes || 0), 0);
    if (targetUsed + dur > (dayCaps[targetDay] || 0)) continue;

    byDay[normDay(sourceDay)] = (byDay[normDay(sourceDay)] || []).filter(s => s !== session);
    session.day = targetDay;
    byDay[normDay(targetDay)] = byDay[normDay(targetDay)] || [];
    byDay[normDay(targetDay)].push(session);
    console.log(`  Fix: W${week.week_number} same-day conflict: moved ${session.template_id} from ${sourceDay} → ${targetDay}`);
    return true;
  }

  // Strategy 2: Swap with an Easy session of a DIFFERENT sport on another day
  for (const targetDay of ALL_DAYS) {
    if (targetDay === sourceDay) continue;
    const targetSessions = byDay[normDay(targetDay)] || [];

    for (const candidate of targetSessions) {
      if (candidate.is_brick || candidate.type !== 'Easy') continue;
      if (candidate.sport === sport) continue; // different sport only
      if (!(sportEligibility[targetDay] || []).includes(sport)) continue;
      if (!(sportEligibility[sourceDay] || []).includes(candidate.sport)) continue;

      // Check target day after swap: no same-sport conflict
      if (['bike', 'run'].includes(sport) && targetSessions.some(s => s !== candidate && s.sport === sport)) continue;
      // Check target day after swap: no dual hard
      if (isHard && targetSessions.some(s => s !== candidate && HARD_TYPES.includes(s.type) && ['bike', 'run'].includes(s.sport))) continue;
      // Check source day after swap: no same-sport conflict for candidate
      const sourceSessions = byDay[normDay(sourceDay)] || [];
      if (['bike', 'run'].includes(candidate.sport) && sourceSessions.some(s => s !== session && s.sport === candidate.sport)) continue;

      const candidateDur = candidate.duration_minutes || 0;
      const sourceUsed = sourceSessions.reduce((sum, s) => sum + (s.duration_minutes || 0), 0);
      const sourceRemaining = (dayCaps[sourceDay] || 0) - sourceUsed + dur;
      const targetUsed = targetSessions.reduce((sum, s) => sum + (s.duration_minutes || 0), 0);
      const targetRemaining = (dayCaps[targetDay] || 0) - targetUsed + candidateDur;

      if (sourceRemaining < candidateDur || targetRemaining < dur) continue;

      byDay[normDay(sourceDay)] = (byDay[normDay(sourceDay)] || []).filter(s => s !== session);
      byDay[normDay(targetDay)] = (byDay[normDay(targetDay)] || []).filter(s => s !== candidate);
      session.day = targetDay;
      candidate.day = sourceDay;
      byDay[normDay(targetDay)] = byDay[normDay(targetDay)] || [];
      byDay[normDay(targetDay)].push(session);
      byDay[normDay(sourceDay)] = byDay[normDay(sourceDay)] || [];
      byDay[normDay(sourceDay)].push(candidate);
      console.log(`  Fix: W${week.week_number} same-day conflict: swapped ${session.template_id} (${sourceDay}) ↔ ${candidate.template_id} (${targetDay})`);
      return true;
    }
  }

  // Strategy 3: Downsize + move (for sessions too big for weekday caps)
  if (dur > 60) {
    for (const targetDay of ALL_DAYS) {
      if (targetDay === sourceDay) continue;
      if (!(sportEligibility[targetDay] || []).includes(sport)) continue;
      const targetSessions = byDay[normDay(targetDay)] || [];

      // No same-sport on target day (bike/run only)
      if (['bike', 'run'].includes(sport) && targetSessions.some(s => s.sport === sport)) continue;
      // No dual hard on target day
      if (isHard && targetSessions.some(s => HARD_TYPES.includes(s.type) && ['bike', 'run'].includes(s.sport))) continue;

      const targetUsed = targetSessions.reduce((sum, s) => sum + (s.duration_minutes || 0), 0);
      const targetRemaining = (dayCaps[targetDay] || 0) - targetUsed;

      if (targetRemaining >= 30) {
        const shorterTemplates = (workoutLibrary[sport] || [])
          .filter(t => {
            const tType = t.template_id.split('_')[1];
            return tType === session.type &&
              (t.duration_minutes || 0) <= targetRemaining &&
              (t.duration_minutes || 0) >= 30;
          })
          .sort((a, b) => (b.duration_minutes || 0) - (a.duration_minutes || 0));

        if (shorterTemplates.length > 0) {
          const shorter = shorterTemplates[0];
          byDay[normDay(sourceDay)] = (byDay[normDay(sourceDay)] || []).filter(s => s !== session);
          console.log(`  Fix: W${week.week_number} same-day conflict: downsized+moved ${sport} ${session.type} (${dur}→${shorter.duration_minutes}min) ${sourceDay} → ${targetDay}`);
          session.template_id = shorter.template_id;
          session.duration_minutes = shorter.duration_minutes;
          session.day = targetDay;
          byDay[normDay(targetDay)] = byDay[normDay(targetDay)] || [];
          byDay[normDay(targetDay)].push(session);
          return true;
        }
      }
    }
  }

  return false;
}

// ── Post-processing: spread hard sessions (Tempo/Intervals) to prevent consecutive hard days ──

function fixIntensitySpread(planWeeks, dayCaps, sportEligibility) {
  const HARD_TYPES = ['Tempo', 'Intervals'];
  let fixes = 0;

  for (const week of planWeeks) {
    // Group sessions by day
    const byDay = {};
    for (const session of (week.sessions || [])) {
      const d = normDay(session.day);
      byDay[d] = byDay[d] || [];
      byDay[d].push(session);
    }

    // Build list of hard days (days with at least one bike/run Tempo/Intervals session)
    // Swim intensity is excluded — swim hard day adjacent to bike/run hard day is acceptable
    const hardDays = [];
    for (const day of ALL_DAYS) {
      const sessions = byDay[normDay(day)] || [];
      if (sessions.some(s => HARD_TYPES.includes(s.type) && s.sport !== 'swim')) {
        hardDays.push(day);
      }
    }

    // Find consecutive hard day pairs
    for (let i = 0; i < hardDays.length - 1; i++) {
      const day1 = hardDays[i];
      const day2 = hardDays[i + 1];
      const day1Idx = ALL_DAYS.indexOf(day1);
      const day2Idx = ALL_DAYS.indexOf(day2);

      // Check if they are consecutive in ALL_DAYS
      if (day2Idx !== day1Idx + 1) continue;

      // Try both day2 and day1 — sometimes day1's hard session is easier to relocate
      let resolved = false;
      for (const dayToFix of [day2, day1]) {
        if (resolved) break;
        const daySessions = byDay[normDay(dayToFix)] || [];
        const hardSession = daySessions.find(s => HARD_TYPES.includes(s.type) && s.sport !== 'swim');
        if (!hardSession || hardSession.is_brick) continue;

        const hardSessionDur = hardSession.duration_minutes || 0;

        // Strategy A: Swap with Easy session on another day (post-swap adjacency check)
        for (const candidateDay of ALL_DAYS) {
          if (candidateDay === dayToFix) continue;

          // Post-swap adjacency: after swap, dayToFix is no longer hard, candidateDay becomes hard
          const postSwapHardDays = hardDays.filter(hd => hd !== dayToFix);
          if (!postSwapHardDays.includes(candidateDay)) postSwapHardDays.push(candidateDay);
          postSwapHardDays.sort((a, b) => ALL_DAYS.indexOf(a) - ALL_DAYS.indexOf(b));
          const hasConsecutiveAfterSwap = postSwapHardDays.some((hd, idx) => {
            if (idx === 0) return false;
            return ALL_DAYS.indexOf(hd) === ALL_DAYS.indexOf(postSwapHardDays[idx - 1]) + 1;
          });
          if (hasConsecutiveAfterSwap) continue;

          const candidateSessions = byDay[normDay(candidateDay)] || [];
          if (candidateSessions.some(s => s.is_brick)) continue;

          for (const candidate of candidateSessions) {
            if (candidate.type !== 'Easy' || candidate.is_brick) continue;

            const candidateDur = candidate.duration_minutes || 0;
            if (!(sportEligibility[candidateDay] || []).includes(hardSession.sport)) continue;
            if (!(sportEligibility[dayToFix] || []).includes(candidate.sport)) continue;

            // No same-sport on target day after swap
            if (['bike', 'run'].includes(hardSession.sport) &&
                candidateSessions.some(s => s !== candidate && s.sport === hardSession.sport)) continue;
            // No same-sport on source day after swap
            if (['bike', 'run'].includes(candidate.sport) &&
                daySessions.some(s => s !== hardSession && s.sport === candidate.sport)) continue;

            const dayUsed = daySessions.reduce((sum, s) => sum + (s.duration_minutes || 0), 0);
            const dayRemaining = (dayCaps[dayToFix] || 0) - dayUsed + hardSessionDur;
            const candUsed = candidateSessions.reduce((sum, s) => sum + (s.duration_minutes || 0), 0);
            const candRemaining = (dayCaps[candidateDay] || 0) - candUsed + candidateDur;

            if (dayRemaining < candidateDur || candRemaining < hardSessionDur) continue;

            // Perform swap
            byDay[normDay(dayToFix)] = (byDay[normDay(dayToFix)] || []).filter(s => s !== hardSession);
            byDay[normDay(candidateDay)] = (byDay[normDay(candidateDay)] || []).filter(s => s !== candidate);
            byDay[normDay(candidateDay)] = byDay[normDay(candidateDay)] || [];
            byDay[normDay(candidateDay)].push(hardSession);
            byDay[normDay(dayToFix)] = byDay[normDay(dayToFix)] || [];
            byDay[normDay(dayToFix)].push(candidate);

            console.log(`  Fix: W${week.week_number} intensity spread: swapped ${hardSession.template_id} (${dayToFix}) ↔ ${candidate.template_id} (${candidateDay})`);
            hardSession.day = candidateDay;
            candidate.day = dayToFix;

            fixes++;
            resolved = true;
            break;
          }
          if (resolved) break;
        }

        // Strategy B: Direct move to day with capacity (with post-move adjacency check + optional downsize)
        if (!resolved) {
          for (const gapDay of ALL_DAYS) {
            if (gapDay === dayToFix) continue;
            if ((byDay[normDay(gapDay)] || []).some(s => s.is_brick)) continue;

            // Post-move adjacency check
            const postMoveHardDays = hardDays.filter(hd => hd !== dayToFix);
            if (!postMoveHardDays.includes(gapDay)) postMoveHardDays.push(gapDay);
            postMoveHardDays.sort((a, b) => ALL_DAYS.indexOf(a) - ALL_DAYS.indexOf(b));
            const hasConsecutiveAfterMove = postMoveHardDays.some((hd, idx) => {
              if (idx === 0) return false;
              return ALL_DAYS.indexOf(hd) === ALL_DAYS.indexOf(postMoveHardDays[idx - 1]) + 1;
            });
            if (hasConsecutiveAfterMove) continue;

            if (!(sportEligibility[gapDay] || []).includes(hardSession.sport)) continue;

            const gapSessions = byDay[normDay(gapDay)] || [];
            // No same-sport on target day
            if (['bike', 'run'].includes(hardSession.sport) &&
                gapSessions.some(s => s.sport === hardSession.sport)) continue;
            // No dual hard on target day
            if (gapSessions.some(s => HARD_TYPES.includes(s.type) && ['bike', 'run'].includes(s.sport))) continue;

            const gapUsed = gapSessions.reduce((sum, s) => sum + (s.duration_minutes || 0), 0);
            const gapRemaining = (dayCaps[gapDay] || 0) - gapUsed;

            if (gapRemaining >= hardSessionDur) {
              byDay[normDay(dayToFix)] = (byDay[normDay(dayToFix)] || []).filter(s => s !== hardSession);
              hardSession.day = gapDay;
              byDay[normDay(gapDay)] = byDay[normDay(gapDay)] || [];
              byDay[normDay(gapDay)].push(hardSession);

              console.log(`  Fix: W${week.week_number} intensity spread: moved ${hardSession.template_id} from ${dayToFix} → ${gapDay}`);
              fixes++;
              resolved = true;
              break;
            }

            if (gapRemaining >= 30) {
              const shorterTemplates = (workoutLibrary[hardSession.sport] || [])
                .filter(t => {
                  const tType = t.template_id.split('_')[1];
                  return tType === hardSession.type &&
                    (t.duration_minutes || 0) <= gapRemaining &&
                    (t.duration_minutes || 0) >= 30;
                })
                .sort((a, b) => (b.duration_minutes || 0) - (a.duration_minutes || 0));

              if (shorterTemplates.length > 0) {
                const shorter = shorterTemplates[0];
                byDay[normDay(dayToFix)] = (byDay[normDay(dayToFix)] || []).filter(s => s !== hardSession);
                console.log(`  Fix: W${week.week_number} intensity spread: moved+downsized ${hardSession.template_id} (${hardSession.duration_minutes}min → ${shorter.duration_minutes}min) ${dayToFix} → ${gapDay}`);
                hardSession.template_id = shorter.template_id;
                hardSession.duration_minutes = shorter.duration_minutes;
                hardSession.day = gapDay;
                byDay[normDay(gapDay)] = byDay[normDay(gapDay)] || [];
                byDay[normDay(gapDay)].push(hardSession);
                fixes++;
                resolved = true;
                break;
              }
            }
          }
        }
      }

      if (resolved) {
        // Rebuild hardDays after swap/move (swim excluded)
        hardDays.length = 0;
        for (const d of ALL_DAYS) {
          const sess = byDay[normDay(d)] || [];
          if (sess.some(s => HARD_TYPES.includes(s.type) && s.sport !== 'swim')) {
            hardDays.push(d);
          }
        }
        i = -1; // Restart from beginning (will increment to 0)
        continue;
      }
    }
  }

  return fixes;
}

// ── Helper: Get sports from neighboring single-session days ──────────────────

function getNeighborSingleSessionSports(byDay, targetDay, allDays) {
  const targetIdx = allDays.indexOf(targetDay);
  const neighborSports = [];

  // Check previous day
  if (targetIdx > 0) {
    const prevDay = allDays[targetIdx - 1];
    const prevSessions = byDay[normDay(prevDay)] || [];
    if (prevSessions.length === 1) {
      neighborSports.push(prevSessions[0].sport);
    }
  }

  // Check next day
  if (targetIdx < allDays.length - 1) {
    const nextDay = allDays[targetIdx + 1];
    const nextSessions = byDay[normDay(nextDay)] || [];
    if (nextSessions.length === 1) {
      neighborSports.push(nextSessions[0].sport);
    }
  }

  return neighborSports;
}

// ── Post-processing: fix sport clustering on single-session days ─────────────
// When consecutive single-session days have the same sport, spread them apart

function fixSportClustering(planWeeks, dayCaps, sportEligibility, weeklyHours) {
  // Skip for high-volume athletes — consecutive same-sport days are expected with 3 sports over 7 days
  if ((weeklyHours || 0) >= 8) return 0;
  let fixes = 0;

  for (const week of planWeeks) {
    // Group sessions by day
    const byDay = {};
    for (const session of (week.sessions || [])) {
      const d = normDay(session.day);
      byDay[d] = byDay[d] || [];
      byDay[d].push(session);
    }

    // Identify single-session days
    const singleSessionDays = [];
    for (const day of ALL_DAYS) {
      const cap = dayCaps[day] || 0;
      const sessions = byDay[normDay(day)] || [];
      if (cap > 0 && sessions.length === 1) {
        singleSessionDays.push(day);
      }
    }

    // Check for consecutive single-session days with the same sport
    for (let i = 0; i < singleSessionDays.length - 1; i++) {
      const day1 = singleSessionDays[i];
      const day2 = singleSessionDays[i + 1];

      // Check if they are consecutive in ALL_DAYS
      const idx1 = ALL_DAYS.indexOf(day1);
      const idx2 = ALL_DAYS.indexOf(day2);
      if (idx2 !== idx1 + 1) continue;

      const session1 = byDay[normDay(day1)][0];
      const session2 = byDay[normDay(day2)][0];

      // Never swap brick sessions — would break brick pairing
      if (session2.is_brick) continue;

      // If same sport, try to move session2
      if (session1.sport === session2.sport) {
        const session2Dur = session2.duration_minutes || 0;
        let swapCandidate = null;
        let swapCandidateDay = null;

        // PHASE 1: Try same-sport+type swap first
        for (const candidateDay of ALL_DAYS) {
          // Skip day1 and days adjacent to day1
          const candidateIdx = ALL_DAYS.indexOf(candidateDay);
          if (candidateIdx === idx1 || candidateIdx === idx1 - 1 || candidateIdx === idx1 + 1) {
            continue;
          }

          const candidateSessions = byDay[normDay(candidateDay)] || [];
          for (const candidate of candidateSessions) {
            if (
              candidate.sport === session2.sport &&
              candidate.type === session2.type &&
              !candidate.is_brick
            ) {
              const candidateDur = candidate.duration_minutes || 0;

              // Check if swap is feasible
              const candidateDayEligible = (sportEligibility[candidateDay] || []).includes(session2.sport);
              const candidateDayCap = dayCaps[candidateDay] || 0;
              const candidateDayUsed = candidateSessions.reduce((sum, s) => sum + (s.duration_minutes || 0), 0);
              const candidateDayRemaining = candidateDayCap - candidateDayUsed + candidateDur;

              const day2Eligible = (sportEligibility[day2] || []).includes(candidate.sport);
              const day2Cap = dayCaps[day2] || 0;

              if (
                candidateDayEligible &&
                candidateDayRemaining >= session2Dur &&
                day2Eligible &&
                day2Cap >= candidateDur
              ) {
                swapCandidate = candidate;
                swapCandidateDay = candidateDay;
                break;
              }
            }
          }
          if (swapCandidate) break;
        }

        // PHASE 2: Fall back to cross-sport swap if no same-sport+type found
        if (!swapCandidate) {
          for (const candidateDay of ALL_DAYS) {
            const candidateIdx = ALL_DAYS.indexOf(candidateDay);
            if (candidateIdx === idx1 || candidateIdx === idx1 - 1 || candidateIdx === idx1 + 1) {
              continue;
            }

            const candidateSessions = byDay[normDay(candidateDay)] || [];
            for (const candidate of candidateSessions) {
              if (candidate.is_brick) continue;

              const candidateDur = candidate.duration_minutes || 0;

              // Check sport eligibility both ways
              const session2EligibleOnCandidateDay = (sportEligibility[candidateDay] || []).includes(session2.sport);
              const candidateEligibleOnDay2 = (sportEligibility[day2] || []).includes(candidate.sport);

              if (!session2EligibleOnCandidateDay || !candidateEligibleOnDay2) continue;

              // Check duration caps both ways
              const candidateDayCap = dayCaps[candidateDay] || 0;
              const candidateDayUsed = candidateSessions.reduce((sum, s) => sum + (s.duration_minutes || 0), 0);
              const candidateDayRemaining = candidateDayCap - candidateDayUsed + candidateDur;

              if (candidateDayRemaining < session2Dur) continue;

              const day2Cap = dayCaps[day2] || 0;
              if (day2Cap < candidateDur) continue;

              // Check swap doesn't CREATE new clustering on day2
              const day2Neighbors = getNeighborSingleSessionSports(byDay, day2, ALL_DAYS);
              if (day2Neighbors.includes(candidate.sport)) continue;

              // Also check that session2 doesn't cluster on candidateDay
              const candNeighbors = getNeighborSingleSessionSports(byDay, candidateDay, ALL_DAYS);
              if (candNeighbors.includes(session2.sport)) continue;

              swapCandidate = candidate;
              swapCandidateDay = candidateDay;
              break;
            }
            if (swapCandidate) break;
          }
        }

        // Perform the swap
        if (swapCandidate && swapCandidateDay) {
          // Update byDay to reflect the swap
          byDay[normDay(day2)] = (byDay[normDay(day2)] || []).filter(s => s !== session2);
          byDay[normDay(swapCandidateDay)] = (byDay[normDay(swapCandidateDay)] || []).filter(s => s !== swapCandidate);
          byDay[normDay(swapCandidateDay)] = byDay[normDay(swapCandidateDay)] || [];
          byDay[normDay(swapCandidateDay)].push(session2);
          byDay[normDay(day2)] = byDay[normDay(day2)] || [];
          byDay[normDay(day2)].push(swapCandidate);
          // Update day properties on session objects
          console.log(`  Fix: W${week.week_number} sport clustering: swapped ${session2.template_id} (${day2}) ↔ ${swapCandidate.template_id} (${swapCandidateDay})`);
          session2.day = swapCandidateDay;
          swapCandidate.day = day2;
          fixes++;
        }
      }
    }
  }

  return fixes;
}

// ── Post-processing: enforce RUN_Easy_01 (30min) on all brick-tagged runs ────

function fixBrickRunDuration(planWeeks) {
  const brickRunTemplate = (workoutLibrary.run || []).find(t => t.template_id === 'RUN_Easy_01');
  if (!brickRunTemplate) return 0;

  let fixes = 0;
  for (const week of planWeeks) {
    for (const session of (week.sessions || [])) {
      if (session.is_brick && session.sport === 'run' && (session.duration_minutes || 0) > 30) {
        console.log(`  Fix: W${week.week_number} brick run: ${session.template_id} (${session.duration_minutes}min) → RUN_Easy_01 (30min)`);
        session.template_id = brickRunTemplate.template_id;
        session.duration_minutes = brickRunTemplate.duration_minutes;
        session.type = 'Easy';
        fixes++;
      }
    }
  }
  // Second pass: catch informal bricks (bike+run same day without is_brick tag)
  for (const week of planWeeks) {
    const byDay = {};
    for (const session of (week.sessions || [])) {
      const d = normDay(session.day);
      byDay[d] = byDay[d] || [];
      byDay[d].push(session);
    }
    for (const [day, sessions] of Object.entries(byDay)) {
      const bikes = sessions.filter(s => s.sport === 'bike');
      const runs = sessions.filter(s => s.sport === 'run' && s.type === 'Easy' && !s.is_brick && (s.duration_minutes || 0) > 30);
      if (bikes.length > 0 && runs.length > 0) {
        for (const run of runs) {
          console.log(`  Fix: W${week.week_number} informal brick: ${run.template_id} (${run.duration_minutes}min) → RUN_Easy_01 (30min) on ${day}`);
          run.template_id = brickRunTemplate.template_id;
          run.duration_minutes = brickRunTemplate.duration_minutes;
          run.type = 'Easy';
          run.is_brick = true;
          fixes++;
        }
        for (const bike of bikes) {
          if (!bike.is_brick) bike.is_brick = true;
        }
        // Enforce bike→run order in sessions array for informal bricks
        const bikeIdx = (week.sessions || []).indexOf(bikes[0]);
        const runIdx2 = (week.sessions || []).indexOf(runs[0]);
        if (bikeIdx >= 0 && runIdx2 >= 0 && runIdx2 < bikeIdx) {
          week.sessions[runIdx2] = bikes[0];
          week.sessions[bikeIdx] = runs[0];
        }
      }
    }
  }

  return fixes;
}

// ── Post-processing: fill empty available days with Easy sessions ────────────
// Uses macro plan targets to decide which sport needs the most volume

function fixVolumeGaps(planWeeks, macroWeeks, dayCaps, sportEligibility) {
  let fixes = 0;

  for (const week of planWeeks) {
    const macroWeek = macroWeeks.find(mw => mw.week_number === week.week_number);
    if (!macroWeek) continue;

    // Skip Recovery/Taper — rest days are expected and healthy in these phases
    if (week.phase === 'Recovery' || week.phase === 'Taper') continue;

    // Build byDay
    const byDay = {};
    for (const session of (week.sessions || [])) {
      const d = normDay(session.day);
      byDay[d] = byDay[d] || [];
      byDay[d].push(session);
    }

    // Compute target sport minutes from macro plan
    const targetMinutes = {};
    for (const sport of ['swim', 'bike', 'run']) {
      const sportData = macroWeek[sport];
      targetMinutes[sport] = sportData ? Math.round((sportData.hours || 0) * 60) : 0;
    }

    // Compute current sport minutes
    const currentMinutes = { swim: 0, bike: 0, run: 0 };
    for (const s of (week.sessions || [])) {
      if (currentMinutes[s.sport] !== undefined) {
        currentMinutes[s.sport] += (s.duration_minutes || 0);
      }
    }

    // Check if total is under target (skip if already at/over target)
    const currentTotal = currentMinutes.swim + currentMinutes.bike + currentMinutes.run;
    const targetTotal = targetMinutes.swim + targetMinutes.bike + targetMinutes.run;
    if (currentTotal >= targetTotal) continue;

    // Find empty available days (days with capacity but no sessions)
    const emptyDays = ALL_DAYS.filter(day => {
      const cap = dayCaps[day] || 0;
      if (cap === 0) return false;
      return (byDay[normDay(day)] || []).length === 0;
    });

    if (emptyDays.length === 0) continue;

    for (const day of emptyDays) {
      const cap = dayCaps[day] || 0;
      const eligible = sportEligibility[day] || [];
      if (eligible.length === 0) continue;

      // Rank eligible sports by gap (target - current), largest first
      const sportGaps = eligible.map(sport => ({
        sport,
        gap: targetMinutes[sport] - currentMinutes[sport]
      })).sort((a, b) => b.gap - a.gap);

      // Check sport alternation — prefer sports that don't cluster with neighbors
      const neighborSports = getNeighborSingleSessionSports(byDay, day, ALL_DAYS);

      let chosenSport = null;
      let chosenTemplate = null;

      // First pass: pick sport with largest gap that doesn't cluster
      for (const { sport } of sportGaps) {
        if (neighborSports.includes(sport) && sportGaps.filter(sg => !neighborSports.includes(sg.sport)).length > 0) {
          continue; // skip if would cluster and alternatives exist
        }
        const templates = (workoutLibrary[sport] || [])
          .filter(t => t.template_id.includes('_Easy_') && (t.duration_minutes || 0) <= cap)
          .sort((a, b) => (b.duration_minutes || 0) - (a.duration_minutes || 0));
        if (templates.length > 0) {
          chosenSport = sport;
          chosenTemplate = templates[0];
          break;
        }
      }

      // Fallback: allow clustering if no non-clustering option
      if (!chosenSport) {
        for (const { sport } of sportGaps) {
          const templates = (workoutLibrary[sport] || [])
            .filter(t => t.template_id.includes('_Easy_') && (t.duration_minutes || 0) <= cap)
            .sort((a, b) => (b.duration_minutes || 0) - (a.duration_minutes || 0));
          if (templates.length > 0) {
            chosenSport = sport;
            chosenTemplate = templates[0];
            break;
          }
        }
      }

      if (!chosenSport || !chosenTemplate) continue;

      const deficit = targetMinutes[chosenSport] - currentMinutes[chosenSport];
      const newSession = {
        sport: chosenSport,
        type: 'Easy',
        template_id: chosenTemplate.template_id,
        duration_minutes: chosenTemplate.duration_minutes,
        day: day,
        is_brick: false,
      };

      week.sessions = week.sessions || [];
      week.sessions.push(newSession);
      byDay[normDay(day)] = byDay[normDay(day)] || [];
      byDay[normDay(day)].push(newSession);
      currentMinutes[chosenSport] += chosenTemplate.duration_minutes;

      console.log(`  Fix: W${week.week_number} volume gap: added ${chosenTemplate.template_id} (${chosenTemplate.duration_minutes}min) on ${day} [${chosenSport} deficit: ${deficit}min]`);
      fixes++;
    }
  }

  return fixes;
}

// ── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  // Parse --athlete CLI flag
  const athleteFlagIdx = process.argv.indexOf('--athlete');
  const athleteFilter = athleteFlagIdx !== -1 && process.argv[athleteFlagIdx + 1]
    ? process.argv[athleteFlagIdx + 1]
    : null;

  // Build indexed results with original index preserved
  const indexedStep2 = step2Results.map((r, idx) => ({ r, origIdx: idx }));

  // Filter step2Results if --athlete is provided
  const filteredIndexed = athleteFilter
    ? indexedStep2.filter(({ r, origIdx }) => {
        const step1Vars = step1Results[origIdx]?.vars || {};
        const name = r.vars?.athlete_name || step1Vars.athlete_name || `athlete_${origIdx + 1}`;
        return name.toLowerCase().includes(athleteFilter.toLowerCase());
      })
    : indexedStep2;

  if (athleteFilter) {
    if (filteredIndexed.length === 0) {
      console.error(`No athlete found matching "${athleteFilter}". Available athletes:`);
      for (let idx = 0; idx < step2Results.length; idx++) {
        const r = step2Results[idx];
        const step1Vars = step1Results[idx]?.vars || {};
        const name = r.vars?.athlete_name || step1Vars.athlete_name || `athlete_${idx + 1}`;
        console.error(`  - ${name}`);
      }
      process.exit(1);
    }
    console.log(`Filtering to athlete: "${athleteFilter}" (${filteredIndexed.length} match)`);
  }

  const allResults = [];
  let totalTokens = { prompt: 0, completion: 0 };

  for (let i = 0; i < filteredIndexed.length; i++) {
    const { r, origIdx } = filteredIndexed[i];
    const rawOutput = (r.response?.output || r.output || '').replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();

    let macroPlan;
    try {
      macroPlan = JSON.parse(rawOutput);
    } catch (e) {
      console.warn(`Skipping result ${origIdx}: invalid JSON`);
      continue;
    }

    // Carry forward athlete context
    const step1Vars = step1Results[origIdx]?.vars || {};
    const athleteName = r.vars?.athlete_name || step1Vars.athlete_name || `athlete_${origIdx + 1}`;
    const limiters = step1Vars.limiters || 'none';
    const constraints = constraintMap[athleteName] || 'none';

    console.log(`\n=== ${athleteName} (${macroPlan.weeks.length} weeks) ===`);

    // Split into blocks
    const weeks = macroPlan.weeks;
    const blocks = [];
    for (let j = 0; j < weeks.length; j += BLOCK_SIZE) {
      blocks.push(weeks.slice(j, j + BLOCK_SIZE));
    }
    console.log(`  ${blocks.length} blocks of ${BLOCK_SIZE} weeks`);

    // Process blocks sequentially
    let previouslyUsed = [];
    const allBlockWeeks = [];

    for (let b = 0; b < blocks.length; b++) {
      const block = blocks[b];
      const weekRange = `W${block[0].week_number}-W${block[block.length - 1].week_number}`;
      process.stdout.write(`  Block ${b + 1}/${blocks.length} (${weekRange})...`);

      const prompt = buildPrompt(block, athleteName, limiters, constraints, previouslyUsed);

      try {
        const response = await callOpenAI(prompt);
        const blockResult = JSON.parse(response);

        allBlockWeeks.push(...(blockResult.weeks || []));
        previouslyUsed = extractLastUsed(blockResult);

        console.log(` ✓ ${(blockResult.weeks || []).length} weeks, ${(blockResult.weeks || []).flatMap(w => w.sessions || []).length} sessions`);
      } catch (e) {
        console.log(` ✗ ${e.message}`);
      }
    }

    // Post-processing (matches production fixer chain order)
    const athleteConstraints = parsedConstraintsMap[athleteName] || { dayCaps: {}, sportEligibility: {} };

    const typeFixes = fixTypes(allBlockWeeks);
    if (typeFixes > 0) console.log(`  Post-processing: fixed ${typeFixes} type mismatches`);

    const brickFixes = fixBrickPairs(allBlockWeeks);
    if (brickFixes > 0) console.log(`  Post-processing: fixed ${brickFixes} brick pair issues`);

    const repeatFixes = fixConsecutiveRepeats(allBlockWeeks);
    if (repeatFixes > 0) console.log(`  Post-processing: fixed ${repeatFixes} consecutive repeats`);

    const capFixes = fixDurationCaps(allBlockWeeks, athleteConstraints.dayCaps, athleteConstraints.sportEligibility);
    if (capFixes > 0) console.log(`  Post-processing: fixed ${capFixes} duration cap violations`);

    const restFixes = fixRestDays(allBlockWeeks, weeks, athleteConstraints.dayCaps, athleteConstraints.sportEligibility);
    if (restFixes > 0) console.log(`  Post-processing: fixed ${restFixes} rest day violations`);

    const brickMissingFixes = fixMissingBricks(allBlockWeeks, athleteConstraints.dayCaps, athleteConstraints.sportEligibility);
    if (brickMissingFixes > 0) console.log(`  Post-processing: fixed ${brickMissingFixes} missing brick sessions`);

    const brickDurFixes = fixBrickRunDuration(allBlockWeeks);
    if (brickDurFixes > 0) console.log(`  Post-processing: fixed ${brickDurFixes} brick run durations (capped at 30min)`);

    const brickOrderFixes = fixBrickOrder(allBlockWeeks);
    if (brickOrderFixes > 0) console.log(`  Post-processing: fixed ${brickOrderFixes} brick ordering issues (bike before run)`);

    const sameDayFixes = fixSameDayHardConflicts(allBlockWeeks, athleteConstraints.dayCaps, athleteConstraints.sportEligibility);
    if (sameDayFixes > 0) console.log(`  Post-processing: fixed ${sameDayFixes} same-day hard conflicts`);

    const intensityFixes = fixIntensitySpread(allBlockWeeks, athleteConstraints.dayCaps, athleteConstraints.sportEligibility);
    if (intensityFixes > 0) console.log(`  Post-processing: fixed ${intensityFixes} intensity spread issues`);

    const clusterFixes = fixSportClustering(allBlockWeeks, athleteConstraints.dayCaps, athleteConstraints.sportEligibility, athleteConstraints.weeklyHours);
    if (clusterFixes > 0) console.log(`  Post-processing: fixed ${clusterFixes} sport clustering issues`);

    const volumeFixes = fixVolumeGaps(allBlockWeeks, weeks, athleteConstraints.dayCaps, athleteConstraints.sportEligibility);
    if (volumeFixes > 0) console.log(`  Post-processing: filled ${volumeFixes} volume gaps on empty days`);

    // Re-run duration caps after all changes to catch any new violations
    const capFixes2 = fixDurationCaps(allBlockWeeks, athleteConstraints.dayCaps, athleteConstraints.sportEligibility);
    if (capFixes2 > 0) console.log(`  Post-processing: fixed ${capFixes2} duration cap violations (re-run)`);

    // Re-run same-day conflicts — volume gaps or cap fixes may have introduced new ones
    const sameDayFixes2 = fixSameDayHardConflicts(allBlockWeeks, athleteConstraints.dayCaps, athleteConstraints.sportEligibility);
    if (sameDayFixes2 > 0) console.log(`  Post-processing: fixed ${sameDayFixes2} same-day hard conflicts (re-run)`);

    // Final brick order pass — catch any bricks reordered by later fixers
    const brickOrderFixes2 = fixBrickOrder(allBlockWeeks);
    if (brickOrderFixes2 > 0) console.log(`  Post-processing: fixed ${brickOrderFixes2} brick ordering issues (re-run)`);

    const combinedPlan = { weeks: allBlockWeeks };
    const totalSessions = allBlockWeeks.flatMap(w => w.sessions || []).length;
    const brickCount = allBlockWeeks.flatMap(w => w.sessions || []).filter(s => s.is_brick).length;
    console.log(`  Final: ${allBlockWeeks.length} weeks, ${totalSessions} sessions, ${brickCount / 2} brick pairs`);

    allResults.push({
      athlete_name: athleteName,
      limiters,
      constraints,
      macro_plan_json: rawOutput,
      output: JSON.stringify(combinedPlan)
    });
  }

  // Write results in a format that promptfoo can validate
  // Create step3-inputs.yaml for assertion-only eval
  const yamlPath = path.join(__dirname, 'vars', 'step3-inputs.yaml');
  let yaml = '# Auto-generated from block orchestrator — do not edit\n\n';

  for (const r of allResults) {
    yaml += `- vars:\n`;
    yaml += `    athlete_name: "${r.athlete_name}"\n`;
    yaml += `    limiters: "${r.limiters}"\n`;
    yaml += `    constraints: "${r.constraints}"\n`;
    yaml += `    macro_plan_json: |\n`;
    const macroLines = r.macro_plan_json.split('\n');
    for (const line of macroLines) {
      yaml += `      ${line}\n`;
    }
    yaml += '\n';
  }

  fs.mkdirSync(path.dirname(yamlPath), { recursive: true });
  fs.writeFileSync(yamlPath, yaml);

  // Write raw results for inspection
  fs.mkdirSync(path.join(__dirname, 'results'), { recursive: true });
  fs.writeFileSync(outputPath, JSON.stringify(allResults, null, 2));

  // Write the outputs as a separate file that promptfoo can use as provider output
  // We'll use a custom script provider that returns pre-computed outputs
  const outputsPath = path.join(__dirname, 'results', 'step3-outputs.json');
  fs.writeFileSync(outputsPath, JSON.stringify(allResults.map(r => r.output), null, 2));

  console.log(`\nWrote ${allResults.length} results to ${outputPath}`);
  console.log(`Wrote test inputs to ${yamlPath}`);
  console.log(`Wrote outputs to ${outputsPath}`);
}

main().catch(e => {
  console.error('Fatal:', e.message);
  process.exit(1);
});
