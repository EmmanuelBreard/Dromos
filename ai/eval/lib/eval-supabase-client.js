// eval-supabase-client.js — DRO-313 (Phase 1 of the DRO-311 eval harness)
//
// Reusable Supabase plumbing for the plan-quality eval harness. This promotes the
// logic proven end-to-end in `ai/eval/poc-generate-e2e.js` (DRO-311 PoC) into
// standalone, composable exports the full harness runners depend on:
//   synthetic user → JWT → invoke generate-plan → poll → read plan → cleanup.
//
// Environment: PRODUCTION project + strict cleanup (see DRO-311 PoC verdict — preview
// branches were not validated to serve edge functions; main + cleanup is the settled
// choice). Auth: anon `signUp` returns a session token directly (email confirmation is
// off) — no service-role key is required for the create → invoke → read path.

const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "../../../.env") });
const { createClient } = require("@supabase/supabase-js");

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;
// Admin key for programmatic test-user teardown. Accepts either the legacy
// service_role JWT (SUPABASE_SERVICE_ROLE_KEY) or the modern secret key
// (SUPABASE_SECRET_KEY, format sb_secret_...). Either grants Auth admin access.
const SUPABASE_SERVICE_ROLE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SECRET_KEY;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  throw new Error(
    "eval-supabase-client: missing SUPABASE_URL / SUPABASE_ANON_KEY in .env " +
      "(copy from the app root .env — see tech-specs/DRO-311-eval-harness.md)"
  );
}

// Day-duration columns on public.users. Each is `NULL OR 30..420` at the DB level
// (check_<day>_duration) — a day is "rest" only when the column is NULL, never 0.
const DAY_DURATION_FIELDS = [
  "mon_duration",
  "tue_duration",
  "wed_duration",
  "thu_duration",
  "fri_duration",
  "sat_duration",
  "sun_duration",
];

/** A fresh anon client per call — no shared/mutable session state between test users. */
function createAnonClient() {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/**
 * An anon-keyed client that authenticates every request (REST + Functions) as the
 * given user via the Authorization header. This is how RLS-scoped reads/writes and
 * edge-function invocations are made "as" a specific synthetic test user without
 * juggling stateful client sessions across the harness's async runners.
 */
function clientForJwt(jwt) {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
}

/**
 * Normalizes a scenario profile's day-duration fields for DB seeding:
 * 0, "0", null, undefined, or an absent key all mean "rest day" → NULL.
 * (The eval's athletes.yaml vars use "0" for rest by convention; the DB constraint
 * requires NULL, not 0 — see DRO-311 PoC "Data hygiene finding".) Any other value is
 * coerced to a Number so string vars ("60") seed correctly as integers.
 */
function normalizeRestDays(profile) {
  const seeded = { ...profile };
  for (const field of DAY_DURATION_FIELDS) {
    const raw = field in profile ? profile[field] : null;
    const num = raw === null || raw === undefined || raw === "" ? NaN : Number(raw);
    seeded[field] = !num || Number.isNaN(num) ? null : num;
  }
  return seeded;
}

/**
 * Creates a synthetic auth user (anon signUp — no service-role key needed) and seeds
 * its public.users profile row via the user's own JWT (RLS "Users can update own
 * profile"; the on_auth_user_created trigger creates the row on signup).
 *
 * @param {object} profile - athlete profile fields to seed onto public.users
 *   (race_objective, race_date, onboarding_completed, availability, performance
 *   metrics, etc). Day-duration fields are rest-day-normalized — see normalizeRestDays.
 * @returns {Promise<{userId: string, jwt: string, email: string}>}
 */
async function createTestUser(profile) {
  const stamp = Date.now();
  const rand = Math.random().toString(36).slice(2, 8);
  const email = `eval-${stamp}-${rand}@example.com`;
  const password = `Eval-${stamp}-${rand}!aA`;

  const anon = createAnonClient();
  const { data: signUpData, error: signUpErr } = await anon.auth.signUp({ email, password });
  if (signUpErr || !signUpData.session) {
    throw new Error(`createTestUser: signUp failed: ${signUpErr?.message || "no session returned"}`);
  }
  const userId = signUpData.user.id;
  const jwt = signUpData.session.access_token;

  const seedFields = normalizeRestDays(profile);
  const authed = clientForJwt(jwt);
  const { error: updateErr } = await authed.from("users").update(seedFields).eq("id", userId);
  if (updateErr) {
    // The auth user already exists at this point (signUp succeeded) but the caller
    // never receives its id when we throw here — so it would leak with no way for the
    // caller to clean it up. Best-effort self-clean the partial user before re-throwing
    // so a seed failure never orphans an auth.users row.
    try {
      await deleteTestUser(userId);
    } catch (cleanupErr) {
      console.warn(
        `createTestUser: seed failed AND partial-user cleanup failed for ${userId}: ${cleanupErr.message}\n` +
          `  Clean up manually: DELETE FROM auth.users WHERE id='${userId}';`
      );
    }
    throw new Error(`createTestUser: profile seed failed (RLS?): ${updateErr.message}`);
  }

  return { userId, jwt, email };
}

/**
 * Signs in an existing test user and mints a fresh session JWT.
 * @returns {Promise<{userId: string, jwt: string, email: string}>}
 */
async function signIn(email, password) {
  const anon = createAnonClient();
  const { data, error } = await anon.auth.signInWithPassword({ email, password });
  if (error || !data.session) {
    throw new Error(`signIn failed: ${error?.message || "no session returned"}`);
  }
  return { userId: data.user.id, jwt: data.session.access_token, email };
}

/**
 * Invokes the deployed `generate-plan` edge function as the given user.
 * The function reads the user + profile from the JWT server-side; the request body
 * is ignored (mirrors the proven PoC contract).
 * @returns {Promise<string>} planId
 */
async function invokeGeneratePlan(jwt) {
  const authed = clientForJwt(jwt);
  const { data, error } = await authed.functions.invoke("generate-plan", { body: {} });
  if (error) throw new Error(`invokeGeneratePlan failed: ${error.message}`);
  const planId = data?.planId;
  if (!planId) throw new Error(`invokeGeneratePlan: no planId returned: ${JSON.stringify(data)}`);
  return planId;
}

/**
 * Polls training_plans.status until it settles or the timeout elapses.
 *
 * Generation errors are persisted as status='failed' + error_message (DRO-312 fixed
 * the zombie bug where failures silently stuck at 'generating' forever). This still
 * treats a plan stuck in 'generating' past the timeout as a failure — belt-and-braces
 * against any *other* path that never flips status (e.g. an edge function crash before
 * the catch block runs, or cold-start/infra issues).
 *
 * @returns {Promise<'active' | {status: 'failed', error_message: string|null} | 'timeout'>}
 */
async function pollStatus(planId, jwt, timeoutMs = 240000, pollMs = 5000) {
  const authed = clientForJwt(jwt);
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const { data, error } = await authed
      .from("training_plans")
      .select("status, error_message")
      .eq("id", planId)
      .single();
    if (error) throw new Error(`pollStatus: status poll failed: ${error.message}`);

    if (data.status === "active") return "active";
    if (data.status === "failed") {
      return { status: "failed", error_message: data.error_message || null };
    }
    // status === 'generating' — keep polling
    await new Promise((r) => setTimeout(r, pollMs));
  }
  return "timeout";
}

