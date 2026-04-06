#!/usr/bin/env node
/**
 * generate-for-user.js
 * Runs the full plan generation pipeline locally for a specific user
 * and saves the result as a JSON file ready for DB insertion.
 *
 * Usage: node ai/eval/generate-for-user.js
 * Output: ai/eval/results/generated-plan-<userId>.json
 */

require("dotenv").config({ path: require("path").join(__dirname, "../../.env") });
const fs = require("fs");
const path = require("path");
const OpenAI = require("openai").default || require("openai");

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

// ── Constants (match production) ───────────────────────────────────────────────
const MODEL_STEP1 = "gpt-4.1";
const MODEL_STEP2 = "gpt-4o-mini";
const MODEL_STEP3 = "gpt-4.1";
const TEMPERATURE = 0.2;
const MAX_TOKENS_STEP1 = 16384;
const MAX_TOKENS_STEP2 = 16384;
const MAX_TOKENS_STEP3 = 4096;
const BLOCK_SIZE = 4;

// ── User profile (apple@gmail.com) ─────────────────────────────────────────────
const USER_ID = "72342429-6a18-432b-9370-4be4de0a83e9";
const userProfile = {
  id: USER_ID,
  race_objective: "Ironman 70.3",
  race_date: "2026-07-31T14:13:00+00:00",
  vma: 18.0,
  ftp: 200,
  experience_years: 2,
  current_weekly_hours: 10.5,
  css_seconds_per100m: 120,
  swim_days: ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"],
  bike_days: ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"],
  run_days:  ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"],
  mon_duration: 60,
  tue_duration: 60,
  wed_duration: 60,
  thu_duration: 60,
  fri_duration: 240,
  sat_duration: 240,
  sun_duration: 60,
  limiters: null,
  onboarding_completed: true,
};

// ── Load assets ────────────────────────────────────────────────────────────────
const STEP1_PROMPT_TEMPLATE = fs.readFileSync(path.join(__dirname, "../prompts/step1-macro-plan.txt"), "utf8");
const STEP2_PROMPT_TEMPLATE = fs.readFileSync(path.join(__dirname, "../prompts/step2-md-to-json.txt"), "utf8");
const STEP3_PROMPT_TEMPLATE = fs.readFileSync(path.join(__dirname, "../prompts/step3-workout-block.txt"), "utf8");
const TRAINING_PHILOSOPHY   = fs.readFileSync(path.join(__dirname, "../context/training-philosophy.md"), "utf8");
const workoutLibrary        = JSON.parse(fs.readFileSync(path.join(__dirname, "../context/workout-library.json"), "utf8"));

// ── Helpers (mirror production) ────────────────────────────────────────────────
function formatDate(date) { return date.toISOString().split("T")[0]; }
function daysBetween(d1, d2) { return Math.ceil((d2 - d1) / 86400000); }
function addDays(date, days) { const d = new Date(date); d.setDate(d.getDate() + days); return d; }

function mapExperienceLevel(years) {
  if (!years) return "beginner";
  if (years <= 1) return "beginner";
  if (years <= 4) return "intermediate";
  return "experienced";
}

function expandRaceObjective(obj) {
  const map = {
    Sprint: "Sprint (750m swim / 20km bike / 5km run)",
    Olympic: "Olympic (1.5km swim / 40km bike / 10km run)",
    "Ironman 70.3": "Half-Ironman (1.9km swim / 90km bike / 21.1km run)",
    Ironman: "Ironman (3.8km swim / 180km bike / 42.2km run)",
  };
  return map[obj] || obj;
}

function formatCSS(secs) {
  if (!secs) return "not provided";
  return `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, "0")}`;
}

function calculateWeeklyHours(u) {
  const total = [u.mon_duration,u.tue_duration,u.wed_duration,u.thu_duration,u.fri_duration,u.sat_duration,u.sun_duration]
    .reduce((s, d) => s + (d || 0), 0);
  return Math.round((total / 60) * 10) / 10;
}

function calculateSessionDurationCaps(u) {
  const weekday = [u.mon_duration,u.tue_duration,u.wed_duration,u.thu_duration,u.fri_duration].filter(Boolean);
  const weekend = [u.sat_duration,u.sun_duration].filter(Boolean);
  return {
    maxWeekday: weekday.length ? Math.min(...weekday) : 60,
    maxWeekend: weekend.length ? Math.max(...weekend) : 240,
  };
}

