#!/usr/bin/env node
/**
 * test-step3-parallel.js
 * Validates the parallel step 3 change against sequential:
 * - Correct output (all weeks + sessions have template_id assigned)
 * - Timing improvement
 * - No regressions in structure
 *
 * Uses real production prompts and a real 15-week macro plan.
 * Run: node ai/eval/test-step3-parallel.js
 */

require("dotenv").config({ path: require("path").join(__dirname, "../../.env") });
const fs = require("fs");
const path = require("path");
const yaml = require("js-yaml");
const OpenAI = require("openai").default || require("openai");

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

const MODEL_STEP3 = "gpt-4.1";
const TEMPERATURE = 0.7;
const MAX_TOKENS_STEP3 = 4096;
const BLOCK_SIZE = 4;

// ---------------------------------------------------------------------------
// Load real production assets
// ---------------------------------------------------------------------------
const PROMPT_TEMPLATE = fs.readFileSync(
  path.join(__dirname, "../prompts/step3-workout-block.txt"),
  "utf8"
);
const WORKOUT_LIBRARY = JSON.parse(
  fs.readFileSync(path.join(__dirname, "../context/workout-library.json"), "utf8")
);

// Load the first athlete from step3-inputs.yaml (15-week real plan)
const step3Inputs = yaml.load(
  fs.readFileSync(path.join(__dirname, "vars/step3-inputs.yaml"), "utf8")
);
const testVars = step3Inputs[0].vars;
const macroPlan = JSON.parse(testVars.macro_plan_json);
const weeks = macroPlan.weeks;

// ---------------------------------------------------------------------------
// Helpers matching production buildSimplifiedLibrary
// ---------------------------------------------------------------------------
function buildSimplifiedLibrary(lib) {
  const lines = [];
  for (const sport of ["swim", "bike", "run"]) {
    for (const tmpl of lib[sport] || []) {
      const tid = tmpl.template_id;
      const typeStr = tmpl.type || tid.split("_")[1];
      lines.push(`${tid} | ${sport} | ${typeStr} | ${tmpl.duration_minutes}min`);
    }
  }
  return "template_id | sport | type | duration\n" + lines.join("\n");
}

const simplifiedLibrary = buildSimplifiedLibrary(WORKOUT_LIBRARY);

function buildPrompt(block, previouslyUsed = "None — blocks processed in parallel.") {
  return PROMPT_TEMPLATE
    .replace("{{workout_library}}", simplifiedLibrary)
    .replace("{{block_weeks_json}}", JSON.stringify(block, null, 2))
    .replace("{{limiters}}", testVars.limiters || "none")
    .replace("{{constraints}}", testVars.constraints || "")
    .replace("{{previously_used}}", previouslyUsed);
}

async function callOpenAI(prompt) {
  const res = await openai.chat.completions.create({
    model: MODEL_STEP3,
    messages: [{ role: "user", content: prompt }],
    temperature: TEMPERATURE,
    max_tokens: MAX_TOKENS_STEP3,
    response_format: { type: "json_object" },
  });
  const raw = res.choices[0].message.content
    .replace(/```json\n?/g, "")
    .replace(/```\n?/g, "")
    .trim();
  return JSON.parse(raw);
}

