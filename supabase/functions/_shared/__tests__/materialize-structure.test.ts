/**
 * materialize-structure.test.ts
 *
 * Deno built-in test runner.
 * Run from the repo root:
 *   deno test supabase/functions/_shared/__tests__/materialize-structure.test.ts
 *
 * Tests cover every requirement called out in DRO-215:
 *   ✓ ftp_pct template (single value)
 *   ✓ vma_pct template (canonical key)
 *   ✓ mas_pct legacy key → vma_pct at materialisation
 *   ✓ swim pace tags → RPE mapping (all 5 distinct values)
 *   ✓ nested repeats (3 levels — SWIM_Tempo_02 fixture)
 *   ✓ cadence_rpm preservation
 *   ✓ cue preservation
 *   ✓ RUN_Easy_07 edge case: duration + distance → keep duration only
 */

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { materialize, type WorkoutTemplate } from "../materialize-structure.ts";

// ---------------------------------------------------------------------------
// Fixture helpers
// ---------------------------------------------------------------------------

function simpleTemplate(
  id: string,
  segments: WorkoutTemplate["segments"]
): WorkoutTemplate {
  return { template_id: id, duration_minutes: 45, segments };
}

// ---------------------------------------------------------------------------
// ftp_pct template
// ---------------------------------------------------------------------------

Deno.test("ftp_pct: single-value target is preserved", () => {
  const tpl = simpleTemplate("BIKE_Tempo_01", [
    { label: "warmup", duration_minutes: 15, ftp_pct: 70, cadence_rpm: 90 },
    { label: "work", duration_minutes: 20, ftp_pct: 88, cadence_rpm: 90 },
    { label: "cooldown", duration_minutes: 10, ftp_pct: 65, cadence_rpm: 90 },
  ]);

  const result = materialize(tpl);
  assertEquals(result.segments.length, 3);

  const warmup = result.segments[0];
  assertEquals(warmup.label, "warmup");
  assertEquals(warmup.duration_minutes, 15);
  assertEquals(warmup.target, { type: "ftp_pct", value: 70 });
  assertEquals(warmup.cadence_rpm, 90);
  assertEquals(warmup.distance_meters, undefined);
});

// ---------------------------------------------------------------------------
// vma_pct template (canonical key)
// ---------------------------------------------------------------------------

Deno.test("vma_pct: canonical key produces vma_pct target", () => {
  const tpl = simpleTemplate("RUN_Tempo_01", [
    { label: "warmup", duration_minutes: 15, vma_pct: 75 },
    { label: "work", duration_minutes: 20, vma_pct: 90 },
    { label: "cooldown", duration_minutes: 10, vma_pct: 70 },
  ]);

  const result = materialize(tpl);
  assertEquals(result.segments[1].target, { type: "vma_pct", value: 90 });
});

// ---------------------------------------------------------------------------
// mas_pct legacy key → vma_pct rename
// ---------------------------------------------------------------------------

Deno.test("mas_pct: legacy key is silently renamed to vma_pct", () => {
  const tpl = simpleTemplate("RUN_Tempo_01_legacy", [
    { label: "warmup", duration_minutes: 15, mas_pct: 75 },
    { label: "work", duration_minutes: 20, mas_pct: 90 },
    { label: "cooldown", duration_minutes: 10, mas_pct: 70 },
  ]);

  const result = materialize(tpl);
  // All three segments must have type: vma_pct — no mas_pct in output
  for (const seg of result.segments) {
    assertExists(seg.target);
    assertEquals(seg.target!.type, "vma_pct");
  }
  assertEquals(result.segments[1].target, { type: "vma_pct", value: 90 });
});

// ---------------------------------------------------------------------------
// Swim pace tags → RPE
// ---------------------------------------------------------------------------

Deno.test("swim pace: slow → RPE 3", () => {
  const tpl = simpleTemplate("SWIM_Easy_01", [
    { label: "warmup", distance_meters: 200, pace: "slow" },
  ]);
  assertEquals(materialize(tpl).segments[0].target, { type: "rpe", value: 3 });
});

