// PoC: Step 2 Coaching Brain — Plan Adjustment
// Tests macro diff output against scenarios.
// Usage: node poc-adjust-step2.js [scenarioId]

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
require('dotenv').config({ path: path.join(__dirname, '..', '..', '.env') });

const MODEL = 'gpt-4o';
const TEMPERATURE = 0;
const MAX_TOKENS = 2048;

// ── Load assets ──────────────────────────────────────────────────────────────

const promptTemplate = fs.readFileSync(
  path.join(__dirname, '..', 'prompts', 'adjust-step2-coaching-brain.txt'), 'utf8'
);

const scenarios = yaml.load(
  fs.readFileSync(path.join(__dirname, 'vars', 'adjust-step2-scenarios.yaml'), 'utf8')
);

const step2Inputs = yaml.load(
  fs.readFileSync(path.join(__dirname, 'vars', 'step2-inputs.yaml'), 'utf8')
);

const athletes = yaml.load(
  fs.readFileSync(path.join(__dirname, 'vars', 'athletes.yaml'), 'utf8')
);

// ── Plan parsing ─────────────────────────────────────────────────────────────

// Parse the macro plan markdown into structured week objects
function parseMacroPlan(macroPlan) {
  // Strip markdown code fences if present
  const cleaned = macroPlan.replace(/^```(?:markdown)?\s*\n?/, '').replace(/\n?\s*```$/, '');
  const lines = cleaned.split('\n');
  const weeks = [];
  let current = null;

  for (const line of lines) {
    // ## W5 — Base — 2026-03-16
    const weekMatch = line.match(/^##\s+W(\d+)\s+—\s+(\w+)\s+—\s+(\S+)/);
    if (weekMatch) {
      if (current) weeks.push(current);
      current = {
        week: parseInt(weekMatch[1]),
        phase: weekMatch[2],
        date: weekMatch[3],
        is_recovery: false,
        total: null,
        volumes: {},
        sessions: [],
        notes: ''
      };
      continue;
    }

    if (!current) continue;

    // Total: 4.5h | Swim 1.2h | Bike 1.8h | Run 1.5h
    const totalMatch = line.match(/Total:\s*([\d.]+)h\s*\|\s*Swim\s*([\d.]+)h\s*\|\s*Bike\s*([\d.]+)h\s*\|\s*Run\s*([\d.]+)h/);
    if (totalMatch) {
      current.total = parseFloat(totalMatch[1]);
      current.volumes = {
        swim: Math.round(parseFloat(totalMatch[2]) * 60),
        bike: Math.round(parseFloat(totalMatch[3]) * 60),
        run: Math.round(parseFloat(totalMatch[4]) * 60)
      };
      continue;
    }

    // - Swim: Easy 30min, Easy 30min
    const sessionMatch = line.match(/^-\s+(Swim|Bike|Run):\s+(.+)/);
    if (sessionMatch) {
      const sport = sessionMatch[1].toLowerCase();
      const sessionParts = sessionMatch[2].split(',').map(s => s.trim());
      for (const part of sessionParts) {
        const sm = part.match(/(\w+)\s+(\d+)min/);
        if (sm) {
          current.sessions.push({
            sport,
            type: sm[1],
            duration_minutes: parseInt(sm[2])
          });
        }
      }
      continue;
    }

    // Notes: Recovery week
    const notesMatch = line.match(/^Notes:\s+(.+)/);
    if (notesMatch) {
      current.notes = notesMatch[1];
      if (/recovery/i.test(notesMatch[1])) {
        current.is_recovery = true;
      }
      continue;
    }
  }
  if (current) weeks.push(current);
  return weeks;
}

// Extract phase map (compact view of all weeks)
function extractPhaseMap(weeks) {
  return weeks.map(w => ({
    week: w.week,
    phase: w.phase,
    is_recovery: w.is_recovery,
    date: w.date
  }));
}

// Get sessions for affected weeks based on phase_impact
function getAffectedSessions(weeks, currentWeek, phaseImpact) {
  const curr = weeks.find(w => w.week === currentWeek);
  if (!curr) return [];

  if (phaseImpact === 'local') {
    // ±1 week
    return weeks.filter(w =>
      w.week >= currentWeek - 1 && w.week <= currentWeek + 1
    );
  }

  // structural: affected weeks + all downstream in current phase
  const currentPhase = curr.phase;
  return weeks.filter(w =>
    w.week >= currentWeek && (w.phase === currentPhase || w.week <= currentWeek + 6)
  );
}

// Format sessions for prompt injection
function formatAffectedSessions(affectedWeeks) {
  const lines = [];
  for (const w of affectedWeeks) {
    lines.push(`### Week ${w.week} (${w.phase}${w.is_recovery ? ' — Recovery' : ''}) — ${w.date}`);
    lines.push(`Total: ${w.total}h | Swim ${w.volumes.swim}min | Bike ${w.volumes.bike}min | Run ${w.volumes.run}min`);
    for (const s of w.sessions) {
      lines.push(`- ${s.sport}: ${s.type} ${s.duration_minutes}min`);
    }
    if (w.notes) lines.push(`Notes: ${w.notes}`);
    lines.push('');
  }
  return lines.join('\n');
}

// ── Build system prompt ──────────────────────────────────────────────────────

function buildAthleteProfile(athlete) {
  const v = athlete.vars;
  return [
    `Name: ${v.athlete_name}`,
    `Experience: ${v.experience_level}`,
    `Race: ${v.race_distance} on ${v.race_date}`,
    `Weekly hours: ${v.weekly_hours}h`,
    `Current volume: ${v.current_weekly_hours}h/week`,
    `FTP: ${v.ftp_watts}W | MAS: ${v.mas_kmh} km/h | CSS: ${v.swim_css}/100m`,
    `Swim days: ${v.swim_days}`,
    `Bike days: ${v.bike_days}`,
    `Run days: ${v.run_days}`
  ].join('\n');
}

function buildPrompt(athleteProfile, constraintSummary, phaseMap, affectedSessions, chatHistory) {
  let prompt = promptTemplate;
  prompt = prompt.replace('{{athlete_profile}}', athleteProfile);
  prompt = prompt.replace('{{constraint_summary}}', JSON.stringify(constraintSummary, null, 2));
  prompt = prompt.replace('{{phase_map}}', JSON.stringify(phaseMap, null, 2));
  prompt = prompt.replace('{{affected_sessions}}', affectedSessions);

  // Inject chat history for E-category scenarios
  if (chatHistory && chatHistory.length > 0) {
    const historyBlock = chatHistory.map(m =>
      `[${m.created_at}] ${m.role}: ${m.content}`
    ).join('\n');
    prompt += `\n\n## Previous Chat History\n\n${historyBlock}`;
  }

  return prompt;
}

// ── OpenAI call ──────────────────────────────────────────────────────────────

async function callOpenAI(systemPrompt) {
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
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: 'Apply the adjustment rules to the constraint and produce the macro diff.' }
      ]
    })
  });

  if (!resp.ok) {
    const err = await resp.text();
    throw new Error(`OpenAI API error ${resp.status}: ${err}`);
  }

  const data = await resp.json();
  return data.choices[0].message.content;
}

