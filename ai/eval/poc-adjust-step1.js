// PoC: Step 1 Conversation Agent — Plan Adjustment
// Tests multi-turn conversation flow against scenarios.
// Usage: node poc-adjust-step1.js [scenarioId]

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
require('dotenv').config({ path: path.join(__dirname, '..', '..', '.env') });

const MODEL = 'gpt-4o';
const TEMPERATURE = 0;
const MAX_TOKENS = 1024;
const MAX_TURNS = 10; // safety cap — should never hit this

// ── Load assets ──────────────────────────────────────────────────────────────

const promptTemplate = fs.readFileSync(
  path.join(__dirname, '..', 'prompts', 'adjust-step1-conversation.txt'), 'utf8'
);

const scenarios = yaml.load(
  fs.readFileSync(path.join(__dirname, 'vars', 'adjust-step1-scenarios.yaml'), 'utf8')
);

// Use first athlete from step2-inputs for plan context
const step2Inputs = yaml.load(
  fs.readFileSync(path.join(__dirname, 'vars', 'step2-inputs.yaml'), 'utf8')
);
const athletes = yaml.load(
  fs.readFileSync(path.join(__dirname, 'vars', 'athletes.yaml'), 'utf8')
);

// ── Build context ────────────────────────────────────────────────────────────

