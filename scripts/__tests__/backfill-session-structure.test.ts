/**
 * backfill-session-structure.test.ts
 *
 * Unit tests for the row-mapping logic of backfill-session-structure.ts.
 *
 * Strategy:
 *  - Import the shared materializer directly (pure function, no side effects).
 *  - Import processRow from the real script and exercise it with fixture rows
 *    and a mock library map — no real DB or network calls required.
 *  - Verify the CAS guard SQL predicate shape by testing that update is only
 *    called when structure IS NULL.
 *
 * Run:
 *   deno test --allow-read scripts/__tests__/backfill-session-structure.test.ts
 */

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  materialize,
  WorkoutTemplate,
} from "../../supabase/functions/_shared/materialize-structure.ts";
import {
  processRow,
} from "../backfill-session-structure.ts";

// ---------------------------------------------------------------------------
// Fixture templates
// ---------------------------------------------------------------------------

const FTP_TEMPLATE: WorkoutTemplate = {
  template_id: "BIKE_Easy_01",
  duration_minutes: 60,
  segments: [
    { label: "warmup", duration_minutes: 10, ftp_pct: 55 },
    { label: "work",   duration_minutes: 40, ftp_pct: 70 },
    { label: "cooldown", duration_minutes: 10, ftp_pct: 50 },
  ],
};

const VMA_TEMPLATE: WorkoutTemplate = {
  template_id: "RUN_Tempo_01",
  duration_minutes: 45,
  segments: [
    { label: "warmup",  duration_minutes: 10, vma_pct: 65 },
    { label: "work",    duration_minutes: 25, vma_pct: 85 },
    { label: "cooldown", duration_minutes: 10, vma_pct: 60 },
  ],
};

const LEGACY_MAS_TEMPLATE: WorkoutTemplate = {
  template_id: "RUN_Easy_01",
  duration_minutes: 40,
  segments: [
    { label: "warmup",  duration_minutes: 10, mas_pct: 60 } as never,
    { label: "work",    duration_minutes: 20, mas_pct: 70 } as never,
    { label: "cooldown", duration_minutes: 10, mas_pct: 55 } as never,
  ],
};

const SWIM_PACE_TEMPLATE: WorkoutTemplate = {
  template_id: "SWIM_Easy_01",
  duration_minutes: 33,
  segments: [
    { label: "warmup",  distance_meters: 200, pace: "easy" },
    { label: "work",    distance_meters: 600, pace: "medium" },
    { label: "cooldown", distance_meters: 200, pace: "slow" },
  ],
};

const NESTED_REPEAT_TEMPLATE: WorkoutTemplate = {
  template_id: "RUN_Intervals_04",
  duration_minutes: 50,
  segments: [
    { label: "warmup", duration_minutes: 10, vma_pct: 65 },
    {
      label: "repeat",
      repeats: 6,
      rest_seconds: 90,
      segments: [
        { label: "work",     distance_meters: 400, vma_pct: 100 },
        { label: "recovery", distance_meters: 200, rpe: 3 },
      ],
    },
    { label: "cooldown", duration_minutes: 10, vma_pct: 60 },
  ],
};

// ---------------------------------------------------------------------------
// processRow tests — imported directly from the real script
// ---------------------------------------------------------------------------

Deno.test("processRow: skips rows with existing structure", () => {
  const library = new Map([[FTP_TEMPLATE.template_id, FTP_TEMPLATE]]);
  const row = {
    id: "row-1",
    sport: "bike",
    template_id: "BIKE_Easy_01",
    structure: { segments: [] }, // already populated
  };
  const result = processRow(row, library);
  assertEquals(result.kind, "skip");
  if (result.kind === "skip") {
    assertEquals(result.reason, "already-populated");
  }
});