// ---------------------------------------------------------------------------
// Validation: check all weeks have sessions with template_id assigned
// ---------------------------------------------------------------------------
function validateOutput(allWeeks, label) {
  let issues = [];
  let totalSessions = 0;
  let assignedSessions = 0;

  for (const week of allWeeks) {
    const sessions = week.sessions || [];
    for (const s of sessions) {
      totalSessions++;
      if (s.template_id) {
        assignedSessions++;
      } else {
        issues.push(`W${week.week_number} ${s.day} ${s.sport}: missing template_id`);
      }
    }
  }

  const weekNumbers = allWeeks.map((w) => w.week_number).sort((a, b) => a - b);
  const expectedWeeks = weeks.map((w) => w.week_number).sort((a, b) => a - b);
  const missingWeeks = expectedWeeks.filter((n) => !weekNumbers.includes(n));
  const extraWeeks = weekNumbers.filter((n) => !expectedWeeks.includes(n));

  console.log(`\n  [${label}] Validation:`);
  console.log(`    Weeks:    ${weekNumbers.length}/${expectedWeeks.length} returned${missingWeeks.length ? ` — MISSING: W${missingWeeks.join(", W")}` : " ✓"}`);
  if (extraWeeks.length) console.log(`    Extra weeks returned: W${extraWeeks.join(", W")} ⚠`);
  console.log(`    Sessions: ${assignedSessions}/${totalSessions} have template_id${assignedSessions === totalSessions ? " ✓" : " ⚠"}`);
  if (issues.length) {
    console.log(`    Issues (${issues.length}):`);
    issues.slice(0, 5).forEach((i) => console.log(`      - ${i}`));
    if (issues.length > 5) console.log(`      ... and ${issues.length - 5} more`);
  }

  return issues.length === 0 && missingWeeks.length === 0;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
  const blocks = [];
  for (let j = 0; j < weeks.length; j += BLOCK_SIZE) {
    blocks.push(weeks.slice(j, j + BLOCK_SIZE));
  }

  console.log(`\n=== Step 3 parallel vs sequential — ${weeks.length} weeks, ${blocks.length} blocks ===\n`);
  console.log(`  Using: ${MODEL_STEP3}, real production prompt, real ${macroPlan.plan_summary?.race || "triathlon"} plan`);
  console.log(`  Blocks: ${blocks.map((b, i) => `B${i + 1}(W${b[0].week_number}-W${b[b.length - 1].week_number})`).join(", ")}\n`);

  // --- Sequential ---
  console.log("--- SEQUENTIAL ---");
  const seqStart = Date.now();
  let previouslyUsed = [];
  const seqWeeks = [];

  for (let b = 0; b < blocks.length; b++) {
    const block = blocks[b];
    const prevStr =
      previouslyUsed.length > 0
        ? previouslyUsed.map((p) => `- ${p.sport} ${p.type}: last used ${p.template_id} in W${p.week}`).join("\n")
        : "None — this is the first block.";

    const t = Date.now();
    const result = await callOpenAI(buildPrompt(block, prevStr));
    console.log(`  Block ${b + 1} (W${block[0].week_number}-W${block[block.length - 1].week_number}): ${((Date.now() - t) / 1000).toFixed(1)}s`);
    seqWeeks.push(...(result.weeks || []));

    // Carry previouslyUsed forward
    const lastWeek = result.weeks?.[result.weeks.length - 1];
    if (lastWeek) {
      previouslyUsed = (lastWeek.sessions || []).map((s) => ({
        sport: s.sport,
        type: s.type,
        template_id: s.template_id,
        week: lastWeek.week_number,
      }));
    }
  }

  const seqMs = Date.now() - seqStart;
  console.log(`  Total sequential: ${(seqMs / 1000).toFixed(1)}s`);
  const seqOk = validateOutput(seqWeeks, "sequential");

  // --- Parallel ---
  console.log("\n--- PARALLEL ---");
  const parStart = Date.now();
  const blockTimes = [];

  const parResults = await Promise.all(
    blocks.map(async (block, b) => {
      const t = Date.now();
      const result = await callOpenAI(buildPrompt(block));
      blockTimes[b] = (Date.now() - t) / 1000;
      return result;
    })
  );

  // Log block times after all complete
  blocks.forEach((block, b) => {
    console.log(`  Block ${b + 1} (W${block[0].week_number}-W${block[block.length - 1].week_number}): ${blockTimes[b].toFixed(1)}s`);
  });

  const parWeeks = parResults.flatMap((r) => r.weeks || []);
  const parMs = Date.now() - parStart;
  console.log(`  Total parallel: ${(parMs / 1000).toFixed(1)}s`);
  const parOk = validateOutput(parWeeks, "parallel");

  // --- Summary ---
  console.log("\n=== SUMMARY ===");
  console.log(`  Sequential: ${(seqMs / 1000).toFixed(1)}s  ${seqOk ? "✓" : "✗ VALIDATION FAILED"}`);
  console.log(`  Parallel:   ${(parMs / 1000).toFixed(1)}s  ${parOk ? "✓" : "✗ VALIDATION FAILED"}`);
  console.log(`  Speedup:    ${(seqMs / parMs).toFixed(1)}x  (saved ${((seqMs - parMs) / 1000).toFixed(1)}s)`);
  console.log(`\n  Projected full pipeline (step1~40s + step2~40s + overhead~15s):`);
  console.log(`    Sequential: ~${Math.round(40 + 40 + seqMs / 1000 + 15)}s`);
  console.log(`    Parallel:   ~${Math.round(40 + 40 + parMs / 1000 + 15)}s`);
  console.log(`    Supabase free limit: 150s\n`);

  // Save outputs for violation checking
  const resultsDir = path.join(__dirname, "results");
  if (!fs.existsSync(resultsDir)) fs.mkdirSync(resultsDir, { recursive: true });

  const seqRecord = [{ athlete_name: "Emmanuel - Half-Ironman", limiters: testVars.limiters, constraints: testVars.constraints, macro_plan_json: testVars.macro_plan_json, output: JSON.stringify({ weeks: seqWeeks }) }];
  fs.writeFileSync(path.join(resultsDir, "test-parallel-sequential.json"), JSON.stringify(seqRecord, null, 2));

  const parRecord = [{ athlete_name: "Emmanuel - Half-Ironman", limiters: testVars.limiters, constraints: testVars.constraints, macro_plan_json: testVars.macro_plan_json, output: JSON.stringify({ weeks: parWeeks }) }];
  fs.writeFileSync(path.join(resultsDir, "test-parallel-parallel.json"), JSON.stringify(parRecord, null, 2));
}

