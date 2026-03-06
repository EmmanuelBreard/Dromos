// PoC: E2E Integration — Step 1 → Step 2 → Apply Diff → Validate Plan
// Tests the full pipeline: user message → conversation → macro diff → modified plan → quality checks
// Usage: node poc-adjust-e2e.js [scenarioId]

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
require('dotenv').config({ path: path.join(__dirname, '..', '..', '.env') });

const MODEL = 'gpt-4o';
const TEMPERATURE = 0;
const MAX_TOKENS_STEP1 = 1024;
const MAX_TOKENS_STEP2 = 2048;
const MAX_TURNS = 10;

// ── Load assets ──────────────────────────────────────────────────────────────

const step1Prompt = fs.readFileSync(
  path.join(__dirname, '..', 'prompts', 'adjust-step1-conversation.txt'), 'utf8'
);
const step2Prompt = fs.readFileSync(
  path.join(__dirname, '..', 'prompts', 'adjust-step2-coaching-brain.txt'), 'utf8'
);

const step2Inputs = yaml.load(
  fs.readFileSync(path.join(__dirname, 'vars', 'step2-inputs.yaml'), 'utf8')
);
const athletes = yaml.load(
  fs.readFileSync(path.join(__dirname, 'vars', 'athletes.yaml'), 'utf8')
);

// ── E2E Scenarios ────────────────────────────────────────────────────────────
// 3 scenarios testing the full pipeline with different complexity levels

const scenarios = [
  {
    id: 'E2E_1_simple_equipment',
    description: 'Single-turn → local adjustment',
    current_week: 5,
    messages: [
      { role: 'user', content: "I'm traveling to London March 16-22. Hotel has a gym with treadmill and spin bike but no pool." }
    ],
    validation: {
      step1: {
        expected_status: 'ready',
        expected_type: 'equipment',
        expected_affected_sports: ['swim']
      },
      step2: {
        swim_removed: true,
        equipment_acknowledged: true,
        no_ramp_back: true
      }
    },
    notes: 'Happy path: single-turn conversation, clean equipment swap, no cascading'
  },
  {
    id: 'E2E_2_injury_multi_turn',
    description: 'Multi-turn → structural adjustment with ramp-back',
    current_week: 13,
    messages: [
      { role: 'user', content: "I hurt myself" },
      { role: 'user', content: "It's my left shin, feels like shin splints" },
      { role: 'user', content: "Running is painful. Biking and swimming are fine." }
    ],
    validation: {
      step1: {
        expected_status: 'ready',
        expected_type: 'injury',
        expected_affected_sports: ['run']
      },
      step2: {
        run_removed: true,
        substitution_within_ceiling: true,
        ramp_back_included: true
      }
    },
    notes: '3-turn injury conversation → structural diff with ramp-back'
  },
  {
    id: 'E2E_3_illness_fever_gate',
    description: 'Multi-turn with fever gate → full stop',
    current_week: 11,
    messages: [
      { role: 'user', content: "I've been feeling really sick since yesterday" },
      { role: 'user', content: "Yes I have a fever, 38.5, and my chest feels tight" }
    ],
    validation: {
      step1: {
        expected_status: 'ready',
        expected_type: 'illness'
      },
      step2: {
        all_sessions_removed: true,
        ramp_back_included: true,
        no_substitution: true
      }
    },
    notes: 'Illness with fever → below-neck full stop with ramp-back'
  }
];

// ── Plan parsing (reused from poc-adjust-step2.js) ───────────────────────────

