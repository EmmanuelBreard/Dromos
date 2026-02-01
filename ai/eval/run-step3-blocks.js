// Step 3 Block Orchestrator
// Splits each athlete's macro plan into 4-week blocks, processes sequentially
// with OpenAI, carries previously_used_templates between blocks, then
// concatenates results and applies post-processing fixes.

const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '..', '.env') });

const BLOCK_SIZE = 4;
const MODEL = 'gpt-4o';
const TEMPERATURE = 0.2;
const MAX_TOKENS = 4096; // Much smaller per block — only 4 weeks

// ── Load assets ──────────────────────────────────────────────────────────────

const promptTemplate = fs.readFileSync(
  path.join(__dirname, '..', 'prompts', 'step3-workout-block.txt'), 'utf8'
);
const workoutLibrary = fs.readFileSync(
  path.join(__dirname, '..', 'context', 'workout-library.json'), 'utf8'
);

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
  prompt = prompt.replace('{{workout_library}}', workoutLibrary);
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
  const lib = JSON.parse(workoutLibrary);
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

    // Check current week for repeats and swap
    for (const session of (currWeek.sessions || [])) {
      const key = `${session.sport}_${session.type}`;
      if (prevMap[key] && prevMap[key].has(session.template_id)) {
        const options = (catalog[key] || []).filter(t => t !== session.template_id);
        if (options.length > 0) {
          // Pick a random alternative to avoid always defaulting to the same swap
          const alt = options[Math.floor(Math.random() * options.length)];
          console.log(`  Fix: W${currWeek.week_number} ${session.template_id} → ${alt} (consecutive repeat)`);
          session.template_id = alt;
          fixes++;
        }
      }
    }
  }
  return fixes;
}

// ── Post-processing: fix rest day violations ─────────────────────────────────

function fixRestDays(planWeeks, macroWeeks) {
  let fixes = 0;
  for (const week of planWeeks) {
    const macroWeek = macroWeeks.find(w => w.week_number === week.week_number);
    if (!macroWeek || !macroWeek.rest_days) continue;

    const restDays = new Set(macroWeek.rest_days.map(normDay));
    if (restDays.size === 0) continue;

    // Find available days (not rest days)
    const usedDays = {};
    for (const s of (week.sessions || [])) {
      const d = normDay(s.day);
      usedDays[d] = (usedDays[d] || 0) + 1;
    }

    for (const session of (week.sessions || [])) {
      const d = normDay(session.day);
      if (restDays.has(d)) {
        // Find the least-loaded available day
        const available = ALL_DAYS.filter(day => !restDays.has(day));
        available.sort((a, b) => (usedDays[a] || 0) - (usedDays[b] || 0));
        const newDay = available[0];
        if (newDay) {
          console.log(`  Fix: W${week.week_number} ${session.template_id} ${d} → ${newDay} (rest day)`);
          usedDays[d] = (usedDays[d] || 1) - 1;
          session.day = newDay;
          usedDays[newDay] = (usedDays[newDay] || 0) + 1;
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
    const limiters = step1Vars.limiters || 'none specified';
    const constraints = step1Vars.constraints || 'none';

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

    const restFixes = fixRestDays(allBlockWeeks, weeks);
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
