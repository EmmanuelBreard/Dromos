/**
 * re-materialize-swim-sessions.ts
 *
 * One-time Deno script that re-materialises plan_sessions.structure for the
 * Phase 2 swim templates that were restructured in DRO-296 (added warmup +
 * drills + cooldown coaching shape to previously sparse templates).
 *
 * Targets: all sessions belonging to the active plan of ebreard4@gmail.com
 * whose template_id is one of the restructured templates.
 *
 * Usage:
 *   SUPABASE_URL=https://cumbrfnguykvxhvdelru.supabase.co \
 *   SUPABASE_SERVICE_ROLE_KEY=<service-role-key> \
 *   deno run --allow-net --allow-read --allow-env scripts/re-materialize-swim-sessions.ts
 *
 * Safe to re-run: each PATCH is unconditional (overwrites stale structure).
 * Exit code: non-zero when failed > 0, zero otherwise.
 */

import {
  materialize,
  WorkoutTemplate,
} from "../supabase/functions/_shared/materialize-structure.ts";

// ---------------------------------------------------------------------------
// Restructured template IDs (DRO-296)
// ---------------------------------------------------------------------------

const RESTRUCTURED_TEMPLATES = [
  "SWIM_Z2_endurance_2500m",
  "SWIM_THR_6x150_1_50",
  "SWIM_CSS_8x100_1_45",
  "SWIM_RACE_2x750_1_48",
  "SWIM_VO2_8x50_fast",
  "SWIM_DRILLS_1800m",
];

const TARGET_EMAIL = "ebreard4@gmail.com";

// ---------------------------------------------------------------------------
// Env validation
// ---------------------------------------------------------------------------

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error(
    "[re-materialize] ERROR: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set.",
  );
  Deno.exit(1);
}

// ---------------------------------------------------------------------------
// Workout library loader
// ---------------------------------------------------------------------------

async function loadLibrary(): Promise<Map<string, WorkoutTemplate>> {
  const scriptDir = decodeURIComponent(new URL(".", import.meta.url).pathname);
  const libPath = `${scriptDir}../ai/context/workout-library.json`;

  const raw = await Deno.readTextFile(libPath);
  const data = JSON.parse(raw) as Record<string, WorkoutTemplate[]>;

  const map = new Map<string, WorkoutTemplate>();
  for (const templates of Object.values(data)) {
    for (const template of templates) {
      map.set(template.template_id, template);
    }
  }
  return map;
}

// ---------------------------------------------------------------------------
// REST helpers
// ---------------------------------------------------------------------------

const HEADERS = {
  "apikey": SERVICE_ROLE_KEY,
  "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
  "Content-Type": "application/json",
  "Prefer": "return=minimal,count=exact",
};

interface PlanSessionRow {
  id: string;
  template_id: string;
  week_number: number;
  day: string;
}

/**
 * Query plan_sessions for ebreard4's active plan filtered to the restructured
 * template IDs. Uses a nested relationship filter via PostgREST.
 */
async function fetchTargetSessions(): Promise<PlanSessionRow[]> {
  // Filter: plan_sessions that belong to an active training_plan of ebreard4
  // and whose template_id is one of the restructured ones.
  const inClause = RESTRUCTURED_TEMPLATES.map((t) => `"${t}"`).join(",");
  const filter = [
    `template_id=in.(${RESTRUCTURED_TEMPLATES.join(",")})`,
    `select=id,template_id,day,plan_weeks!inner(week_number,training_plans!inner(status,users!inner(email)))`,
    `plan_weeks.training_plans.status=eq.active`,
    `plan_weeks.training_plans.users.email=eq.${TARGET_EMAIL}`,
    `order=id.asc`,
  ].join("&");

  const url = `${SUPABASE_URL}/rest/v1/plan_sessions?${filter}`;
  const resp = await fetch(url, { headers: HEADERS });

  if (!resp.ok) {
    const body = await resp.text();
    throw new Error(`fetchTargetSessions failed (${resp.status}): ${body}`);
  }

  const rows = (await resp.json()) as Array<{
    id: string;
    template_id: string;
    day: string;
    plan_weeks: { week_number: number };
  }>;

  return rows.map((r) => ({
    id: r.id,
    template_id: r.template_id,
    week_number: r.plan_weeks?.week_number ?? 0,
    day: r.day,
  }));
}

/**
 * Unconditional PATCH — overwrites stale structure with new materialised value.
 */
async function updateStructure(id: string, structure: unknown): Promise<void> {
  const url = `${SUPABASE_URL}/rest/v1/plan_sessions?id=eq.${encodeURIComponent(id)}`;
  const resp = await fetch(url, {
    method: "PATCH",
    headers: HEADERS,
    body: JSON.stringify({ structure }),
  });

  if (!resp.ok) {
    const body = await resp.text();
    throw new Error(`updateStructure failed for id=${id} (${resp.status}): ${body}`);
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function run(): Promise<void> {
  console.log("[re-materialize] Starting DRO-296 swim template re-materialisation ...");
  console.log(`[re-materialize] Target user: ${TARGET_EMAIL}`);
  console.log(`[re-materialize] Restructured templates: ${RESTRUCTURED_TEMPLATES.join(", ")}`);

  const library = await loadLibrary();
  console.log(`[re-materialize] Loaded ${library.size} templates from workout-library.json`);

  const sessions = await fetchTargetSessions();
  console.log(`[re-materialize] Found ${sessions.length} matching plan_sessions to update`);

  if (sessions.length === 0) {
    console.log("[re-materialize] Nothing to do. Exiting.");
    Deno.exit(0);
  }

  let updated = 0;
  let failed = 0;

  for (const session of sessions) {
    const tpl = library.get(session.template_id);
    if (!tpl) {
      console.error(
        `[re-materialize] ORPHAN: template_id=${session.template_id} not found in library — skipping id=${session.id}`,
      );
      failed++;
      continue;
    }

    let structure;
    try {
      structure = materialize(tpl);
    } catch (err) {
      console.error(
        `[re-materialize] FAILED (materialize) id=${session.id} template_id=${session.template_id}: ${err}`,
      );
      failed++;
      continue;
    }

    try {
      await updateStructure(session.id, structure);
      const segCount = structure.segments.length;
      console.log(
        `[re-materialize] UPDATED id=${session.id} template_id=${session.template_id} wk=${session.week_number} day=${session.day} segments=${segCount}`,
      );
      updated++;
    } catch (err) {
      console.error(
        `[re-materialize] FAILED (update) id=${session.id}: ${err}`,
      );
      failed++;
    }
  }

  console.log("\n[re-materialize] ====== SUMMARY ======");
  console.log(`[re-materialize]   updated : ${updated}`);
  console.log(`[re-materialize]   failed  : ${failed}`);
  console.log("[re-materialize] ====================\n");

  if (failed > 0) {
    console.error(`[re-materialize] Exiting with error: ${failed} row(s) failed.`);
    Deno.exit(1);
  }

  console.log("[re-materialize] Done.");
}

await run();
