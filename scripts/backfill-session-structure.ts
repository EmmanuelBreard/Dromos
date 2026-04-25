/**
 * backfill-session-structure.ts
 *
 * One-time Deno script that materialises plan_sessions.structure for all
 * existing rows that don't have it yet.
 *
 * Usage:
 *   deno run --allow-net --allow-read --allow-env scripts/backfill-session-structure.ts
 *
 * Requires env vars (from .env or shell):
 *   SUPABASE_URL             — e.g. https://<project>.supabase.co
 *   SUPABASE_SERVICE_ROLE_KEY — JWT with service-role privileges
 *
 * Idempotent: rows with structure IS NOT NULL are skipped.
 * Strength rows are left untouched (structure stays NULL; Phase 8 deletes them).
 * Exit code: non-zero when failed > 0, zero otherwise.
 */

import { materialize, WorkoutTemplate } from "../supabase/functions/_shared/materialize-structure.ts";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const BATCH_SIZE = 100;

// ---------------------------------------------------------------------------
// Env validation
// ---------------------------------------------------------------------------

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("[backfill] ERROR: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set.");
  Deno.exit(1);
}

// ---------------------------------------------------------------------------
// Workout library loader — builds Map<template_id, WorkoutTemplate>
// ---------------------------------------------------------------------------

async function loadLibrary(): Promise<Map<string, WorkoutTemplate>> {
  // Resolve path relative to this script file's directory.
  // Decode URL-encoded path to handle spaces in directory names.
  const scriptDir = decodeURIComponent(new URL(".", import.meta.url).pathname);
  const libPath = `${scriptDir}../ai/context/workout-library.json`;

  const raw = await Deno.readTextFile(libPath);
  const data = JSON.parse(raw) as Record<string, WorkoutTemplate[]>;

  const map = new Map<string, WorkoutTemplate>();
  // Iterate all top-level arrays: swim, bike, run, race
  for (const templates of Object.values(data)) {
    for (const template of templates) {
      map.set(template.template_id, template);
    }
  }

  return map;
}

// ---------------------------------------------------------------------------
// Supabase REST helpers
// ---------------------------------------------------------------------------

interface PlanSessionRow {
  id: string;
  sport: string;
  template_id: string | null;
  structure: unknown | null;
}

const HEADERS = {
  "apikey": SERVICE_ROLE_KEY,
  "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
  "Content-Type": "application/json",
  "Prefer": "return=minimal",
};

async function fetchBatch(lastId: string | null): Promise<PlanSessionRow[]> {
  // Use keyset pagination: id > lastId, ordered by id, limit BATCH_SIZE
  let filter = "sport=neq.strength&structure=is.null&select=id,sport,template_id,structure&order=id.asc&limit=" + BATCH_SIZE;
  if (lastId !== null) {
    filter += `&id=gt.${lastId}`;
  }

  const url = `${SUPABASE_URL}/rest/v1/plan_sessions?${filter}`;
  const resp = await fetch(url, { headers: HEADERS });

  if (!resp.ok) {
    const body = await resp.text();
    throw new Error(`fetchBatch failed (${resp.status}): ${body}`);
  }

  return resp.json() as Promise<PlanSessionRow[]>;
}

async function updateStructure(id: string, structure: unknown): Promise<void> {
  // CAS guard: only update where structure IS NULL (race-condition safety)
  const url = `${SUPABASE_URL}/rest/v1/plan_sessions?id=eq.${id}&structure=is.null`;
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
// Main backfill loop
// ---------------------------------------------------------------------------

async function run(): Promise<void> {
  console.log("[backfill] Starting backfill of plan_sessions.structure ...");

  const library = await loadLibrary();
  console.log(`[backfill] Loaded ${library.size} templates from workout-library.json`);

  let populated = 0;
  let skipped = 0;    // structure already non-null
  let orphaned = 0;   // template_id not in library
  let failed = 0;

  let lastId: string | null = null;
  let batchNum = 0;

  while (true) {
    const batch = await fetchBatch(lastId);

    if (batch.length === 0) {
      break; // All done
    }

    batchNum++;
    console.log(`[backfill] Batch ${batchNum}: ${batch.length} rows (starting after id=${lastId ?? "beginning"})`);

    for (const row of batch) {
      // The query already filters structure IS NULL and sport != strength,
      // but guard here too for extra safety.
      if (row.structure !== null) {
        skipped++;
        continue;
      }

      if (row.sport === "strength") {
        // Should not appear due to filter, but defensive skip
        console.log(`[backfill]   SKIP (strength) id=${row.id}`);
        skipped++;
        continue;
      }

      if (!row.template_id) {
        console.log(`[backfill]   ORPHAN (no template_id) id=${row.id} sport=${row.sport}`);
        orphaned++;
        continue;
      }

      const template = library.get(row.template_id);
      if (!template) {
        console.log(`[backfill]   ORPHAN (template not found) id=${row.id} template_id=${row.template_id}`);
        orphaned++;
        continue;
      }

      let structure: unknown;
      try {
        structure = materialize(template);
      } catch (err) {
        console.error(`[backfill]   FAILED (materialize) id=${row.id} template_id=${row.template_id}: ${err}`);
        failed++;
        continue;
      }

      try {
        await updateStructure(row.id, structure);
        console.log(`[backfill]   POPULATED id=${row.id} template_id=${row.template_id}`);
        populated++;
      } catch (err) {
        console.error(`[backfill]   FAILED (update) id=${row.id}: ${err}`);
        failed++;
      }
    }

    lastId = batch[batch.length - 1].id;
  }

  // ---------------------------------------------------------------------------
  // Summary
  // ---------------------------------------------------------------------------
  console.log("\n[backfill] ====== SUMMARY ======");
  console.log(`[backfill]   populated : ${populated}`);
  console.log(`[backfill]   skipped   : ${skipped}`);
  console.log(`[backfill]   orphaned  : ${orphaned}`);
  console.log(`[backfill]   failed    : ${failed}`);
  console.log("[backfill] ====================\n");

  if (failed > 0) {
    console.error(`[backfill] Exiting with error: ${failed} row(s) failed.`);
    Deno.exit(1);
  }

  console.log("[backfill] Done.");
}

await run();