async function runViolationCheck(allWeeks, label) {
  const outputFile = path.join(__dirname, `results/test-parallel-${label}.json`);
  const record = [{
    athlete_name: "Emmanuel - Half-Ironman",
    limiters: testVars.limiters,
    constraints: testVars.constraints,
    macro_plan_json: testVars.macro_plan_json,
    output: JSON.stringify({ weeks: allWeeks }),
  }];
  fs.writeFileSync(outputFile, JSON.stringify(record, null, 2));

  console.log(`\n  Running violation checker on ${label} output...`);
  const { execSync } = require("child_process");
  try {
    const result = execSync(`node "${path.join(__dirname, "check-step3-violations.js")}" "${outputFile}"`, {
      encoding: "utf8",
    });
    // Extract just the summary lines
    const lines = result.split("\n").filter((l) =>
      l.includes("===") || l.includes("violation") || l.includes("TOTAL") || l.includes("✓") || l.includes("✗") || l.match(/^\s+(Duration|Sport|Rest|Brick|Cluster|SameDay|Intensity|BrickOrder)/)
    );
    console.log(lines.join("\n"));
  } catch (e) {
    console.log(e.stdout || e.message);
  }
}

async function mainWithQA() {
  await main();

  // Re-run to save outputs for violation checking
  // (reuse saved outputs from main() run)
  console.log("\n=== QUALITY CHECK (violation checker) ===");

  const seqFile = path.join(__dirname, "results/test-parallel-sequential.json");
  const parFile = path.join(__dirname, "results/test-parallel-parallel.json");

  if (fs.existsSync(seqFile)) {
    const seqData = JSON.parse(fs.readFileSync(seqFile));
    console.log("\n--- Sequential ---");
    const { execSync } = require("child_process");
    try {
      console.log(execSync(`node "${path.join(__dirname, "check-step3-violations.js")}" "${seqFile}"`, { encoding: "utf8" }));
    } catch (e) { console.log(e.stdout || e.message); }
  }
  if (fs.existsSync(parFile)) {
    console.log("\n--- Parallel ---");
    const { execSync } = require("child_process");
    try {
      console.log(execSync(`node "${path.join(__dirname, "check-step3-violations.js")}" "${parFile}"`, { encoding: "utf8" }));
    } catch (e) { console.log(e.stdout || e.message); }
  }
}

mainWithQA().catch(console.error);