function parseMacroPlan(macroPlan) {
  const cleaned = macroPlan.replace(/^```(?:markdown)?\s*\n?/, '').replace(/\n?\s*```$/, '');
  const lines = cleaned.split('\n');
  const weeks = [];
  let current = null;

  for (const line of lines) {
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

    const sessionMatch = line.match(/^-\s+(Swim|Bike|Run):\s+(.+)/);
    if (sessionMatch) {
      const sport = sessionMatch[1].toLowerCase();
      const sessionParts = sessionMatch[2].split(',').map(s => s.trim());
      for (const part of sessionParts) {
        const sm = part.match(/(\w+)\s+(\d+)min/);
        if (sm) {
          current.sessions.push({ sport, type: sm[1], duration_minutes: parseInt(sm[2]) });
        }
      }
      continue;
    }

    const notesMatch = line.match(/^Notes:\s+(.+)/);
    if (notesMatch) {
      current.notes = notesMatch[1];
      if (/recovery/i.test(notesMatch[1])) current.is_recovery = true;
    }
  }
  if (current) weeks.push(current);
  return weeks;
}

function extractPhaseMap(weeks) {
  return weeks.map(w => ({
    week: w.week, phase: w.phase, is_recovery: w.is_recovery, date: w.date
  }));
}

function getAffectedSessions(weeks, currentWeek, phaseImpact) {
  const curr = weeks.find(w => w.week === currentWeek);
  if (!curr) return [];
  if (phaseImpact === 'local') {
    return weeks.filter(w => w.week >= currentWeek - 1 && w.week <= currentWeek + 1);
  }
  const currentPhase = curr.phase;
  return weeks.filter(w =>
    w.week >= currentWeek && (w.phase === currentPhase || w.week <= currentWeek + 6)
  );
}

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

// ── Athlete profile ──────────────────────────────────────────────────────────

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

// ── OpenAI call ──────────────────────────────────────────────────────────────

async function callOpenAI(messages, maxTokens) {
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
      max_tokens: maxTokens,
      messages
    })
  });

  if (!resp.ok) {
    const err = await resp.text();
    throw new Error(`OpenAI API error ${resp.status}: ${err}`);
  }

  const data = await resp.json();
  return data.choices[0].message.content;
}

// ── JSON detection (from Step 1) ─────────────────────────────────────────────

function tryParseTerminal(text) {
  try {
    const obj = JSON.parse(text);
    if (obj.status) return obj;
  } catch {}

  const match = text.match(/```(?:json)?\s*\n?([\s\S]*?)\n?\s*```/);
  if (match) {
    try {
      const obj = JSON.parse(match[1]);
      if (obj.status) return obj;
    } catch {}
  }

  return null;
}

// ── Step 1: Conversation ─────────────────────────────────────────────────────

async function runStep1(scenario, systemPrompt) {
  const userMessages = scenario.messages;
  const conversationMessages = [{ role: 'system', content: systemPrompt }];
  const turns = [];
  let finalResult = null;
  let userMsgIndex = 0;
  let totalLatency = 0;

  for (let turn = 0; turn < MAX_TURNS; turn++) {
    if (userMsgIndex >= userMessages.length) break;

    conversationMessages.push({ role: 'user', content: userMessages[userMsgIndex].content });
    userMsgIndex++;

    const start = Date.now();
    const response = await callOpenAI(conversationMessages, MAX_TOKENS_STEP1);
    const latency = Date.now() - start;
    totalLatency += latency;

    conversationMessages.push({ role: 'assistant', content: response });

    const terminal = tryParseTerminal(response);
    turns.push({
      turn: turn + 1,
      userMessage: userMessages[userMsgIndex - 1].content,
      aiResponse: response,
      latency,
      isTerminal: !!terminal
    });

    if (terminal) {
      finalResult = terminal;
      break;
    }
  }

  if (!finalResult && turns.length > 0) {
    finalResult = { status: 'need_info', conversationText: turns[turns.length - 1].aiResponse };
  }

  return { turns, finalResult, totalLatency };
}

// ── Step 2: Coaching Brain ───────────────────────────────────────────────────