function buildConstraintString(u) {
  const dayNames = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"];
  const durFields = ["mon_duration","tue_duration","wed_duration","thu_duration","fri_duration","sat_duration","sun_duration"];
  const swimDays = new Set(u.swim_days || []);
  const bikeDays = new Set(u.bike_days || []);
  const runDays  = new Set(u.run_days  || []);
  return dayNames.map((day, i) => {
    const dur = u[durFields[i]];
    if (!dur) return `${day}: REST`;
    const eligible = [];
    if (swimDays.has(day)) eligible.push("swim");
    if (bikeDays.has(day)) eligible.push("bike");
    if (runDays.has(day))  eligible.push("run");
    if (eligible.length === 3) return `${day}: ${dur}min available (all sports)`;
    if (eligible.length === 0) return `${day}: ${dur}min available (no sports eligible)`;
    return `${day}: ${dur}min available (${eligible.join(", ")} only)`;
  }).join("\n");
}

function buildStep1Prompt(u, vars) {
  const caps = calculateSessionDurationCaps(u);
  const weekdays = ["Monday","Tuesday","Wednesday","Thursday","Friday"];
  const weekend  = ["Saturday","Sunday"];
  const swimDays = new Set(u.swim_days || []);
  const bikeDays = new Set(u.bike_days || []);
  const runDays  = new Set(u.run_days  || []);
  return STEP1_PROMPT_TEMPLATE
    .replace("{{training_philosophy}}", TRAINING_PHILOSOPHY)
    .replace("{{experience_level}}", mapExperienceLevel(u.experience_years))
    .replace("{{race_distance}}", expandRaceObjective(u.race_objective))
    .replace("{{race_date}}", vars.raceDate)
    .replace("{{plan_start_date}}", vars.planStartDate)
    .replace("{{total_weeks}}", vars.totalWeeks.toString())
    .replace("{{weekly_hours}}", vars.weeklyHours.toString())
    .replace("{{ftp_watts}}", u.ftp ? u.ftp.toString() : "not provided")
    .replace("{{mas_kmh}}", u.vma ? u.vma.toString() : "not provided")
    .replace("{{swim_css}}", formatCSS(u.css_seconds_per100m))
    .replace("{{limiters}}", (u.limiters || "none").toString().replace(/[\n\r]/g, " ").slice(0, 200))
    .replace("{{current_weekly_hours}}", u.current_weekly_hours != null ? u.current_weekly_hours.toString() : "not provided")
    .replace("{{max_weekday_minutes}}", caps.maxWeekday.toString())
    .replace("{{max_weekend_minutes}}", caps.maxWeekend.toString())
    .replace("{{swim_weekday_count}}", weekdays.filter(d => swimDays.has(d)).length.toString())
    .replace("{{swim_weekend_count}}", weekend.filter(d => swimDays.has(d)).length.toString())
    .replace("{{bike_weekday_count}}", weekdays.filter(d => bikeDays.has(d)).length.toString())
    .replace("{{bike_weekend_count}}", weekend.filter(d => bikeDays.has(d)).length.toString())
    .replace("{{run_weekday_count}}", weekdays.filter(d => runDays.has(d)).length.toString())
    .replace("{{run_weekend_count}}", weekend.filter(d => runDays.has(d)).length.toString());
}

function buildSimplifiedLibrary(lib) {
  const lines = [];
  for (const sport of ["swim","bike","run"]) {
    for (const tmpl of lib[sport] || []) {
      lines.push(`${tmpl.template_id} | ${sport} | ${tmpl.type || tmpl.template_id.split("_")[1]} | ${tmpl.duration_minutes}min`);
    }
  }
  return "template_id | sport | type | duration\n" + lines.join("\n");
}

function buildTemplateDurationMap(lib) {
  const map = {};
  for (const sport of ["swim","bike","run"])
    for (const t of lib[sport] || []) map[t.template_id] = t.duration_minutes;
  return map;
}