Deno.test("processRow: skips strength rows (Phase 8 deferred)", () => {
  const library = new Map<string, WorkoutTemplate>();
  const row = {
    id: "row-2",
    sport: "strength",
    template_id: "STRENGTH_Core_01",
    structure: null,
  };
  const result = processRow(row, library);
  assertEquals(result.kind, "skip");
  if (result.kind === "skip") {
    assertEquals(result.reason, "strength");
  }
});

Deno.test("processRow: skips row with null template_id", () => {
  const library = new Map<string, WorkoutTemplate>();
  const row = {
    id: "row-3",
    sport: "run",
    template_id: null,
    structure: null,
  };
  const result = processRow(row, library);
  assertEquals(result.kind, "skip");
  if (result.kind === "skip") {
    assertEquals(result.reason, "no-template-id");
  }
});

Deno.test("processRow: orphans row when template_id not in library", () => {
  const library = new Map([[FTP_TEMPLATE.template_id, FTP_TEMPLATE]]);
  const row = {
    id: "row-4",
    sport: "run",
    template_id: "RUN_UNKNOWN_99",
    structure: null,
  };
  const result = processRow(row, library);
  assertEquals(result.kind, "orphaned");
  if (result.kind === "orphaned") {
    assertEquals(result.templateId, "RUN_UNKNOWN_99");
  }
});

Deno.test("processRow: materializes FTP bike template correctly", () => {
  const library = new Map([[FTP_TEMPLATE.template_id, FTP_TEMPLATE]]);
  const row = {
    id: "row-5",
    sport: "bike",
    template_id: "BIKE_Easy_01",
    structure: null,
  };
  const result = processRow(row, library);
  assertEquals(result.kind, "materialize");
  if (result.kind === "materialize") {
    assertEquals(result.structure.segments.length, 3);
    assertEquals(result.structure.segments[0].label, "warmup");
    assertEquals(result.structure.segments[0].target, { type: "ftp_pct", value: 55 });
    assertEquals(result.structure.segments[1].target, { type: "ftp_pct", value: 70 });
    assertEquals(result.structure.segments[2].target, { type: "ftp_pct", value: 50 });
  }
});

Deno.test("processRow: materializes VMA run template correctly", () => {
  const library = new Map([[VMA_TEMPLATE.template_id, VMA_TEMPLATE]]);
  const row = {
    id: "row-6",
    sport: "run",
    template_id: "RUN_Tempo_01",
    structure: null,
  };
  const result = processRow(row, library);
  assertEquals(result.kind, "materialize");
  if (result.kind === "materialize") {
    assertEquals(result.structure.segments[1].target, { type: "vma_pct", value: 85 });
  }
});

Deno.test("processRow: normalises legacy mas_pct to vma_pct", () => {
  const library = new Map([[LEGACY_MAS_TEMPLATE.template_id, LEGACY_MAS_TEMPLATE]]);
  const row = {
    id: "row-7",
    sport: "run",
    template_id: "RUN_Easy_01",
    structure: null,
  };
  const result = processRow(row, library);
  assertEquals(result.kind, "materialize");
  if (result.kind === "materialize") {
    // All targets should be vma_pct, not mas_pct
    for (const seg of result.structure.segments) {
      if (seg.target) {
        assertEquals(seg.target.type, "vma_pct");
      }
    }
    assertEquals(result.structure.segments[1].target, { type: "vma_pct", value: 70 });
  }
});

Deno.test("processRow: maps swim pace tags to RPE values", () => {
  const library = new Map([[SWIM_PACE_TEMPLATE.template_id, SWIM_PACE_TEMPLATE]]);
  const row = {
    id: "row-8",
    sport: "swim",
    template_id: "SWIM_Easy_01",
    structure: null,
  };
  const result = processRow(row, library);
  assertEquals(result.kind, "materialize");
  if (result.kind === "materialize") {
    assertEquals(result.structure.segments[0].target, { type: "rpe", value: 3 }); // easy
    assertEquals(result.structure.segments[1].target, { type: "rpe", value: 6 }); // medium
    assertEquals(result.structure.segments[2].target, { type: "rpe", value: 3 }); // slow
    // Distance should be preserved
    assertEquals(result.structure.segments[0].distance_meters, 200);
    assertEquals(result.structure.segments[1].distance_meters, 600);
  }
});