Deno.test("swim pace: easy → RPE 3", () => {
  const tpl = simpleTemplate("SWIM_Easy_01b", [
    { label: "warmup", distance_meters: 200, pace: "easy" },
  ]);
  assertEquals(materialize(tpl).segments[0].target, { type: "rpe", value: 3 });
});

Deno.test("swim pace: medium → RPE 6", () => {
  const tpl = simpleTemplate("SWIM_Tempo_01", [
    { label: "work", distance_meters: 100, pace: "medium" },
  ]);
  assertEquals(materialize(tpl).segments[0].target, { type: "rpe", value: 6 });
});

Deno.test("swim pace: quick → RPE 7", () => {
  const tpl = simpleTemplate("SWIM_Tempo_02x", [
    { label: "work", distance_meters: 100, pace: "quick" },
  ]);
  assertEquals(materialize(tpl).segments[0].target, { type: "rpe", value: 7 });
});

Deno.test("swim pace: threshold → RPE 7", () => {
  const tpl = simpleTemplate("SWIM_Tempo_03x", [
    { label: "work", distance_meters: 100, pace: "threshold" },
  ]);
  assertEquals(materialize(tpl).segments[0].target, { type: "rpe", value: 7 });
});

Deno.test("swim pace: fast → RPE 8", () => {
  const tpl = simpleTemplate("SWIM_Intervals_01", [
    { label: "work", distance_meters: 50, pace: "fast" },
  ]);
  assertEquals(materialize(tpl).segments[0].target, { type: "rpe", value: 8 });
});

Deno.test("swim pace: very_quick → RPE 9", () => {
  const tpl = simpleTemplate("SWIM_Intervals_02", [
    { label: "work", distance_meters: 50, pace: "very_quick" },
  ]);
  assertEquals(materialize(tpl).segments[0].target, { type: "rpe", value: 9 });
});

// ---------------------------------------------------------------------------
// Nested repeats (3 levels) — SWIM_Tempo_02 fixture
// ---------------------------------------------------------------------------

Deno.test("nested repeats: 3-level structure is preserved correctly (SWIM_Tempo_02)", () => {
  const tpl: WorkoutTemplate = {
    template_id: "SWIM_Tempo_02",
    duration_minutes: 38,
    segments: [
      { label: "warmup", distance_meters: 300, pace: "slow" },
      {
        label: "repeat",
        repeats: 3,
        segments: [
          {
            label: "repeat",
            repeats: 4,
            segments: [
              { label: "work", distance_meters: 100, pace: "medium" },
            ],
            rest_seconds: 15,
          },
        ],
        recovery: { label: "recovery", distance_meters: 100, pace: "slow" },
      },
      { label: "cooldown", distance_meters: 200, pace: "slow" },
    ],
  };

  const result = materialize(tpl);
  assertEquals(result.segments.length, 3);

  // Level 1 repeat
  const outerRepeat = result.segments[1];
  assertEquals(outerRepeat.label, "repeat");
  assertEquals(outerRepeat.repeats, 3);
  assertExists(outerRepeat.recovery);
  assertEquals(outerRepeat.recovery!.label, "recovery");
  assertEquals(outerRepeat.recovery!.target, { type: "rpe", value: 3 }); // pace: "slow" → 3

  // Level 2 repeat
  assertExists(outerRepeat.segments);
  assertEquals(outerRepeat.segments!.length, 1);
  const innerRepeat = outerRepeat.segments![0];
  assertEquals(innerRepeat.label, "repeat");
  assertEquals(innerRepeat.repeats, 4);
  assertEquals(innerRepeat.rest_seconds, 15);

  // Level 3 leaf
  assertExists(innerRepeat.segments);
  assertEquals(innerRepeat.segments!.length, 1);
  const leaf = innerRepeat.segments![0];
  assertEquals(leaf.label, "work");
  assertEquals(leaf.distance_meters, 100);
  assertEquals(leaf.target, { type: "rpe", value: 6 }); // pace: "medium" → 6
});