// ── Day normalization ──────────────────────────────────────────────────────────
const DAY_NORM = {
  mon:"Monday",monday:"Monday",tue:"Tuesday",tues:"Tuesday",tuesday:"Tuesday",
  wed:"Wednesday",wednesday:"Wednesday",thu:"Thursday",thur:"Thursday",thurs:"Thursday",thursday:"Thursday",
  fri:"Friday",friday:"Friday",sat:"Saturday",saturday:"Saturday",sun:"Sunday",sunday:"Sunday"
};
const ALL_DAYS = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"];
function normDay(d) { return DAY_NORM[(d||"").toLowerCase()] || d; }

// ── parseConstraints (for fixers) ─────────────────────────────────────────────
function parseConstraints(u) {
  const dayNames = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"];
  const durFields = ["mon_duration","tue_duration","wed_duration","thu_duration","fri_duration","sat_duration","sun_duration"];
  const swimDays = new Set(u.swim_days || []);
  const bikeDays = new Set(u.bike_days || []);
  const runDays  = new Set(u.run_days  || []);
  const dayCaps = {}, sportEligibility = {};
  for (let i = 0; i < dayNames.length; i++) {
    const day = dayNames[i];
    dayCaps[day] = u[durFields[i]] || 0;
    const e = [];
    if (swimDays.has(day)) e.push("swim");
    if (bikeDays.has(day)) e.push("bike");
    if (runDays.has(day))  e.push("run");
    sportEligibility[day] = e;
  }
  return { dayCaps, sportEligibility };
}

// ── OpenAI call ────────────────────────────────────────────────────────────────
async function callOpenAI(model, prompt, temperature, maxTokens, responseFormat) {
  const params = {
    model, messages: [{ role: "user", content: prompt }],
    temperature, max_tokens: maxTokens,
  };
  if (responseFormat) params.response_format = responseFormat;
  const res = await openai.chat.completions.create(params);
  return res.choices[0].message.content;
}

// ── Fixers (ported from run-step3-blocks.js) ───────────────────────────────────
function sessionPriority(s) {
  return ({ Intervals:3, Tempo:2, Easy:1 }[s.type] || 1) + (s.is_brick ? 0.5 : 0);
}

function fixTypes(weeks) {
  for (const w of weeks)
    for (const s of w.sessions || []) {
      s.day = normDay(s.day);
      if (s.type && !["Easy","Tempo","Intervals"].includes(s.type)) {
        const t = s.type.toLowerCase();
        if (t.includes("interval") || t.includes("interval")) s.type = "Intervals";
        else if (t.includes("tempo") || t.includes("threshold")) s.type = "Tempo";
        else s.type = "Easy";
      }
    }
}

function fixBrickPairs(weeks) {
  for (const w of weeks) {
    const sessions = w.sessions || [];
    const byDay = {};
    for (const s of sessions) {
      const d = normDay(s.day);
      if (!byDay[d]) byDay[d] = [];
      byDay[d].push(s);
    }
    for (const [day, daySessions] of Object.entries(byDay)) {
      const hasBike = daySessions.find(s => s.sport === "bike");
      const hasRun  = daySessions.find(s => s.sport === "run");
      if (hasBike && hasRun) {
        hasBike.is_brick = true;
        hasRun.is_brick = true;
      }
    }
  }
}

function fixConsecutiveRepeats(weeks, lib, templateDurationMap) {
  const ALL_TEMPLATES = {};
  for (const sport of ["swim","bike","run"])
    for (const t of lib[sport] || []) {
      if (!ALL_TEMPLATES[sport]) ALL_TEMPLATES[sport] = [];
      ALL_TEMPLATES[sport].push(t);
    }

  const EXEMPT_TYPES = ["Easy"];
  const windowSize = 3;

  for (const w of weeks) {
    for (const s of w.sessions || []) {
      if (!s.template_id || EXEMPT_TYPES.includes(s.type)) continue;
      // Check if this template was used in the last windowSize sessions of same sport/type
    }
  }

  // Simple consecutive-repeat check across weeks
  const lastUsed = {};
  for (const w of weeks) {
    for (const s of w.sessions || []) {
      if (!s.template_id || EXEMPT_TYPES.includes(s.type)) continue;
      const key = `${s.sport}_${s.type}`;
      if (lastUsed[key] === s.template_id) {
        // Find a different template of same sport/type
        const candidates = (ALL_TEMPLATES[s.sport] || []).filter(t => {
          if (t.template_id === s.template_id) return false;
          const tType = t.type || t.template_id.split("_")[1];
          if (tType && tType.toLowerCase() !== s.type.toLowerCase()) return false;
          const dur = templateDurationMap[t.template_id];
          const target = s.duration_minutes;
          return !target || !dur || Math.abs(dur - target) / target <= 0.2;
        });
        if (candidates.length > 0) {
          s.template_id = candidates[0].template_id;
          s.duration_minutes = templateDurationMap[candidates[0].template_id] || s.duration_minutes;
        }
      }
      lastUsed[key] = s.template_id;
    }
  }
}