async function runStep2(constraintSummary, scenario, athlete, planWeeks) {
  const athleteProfile = buildAthleteProfile(athlete);
  const phaseMap = extractPhaseMap(planWeeks);
  const phaseImpact = constraintSummary.phase_impact || 'local';
  const affectedWeeks = getAffectedSessions(planWeeks, scenario.current_week, phaseImpact);
  const affectedSessionsText = formatAffectedSessions(affectedWeeks);

  let prompt = step2Prompt;
  prompt = prompt.replace('{{athlete_profile}}', athleteProfile);
  prompt = prompt.replace('{{constraint_summary}}', JSON.stringify(constraintSummary, null, 2));
  prompt = prompt.replace('{{phase_map}}', JSON.stringify(phaseMap, null, 2));
  prompt = prompt.replace('{{affected_sessions}}', affectedSessionsText);

  const start = Date.now();
  const response = await callOpenAI([
    { role: 'system', content: prompt },
    { role: 'user', content: 'Apply the adjustment rules to the constraint and produce the macro diff.' }
  ], MAX_TOKENS_STEP2);
  const latency = Date.now() - start;

  return { response, latency };
}

// ── Validation ───────────────────────────────────────────────────────────────

function validateE2E(scenario, step1Result, step2Response) {
  const checks = [];

  // ── Contract validation (Step 1 → Step 2) ──
  // Step 1 must produce a valid constraint_summary
  const cs = step1Result.constraint_summary;
  checks.push({
    name: 'contract_has_status',
    pass: !!step1Result.status,
    description: 'Step 1 outputs a status field'
  });

  checks.push({
    name: 'contract_has_constraint_summary',
    pass: !!cs,
    description: 'Step 1 outputs a constraint_summary object'
  });

  if (cs) {
    checks.push({
      name: 'contract_has_type',
      pass: ['equipment', 'fatigue', 'injury', 'illness'].includes(cs.type),
      description: `constraint_summary.type is valid (got: ${cs.type})`
    });

    checks.push({
      name: 'contract_has_phase_impact',
      pass: ['local', 'structural'].includes(cs.phase_impact),
      description: `constraint_summary.phase_impact is valid (got: ${cs.phase_impact})`
    });
  }

  // ── Step 1 validation ──
  const s1v = scenario.validation.step1;
  if (s1v.expected_status) {
    checks.push({
      name: 'step1_status',
      pass: step1Result.status === s1v.expected_status,
      description: `Step 1 status = ${s1v.expected_status} (got: ${step1Result.status})`
    });
  }

  if (s1v.expected_type && cs) {
    checks.push({
      name: 'step1_type',
      pass: cs.type === s1v.expected_type,
      description: `constraint type = ${s1v.expected_type} (got: ${cs.type})`
    });
  }

  if (s1v.expected_affected_sports && cs) {
    const expected = [...s1v.expected_affected_sports].sort();
    const actual = [...(cs.affected_sports || [])].sort();
    checks.push({
      name: 'step1_affected_sports',
      pass: JSON.stringify(expected) === JSON.stringify(actual),
      description: `affected_sports = ${JSON.stringify(expected)} (got: ${JSON.stringify(actual)})`
    });
  }

  // ── Step 2 validation ──
  const s2v = scenario.validation.step2;
  const text = step2Response.toLowerCase();

  if (s2v.swim_removed) {
    checks.push({
      name: 'step2_swim_removed',
      pass: /remove.*swim/i.test(step2Response),
      description: 'Step 2 removes swim sessions'
    });
  }

  if (s2v.run_removed) {
    checks.push({
      name: 'step2_run_removed',
      pass: /remove.*run/i.test(step2Response),
      description: 'Step 2 removes run sessions'
    });
  }

  if (s2v.equipment_acknowledged) {
    checks.push({
      name: 'step2_equipment_acknowledged',
      pass: /treadmill|spin.*bike|hotel.*gym/i.test(step2Response),
      description: 'Step 2 acknowledges available equipment'
    });
  }

  if (s2v.no_ramp_back) {
    checks.push({
      name: 'step2_no_ramp_back',
      pass: !/ramp.?back|return.*protocol/i.test(step2Response) ||
        /no.*ramp.?back|not.*needed|resume.*immediately/i.test(step2Response),
      description: 'Step 2 does NOT include ramp-back (equipment constraint)'
    });
  }

  if (s2v.substitution_within_ceiling) {
    checks.push({
      name: 'step2_ceiling',
      pass: /ceiling|15%|1\.15/i.test(step2Response),
      description: 'Step 2 shows volume ceiling math'
    });
  }

  if (s2v.ramp_back_included) {
    checks.push({
      name: 'step2_ramp_back',
      pass: /ramp.?back|return.*protocol/i.test(step2Response),
      description: 'Step 2 includes ramp-back protocol'
    });
  }

  if (s2v.all_sessions_removed) {
    checks.push({
      name: 'step2_all_removed',
      pass: /remove/i.test(step2Response) && !/\bkeep\b/i.test(
        // Check only the current week section
        (step2Response.match(new RegExp(`## Week ${scenario.current_week}[\\s\\S]*?(?=## Week|$)`, 'i')) || [''])[0]
      ),
      description: 'Step 2 removes all sessions in current week'
    });
  }

  if (s2v.no_substitution) {
    const weekSection = (step2Response.match(
      new RegExp(`## Week ${scenario.current_week}[\\s\\S]*?(?=## Week|$)`, 'i')
    ) || [''])[0];
    checks.push({
      name: 'step2_no_substitution',
      pass: !/\bADD\b/i.test(weekSection),
      description: 'Step 2 does not substitute in current week (illness full stop)'
    });
  }

  return checks;
}

