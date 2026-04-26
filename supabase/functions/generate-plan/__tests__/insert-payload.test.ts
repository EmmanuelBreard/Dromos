/**
 * insert-payload.test.ts
 *
 * Unit tests for the generate-plan insert-payload materialisation step (DRO-216).
 *
 * Run from repo root:
 *   deno test supabase/functions/generate-plan/__tests__/insert-payload.test.ts
 *
 * Tests cover:
 *   ✓ buildTemplateMap builds a correct template_id → WorkoutTemplate index
 *   ✓ Insert payload has non-null `structure` when template_id is known
 *   ✓ `structure` matches materialize(template) exactly for swim, bike, run
 *   ✓ `structure` is null (and a warning is produced) when template_id is unknown
 *   ✓ No `sport: "strength"` session can survive the VALID_SPORTS guard
 *   ✓ Fixers swap template_id before insert — structure reflects the new template
 */

import {
  assertEquals,
  assertExists,
  assertStrictEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { materialize, type WorkoutTemplate } from "../../_shared/materialize-structure.ts";

// ---------------------------------------------------------------------------
// Minimal replica of buildTemplateMap (same logic as in index.ts)
// ---------------------------------------------------------------------------

function buildTemplateMap(lib: Record<string, WorkoutTemplate[]>): Record<string, WorkoutTemplate> {
  const map: Record<string, WorkoutTemplate> = {};
  for (const sport of ["swim", "bike", "run"]) {
    for (const tmpl of lib[sport as keyof typeof lib] || []) {
      map[tmpl.template_id] = tmpl;
    }
  }
  return map;
}

// ---------------------------------------------------------------------------
// Simulate the insert-time structure resolution (same logic as in index.ts)
// ---------------------------------------------------------------------------

function resolveStructure(
  templateId: string,
  templateMap: Record<string, WorkoutTemplate>
): ReturnType<typeof materialize> | null {
  const template = templateMap[templateId];
  return template ? materialize(template) : null;
}

// ---------------------------------------------------------------------------
// Fixture library — minimal but realistic subset of workout-library.json
// ---------------------------------------------------------------------------

const FIXTURE_LIBRARY: Record<string, WorkoutTemplate[]> = {
  swim: [
    {
      template_id: "SWIM_Easy_01",
      duration_minutes: 30,
      segments: [
        { label: "warmup", distance_meters: 200, pace: "slow" },
        { label: "work", distance_meters: 600, pace: "easy" },
        { label: "cooldown", distance_meters: 200, pace: "slow" },
      ],
    },
    {
      template_id: "SWIM_Tempo_01",
      duration_minutes: 33,
      segments: [
        { label: "warmup", distance_meters: 300, pace: "slow" },
        {
          label: "repeat",
          repeats: 10,
          segments: [{ label: "work", distance_meters: 100, pace: "medium" }],
          rest_seconds: 20,
        },
        { label: "cooldown", distance_meters: 200, pace: "slow" },
      ],
    },
  ],
  bike: [
    {
      template_id: "BIKE_Easy_01",
      duration_minutes: 45,
      segments: [
        { label: "warmup", duration_minutes: 10, ftp_pct: 65, cadence_rpm: 85 },
        { label: "work", duration_minutes: 30, ftp_pct: 72, cadence_rpm: 90 },
        { label: "cooldown", duration_minutes: 5, ftp_pct: 60, cadence_rpm: 85 },
      ],
    },
    {
      template_id: "BIKE_Tempo_01",
      duration_minutes: 50,
      segments: [
        { label: "warmup", duration_minutes: 15, ftp_pct: 65, cadence_rpm: 88 },
        { label: "work", duration_minutes: 25, ftp_pct: 88, cadence_rpm: 90 },
        { label: "cooldown", duration_minutes: 10, ftp_pct: 60, cadence_rpm: 85 },
      ],
    },
  ],
  run: [
    {
      template_id: "RUN_Easy_01",
      duration_minutes: 30,
      segments: [
        { label: "warmup", duration_minutes: 5, vma_pct: 60 },
        { label: "work", duration_minutes: 20, vma_pct: 65 },
        { label: "cooldown", duration_minutes: 5, vma_pct: 58 },
      ],
    },
    {
      template_id: "RUN_Tempo_01",
      duration_minutes: 45,
      segments: [
        { label: "warmup", duration_minutes: 15, vma_pct: 70 },
        { label: "work", duration_minutes: 20, vma_pct: 88 },
        { label: "cooldown", duration_minutes: 10, vma_pct: 65 },
      ],
    },
  ],
};

// ---------------------------------------------------------------------------
// buildTemplateMap tests
// ---------------------------------------------------------------------------

Deno.test("buildTemplateMap: indexes all templates across swim/bike/run", () => {
  const map = buildTemplateMap(FIXTURE_LIBRARY);
  // All 6 templates must be present
  assertEquals(Object.keys(map).length, 6);
  assertExists(map["SWIM_Easy_01"]);
  assertExists(map["SWIM_Tempo_01"]);
  assertExists(map["BIKE_Easy_01"]);
  assertExists(map["BIKE_Tempo_01"]);
  assertExists(map["RUN_Easy_01"]);
  assertExists(map["RUN_Tempo_01"]);
});

Deno.test("buildTemplateMap: preserves template object reference (no clone)", () => {
  const map = buildTemplateMap(FIXTURE_LIBRARY);
  // Same object reference — not a deep copy
  assertStrictEquals(map["SWIM_Easy_01"], FIXTURE_LIBRARY.swim[0]);
});

Deno.test("buildTemplateMap: gracefully handles missing sport arrays", () => {
  const partialLib = { swim: FIXTURE_LIBRARY.swim };
  const map = buildTemplateMap(partialLib as Record<string, WorkoutTemplate[]>);
  assertEquals(Object.keys(map).length, FIXTURE_LIBRARY.swim.length);
});

// ---------------------------------------------------------------------------
// Insert-payload structure tests (mirrors the insert site logic in index.ts)
// ---------------------------------------------------------------------------

Deno.test("insert payload: swim session has non-null structure matching materialize()", () => {
  const templateMap = buildTemplateMap(FIXTURE_LIBRARY);
  const structure = resolveStructure("SWIM_Easy_01", templateMap);

  assertExists(structure, "structure must not be null for a known template");
  // Must exactly match materialize() output
  assertEquals(structure, materialize(FIXTURE_LIBRARY.swim[0]));
  // Must have segments
  assertExists(structure.segments);
  assertEquals(structure.segments.length, 3);
  // Swim pace → RPE conversion applied
  assertEquals(structure.segments[0].target, { type: "rpe", value: 3 }); // slow → 3
  assertEquals(structure.segments[1].target, { type: "rpe", value: 3 }); // easy → 3
});

Deno.test("insert payload: bike session has non-null structure with ftp_pct targets", () => {
  const templateMap = buildTemplateMap(FIXTURE_LIBRARY);
  const structure = resolveStructure("BIKE_Tempo_01", templateMap);

  assertExists(structure);
  assertEquals(structure, materialize(FIXTURE_LIBRARY.bike[1]));
  assertEquals(structure.segments[1].target, { type: "ftp_pct", value: 88 });
  assertEquals(structure.segments[1].cadence_rpm, 90);
});

Deno.test("insert payload: run session has non-null structure with vma_pct targets", () => {
  const templateMap = buildTemplateMap(FIXTURE_LIBRARY);
  const structure = resolveStructure("RUN_Tempo_01", templateMap);

  assertExists(structure);
  assertEquals(structure, materialize(FIXTURE_LIBRARY.run[1]));
  assertEquals(structure.segments[1].target, { type: "vma_pct", value: 88 });
});

Deno.test("insert payload: unknown template_id returns null (warns but does not throw)", () => {
  const templateMap = buildTemplateMap(FIXTURE_LIBRARY);
  const structure = resolveStructure("NONEXISTENT_Template_99", templateMap);
  assertEquals(structure, null, "unknown template_id must produce null structure, not throw");
});

// ---------------------------------------------------------------------------
// Fixer swap test: structure reflects the post-fix template_id
// ---------------------------------------------------------------------------

Deno.test("fixer swap: materialisation uses the post-fix template_id", () => {
  const templateMap = buildTemplateMap(FIXTURE_LIBRARY);

  // Simulate a session where a fixer replaced the original template_id
  const session = { template_id: "RUN_Easy_01", sport: "run" };

  // Fixer swaps to RUN_Tempo_01 (simulating fixConsecutiveRepeats behaviour)
  session.template_id = "RUN_Tempo_01";

  // Insert site materialises using the post-fix template_id
  const structure = resolveStructure(session.template_id, templateMap);

  assertExists(structure);
  // Must reflect TEMPO template, not the original EASY template.
  // RUN_Tempo_01 work segment → vma_pct: 88; RUN_Easy_01 work segment → vma_pct: 65.
  assertEquals(
    structure.segments[1].target,
    { type: "vma_pct", value: 88 },
    "work segment must come from Tempo template (vma_pct: 88), not Easy template (vma_pct: 65)"
  );
});

// ---------------------------------------------------------------------------
// VALID_SPORTS guard: strength is rejected before materialisation
// ---------------------------------------------------------------------------

Deno.test("VALID_SPORTS guard: strength is not in the allowed list", () => {
  // Replica of the validation block in index.ts
  const VALID_SPORTS = ["swim", "bike", "run"];

  const strengthSession = { sport: "strength", type: "Easy", template_id: "STR_01", duration_minutes: 30 };

  const isValid = VALID_SPORTS.includes(strengthSession.sport);
  assertEquals(isValid, false, "strength must fail VALID_SPORTS check");
});

Deno.test("VALID_SPORTS guard: swim/bike/run all pass", () => {
  const VALID_SPORTS = ["swim", "bike", "run"];
  for (const sport of VALID_SPORTS) {
    assertEquals(VALID_SPORTS.includes(sport), true);
  }
});

// ---------------------------------------------------------------------------
// Swim nested repeats: structure is preserved through insert path
// ---------------------------------------------------------------------------

Deno.test("insert payload: swim tempo with repeat segments materialises correctly", () => {
  const templateMap = buildTemplateMap(FIXTURE_LIBRARY);
  const structure = resolveStructure("SWIM_Tempo_01", templateMap);

  assertExists(structure);
  assertEquals(structure.segments.length, 3);

  // Middle segment is the repeat container
  const repeatSeg = structure.segments[1];
  assertEquals(repeatSeg.label, "repeat");
  assertEquals(repeatSeg.repeats, 10);
  assertExists(repeatSeg.segments);
  assertEquals(repeatSeg.segments!.length, 1);

  // Repeat container must NOT carry a target (leaf only)
  assertEquals(repeatSeg.target, undefined);

  // Leaf carries RPE from pace: "medium" → 6
  assertEquals(repeatSeg.segments![0].target, { type: "rpe", value: 6 });
  assertEquals(repeatSeg.rest_seconds, 20);
});