function fixDurationCaps(weeks, lib, templateDurationMap, dayCaps, sportEligibility) {
  const ALL_TEMPLATES = {};
  for (const sport of ["swim","bike","run"])
    for (const t of lib[sport] || []) {
      if (!ALL_TEMPLATES[sport]) ALL_TEMPLATES[sport] = {};
      if (!ALL_TEMPLATES[sport][t.type || "Easy"]) ALL_TEMPLATES[sport][t.type || "Easy"] = [];
      ALL_TEMPLATES[sport][t.type || "Easy"].push(t);
    }

  const WEEKEND = new Set(["Saturday","Sunday"]);

  for (const w of weeks) {
    for (const s of w.sessions || []) {
      const day = normDay(s.day);
      const cap = dayCaps[day];
      if (!cap || !s.duration_minutes) continue;
      const capWithBuffer = cap * 1.1;
      if (s.duration_minutes <= capWithBuffer) continue;

      // Try to find a shorter template of same sport/type
      const type = s.type || "Easy";
      const candidates = ((ALL_TEMPLATES[s.sport] || {})[type] || [])
        .filter(t => (templateDurationMap[t.template_id] || 999) <= capWithBuffer)
        .sort((a, b) => (templateDurationMap[b.template_id] || 0) - (templateDurationMap[a.template_id] || 0));

      if (candidates.length > 0) {
        s.template_id = candidates[0].template_id;
        s.duration_minutes = templateDurationMap[candidates[0].template_id] || s.duration_minutes;
      } else {
        s.duration_minutes = cap;
      }
    }
  }
}

function fixRestDays(weeks, macroPlan, dayCaps, sportEligibility) {
  // Remove sessions from days that are REST (cap = 0) or sport-ineligible
  for (const w of weeks) {
    w.sessions = (w.sessions || []).filter(s => {
      const day = normDay(s.day);
      if (!dayCaps[day]) return false;
      if (!(sportEligibility[day] || []).includes(s.sport)) return false;
      return true;
    });
  }
}

function fixMissingBricks(weeks, lib, dayCaps, sportEligibility) {
  // Ensure Build/Peak/even-Base weeks have at least one brick session
  for (const w of weeks) {
    const phase = w.phase;
    const wNum = w.week_number;
    const needsBrick = phase === "Build" || phase === "Peak" || (phase === "Base" && wNum % 2 === 0);
    if (!needsBrick) continue;

    const sessions = w.sessions || [];
    const hasBrick = sessions.some(s => s.is_brick);
    if (hasBrick) continue;

    // Find a day with both bike and run eligible
    const candidateDays = ALL_DAYS.filter(day => {
      const cap = dayCaps[day] || 0;
      const elig = sportEligibility[day] || [];
      return cap >= 60 && elig.includes("bike") && elig.includes("run");
    });
    if (candidateDays.length === 0) continue;

    // Pick the day with the highest cap
    const brickDay = candidateDays.sort((a,b) => (dayCaps[b]||0) - (dayCaps[a]||0))[0];

    // Remove existing sessions on that day
    w.sessions = sessions.filter(s => normDay(s.day) !== brickDay);

    // Add bike + run brick
    const bikeTemplate = (lib.bike || []).find(t => t.type === "Easy" || t.template_id.includes("easy")) || lib.bike?.[0];
    const runTemplate  = (lib.run  || []).find(t => t.type === "Easy" || t.template_id.includes("easy")) || lib.run?.[0];

    if (bikeTemplate) w.sessions.push({ day: brickDay, sport: "bike", type: "Easy", template_id: bikeTemplate.template_id, duration_minutes: bikeTemplate.duration_minutes, is_brick: true });
    if (runTemplate)  w.sessions.push({ day: brickDay, sport: "run",  type: "Easy", template_id: runTemplate.template_id,  duration_minutes: Math.min(30, runTemplate.duration_minutes), is_brick: true });
  }
}