/**
 * Reads the materialized plan back: training_plans + nested plan_weeks + plan_sessions.
 * Pass through `db-plan-to-eval-shape.js`'s `dbPlanToEvalShape()` before scoring.
 * @returns {Promise<object>} the raw training_plans row with nested weeks/sessions
 */
async function readPlan(planId, jwt) {
  const authed = clientForJwt(jwt);
  const { data, error } = await authed
    .from("training_plans")
    .select("*, plan_weeks(*, plan_sessions(*))")
    .eq("id", planId)
    .single();
  if (error) throw new Error(`readPlan: plan read failed: ${error.message}`);
  return data;
}

/**
 * Deletes a synthetic test user and all cascaded rows (public.users, training_plans,
 * plan_weeks, plan_sessions).
 *
 * NOTE: a user cannot delete its own auth.users row via the anon key/RLS — Supabase
 * Auth admin operations require the service-role key, which the harness does not keep
 * in .env by default (kept out of local dev to limit blast radius — see DRO-311 PoC).
 *
 * If SUPABASE_SERVICE_ROLE_KEY IS present in env, this calls the Auth admin API
 * directly and deletes for real. If it is NOT present, this logs the userId and the
 * equivalent SQL for manual/MCP cleanup instead of silently no-op'ing, so callers
 * always get a visible signal that cleanup still needs to happen.
 *
 * @returns {Promise<{deleted: boolean, userId: string}>}
 */
async function deleteTestUser(userId) {
  if (!SUPABASE_SERVICE_ROLE_KEY) {
    console.warn(
      `deleteTestUser: no SUPABASE_SERVICE_ROLE_KEY / SUPABASE_SECRET_KEY in env — cannot delete auth user programmatically.\n` +
        `  Clean up manually (e.g. via the Supabase MCP execute_sql tool):\n` +
        `    DELETE FROM auth.users WHERE id='${userId}';\n` +
        `  (CASCADEs to public.users → training_plans → plan_weeks → plan_sessions.)`
    );
    return { deleted: false, userId };
  }

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { error } = await admin.auth.admin.deleteUser(userId);
  if (error) throw new Error(`deleteTestUser: admin deleteUser failed: ${error.message}`);
  return { deleted: true, userId };
}

/**
 * TODO(Phase 4 — DRO-311 chat-adjust runner): invoke the deployed `chat-adjust` edge
 * function for a multi-turn adjustment scenario and return the adjusted plan / diff.
 * Stubbed here so Phase 1 exports a complete, stable client surface for later phases
 * to build against without another breaking API pass.
 *
 * Expected shape (subject to change once the chat-adjust contract is spec'd):
 *   turns: [{ message: string }, ...] — sequential user turns in the adjustment chat.
 *   returns: Promise<{ planId: string, weeks: Array }> — the plan state after the
 *   final turn, read back the same way `readPlan()` does for generate-plan.
 *
 * @param {string} jwt
 * @param {Array<{message: string}>} turns
 */
async function invokeChatAdjust(jwt, turns) {
  throw new Error(
    "invokeChatAdjust is not implemented yet (DRO-311 Phase 4 — chat-adjust runner). " +
      "See tech-specs/DRO-311-eval-harness.md for the planned contract."
  );
}

module.exports = {
  createTestUser,
  signIn,
  invokeGeneratePlan,
  pollStatus,
  readPlan,
  deleteTestUser,
  invokeChatAdjust,
  // exported for reuse/testing (e.g. verifying the 0/absent → NULL translation)
  normalizeRestDays,
};
