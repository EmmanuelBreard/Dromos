/**
 * Local test script for Step 1 (macro plan) using gpt-5.4 + account token.
 * Usage: node scripts/test-plan-step1.mjs
 *
 * Requires OPENAI_ACCOUNT_TOKEN in .env
 */

import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import OpenAI from "openai";

// Load .env manually
const envPath = join(dirname(fileURLToPath(import.meta.url)), "../.env");
const envVars = readFileSync(envPath, "utf8")
  .split("\n")
  .filter((l) => l.includes("=") && !l.startsWith("#"))
  .reduce((acc, l) => {
    const [key, ...rest] = l.split("=");
    acc[key.trim()] = rest.join("=").trim().replace(/^"|"$/g, "");
    return acc;
  }, {});

const accountToken = envVars["OPENAI_ACCOUNT_TOKEN"];
const apiKey = envVars["OPENAI_API_KEY"];

if (!accountToken && !apiKey) {
  console.error("No OPENAI_ACCOUNT_TOKEN or OPENAI_API_KEY in .env");
  process.exit(1);
}

const client = accountToken
  ? new OpenAI({ apiKey: "placeholder", defaultHeaders: { Authorization: `Bearer ${accountToken}` } })
  : new OpenAI({ apiKey });

const model = accountToken ? "chatgpt-4o-latest" : "gpt-4.1";
console.log(`Using model: ${model} via ${accountToken ? "account token" : "API key"}\n`);

// Sample athlete profile — edit to match a real test user
const user = {
  experience_years: 3,
  race_objective: "Ironman 70.3",
  ftp: 240,
  vma: 14.5,
  css_seconds_per100m: 105,
  limiters: "running endurance",
  current_weekly_hours: 8,
  swim_days: ["Tuesday", "Thursday", "Saturday"],
  bike_days: ["Monday", "Wednesday", "Saturday", "Sunday"],
  run_days: ["Monday", "Wednesday", "Friday", "Sunday"],
  mon_duration: 60, tue_duration: 45, wed_duration: 75,
  thu_duration: 45, fri_duration: 60, sat_duration: 180, sun_duration: 120,
};

const vars = {
  raceDate: "2026-09-06",
  planStartDate: "2026-04-13",
  totalWeeks: 21,
  weeklyHours: 9.25,
};

// Build prompt (mirrors buildStep1Prompt in index.ts)
function formatCSS(s) {
  if (!s) return "not provided";
  return `${Math.floor(s / 60)}:${(s % 60).toString().padStart(2, "0")}`;
}
function mapExperience(y) {
  if (!y || y <= 1) return "beginner";
  if (y <= 4) return "intermediate";
  return "experienced";
}
function expandRace(r) {
  const m = {
    "Sprint": "Sprint (750m swim / 20km bike / 5km run)",
    "Olympic": "Olympic (1.5km swim / 40km bike / 10km run)",
    "Ironman 70.3": "Half-Ironman (1.9km swim / 90km bike / 21.1km run)",
    "Ironman": "Ironman (3.8km swim / 180km bike / 42.2km run)",
  };
  return m[r] || r;
}

// Read the actual prompt template
const promptTemplate = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), "../supabase/functions/generate-plan/prompts/step1-macro-plan-prompt.ts"),
  "utf8"
).replace(/^export default `/, "").replace(/`;?\s*$/, "");

const weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"];
const weekendDays = ["Saturday", "Sunday"];
const swimDays = new Set(user.swim_days);
const bikeDays = new Set(user.bike_days);
const runDays = new Set(user.run_days);

const weekdayDurations = [user.mon_duration, user.tue_duration, user.wed_duration, user.thu_duration, user.fri_duration].filter(Boolean);
const weekendDurations = [user.sat_duration, user.sun_duration].filter(Boolean);
const maxWeekday = Math.min(...weekdayDurations);
const maxWeekend = Math.max(...weekendDurations);

let prompt = promptTemplate
  .replace("{{training_philosophy}}", "(omitted for brevity in local test)")
  .replace("{{experience_level}}", mapExperience(user.experience_years))
  .replace("{{race_distance}}", expandRace(user.race_objective))
  .replace("{{race_date}}", vars.raceDate)
  .replace("{{plan_start_date}}", vars.planStartDate)
  .replace("{{total_weeks}}", vars.totalWeeks.toString())
  .replace("{{weekly_hours}}", vars.weeklyHours.toString())
  .replace("{{current_weekly_hours}}", user.current_weekly_hours.toString())
  .replace("{{ftp_watts}}", user.ftp.toString())
  .replace("{{mas_kmh}}", user.vma.toString())
  .replace("{{swim_css}}", formatCSS(user.css_seconds_per100m))
  .replace("{{limiters}}", user.limiters)
  .replace("{{max_weekday_minutes}}", maxWeekday.toString())
  .replace("{{max_weekend_minutes}}", maxWeekend.toString())
  .replace("{{swim_weekday_count}}", weekdays.filter(d => swimDays.has(d)).length.toString())
  .replace("{{swim_weekend_count}}", weekendDays.filter(d => swimDays.has(d)).length.toString())
  .replace("{{bike_weekday_count}}", weekdays.filter(d => bikeDays.has(d)).length.toString())
  .replace("{{bike_weekend_count}}", weekendDays.filter(d => bikeDays.has(d)).length.toString())
  .replace("{{run_weekday_count}}", weekdays.filter(d => runDays.has(d)).length.toString())
  .replace("{{run_weekend_count}}", weekendDays.filter(d => runDays.has(d)).length.toString());

console.log("Calling OpenAI Step 1...\n");
const start = Date.now();

const response = await client.chat.completions.create({
  model,
  messages: [{ role: "user", content: prompt }],
  temperature: 0.2,
});

const elapsed = ((Date.now() - start) / 1000).toFixed(1);
const output = response.choices[0].message.content;

console.log(`=== STEP 1 OUTPUT (${elapsed}s) ===\n`);
console.log(output);
console.log(`\n=== TOKENS: ${response.usage?.total_tokens} total ===`);