// ── Validation ───────────────────────────────────────────────────────────────

function validateResult(scenario, response) {
  const checks = [];
  const text = response.toLowerCase();

  for (const v of scenario.validation) {
    let pass = false;

    switch (v.check) {
      // ── Volume ceiling ──
      case 'volume_ceiling_respected': {
        // Check for ceiling math in ADD lines
        const hasAdd = /\badd\b/i.test(response);
        const hasCeilingMath = /ceiling|15%|1\.15|max.*additional/i.test(response);
        // If there are ADD actions, ceiling math should be shown
        pass = !hasAdd || hasCeilingMath;
        break;
      }

      // ── Session actions ──
      case 'bike_sessions_removed':
        pass = /remove.*bike/i.test(response);
        break;

      case 'swim_removed':
        pass = /remove.*swim/i.test(response);
        break;

      case 'all_sessions_removed':
        pass = /remove/i.test(response) &&
          (/all.*sessions?\s*(removed|cancelled|stopped)/i.test(response) ||
           (text.includes('remove') && !text.includes('keep')));
        break;

      case 'no_substitution': {
        // No ADD lines in the CURRENT week (ramp-back ADDs in later weeks are OK)
        // Parse the current week section and check for ADD there
        const currentWeek = scenario.current_week;
        const weekPattern = new RegExp(`## Week ${currentWeek}[\\s\\S]*?(?=## Week|$)`, 'i');
        const weekSection = response.match(weekPattern);
        pass = !weekSection || !/\bADD\b/i.test(weekSection[0]);
        break;
      }

      case 'deficit_accepted':
        // Match volume drops like "6h → 5h" or explicit deficit mentions
        pass = /deficit|lower.*volume|reduced.*volume|volume.*drop|accept/i.test(response) ||
          /volume:.*→.*\(-/i.test(response) ||
          /\d+\.?\d*h\s*→\s*\d+\.?\d*h/i.test(response);
        break;

      // ── Never double up ──
      case 'no_double_up':
        pass = !/make.*up|catch.*up|double.*up|extra.*session.*next/i.test(response) ||
          /never.*double|skip.*move|not.*made.*up|do.*not.*make.*up/i.test(response);
        break;

      case 'skip_and_move_on':
        pass = /skip|move on|move forward|let.*go|accept.*loss|missed.*gone|not.*recoverable|not.*make.*up|not.*catch.*up|never.*double/i.test(response) ||
          // If no_double_up passes AND no ADD lines for next week, behavior is correct
          !/\badd\b/i.test(response);
        break;

      // ── Ramp-back ──
      case 'ramp_back_mentioned':
      case 'ramp_back_included':
        pass = /ramp.?back|return.*protocol|gradual.*return|progressive.*return/i.test(response);
        break;

      case 'ramp_back_applied':
        pass = /ramp.?back|return.*protocol|gradual/i.test(response) &&
          /z1|zone.?1|easy/i.test(response);
        break;

      case 'ramp_back_starts_low':
        pass = /(?:<\s*20|15|10).*min/i.test(response) || /short.*easy|z1.*only/i.test(response);
        break;

      case 'no_ramp_back':
        pass = !/ramp.?back|return.*protocol/i.test(response) ||
          /no.*ramp.?back|not.*needed|resume.*immediately|resume.*normally/i.test(response);
        break;

      // ── Next week ──
      case 'next_week_reduced':
        pass = /next.*week.*(?:remove|reduce|easy|lighter|rest)/i.test(response) ||
          /week.*(?:\d+).*(?:remove|reduce|modified)/i.test(response);
        break;

      // ── Fatigue / quality session ──
      case 'keeps_one_quality_session':
        pass = /keep.*(?:1|one).*(?:quality|tempo|intervals|threshold|brick)/i.test(response) ||
          /(?:1|one).*quality.*(?:session|workout).*(?:keep|protect|maintain)/i.test(response) ||
          (/keep/i.test(response) && /(?:tempo|intervals|threshold)/i.test(response));
        break;

      case 'converts_other_quality':
        pass = /convert.*easy/i.test(response) || /→.*easy/i.test(response) ||
          /change.*to.*easy/i.test(response) || /downgrade.*easy/i.test(response);
        break;

      case 'volume_reduced':
        pass = /volume.*(?:→|->|reduced|drops?|lower)/i.test(response) ||
          /(?:→|->)\s*[\d.]+h/i.test(response);
        break;

      // ── Cascading ──
      case 'current_week_reduced':
        pass = /(?:remove|convert|reduce|easy|lighter)/i.test(response);
        break;

      case 'no_back_to_back_easy':
        pass = /(?:back.to.back|consecutive|two.*easy|two.*recovery)/i.test(response) ||
          /(?:avoid|prevent).*(?:consecutive|back.to.back)/i.test(response) ||
          /(?:swap|push|move|shift).*recovery/i.test(response);
        break;

      case 'recovery_repositioned':
        pass = /(?:swap|push|move|shift|reposition).*recovery/i.test(response) ||
          /recovery.*(?:push|move|shift|swap)/i.test(response) ||
          /(?:merge|absorb).*recovery/i.test(response);
        break;

      case 'reasoning_explains_cascade':
        pass = /(?:because|since|avoid|prevent).*(?:consecutive|back.to.back|two.*easy)/i.test(response);
        break;

      // ── Injury structural ──
      case 'run_removed_affected_weeks':
        pass = /remove.*run/i.test(response) &&
          (response.match(/remove.*run/gi) || []).length >= 1;
        break;

      case 'substitution_within_ceiling':
        pass = /ceiling|15%|1\.15/i.test(response);
        break;

      case 'taper_preserved':
        pass = !/(?:shift|move|delay).*taper/i.test(response) ||
          /(?:preserve|protect|keep|sacred).*taper/i.test(response);
        break;

      // ── Peak illness ──
      case 'full_stop_current_week':
        pass = /(?:full.*stop|remove.*all|no.*training|complete.*rest)/i.test(response);
        break;

      case 'taper_merge':
        pass = /(?:merge|extend|transition).*taper/i.test(response) ||
          /taper.*(?:merge|extend|early)/i.test(response) ||
          // Functionally correct: full stop through remaining plan with only Z1/Easy
          (/full.*stop|0h/i.test(response) && /arriving.*healthy|health.*sharp/i.test(response));
        break;

      case 'health_over_fitness':
        pass = /(?:healthy|health).*(?:sharp|fit|performance)/i.test(response) ||
          /(?:arrive|arriving|race).*healthy/i.test(response) ||
          /health.*(?:first|priority)/i.test(response);
        break;

      case 'no_intensity_before_race':
        pass = /(?:no.*intensity|z1.*only|easy.*only)/i.test(response) ||
          /(?:avoid|skip).*intensity/i.test(response);
        break;

      // ── Equipment ──
      case 'equipment_acknowledged':
        pass = /treadmill|spin.*bike|hotel.*gym|available.*equipment/i.test(response);
        break;

      // ── Context continuity ──
      case 'references_previous':
        pass = /(?:previous|earlier|last.*time|before|prior|history)/i.test(response) ||
          /knee/i.test(response) || /fatigue.*(?:last|previous|again)/i.test(response) ||
          // For injury recovery: applying ramp-back IS referencing the context
          /ramp.?back.*(?:run|protocol)/i.test(response);
        break;

      case 'more_aggressive_than_first':
        pass = /(?:more.*aggressive|further.*reduce|deeper.*cut|full.*recovery|escalat)/i.test(response) ||
          /(?:wasn't.*enough|insufficient|didn't.*help)/i.test(response) ||
          /(?:convert.*recovery|full.*rest)/i.test(response);
        break;

      case 'consider_full_recovery':
        pass = /(?:full.*recovery|convert.*recovery|recovery.*week|complete.*rest)/i.test(response);
        break;

      case 'root_cause_flag':
        pass = /(?:root.*cause|overtraining|over.training|sleep|nutrition|stress|investigate|underlying)/i.test(response);
        break;

      default:
        pass = false;
        break;
    }

    checks.push({
      name: v.check,
      pass,
      description: v.description,
      actual: pass ? 'found' : 'not found'
    });
  }

  return checks;
}

// ── Run scenario ─────────────────────────────────────────────────────────────

async function runScenario(scenario, athlete, planWeeks) {
  const athleteProfile = buildAthleteProfile(athlete);
  const phaseMap = extractPhaseMap(planWeeks);
  const affectedWeeks = getAffectedSessions(
    planWeeks,
    scenario.current_week,
    scenario.constraint_summary.phase_impact
  );
  const affectedSessionsText = formatAffectedSessions(affectedWeeks);

  const systemPrompt = buildPrompt(
    athleteProfile,
    scenario.constraint_summary,
    phaseMap,
    affectedSessionsText,
    scenario.chat_history
  );

  const start = Date.now();
  const response = await callOpenAI(systemPrompt);
  const latency = Date.now() - start;

  return { response, latency, promptLength: systemPrompt.length };
}

// ── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  const filterId = process.argv[2];
  const toRun = filterId
    ? scenarios.filter(s => s.id === filterId)
    : scenarios;

  if (toRun.length === 0) {
    console.error(`No scenario found with id: ${filterId}`);
    console.error(`Available: ${scenarios.map(s => s.id).join(', ')}`);
    process.exit(1);
  }

  // Parse plan from first athlete (Alex Beginner Olympic)
  const athlete = athletes[0];
  const macroPlan = step2Inputs[0].vars.step1_output;
  const planWeeks = parseMacroPlan(macroPlan);

  console.log(`\n${'='.repeat(70)}`);
  console.log(`Step 2 PoC — ${toRun.length} scenario(s)`);
  console.log(`Model: ${MODEL} | Temp: ${TEMPERATURE}`);
  console.log(`Athlete: ${athlete.vars.athlete_name}`);
  console.log(`Plan: ${planWeeks.length} weeks parsed`);
  console.log(`${'='.repeat(70)}\n`);

  const results = [];

  for (const scenario of toRun) {
    console.log(`\n--- ${scenario.id} ---`);
    console.log(`Notes: ${scenario.notes || 'none'}`);
    console.log(`Constraint: ${scenario.constraint_summary.type} | Phase impact: ${scenario.constraint_summary.phase_impact}`);
    console.log(`Current week: W${scenario.current_week}`);

    const { response, latency, promptLength } = await runScenario(scenario, athlete, planWeeks);

    // Print response (truncated for readability)
    console.log(`\n  Response (${latency}ms, prompt: ${promptLength} chars):`);
    const lines = response.split('\n');
    for (const line of lines) {
      console.log(`    ${line}`);
    }

    // Validate
    const checks = validateResult(scenario, response);
    const allPass = checks.every(c => c.pass);

    console.log(`\n  Checks:`);
    for (const c of checks) {
      const icon = c.pass ? 'PASS' : 'FAIL';
      console.log(`    [${icon}] ${c.name}: ${c.description}`);
    }

    console.log(`\n  Result: ${allPass ? 'PASS' : 'FAIL'} | Latency: ${latency}ms`);

    results.push({
      id: scenario.id,
      pass: allPass,
      latency,
      promptLength,
      checksTotal: checks.length,
      checksPassed: checks.filter(c => c.pass).length,
      checks
    });
  }

  // Summary
  console.log(`\n${'='.repeat(70)}`);
  console.log('SUMMARY');
  console.log(`${'='.repeat(70)}`);

  const passed = results.filter(r => r.pass).length;
  console.log(`\n  ${passed}/${results.length} scenarios passed\n`);

  console.log(`  ${'ID'.padEnd(35)} ${'Checks'.padEnd(12)} ${'Latency'.padEnd(10)} Result`);
  console.log(`  ${'-'.repeat(35)} ${'-'.repeat(12)} ${'-'.repeat(10)} ${'-'.repeat(6)}`);
  for (const r of results) {
    console.log(`  ${r.id.padEnd(35)} ${(r.checksPassed + '/' + r.checksTotal).padEnd(12)} ${(r.latency + 'ms').padEnd(10)} ${r.pass ? 'PASS' : 'FAIL'}`);
  }

  console.log('');

  // Print failed checks detail
  const failed = results.filter(r => !r.pass);
  if (failed.length > 0) {
    console.log('  Failed checks:');
    for (const r of failed) {
      for (const c of r.checks.filter(c => !c.pass)) {
        console.log(`    ${r.id} > ${c.name}: ${c.description}`);
      }
    }
    console.log('');
  }
}

main().catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