function fixBrickRunDuration(weeks, lib) {
  const MAX_BRICK_RUN = 45;
  for (const w of weeks)
    for (const s of w.sessions || [])
      if (s.is_brick && s.sport === "run" && s.duration_minutes > MAX_BRICK_RUN) {
        const t = (lib.run || []).find(t => t.duration_minutes <= MAX_BRICK_RUN && t.type === "Easy") || lib.run?.[0];
        if (t) { s.template_id = t.template_id; s.duration_minutes = t.duration_minutes; }
      }
}

function fixBrickOrder(weeks) {
  for (const w of weeks) {
    const byDay = {};
    for (const s of w.sessions || []) {
      const d = normDay(s.day);
      if (!byDay[d]) byDay[d] = [];
      byDay[d].push(s);
    }
    for (const sessions of Object.values(byDay)) {
      const brickBike = sessions.find(s => s.is_brick && s.sport === "bike");
      const brickRun  = sessions.find(s => s.is_brick && s.sport === "run");
      if (brickBike && brickRun) {
        brickBike.order_in_day = 0;
        brickRun.order_in_day  = 1;
      }
    }
  }
}

function fixSameDayHardConflicts(weeks, dayCaps, sportEligibility, lib) {
  for (const w of weeks) {
    const byDay = {};
    for (const s of w.sessions || []) {
      const d = normDay(s.day);
      if (!byDay[d]) byDay[d] = [];
      byDay[d].push(s);
    }
    for (const [day, sessions] of Object.entries(byDay)) {
      const hardNonSwim = sessions.filter(s => ["Tempo","Intervals"].includes(s.type) && s.sport !== "swim");
      if (hardNonSwim.length >= 2) {
        // Demote the lower-priority one to Easy
        hardNonSwim.sort((a,b) => sessionPriority(a) - sessionPriority(b));
        const toFix = hardNonSwim[0];
        const easyTemplate = (lib[toFix.sport] || []).find(t => (t.type || "") === "Easy") || lib[toFix.sport]?.[0];
        if (easyTemplate) {
          toFix.type = "Easy";
          toFix.template_id = easyTemplate.template_id;
          toFix.duration_minutes = easyTemplate.duration_minutes;
        }
      }
    }
  }
}

function fixIntensitySpread(weeks, dayCaps, sportEligibility) {
  // Simple: ensure no same-sport hard sessions on back-to-back days
  for (const w of weeks) {
    const byDay = {};
    for (const s of w.sessions || []) {
      const d = normDay(s.day);
      if (!byDay[d]) byDay[d] = [];
      byDay[d].push(s);
    }
    // Check each day pair
    for (let i = 0; i < ALL_DAYS.length - 1; i++) {
      const d1 = ALL_DAYS[i], d2 = ALL_DAYS[i+1];
      const s1 = (byDay[d1] || []).filter(s => ["Tempo","Intervals"].includes(s.type) && s.sport !== "swim");
      const s2 = (byDay[d2] || []).filter(s => ["Tempo","Intervals"].includes(s.type) && s.sport !== "swim");
      const sameSport = s1.some(a => s2.some(b => a.sport === b.sport));
      if (sameSport) {
        // Demote one in day2
        const toFix = s2.sort((a,b) => sessionPriority(a) - sessionPriority(b))[0];
        if (toFix) toFix.type = "Easy";
      }
    }
  }
}

function fixSportClustering(weeks, dayCaps, sportEligibility, weeklyHours) {
  if (weeklyHours >= 8) return; // High volume: clustering is expected
  // Simple: no more than 2 consecutive same-sport days
  for (const w of weeks) {
    const byDay = {};
    for (const s of w.sessions || []) {
      const d = normDay(s.day);
      if (!byDay[d]) byDay[d] = [];
      byDay[d].push(s);
    }
    for (let i = 0; i < ALL_DAYS.length - 2; i++) {
      const d1 = ALL_DAYS[i], d2 = ALL_DAYS[i+1], d3 = ALL_DAYS[i+2];
      for (const sport of ["swim","bike","run"]) {
        const c1 = (byDay[d1]||[]).filter(s=>s.sport===sport).length;
        const c2 = (byDay[d2]||[]).filter(s=>s.sport===sport).length;
        const c3 = (byDay[d3]||[]).filter(s=>s.sport===sport).length;
        if (c1 > 0 && c2 > 0 && c3 > 0) {
          // Remove the session on day 3
          byDay[d3] = (byDay[d3]||[]).filter(s=>s.sport!==sport);
          w.sessions = w.sessions.filter(s => !(normDay(s.day)===d3 && s.sport===sport));
        }
      }
    }
  }
}

