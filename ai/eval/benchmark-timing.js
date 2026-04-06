#!/usr/bin/env node
/**
 * benchmark-timing.js
 * Measures actual OpenAI call latency for each step of generate-plan.
 * Run: node ai/eval/benchmark-timing.js
 */

require("dotenv").config({ path: require("path").join(__dirname, "../../.env") });
const OpenAI = require("openai").default || require("openai");
const fs = require("fs");
const path = require("path");

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

const MODEL_STEP1 = "gpt-4.1";
const MODEL_STEP2 = "gpt-4o-mini";
const MODEL_STEP3 = "gpt-4.1";
const TEMPERATURE = 0.7;

// ---------------------------------------------------------------------------
// Minimal realistic user profile (triathlete, ~16-week plan)
// ---------------------------------------------------------------------------
const USER_PROFILE = {
  race_objective: "olympic",
  race_date: "2026-09-15",
  vma: 14.5,
  css_seconds_per100m: 105,
  ftp: 220,
  experience: "intermediate",
  current_weekly_hours: 8,
  swim_days: ["Tuesday", "Thursday"],
  bike_days: ["Monday", "Wednesday", "Saturday"],
  run_days: ["Tuesday", "Thursday", "Sunday"],
  mon_duration: 90, tue_duration: 75, wed_duration: 90,
  thu_duration: 75, fri_duration: 0, sat_duration: 120, sun_duration: 90,
};

async function callOpenAI(model, prompt, temperature, maxTokens, responseFormat) {
  const params = {
    model,
    messages: [{ role: "user", content: prompt }],
    temperature,
    max_tokens: maxTokens,
  };
  if (responseFormat) params.response_format = responseFormat;
  const res = await openai.chat.completions.create(params);
  return res.choices[0].message.content;
}

function timer(label) {
  const start = Date.now();
  return () => {
    const ms = Date.now() - start;
    console.log(`  ✓ ${label}: ${(ms / 1000).toFixed(1)}s`);
    return ms;
  };
}

// ---------------------------------------------------------------------------
// Minimal prompts (same structure as production, abbreviated for benchmark)
// ---------------------------------------------------------------------------
function buildStep1Prompt(profile) {
  return `You are a triathlon coach. Create a ${16}-week periodized training plan for an athlete with:
- Race: ${profile.race_objective} triathlon on ${profile.race_date}
- FTP: ${profile.ftp}W, VMA: ${profile.vma} km/h, CSS: ${Math.floor(profile.css_seconds_per100m / 60)}:${String(profile.css_seconds_per100m % 60).padStart(2, "0")}/100m
- Experience: ${profile.experience}, current weekly hours: ${profile.current_weekly_hours}h
- Available days: Mon/Wed/Sat bike, Tue/Thu swim+run, Sun run

Return a detailed markdown plan with 16 weeks, grouped by phase (Base, Build, Peak, Taper).
For each week specify: phase, total hours, sessions per sport, key workouts.`;
}

function buildStep2Prompt(step1Output) {
  return `Convert the following triathlon training plan from markdown to JSON.

Return ONLY valid JSON with this structure:
{
  "weeks": [
    {
      "week_number": 1,
      "phase": "Base",
      "is_recovery": false,
      "total_hours": 8,
      "sessions": [
        { "day": "Monday", "sport": "bike", "type": "Easy", "duration_minutes": 90 }
      ]
    }
  ]
}

PLAN:
${step1Output.slice(0, 3000)}`;
}

function buildStep3BlockPrompt(block, blockIndex) {
  return `You are assigning workouts to a triathlon training block.

Block ${blockIndex + 1} contains ${block.length} week(s) with these sessions:
${JSON.stringify(block, null, 2).slice(0, 2000)}

For each session, assign a template_id from this simplified library:
- run_easy_01, run_easy_02, run_tempo_01, run_intervals_01, run_long_01
- bike_easy_01, bike_easy_02, bike_tempo_01, bike_intervals_01, bike_long_01
- swim_easy_01, swim_technique_01, swim_endurance_01, swim_intervals_01

Previously used: None

Return JSON: { "weeks": [ { "week_number": N, "sessions": [ { ...session, "template_id": "..." } ] } ] }`;
}

// ---------------------------------------------------------------------------
// Main benchmark
// ---------------------------------------------------------------------------
async function main() {
  console.log("\n=== generate-plan timing benchmark ===\n");

  // Step 1
  let t = timer("Step 1 (gpt-4.1, macro plan)");
  const step1Out = await callOpenAI(MODEL_STEP1, buildStep1Prompt(USER_PROFILE), TEMPERATURE, 16384);
  const step1Ms = t();

  // Step 2
  t = timer("Step 2 (gpt-4o-mini, JSON parse)");
  const step2Out = await callOpenAI(MODEL_STEP2, buildStep2Prompt(step1Out), 0, 16384, { type: "json_object" });
  const step2Ms = t();

  let macroPlan;
  try {
    macroPlan = JSON.parse(step2Out);
  } catch {
    console.log("  ⚠ Step 2 JSON parse failed — using dummy 16-week plan for step 3 timing");
    macroPlan = { weeks: Array.from({ length: 16 }, (_, i) => ({ week_number: i + 1, phase: "Base", sessions: [] })) };
  }

  const weeks = macroPlan.weeks || [];
  const BLOCK_SIZE = 4;
  const blocks = [];
  for (let j = 0; j < weeks.length; j += BLOCK_SIZE) blocks.push(weeks.slice(j, j + BLOCK_SIZE));
  console.log(`\n  Plan has ${weeks.length} weeks → ${blocks.length} blocks of ${BLOCK_SIZE}`);

  // Step 3 — Sequential
  console.log("\n--- Step 3 SEQUENTIAL ---");
  t = timer(`Step 3 sequential (${blocks.length} blocks)`);
  for (let b = 0; b < blocks.length; b++) {
    const bt = timer(`  Block ${b + 1}`);
    await callOpenAI(MODEL_STEP3, buildStep3BlockPrompt(blocks[b], b), TEMPERATURE, 4096, { type: "json_object" });
    bt();
  }
  const step3SeqMs = t();

  // Step 3 — Parallel
  console.log("\n--- Step 3 PARALLEL ---");
  t = timer(`Step 3 parallel (${blocks.length} blocks)`);
  await Promise.all(
    blocks.map((block, b) =>
      callOpenAI(MODEL_STEP3, buildStep3BlockPrompt(block, b), TEMPERATURE, 4096, { type: "json_object" })
    )
  );
  const step3ParMs = t();

  // Summary
  const totalSeq = step1Ms + step2Ms + step3SeqMs;
  const totalPar = step1Ms + step2Ms + step3ParMs;
  console.log("\n=== SUMMARY ===");
  console.log(`  Step 1:              ${(step1Ms / 1000).toFixed(1)}s`);
  console.log(`  Step 2:              ${(step2Ms / 1000).toFixed(1)}s`);
  console.log(`  Step 3 sequential:   ${(step3SeqMs / 1000).toFixed(1)}s`);
  console.log(`  Step 3 parallel:     ${(step3ParMs / 1000).toFixed(1)}s`);
  console.log(`  ─────────────────────────`);
  console.log(`  Total (sequential):  ${(totalSeq / 1000).toFixed(1)}s`);
  console.log(`  Total (parallel):    ${(totalPar / 1000).toFixed(1)}s`);
  console.log(`  Supabase free limit: 150s`);
  console.log(`  Headroom (parallel): ${(150 - totalPar / 1000).toFixed(1)}s\n`);
}

main().catch(console.error);