// Extract phase map from macro plan markdown
function extractPhaseMap(macroPlan) {
  const lines = macroPlan.split('\n');
  const weeks = [];
  for (const line of lines) {
    // Match: ## W1 — Base — 2026-02-16
    const match = line.match(/^##\s+W(\d+)\s+—\s+(\w+)\s+—/);
    if (match) {
      const weekNum = parseInt(match[1]);
      const phase = match[2];
      const isRecovery = /recovery/i.test(line) ||
        lines.find((l, i) => i > lines.indexOf(line) && i < lines.indexOf(line) + 5 && /recovery/i.test(l));
      weeks.push({
        week: weekNum,
        phase,
        is_recovery: !!isRecovery
      });
    }
  }
  return weeks;
}

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

function buildSystemPrompt(athleteProfile, phaseMap) {
  let prompt = promptTemplate;
  prompt = prompt.replace('{{athlete_profile}}', athleteProfile);
  prompt = prompt.replace('{{phase_map}}', JSON.stringify(phaseMap, null, 2));
  return prompt;
}

// ── OpenAI call ──────────────────────────────────────────────────────────────

async function callOpenAI(messages) {
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

// ── JSON detection ───────────────────────────────────────────────────────────

// Try to parse response as JSON (terminal state) or return null (conversation)
function tryParseTerminal(text) {
  // Try raw parse first
  try {
    const obj = JSON.parse(text);
    if (obj.status) return obj;
  } catch {}

  // Try extracting from markdown code block
  const match = text.match(/```(?:json)?\s*\n?([\s\S]*?)\n?\s*```/);
  if (match) {
    try {
      const obj = JSON.parse(match[1]);
      if (obj.status) return obj;
    } catch {}
  }

  return null;
}

// ── Validation ───────────────────────────────────────────────────────────────

function validateResult(scenario, result) {
  const checks = [];

  // Check final status
  const expectedStatus = scenario.expected_status || scenario.expected_final_status;
  if (expectedStatus) {
    checks.push({
      name: 'status_match',
      pass: result.status === expectedStatus,
      expected: expectedStatus,
      actual: result.status
    });
  }

  // Check constraint summary fields (when ready)
  const expectedSummary = scenario.expected_constraint_summary;
  if (expectedSummary && result.constraint_summary) {
    const cs = result.constraint_summary;

    if (expectedSummary.type) {
      checks.push({
        name: 'type_match',
        pass: cs.type === expectedSummary.type,
        expected: expectedSummary.type,
        actual: cs.type
      });
    }

    if (expectedSummary.affected_sports) {
      const expected = [...expectedSummary.affected_sports].sort();
      const actual = [...(cs.affected_sports || [])].sort();
      checks.push({
        name: 'affected_sports_match',
        pass: JSON.stringify(expected) === JSON.stringify(actual),
        expected,
        actual
      });
    }

    if (expectedSummary.available_sports) {
      const expected = [...expectedSummary.available_sports].sort();
      const actual = [...(cs.available_sports || [])].sort();
      checks.push({
        name: 'available_sports_match',
        pass: JSON.stringify(expected) === JSON.stringify(actual),
        expected,
        actual
      });
    }

    if (expectedSummary.severity) {
      checks.push({
        name: 'severity_match',
        pass: cs.severity === expectedSummary.severity,
        expected: expectedSummary.severity,
        actual: cs.severity
      });
    }
  }

  // Check follow-up targets (when need_info)
  if (scenario.expected_follow_up_targets && result.conversationText) {
    const text = result.conversationText.toLowerCase();
    for (const target of scenario.expected_follow_up_targets) {
      const keywords = {
        body_location: ['where', 'body', 'location', 'what hurts', 'which part', 'area'],
        which_sports_painful: ['sport', 'swim', 'bike', 'run', 'which', 'can you still', 'affect'],
        fever: ['fever', 'temperature', 'temp']
      };
      const targetKeywords = keywords[target] || [target];
      const found = targetKeywords.some(kw => text.includes(kw));
      checks.push({
        name: `follow_up_asks_${target}`,
        pass: found,
        expected: `mentions ${target}`,
        actual: found ? 'found' : 'not found in: ' + text.substring(0, 100)
      });
    }
  }

  return checks;
}

// ── Run scenario ─────────────────────────────────────────────────────────────

async function runScenario(scenario, systemPrompt) {
  const userMessages = scenario.messages.filter(m => m.role === 'user');
  const conversationMessages = [{ role: 'system', content: systemPrompt }];
  const turns = [];
  let finalResult = null;
  let userMsgIndex = 0;

  for (let turn = 0; turn < MAX_TURNS; turn++) {
    if (userMsgIndex >= userMessages.length) break;

    // Send next user message
    const userMsg = userMessages[userMsgIndex];
    conversationMessages.push({ role: 'user', content: userMsg.content });
    userMsgIndex++;

    // Get AI response
    const start = Date.now();
    const response = await callOpenAI(conversationMessages);
    const latency = Date.now() - start;

    conversationMessages.push({ role: 'assistant', content: response });

    const terminal = tryParseTerminal(response);
    turns.push({
      turn: turn + 1,
      userMessage: userMsg.content,
      aiResponse: response,
      latency,
      isTerminal: !!terminal
    });

    if (terminal) {
      finalResult = terminal;
      break;
    }

    // If there are more user messages scripted, continue.
    // If no more scripted messages and not terminal, that's a problem.
  }

  // If the LLM never reached terminal and we ran out of scripted messages,
  // record whatever the last response was.
  if (!finalResult && turns.length > 0) {
    const lastResponse = turns[turns.length - 1].aiResponse;
    finalResult = { status: 'need_info', conversationText: lastResponse };
  }

  // Attach conversation text for follow-up target validation
  if (finalResult && !finalResult.conversationText && turns.length > 0) {
    // For need_info, the first AI response is what we validate
    finalResult.conversationText = turns.map(t => t.aiResponse).join('\n');
  }

  return { turns, finalResult };
}

// ── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  const filterId = process.argv[2]; // optional: run single scenario
  const toRun = filterId
    ? scenarios.filter(s => s.id === filterId)
    : scenarios;

  if (toRun.length === 0) {
    console.error(`No scenario found with id: ${filterId}`);
    console.error(`Available: ${scenarios.map(s => s.id).join(', ')}`);
    process.exit(1);
  }

  // Build context from first athlete
  const athlete = athletes[0];
  const macroPlan = step2Inputs[0].vars.step1_output;
  const phaseMap = extractPhaseMap(macroPlan);
  const athleteProfile = buildAthleteProfile(athlete);
  const systemPrompt = buildSystemPrompt(athleteProfile, phaseMap);

  console.log(`\n${'='.repeat(70)}`);
  console.log(`Step 1 PoC — ${toRun.length} scenario(s)`);
  console.log(`Model: ${MODEL} | Temp: ${TEMPERATURE}`);
  console.log(`Athlete: ${athlete.vars.athlete_name}`);
  console.log(`Phase map: ${phaseMap.length} weeks`);
  console.log(`${'='.repeat(70)}\n`);

  const results = [];

  for (const scenario of toRun) {
    console.log(`\n--- ${scenario.id} ---`);
    console.log(`Notes: ${scenario.notes || 'none'}`);

    const { turns, finalResult } = await runScenario(scenario, systemPrompt);

    // Print conversation
    for (const t of turns) {
      console.log(`\n  [Turn ${t.turn}] User: "${t.userMessage}"`);
      console.log(`  [Turn ${t.turn}] AI (${t.latency}ms)${t.isTerminal ? ' [TERMINAL]' : ''}:`);
      // Indent AI response
      const lines = t.aiResponse.split('\n');
      for (const line of lines) {
        console.log(`    ${line}`);
      }
    }

    // Validate
    const checks = validateResult(scenario, finalResult);
    const allPass = checks.every(c => c.pass);

    console.log(`\n  Checks:`);
    for (const c of checks) {
      const icon = c.pass ? 'PASS' : 'FAIL';
      console.log(`    [${icon}] ${c.name}: expected=${JSON.stringify(c.expected)} actual=${JSON.stringify(c.actual)}`);
    }

    console.log(`\n  Result: ${allPass ? 'PASS' : 'FAIL'} | Turns: ${turns.length} | Total latency: ${turns.reduce((s, t) => s + t.latency, 0)}ms`);

    results.push({
      id: scenario.id,
      pass: allPass,
      turns: turns.length,
      totalLatency: turns.reduce((s, t) => s + t.latency, 0),
      finalStatus: finalResult?.status,
      checks
    });
  }

  // Summary
  console.log(`\n${'='.repeat(70)}`);
  console.log('SUMMARY');
  console.log(`${'='.repeat(70)}`);

  const passed = results.filter(r => r.pass).length;
  console.log(`\n  ${passed}/${results.length} scenarios passed\n`);

  console.log(`  ${'ID'.padEnd(30)} ${'Status'.padEnd(12)} ${'Turns'.padEnd(8)} ${'Latency'.padEnd(10)} Result`);
  console.log(`  ${'-'.repeat(30)} ${'-'.repeat(12)} ${'-'.repeat(8)} ${'-'.repeat(10)} ${'-'.repeat(6)}`);
  for (const r of results) {
    console.log(`  ${r.id.padEnd(30)} ${(r.finalStatus || '?').padEnd(12)} ${String(r.turns).padEnd(8)} ${(r.totalLatency + 'ms').padEnd(10)} ${r.pass ? 'PASS' : 'FAIL'}`);
  }

  console.log('');

  // Print failed checks detail
  const failed = results.filter(r => !r.pass);
  if (failed.length > 0) {
    console.log('  Failed checks:');
    for (const r of failed) {
      for (const c of r.checks.filter(c => !c.pass)) {
        console.log(`    ${r.id} > ${c.name}: expected=${JSON.stringify(c.expected)} got=${JSON.stringify(c.actual)}`);
      }
    }
    console.log('');
  }
}

main().catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