function fixVolumeGaps(weeks, macroPlan, dayCaps, sportEligibility, lib) {
  // Fill empty available days in non-Recovery/Taper weeks
  for (let wi = 0; wi < weeks.length; wi++) {
    const w = weeks[wi];
    if (w.phase === "Recovery" || w.phase === "Taper") continue;

    const usedDays = new Set((w.sessions||[]).map(s=>normDay(s.day)));
    for (const day of ALL_DAYS) {
      if (usedDays.has(day)) continue;
      if (!dayCaps[day]) continue;
      const eligible = (sportEligibility[day]||[]).filter(s=>s!=="swim");
      if (eligible.length === 0) continue;

      // Alternate sport based on neighbor days
      const sport = eligible[wi % eligible.length];
      const template = (lib[sport]||[]).find(t=>(t.type||"")==="Easy") || lib[sport]?.[0];
      if (!template) continue;
      (w.sessions = w.sessions || []).push({
        day, sport, type:"Easy",
        template_id: template.template_id,
        duration_minutes: Math.min(template.duration_minutes, dayCaps[day]),
        is_brick: false,
      });
    }
  }
}

// ── Main pipeline ──────────────────────────────────────────────────────────────
async function main() {
  const planStartDate = new Date(Date.now() + 86400000); // tomorrow
  const raceDate = new Date(userProfile.race_date);
  const totalWeeks = Math.ceil(daysBetween(planStartDate, raceDate) / 7);
  const weeklyHours = calculateWeeklyHours(userProfile);

  const vars = {
    raceDate: formatDate(raceDate),
    planStartDate: formatDate(planStartDate),
    totalWeeks,
    weeklyHours,
  };

  console.log(`\n=== Generating plan for apple@gmail.com ===`);
  console.log(`  Race: ${userProfile.race_objective} on ${vars.raceDate}`);
  console.log(`  Plan: ${vars.totalWeeks} weeks starting ${vars.planStartDate}`);
  console.log(`  Volume: ${weeklyHours}h/week\n`);

  // Step 1
  let t = Date.now();
  process.stdout.write("  Step 1 (macro plan, gpt-4.1)... ");
  const step1Output = await callOpenAI(MODEL_STEP1, buildStep1Prompt(userProfile, vars), TEMPERATURE, MAX_TOKENS_STEP1);
  console.log(`${((Date.now()-t)/1000).toFixed(1)}s`);

  // Step 2
  t = Date.now();
  process.stdout.write("  Step 2 (JSON parse, gpt-4o-mini)... ");
  const step2Prompt = STEP2_PROMPT_TEMPLATE.replace("{{step1_output}}", step1Output);
  const step2Raw = await callOpenAI(MODEL_STEP2, step2Prompt, 0, MAX_TOKENS_STEP2, { type: "json_object" });
  const macroPlan = JSON.parse(step2Raw.replace(/```json\n?/g,"").replace(/```\n?/g,"").trim());
  console.log(`${((Date.now()-t)/1000).toFixed(1)}s`);

  if (!macroPlan.weeks?.length) throw new Error("Step 2 returned no weeks");
  const weeks = macroPlan.weeks;
  console.log(`  → ${weeks.length} weeks parsed`);

  // Step 3 (parallel blocks)
  t = Date.now();
  process.stdout.write("  Step 3 (workout assignment, parallel blocks)... ");
  const simplifiedLibrary = buildSimplifiedLibrary(workoutLibrary);
  const constraintString = buildConstraintString(userProfile);
  const limiters = (userProfile.limiters || "none").toString().replace(/[\n\r]/g," ").slice(0,200);

  const blocks = [];
  for (let j = 0; j < weeks.length; j += BLOCK_SIZE) blocks.push(weeks.slice(j, j+BLOCK_SIZE));

  const blockResults = await Promise.all(blocks.map(async (block) => {
    const prompt = STEP3_PROMPT_TEMPLATE
      .replace("{{workout_library}}", simplifiedLibrary)
      .replace("{{block_weeks_json}}", JSON.stringify(block, null, 2))
      .replace("{{limiters}}", limiters)
      .replace("{{constraints}}", constraintString)
      .replace("{{previously_used}}", "None — blocks processed in parallel.");
    const raw = await callOpenAI(MODEL_STEP3, prompt, TEMPERATURE, MAX_TOKENS_STEP3, { type: "json_object" });
    return JSON.parse(raw.replace(/```json\n?/g,"").replace(/```\n?/g,"").trim());
  }));

  const allWeeks = blockResults.flatMap(r => r.weeks || []);
  console.log(`${((Date.now()-t)/1000).toFixed(1)}s`);

  // Validate
  const missing = allWeeks.filter(w => !(w.sessions||[]).every(s=>s.template_id));
  if (missing.length) console.warn(`  ⚠ ${missing.length} sessions missing template_id`);

  // Post-processing fixers
  process.stdout.write("  Post-processing fixers... ");
  const templateDurationMap = buildTemplateDurationMap(workoutLibrary);
  const { dayCaps, sportEligibility } = parseConstraints(userProfile);

  fixTypes(allWeeks);
  fixBrickPairs(allWeeks);
  fixConsecutiveRepeats(allWeeks, workoutLibrary, templateDurationMap);
  fixDurationCaps(allWeeks, workoutLibrary, templateDurationMap, dayCaps, sportEligibility);
  fixRestDays(allWeeks, weeks, dayCaps, sportEligibility);
  fixMissingBricks(allWeeks, workoutLibrary, dayCaps, sportEligibility);
  fixBrickRunDuration(allWeeks, workoutLibrary);
  fixBrickOrder(allWeeks);
  fixSameDayHardConflicts(allWeeks, dayCaps, sportEligibility, workoutLibrary);
  fixIntensitySpread(allWeeks, dayCaps, sportEligibility);
  fixSportClustering(allWeeks, dayCaps, sportEligibility, weeklyHours);
  fixVolumeGaps(allWeeks, weeks, dayCaps, sportEligibility, workoutLibrary);
  fixDurationCaps(allWeeks, workoutLibrary, templateDurationMap, dayCaps, sportEligibility);
  fixSameDayHardConflicts(allWeeks, dayCaps, sportEligibility, workoutLibrary);
  fixBrickOrder(allWeeks);
  console.log("done");

  // Build output for DB insertion
  allWeeks.sort((a,b) => a.week_number - b.week_number);
  const planData = {
    userId: USER_ID,
    raceDate: vars.raceDate,
    raceObjective: userProfile.race_objective,
    totalWeeks,
    startDate: vars.planStartDate,
    weeks: allWeeks.map(w => {
      const scheduledDays = new Set((w.sessions||[]).map(s=>normDay(s.day)));
      const restDays = ALL_DAYS.filter(d => !scheduledDays.has(d));
      const weekStartDate = addDays(planStartDate, (w.week_number - 1) * 7);
      const macroWeek = weeks.find(mw => mw.week_number === w.week_number);
      return {
        weekNumber: w.week_number,
        phase: w.phase,
        isRecovery: w.phase === "Recovery",
        restDays,
        notes: macroWeek?.notes || null,
        startDate: formatDate(weekStartDate),
        sessions: (w.sessions||[]).map((s, idx) => ({
          day: normDay(s.day),
          sport: s.sport,
          type: s.type,
          templateId: s.template_id,
          durationMinutes: s.duration_minutes,
          isBrick: s.is_brick || false,
          orderInDay: s.order_in_day != null ? s.order_in_day : idx,
        })),
      };
    }),
  };

  // Summary
  const totalSessions = planData.weeks.reduce((s,w) => s + w.sessions.length, 0);
  console.log(`\n  ✓ ${planData.weeks.length} weeks, ${totalSessions} sessions`);
  console.log(`  ✓ Phases: ${[...new Set(planData.weeks.map(w=>w.phase))].join(" → ")}\n`);

  // Save
  const outPath = path.join(__dirname, `results/generated-plan-${USER_ID}.json`);
  fs.writeFileSync(outPath, JSON.stringify(planData, null, 2));
  console.log(`  Saved to ${outPath}\n`);
  return planData;
}

main().catch(err => { console.error(err); process.exit(1); });