// ── Diff Applier ─────────────────────────────────────────────────────────────
// Applies Step 2 macro diff to the original plan, producing a modified plan

function applyDiffToPlan(originalWeeks, diffText) {
  // Parse which weeks are modified and their new state
  const modifiedWeeks = new Map();

  // Split diff into week sections
  const weekSections = diffText.split(/(?=## Week \d+)/i).filter(s => /## Week \d+/i.test(s));

  for (const section of weekSections) {
    const weekMatch = section.match(/## Week (\d+)/i);
    if (!weekMatch) continue;
    const weekNum = parseInt(weekMatch[1]);

    // Extract new volume if present: "Volume: 6.5h → 4.5h"
    const volumeMatch = section.match(/Volume:.*?→\s*([\d.]+)h/i);
    const newTotalHours = volumeMatch ? parseFloat(volumeMatch[1]) : null;

    // Collect sessions from KEEP, ADD, CONVERT lines
    const sessions = [];
    const lines = section.split('\n');

    for (const line of lines) {
      // KEEP: [day] [type] [sport] [duration]min
      const keepMatch = line.match(/KEEP:.*?(\w+)\s+(swim|bike|run)\s+(\d+)min/i) ||
                        line.match(/KEEP:.*?(swim|bike|run)\s+(\w+)\s+(\d+)min/i);
      if (keepMatch) {
        if (/swim|bike|run/i.test(keepMatch[1])) {
          sessions.push({ sport: keepMatch[1].toLowerCase(), type: keepMatch[2], duration: parseInt(keepMatch[3]) });
        } else {
          sessions.push({ sport: keepMatch[2].toLowerCase(), type: keepMatch[1], duration: parseInt(keepMatch[3]) });
        }
        continue;
      }

      // ADD: [day] [type] [sport] [duration]min
      const addMatch = line.match(/ADD:.*?(\w+)\s+(swim|bike|run).*?(\d+)min/i) ||
                       line.match(/ADD:.*?(swim|bike|run)\s+(\w+).*?(\d+)min/i);
      if (addMatch) {
        if (/swim|bike|run/i.test(addMatch[1])) {
          sessions.push({ sport: addMatch[1].toLowerCase(), type: addMatch[2], duration: parseInt(addMatch[3]) });
        } else {
          sessions.push({ sport: addMatch[2].toLowerCase(), type: addMatch[1], duration: parseInt(addMatch[3]) });
        }
        continue;
      }

      // CONVERT: [type] [sport] → [new_type] [sport] [duration]min
      const convertMatch = line.match(/CONVERT:.*?→\s*(\w+)\s+(swim|bike|run)\s+(\d+)min/i) ||
                           line.match(/CONVERT:.*?→\s*(swim|bike|run)\s+(\w+)\s+(\d+)min/i);
      if (convertMatch) {
        if (/swim|bike|run/i.test(convertMatch[1])) {
          sessions.push({ sport: convertMatch[1].toLowerCase(), type: convertMatch[2], duration: parseInt(convertMatch[3]) });
        } else {
          sessions.push({ sport: convertMatch[2].toLowerCase(), type: convertMatch[1], duration: parseInt(convertMatch[3]) });
        }
        continue;
      }
    }

    // Check for RESTRUCTURED/SWAP (recovery moved)
    const isRestructured = /RESTRUCTURED|SWAP/i.test(section);
    const isFullStop = sessions.length === 0 && /remove/i.test(section) && !/keep/i.test(section);

    modifiedWeeks.set(weekNum, { newTotalHours, sessions, isRestructured, isFullStop });
  }

  // Build modified plan
  const result = originalWeeks.map(w => {
    const mod = modifiedWeeks.get(w.week);
    if (!mod) return { ...w }; // unmodified

    if (mod.isFullStop) {
      return {
        ...w,
        total: mod.newTotalHours || 0,
        volumes: { swim: 0, bike: 0, run: 0 },
        sessions: [],
        is_recovery: true // full stop acts as recovery
      };
    }

    // Rebuild from parsed sessions
    const newSessions = mod.sessions.map(s => ({
      sport: s.sport,
      type: s.type,
      duration_minutes: s.duration
    }));

    // Compute volumes
    const volumes = { swim: 0, bike: 0, run: 0 };
    for (const s of newSessions) {
      if (volumes[s.sport] !== undefined) {
        volumes[s.sport] += s.duration_minutes;
      }
    }

    const totalMinutes = volumes.swim + volumes.bike + volumes.run;
    const total = mod.newTotalHours || parseFloat((totalMinutes / 60).toFixed(1));

    return {
      ...w,
      total,
      volumes,
      sessions: newSessions,
      is_recovery: mod.isRestructured ? true : w.is_recovery
    };
  });

  return result;
}

// Render modified plan as markdown (same format as original)
function renderPlanMarkdown(weeks, summary) {
  const lines = [];
  if (summary) lines.push(summary);
  lines.push('');

  for (const w of weeks) {
    const swimH = (w.volumes.swim / 60).toFixed(1);
    const bikeH = (w.volumes.bike / 60).toFixed(1);
    const runH = (w.volumes.run / 60).toFixed(1);

    lines.push(`## W${w.week} — ${w.phase} — ${w.date}`);
    lines.push(`Total: ${w.total}h | Swim ${swimH}h | Bike ${bikeH}h | Run ${runH}h`);

    // Group sessions by sport
    const bySport = { swim: [], bike: [], run: [] };
    for (const s of w.sessions) {
      if (bySport[s.sport]) {
        bySport[s.sport].push(`${s.type} ${s.duration_minutes}min`);
      }
    }

    for (const sport of ['swim', 'bike', 'run']) {
      const sportSessions = bySport[sport];
      if (sportSessions.length > 0) {
        const label = sport.charAt(0).toUpperCase() + sport.slice(1);
        lines.push(`- ${label}: ${sportSessions.join(', ')}`);
      }
    }

    if (w.notes) lines.push(`Notes: ${w.notes}`);
    lines.push('');
  }

  return lines.join('\n');
}

// ── Plan Quality Validation ──────────────────────────────────────────────────
// Runs the same checks as validate-macro-plan-md.js + adjustment-specific checks

function validateModifiedPlan(modifiedWeeks, originalWeeks, constraintSummary, weeklyHoursBudget) {
  const checks = [];

  // ── Structural checks (from validate-macro-plan-md.js) ──

  // 1. Volume within budget
  for (const w of modifiedWeeks) {
    if (w.total > weeklyHoursBudget * 1.2) {
      checks.push({
        name: `plan_volume_budget_W${w.week}`,
        pass: false,
        description: `W${w.week}: ${w.total}h exceeds budget ${weeklyHoursBudget}h (+20%)`
      });
    }
  }
  if (!checks.some(c => c.name.startsWith('plan_volume_budget'))) {
    checks.push({
      name: 'plan_volume_within_budget',
      pass: true,
      description: 'All weeks within volume budget'
    });
  }

  // 2. No more than 5 consecutive load weeks
  let loadStreak = 0;
  let maxStreak = 0;
  for (const w of modifiedWeeks) {
    const isRecovery = w.is_recovery || w.phase === 'Taper' || w.phase === 'Recovery' || w.total === 0;
    if (isRecovery) {
      loadStreak = 0;
    } else {
      loadStreak++;
      maxStreak = Math.max(maxStreak, loadStreak);
    }
  }
  checks.push({
    name: 'plan_load_recovery_pattern',
    pass: maxStreak <= 5,
    description: `Max consecutive load weeks: ${maxStreak} (limit: 5)`
  });

  // 3. Taper preserved
  const hasT = modifiedWeeks.some(w => w.phase === 'Taper');
  checks.push({
    name: 'plan_taper_preserved',
    pass: hasT,
    description: 'Taper phase still present in modified plan'
  });

  // 4. Last week still Taper or Recovery
  const lastWeek = modifiedWeeks[modifiedWeeks.length - 1];
  checks.push({
    name: 'plan_last_week_phase',
    pass: lastWeek.phase === 'Taper' || lastWeek.phase === 'Recovery',
    description: `Last week phase: ${lastWeek.phase}`
  });

  // ── Adjustment-specific checks ──

  // 5. Volume ceiling per sport: no sport gained more than 15% vs original
  const affectedSports = constraintSummary.available_sports || [];
  for (const sport of affectedSports) {
    for (const w of modifiedWeeks) {
      const orig = originalWeeks.find(ow => ow.week === w.week);
      if (!orig) continue;

      const origVol = orig.volumes[sport] || 0;
      const modVol = w.volumes[sport] || 0;

      if (origVol > 0 && modVol > origVol) {
        const increase = modVol - origVol;
        const ceiling = origVol * 0.15;
        if (increase > ceiling + 5) { // 5min tolerance
          checks.push({
            name: `plan_ceiling_${sport}_W${w.week}`,
            pass: false,
            description: `W${w.week} ${sport}: +${increase}min exceeds 15% ceiling of ${Math.round(ceiling)}min`
          });
        }
      }
    }
  }
  if (!checks.some(c => c.name.startsWith('plan_ceiling'))) {
    checks.push({
      name: 'plan_volume_ceiling_respected',
      pass: true,
      description: 'All sport volumes within 15% ceiling'
    });
  }

  // 6. No week exceeds original volume (adjustments should reduce, not inflate)
  let anyInflation = false;
  for (const w of modifiedWeeks) {
    const orig = originalWeeks.find(ow => ow.week === w.week);
    if (!orig) continue;
    if (w.total > orig.total + 0.3) { // 0.3h tolerance
      anyInflation = true;
      checks.push({
        name: `plan_no_inflation_W${w.week}`,
        pass: false,
        description: `W${w.week}: ${w.total}h > original ${orig.total}h (adjustments should not inflate volume)`
      });
    }
  }
  if (!anyInflation) {
    checks.push({
      name: 'plan_no_volume_inflation',
      pass: true,
      description: 'No week exceeds original volume'
    });
  }

  // 7. Intensity cap: Tempo/Intervals ≤ 60min
  for (const w of modifiedWeeks) {
    for (const s of w.sessions) {
      if ((s.type === 'Tempo' || s.type === 'Intervals') && s.duration_minutes > 60) {
        checks.push({
          name: `plan_intensity_cap_W${w.week}`,
          pass: false,
          description: `W${w.week}: ${s.type} ${s.sport} ${s.duration_minutes}min exceeds 60min cap`
        });
      }
    }
  }
  if (!checks.some(c => c.name.startsWith('plan_intensity_cap'))) {
    checks.push({
      name: 'plan_intensity_cap_respected',
      pass: true,
      description: 'All Tempo/Intervals sessions ≤ 60min'
    });
  }

  // 8. Sessions exist for weeks with volume > 0
  for (const w of modifiedWeeks) {
    if (w.total > 0 && w.sessions.length === 0) {
      checks.push({
        name: `plan_sessions_exist_W${w.week}`,
        pass: false,
        description: `W${w.week}: ${w.total}h volume but no sessions parsed`
      });
    }
  }
  if (!checks.some(c => c.name.startsWith('plan_sessions_exist'))) {
    checks.push({
      name: 'plan_sessions_exist',
      pass: true,
      description: 'All non-zero weeks have sessions'
    });
  }

  return checks;
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

  const athlete = athletes[0];
  const macroPlan = step2Inputs[0].vars.step1_output;
  const planWeeks = parseMacroPlan(macroPlan);
  const phaseMap = extractPhaseMap(planWeeks);
  const athleteProfile = buildAthleteProfile(athlete);

  // Build Step 1 system prompt
  let step1SystemPrompt = step1Prompt;
  step1SystemPrompt = step1SystemPrompt.replace('{{athlete_profile}}', athleteProfile);
  step1SystemPrompt = step1SystemPrompt.replace('{{phase_map}}', JSON.stringify(phaseMap, null, 2));

  console.log(`\n${'='.repeat(70)}`);
  console.log(`E2E Integration PoC — ${toRun.length} scenario(s)`);
  console.log(`Model: ${MODEL} | Temp: ${TEMPERATURE}`);
  console.log(`Athlete: ${athlete.vars.athlete_name}`);
  console.log(`${'='.repeat(70)}\n`);

  const results = [];

  for (const scenario of toRun) {
    console.log(`\n--- ${scenario.id}: ${scenario.description} ---`);
    console.log(`Notes: ${scenario.notes}`);

    // ── Step 1 ──
    console.log(`\n  [Step 1] Running conversation (${scenario.messages.length} user messages)...`);
    const { turns, finalResult, totalLatency: step1Latency } = await runStep1(scenario, step1SystemPrompt);

    for (const t of turns) {
      console.log(`    Turn ${t.turn}: User: "${t.userMessage}"`);
      const preview = t.aiResponse.substring(0, 150).replace(/\n/g, ' ');
      console.log(`    Turn ${t.turn}: AI (${t.latency}ms)${t.isTerminal ? ' [TERMINAL]' : ''}: ${preview}...`);
    }

    console.log(`  [Step 1] Status: ${finalResult?.status} | Turns: ${turns.length} | Latency: ${step1Latency}ms`);

    // ── Contract check ──
    if (finalResult?.status !== 'ready' || !finalResult?.constraint_summary) {
      console.log(`  [SKIP Step 2] Step 1 did not produce a ready constraint_summary`);

      const checks = validateE2E(scenario, finalResult || {}, '');
      const allPass = checks.every(c => c.pass);

      console.log(`\n  Checks:`);
      for (const c of checks) {
        console.log(`    [${c.pass ? 'PASS' : 'FAIL'}] ${c.name}: ${c.description}`);
      }

      results.push({
        id: scenario.id,
        pass: false,
        step1Turns: turns.length,
        step1Latency,
        step2Latency: 0,
        totalLatency: step1Latency,
        step1Status: finalResult?.status,
        step2Ran: false,
        checks
      });
      continue;
    }

    // ── Step 2 ──
    console.log(`\n  [Step 2] Running coaching brain...`);
    console.log(`    Constraint: ${JSON.stringify(finalResult.constraint_summary)}`);

    const { response: step2Response, latency: step2Latency } = await runStep2(
      finalResult.constraint_summary, scenario, athlete, planWeeks
    );

    // Print Step 2 response
    const step2Lines = step2Response.split('\n');
    for (const line of step2Lines) {
      console.log(`    ${line}`);
    }

    console.log(`  [Step 2] Latency: ${step2Latency}ms`);

    // ── Step 3: Apply diff + Validate plan quality ──
    console.log(`\n  [Step 3] Applying diff to plan and validating...`);
    const modifiedWeeks = applyDiffToPlan(planWeeks, step2Response);
    const modifiedPlanMd = renderPlanMarkdown(modifiedWeeks, '# Modified Plan');

    // Print modified week summaries
    for (const w of modifiedWeeks) {
      const orig = planWeeks.find(ow => ow.week === w.week);
      if (orig && (orig.total !== w.total || JSON.stringify(orig.volumes) !== JSON.stringify(w.volumes))) {
        console.log(`    W${w.week} (${w.phase}): ${orig.total}h → ${w.total}h | S:${w.volumes.swim}m B:${w.volumes.bike}m R:${w.volumes.run}m`);
      }
    }

    const planChecks = validateModifiedPlan(
      modifiedWeeks, planWeeks,
      finalResult.constraint_summary,
      parseFloat(athlete.vars.weekly_hours)
    );

    // ── Combine all checks ──
    const pipelineChecks = validateE2E(scenario, finalResult, step2Response);
    const allChecks = [...pipelineChecks, ...planChecks];
    const allPass = allChecks.every(c => c.pass);

    console.log(`\n  Pipeline checks:`);
    for (const c of pipelineChecks) {
      console.log(`    [${c.pass ? 'PASS' : 'FAIL'}] ${c.name}: ${c.description}`);
    }
    console.log(`  Plan quality checks:`);
    for (const c of planChecks) {
      console.log(`    [${c.pass ? 'PASS' : 'FAIL'}] ${c.name}: ${c.description}`);
    }

    const totalLatency = step1Latency + step2Latency;
    console.log(`\n  Result: ${allPass ? 'PASS' : 'FAIL'} | Total latency: ${totalLatency}ms (S1: ${step1Latency}ms + S2: ${step2Latency}ms)`);

    results.push({
      id: scenario.id,
      pass: allPass,
      step1Turns: turns.length,
      step1Latency,
      step2Latency,
      totalLatency,
      step1Status: finalResult.status,
      step2Ran: true,
      checks: allChecks
    });
  }

  // ── Summary ──
  console.log(`\n${'='.repeat(70)}`);
  console.log('E2E SUMMARY');
  console.log(`${'='.repeat(70)}`);

  const passed = results.filter(r => r.pass).length;
  console.log(`\n  ${passed}/${results.length} scenarios passed\n`);

  console.log(`  ${'ID'.padEnd(30)} ${'S1 Turns'.padEnd(10)} ${'S1 ms'.padEnd(10)} ${'S2 ms'.padEnd(10)} ${'Total ms'.padEnd(12)} Result`);
  console.log(`  ${'-'.repeat(30)} ${'-'.repeat(10)} ${'-'.repeat(10)} ${'-'.repeat(10)} ${'-'.repeat(12)} ${'-'.repeat(6)}`);
  for (const r of results) {
    console.log(`  ${r.id.padEnd(30)} ${String(r.step1Turns).padEnd(10)} ${(r.step1Latency + 'ms').padEnd(10)} ${(r.step2Ran ? r.step2Latency + 'ms' : 'skip').padEnd(10)} ${(r.totalLatency + 'ms').padEnd(12)} ${r.pass ? 'PASS' : 'FAIL'}`);
  }

  console.log('');

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

  // Latency summary
  const avgTotal = Math.round(results.reduce((s, r) => s + r.totalLatency, 0) / results.length);
  const avgS1 = Math.round(results.reduce((s, r) => s + r.step1Latency, 0) / results.length);
  const avgS2 = Math.round(results.filter(r => r.step2Ran).reduce((s, r) => s + r.step2Latency, 0) / results.filter(r => r.step2Ran).length || 0);
  console.log(`  Latency avg: Total ${avgTotal}ms | S1 ${avgS1}ms | S2 ${avgS2}ms`);
  console.log('');
}

main().catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