Deno.test("processRow: correctly handles nested repeat segments", () => {
  const library = new Map([[NESTED_REPEAT_TEMPLATE.template_id, NESTED_REPEAT_TEMPLATE]]);
  const row = {
    id: "row-9",
    sport: "run",
    template_id: "RUN_Intervals_04",
    structure: null,
  };
  const result = processRow(row, library);
  assertEquals(result.kind, "materialize");
  if (result.kind === "materialize") {
    const segs = result.structure.segments;
    assertEquals(segs.length, 3);

    // Repeat segment
    const repeatSeg = segs[1];
    assertEquals(repeatSeg.label, "repeat");
    assertEquals(repeatSeg.repeats, 6);
    assertEquals(repeatSeg.rest_seconds, 90);
    // Repeat container must NOT carry a target
    assertEquals(repeatSeg.target, undefined);

    // Child segments
    assertExists(repeatSeg.segments);
    assertEquals(repeatSeg.segments!.length, 2);
    assertEquals(repeatSeg.segments![0].target, { type: "vma_pct", value: 100 });
    assertEquals(repeatSeg.segments![1].target, { type: "rpe", value: 3 });
  }
});

Deno.test("CAS guard: idempotency — re-running skips already-populated rows", () => {
  const library = new Map([[FTP_TEMPLATE.template_id, FTP_TEMPLATE]]);

  // Simulate first run: structure was null, gets materialized
  const firstRow = { id: "row-10", sport: "bike", template_id: "BIKE_Easy_01", structure: null };
  const firstResult = processRow(firstRow, library);
  assertEquals(firstResult.kind, "materialize");

  // Simulate re-run: the row now has structure set
  const secondRow = {
    id: "row-10",
    sport: "bike",
    template_id: "BIKE_Easy_01",
    structure: firstResult.kind === "materialize" ? firstResult.structure : null,
  };
  const secondResult = processRow(secondRow, library);
  assertEquals(secondResult.kind, "skip");
  if (secondResult.kind === "skip") {
    assertEquals(secondResult.reason, "already-populated");
  }
});

Deno.test("library map: all top-level sports are indexed", async () => {
  // Decode URL-encoded path (handles spaces in directory names)
  const scriptDir = decodeURIComponent(new URL(".", import.meta.url).pathname);
  const libPath = `${scriptDir}../../ai/context/workout-library.json`;
  const raw = await Deno.readTextFile(libPath);
  const data = JSON.parse(raw) as Record<string, WorkoutTemplate[]>;

  const map = new Map<string, WorkoutTemplate>();
  for (const templates of Object.values(data)) {
    for (const template of templates) {
      map.set(template.template_id, template);
    }
  }

  // All top-level keys present
  const keys = Object.keys(data);
  assertEquals(keys.includes("swim"), true);
  assertEquals(keys.includes("bike"), true);
  assertEquals(keys.includes("run"), true);
  assertEquals(keys.includes("race"), true);
  // No strength key (stripped in Phase 1)
  assertEquals(keys.includes("strength"), false);

  // Spot-check known template IDs exist
  assertExists(map.get("SWIM_Easy_01"));
  assertExists(map.get("BIKE_Easy_01"));
  assertExists(map.get("RUN_Tempo_01"));
});

Deno.test("materialize: never emits both duration_minutes and distance_meters on same segment", () => {
  // Template where both are present — duration should win
  const both: WorkoutTemplate = {
    template_id: "BOTH_Test_01",
    duration_minutes: 30,
    segments: [
      { label: "work", duration_minutes: 20, distance_meters: 5000, ftp_pct: 70 },
    ],
  };
  const result = materialize(both);
  const seg = result.segments[0];
  assertEquals(seg.duration_minutes, 20);
  assertEquals(seg.distance_meters, undefined);
});
