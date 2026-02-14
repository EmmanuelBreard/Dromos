// Step 3 Block Orchestrator
// Splits each athlete's macro plan into 4-week blocks, processes sequentially
// with OpenAI, carries previously_used_templates between blocks, then
// concatenates results and applies post-processing fixes.

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
require('dotenv').config({ path: path.join(__dirname, '..', '..', '.env') });

const BLOCK_SIZE = 4;
const MODEL = 'gpt-4o';
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

  return { dayCaps, sportEligibility };
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

// ── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  const allResults = [];
  let totalTokens = { prompt: 0, completion: 0 };

  for (let i = 0; i < step2Results.length; i++) {
    const r = step2Results[i];
    const rawOutput = (r.response?.output || r.output || '').replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();

    let macroPlan;
    try {
      macroPlan = JSON.parse(rawOutput);
    } catch (e) {
      console.warn(`Skipping result ${i}: invalid JSON`);
      continue;
    }

    // Carry forward athlete context
    const step1Vars = step1Results[i]?.vars || {};
    const athleteName = r.vars?.athlete_name || step1Vars.athlete_name || `athlete_${i + 1}`;
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

    // Post-processing
    const typeFixes = fixTypes(allBlockWeeks);
    if (typeFixes > 0) console.log(`  Post-processing: fixed ${typeFixes} type mismatches`);

    const brickFixes = fixBrickPairs(allBlockWeeks);
    if (brickFixes > 0) console.log(`  Post-processing: fixed ${brickFixes} brick pair issues`);

    const repeatFixes = fixConsecutiveRepeats(allBlockWeeks);
    if (repeatFixes > 0) console.log(`  Post-processing: fixed ${repeatFixes} consecutive repeats`);

    const athleteConstraints = parsedConstraintsMap[athleteName] || { dayCaps: {}, sportEligibility: {} };
    const restFixes = fixRestDays(allBlockWeeks, weeks, athleteConstraints.dayCaps, athleteConstraints.sportEligibility);
    if (restFixes > 0) console.log(`  Post-processing: fixed ${restFixes} rest day violations`);

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