// ---------------------------------------------------------------------------
// cadence_rpm preservation
// ---------------------------------------------------------------------------

Deno.test("cadence_rpm: preserved verbatim from source segment", () => {
  const tpl = simpleTemplate("BIKE_Easy_01", [
    { label: "warmup", duration_minutes: 10, ftp_pct: 65, cadence_rpm: 85 },
    { label: "work", duration_minutes: 30, ftp_pct: 72, cadence_rpm: 92 },
    { label: "cooldown", duration_minutes: 5, ftp_pct: 60, cadence_rpm: 85 },
  ]);

  const result = materialize(tpl);
  assertEquals(result.segments[0].cadence_rpm, 85);
  assertEquals(result.segments[1].cadence_rpm, 92);
  assertEquals(result.segments[2].cadence_rpm, 85);
});

Deno.test("cadence_rpm: absent when not in source", () => {
  const tpl = simpleTemplate("RUN_Easy_01", [
    { label: "work", duration_minutes: 30, vma_pct: 65 },
  ]);
  assertEquals(materialize(tpl).segments[0].cadence_rpm, undefined);
});

// ---------------------------------------------------------------------------
// cue preservation
// ---------------------------------------------------------------------------

Deno.test("cue: preserved verbatim from source segment", () => {
  const tpl = simpleTemplate("RUN_Drills_01", [
    {
      label: "drill",
      duration_minutes: 5,
      cue: "High knees — 20m, walk back, repeat x3",
    },
  ]);
  const result = materialize(tpl);
  assertEquals(
    result.segments[0].cue,
    "High knees — 20m, walk back, repeat x3"
  );
});

// ---------------------------------------------------------------------------
// RUN_Easy_07 edge case: duration + distance coexist → keep duration, drop distance
// ---------------------------------------------------------------------------

Deno.test("RUN_Easy_07: when duration_minutes and distance_meters both present, duration wins", () => {
  const tpl: WorkoutTemplate = {
    template_id: "RUN_Easy_07",
    duration_minutes: 45,
    segments: [
      {
        label: "work",
        duration_minutes: 45,
        distance_meters: 8000, // <-- must be dropped
        mas_pct: 63,           // <-- legacy key, must become vma_pct: 63
      },
    ],
  };

  const result = materialize(tpl);
  const seg = result.segments[0];

  assertEquals(seg.duration_minutes, 45, "duration_minutes must be kept");
  assertEquals(seg.distance_meters, undefined, "distance_meters must be dropped");
  assertEquals(seg.target, { type: "vma_pct", value: 63 }, "mas_pct must be renamed to vma_pct");
});

// ---------------------------------------------------------------------------
// No-target segment (drill / skill work)
// ---------------------------------------------------------------------------

Deno.test("target: absent when no intensity fields are present", () => {
  const tpl = simpleTemplate("STRENGTH_Drill_01", [
    { label: "work", duration_minutes: 5, cue: "Front plank" },
    { label: "rest", rest_seconds: 30 },
  ]);

  const result = materialize(tpl);
  assertEquals(result.segments[0].target, undefined);
  assertEquals(result.segments[1].target, undefined);
  assertEquals(result.segments[1].rest_seconds, 30);
});

// ---------------------------------------------------------------------------
// duration_seconds conversion
// ---------------------------------------------------------------------------

Deno.test("duration_seconds: converted to duration_minutes (ceiling)", () => {
  const tpl = simpleTemplate("STRENGTH_Easy_01", [
    { label: "work", duration_seconds: 45 }, // 45s → ceil(0.75) = 1 min
    { label: "work", duration_seconds: 60 }, // 60s → 1 min
    { label: "work", duration_seconds: 90 }, // 90s → 2 min (ceil(1.5))
  ]);

  const result = materialize(tpl);
  assertEquals(result.segments[0].duration_minutes, 1);
  assertEquals(result.segments[1].duration_minutes, 1);
  assertEquals(result.segments[2].duration_minutes, 2);
  // No distance_meters on any
  for (const seg of result.segments) {
    assertEquals(seg.distance_meters, undefined);
  }
});
