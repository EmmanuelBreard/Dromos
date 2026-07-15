#!/usr/bin/env node
/**
 * poc-generate-e2e.js — DRO-311 PoC
 *
 * Proves the riskiest, never-run assumption for the plan-quality eval harness:
 *   synthetic user → programmatic auth (JWT) → invoke the DEPLOYED generate-plan
 *   edge function → poll → read the materialized plan back → run the 8-metric
 *   checker on it → clean up.
 *
 * Environment: PRODUCTION project + strict cleanup (user consented). One scenario, one run.
 * Auth: anon signUp returns a session token (email confirmation is off) — no service-role key needed.
 * DB seeding/reading: via the authenticated user's own JWT (RLS: "Users can update own profile" +
 *   own-plan read policies). Cleanup of the auth user is done separately via the Supabase MCP
 *   (a user cannot delete its own auth row), using the id this script writes to results/.poc-last-user-id.
 *
 * Usage: node ai/eval/poc-generate-e2e.js
 */

require("dotenv").config({ path: require("path").join(__dirname, "../../.env") });
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { createClient } = require("@supabase/supabase-js");
const { dbPlanToEvalShape } = require("./db-plan-to-eval-shape");

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.error("Missing SUPABASE_URL / SUPABASE_ANON_KEY in .env");
  process.exit(1);
}

// ── Scenario: mirrors "Alex - Beginner Olympic" from vars/athletes.yaml so the
//    checker finds matching availability constraints by athlete_name. race_date is
//    set into the future (the function derives total_weeks from it); the checker
//    does not use race_date. ────────────────────────────────────────────────────
const ATHLETE_NAME = "Alex - Beginner Olympic";
const RESULTS_DIR = path.join(__dirname, "results");
const USER_ID_FILE = path.join(RESULTS_DIR, ".poc-last-user-id");
const PLAN_OUT_FILE = path.join(RESULTS_DIR, "poc-generate.json");

const scenarioProfile = {
  race_objective: "Olympic",
  race_date: "2026-11-25T09:00:00+00:00", // ~19 weeks out
  onboarding_completed: true,
  experience_years: 1,
  current_weekly_hours: 3,
  ftp: 180,
  vma: 14,
  css_seconds_per100m: 130,
  swim_days: ["Monday", "Wednesday", "Saturday"],
  bike_days: ["Thursday", "Saturday", "Sunday"],
  run_days: ["Monday", "Wednesday", "Thursday", "Sunday"],
  // Rest days are NULL (not 0): DB constraint requires each duration IS NULL OR 30..420.
  // (The eval's athletes.yaml uses "0" for rest — that convention must be translated to NULL when seeding.)
  mon_duration: 60,
  tue_duration: null,
  wed_duration: 60,
  thu_duration: 60,
  fri_duration: null,
  sat_duration: 120,
  sun_duration: 90,
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  if (!fs.existsSync(RESULTS_DIR)) fs.mkdirSync(RESULTS_DIR, { recursive: true });

  const stamp = Date.now();
  const email = `poc-eval-${stamp}@example.com`;
  const password = `PocEval-${stamp}!aA`;

  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  console.log("=== DRO-311 PoC: real generate-plan invocation ===\n");

  // 1. Create synthetic auth user (trigger on_auth_user_created makes the public.users row)
  console.log("[1/7] signUp → mint JWT");
  const { data: signUpData, error: signUpErr } = await supabase.auth.signUp({ email, password });
  if (signUpErr || !signUpData.session) {
    throw new Error(`signUp failed / no session: ${signUpErr?.message || "no session returned"}`);
  }
  const userId = signUpData.user.id;
  const jwt = signUpData.session.access_token;
  fs.writeFileSync(USER_ID_FILE, userId); // for MCP cleanup even if the script later throws
  console.log(`      user_id=${userId}`);

  // 2. Seed the profile via the user's own JWT (RLS self-update)
  console.log("[2/7] seed profile (availability + race)");
  const { error: updErr } = await supabase.from("users").update(scenarioProfile).eq("id", userId);
  if (updErr) throw new Error(`profile seed failed (RLS?): ${updErr.message}`);

  // 3. Invoke the DEPLOYED edge function (session token attached as Authorization)
  console.log("[3/7] invoke generate-plan");
  const { data: invokeData, error: invokeErr } = await supabase.functions.invoke("generate-plan", {
    body: {},
  });
  if (invokeErr) throw new Error(`invoke failed: ${invokeErr.message}`);
  const planId = invokeData?.planId;
  if (!planId) throw new Error(`no planId returned: ${JSON.stringify(invokeData)}`);
  console.log(`      planId=${planId}`);

  // 4. Poll status → active/failed
  console.log("[4/7] poll training_plans.status");
  const TIMEOUT_MS = 240000;
  const POLL_MS = 5000;
  const start = Date.now();
  let status = "generating";
  while (Date.now() - start < TIMEOUT_MS) {
    await sleep(POLL_MS);
    const { data, error } = await supabase.from("training_plans").select("status").eq("id", planId).single();
    if (error) throw new Error(`status poll failed: ${error.message}`);
    status = data.status;
    process.stdout.write(`      ${Math.round((Date.now() - start) / 1000)}s → ${status}\n`);
    if (status === "active" || status === "failed") break;
  }
  if (status !== "active") throw new Error(`plan did not reach 'active' (last status: ${status})`);

  // 5. Read the materialized plan back
  console.log("[5/7] read plan_weeks + plan_sessions");
  const { data: dbPlan, error: readErr } = await supabase
    .from("training_plans")
    .select("*, plan_weeks(*, plan_sessions(*))")
    .eq("id", planId)
    .single();
  if (readErr) throw new Error(`plan read failed: ${readErr.message}`);
  const weekCount = (dbPlan.plan_weeks || []).length;
  const sessionCount = (dbPlan.plan_weeks || []).reduce((n, w) => n + (w.plan_sessions || []).length, 0);
  console.log(`      ${weekCount} weeks, ${sessionCount} sessions`);
  if (weekCount === 0) throw new Error("plan has 0 weeks — read/materialization problem");

  // 6. Adapt to eval shape + run the existing 8-metric checker unchanged
  console.log("[6/7] run check-step3-violations.js on the DB plan\n");
  const evalPlan = dbPlanToEvalShape(dbPlan);
  const batchRecord = [{ output: JSON.stringify(evalPlan), athlete_name: ATHLETE_NAME }];
  fs.writeFileSync(PLAN_OUT_FILE, JSON.stringify(batchRecord, null, 2));
  const checkerOut = execFileSync("node", [path.join(__dirname, "check-step3-violations.js"), PLAN_OUT_FILE], {
    encoding: "utf8",
  });
  console.log(checkerOut);

  // 7. Verdict
  console.log("[7/7] PoC END-TO-END SUCCEEDED ✅");
  console.log(`      Test user ${userId} still exists — clean it up via MCP:`);
  console.log(`        DELETE FROM auth.users WHERE id='${userId}';`);
  console.log(`      (id also written to ${path.relative(process.cwd(), USER_ID_FILE)})`);
}

main().catch((e) => {
  console.error("\n❌ PoC FAILED:", e.message);
  console.error("   If a test user was created, clean it up via MCP using results/.poc-last-user-id");
  process.exit(1);
});
