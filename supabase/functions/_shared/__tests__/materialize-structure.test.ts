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
  assertThrows,
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

// ---------------------------------------------------------------------------
// Negative-path tests (error handling)
// ---------------------------------------------------------------------------

Deno.test("paceToRpe: unknown pace tag throws", () => {
  const tpl = simpleTemplate("SWIM_Unknown_01", [
    { label: "work", distance_meters: 100, pace: "tempo" },
  ]);
  assertThrows(
    () => materialize(tpl),
    Error,
    'Unknown swim pace tag: "tempo"'
  );
});

Deno.test("validateLabel: invalid label throws", () => {
  const tpl = simpleTemplate("BAD_Label_01", [
    { label: "foo", duration_minutes: 5 },
  ]);
  assertThrows(
    () => materialize(tpl),
    Error,
    'Invalid segment label: "foo"'
  );
});

Deno.test("hr_zone: non-integer value 2.7 rounds to 3", () => {
  const tpl = simpleTemplate("RUN_HR_01", [
    { label: "work", duration_minutes: 30, hr_zone: 2.7 },
  ]);
  const result = materialize(tpl);
  assertEquals(result.segments[0].target, { type: "hr_zone", value: 3 });
});

Deno.test("repeat container: intensity field does not produce a top-level target", () => {
  const tpl = simpleTemplate("BIKE_Repeat_01", [
    {
      label: "repeat",
      repeats: 3,
      ftp_pct: 80, // intensity on container — must NOT appear as target
      segments: [
        { label: "work", duration_minutes: 5, ftp_pct: 90 },
        { label: "recovery", duration_minutes: 2, ftp_pct: 55 },
      ],
    },
  ]);
  const result = materialize(tpl);
  const container = result.segments[0];
  assertEquals(container.repeats, 3);
  assertEquals(container.target, undefined, "repeat container must not carry target");
  // Leaf children still get their targets
  assertEquals(container.segments![0].target, { type: "ftp_pct", value: 90 });
  assertEquals(container.segments![1].target, { type: "ftp_pct", value: 55 });
});

// ---------------------------------------------------------------------------
// Phase 2 — New Target types (DRO-298)
// ---------------------------------------------------------------------------

// --- hr_pct_max ---

Deno.test("hr_pct_max: single value produces hr_pct_max target", () => {
  const tpl = simpleTemplate("RUN_HR_CAP_01", [
    { label: "work", duration_minutes: 45, hr_pct_max: 78 },
  ]);
  assertEquals(
    materialize(tpl).segments[0].target,
    { type: "hr_pct_max", value: 78 },
  );
});

Deno.test("hr_pct_max: min+max range form produces { type, min, max }", () => {
  const tpl = simpleTemplate("RUN_HR_RANGE_01", [
    { label: "work", duration_minutes: 30, hr_pct_max_min: 65, hr_pct_max_max: 78 },
  ]);
  assertEquals(
    materialize(tpl).segments[0].target,
    { type: "hr_pct_max", min: 65, max: 78 },
  );
});

// --- hr_zone clamping ---

Deno.test("hr_zone: value 1 (lower boundary) resolves to zone 1", () => {
  const tpl = simpleTemplate("RUN_HR_Z1", [
    { label: "work", duration_minutes: 30, hr_zone: 1 },
  ]);
  assertEquals(materialize(tpl).segments[0].target, { type: "hr_zone", value: 1 });
});

Deno.test("hr_zone: value 5 (upper boundary) resolves to zone 5", () => {
  const tpl = simpleTemplate("RUN_HR_Z5", [
    { label: "work", duration_minutes: 10, hr_zone: 5 },
  ]);
  assertEquals(materialize(tpl).segments[0].target, { type: "hr_zone", value: 5 });
});

Deno.test("hr_zone: input 0 clamps to zone 1", () => {
  const tpl = simpleTemplate("RUN_HR_CLAMP_LOW", [
    { label: "work", duration_minutes: 10, hr_zone: 0 },
  ]);
  assertEquals(materialize(tpl).segments[0].target, { type: "hr_zone", value: 1 });
});

Deno.test("hr_zone: input 6 clamps to zone 5", () => {
  const tpl = simpleTemplate("RUN_HR_CLAMP_HIGH", [
    { label: "work", duration_minutes: 10, hr_zone: 6 },
  ]);
  assertEquals(materialize(tpl).segments[0].target, { type: "hr_zone", value: 5 });
});

// --- power_watts ---

Deno.test("power_watts: single value produces power_watts target", () => {
  const tpl = simpleTemplate("BIKE_POWER_01", [
    { label: "work", duration_minutes: 15, power_watts: 260 },
  ]);
  assertEquals(
    materialize(tpl).segments[0].target,
    { type: "power_watts", value: 260 },
  );
});

Deno.test("power_watts: min+max range form produces { type, min, max }", () => {
  const tpl = simpleTemplate("BIKE_POWER_RANGE_01", [
    { label: "work", duration_minutes: 40, power_watts_min: 230, power_watts_max: 235 },
  ]);
  assertEquals(
    materialize(tpl).segments[0].target,
    { type: "power_watts", min: 230, max: 235 },
  );
});

// --- pace_per_km ---

Deno.test("pace_per_km: string passthrough produces pace_per_km target", () => {
  const tpl = simpleTemplate("RUN_PACE_01", [
    { label: "work", distance_meters: 400, pace_per_km: "4:15" },
  ]);
  assertEquals(
    materialize(tpl).segments[0].target,
    { type: "pace_per_km", value: "4:15" },
  );
});

// --- pace_per_100m ---

Deno.test("pace_per_100m: string passthrough produces pace_per_100m target", () => {
  const tpl = simpleTemplate("SWIM_PACE100_01", [
    { label: "work", distance_meters: 150, pace_per_100m: "1:50" },
  ]);
  assertEquals(
    materialize(tpl).segments[0].target,
    { type: "pace_per_100m", value: "1:50" },
  );
});

// --- Distance-based interval with distance-based recovery ---

Deno.test("distance interval: work 400m + distance recovery 400m both materialise correctly", () => {
  const tpl = simpleTemplate("RUN_400M_INTERVALS", [
    {
      label: "repeat",
      repeats: 5,
      segments: [
        { label: "work", distance_meters: 400, pace_per_km: "3:35" },
      ],
      recovery: { label: "recovery", distance_meters: 400, pace_per_km: "6:00" },
    },
  ]);

  const result = materialize(tpl);
  const repeat = result.segments[0];
  assertEquals(repeat.repeats, 5);

  const work = repeat.segments![0];
  assertEquals(work.distance_meters, 400);
  assertEquals(work.target, { type: "pace_per_km", value: "3:35" });

  const rec = repeat.recovery!;
  assertEquals(rec.label, "recovery");
  assertEquals(rec.distance_meters, 400);
  assertEquals(rec.target, { type: "pace_per_km", value: "6:00" });
});

// --- Nested repeats with HR-based children (over-under bike pattern) ---

Deno.test("nested repeats with HR children: BIKE_OU over-under structure materialises correctly", () => {
  const tpl: WorkoutTemplate = {
    template_id: "BIKE_OU_TEST",
    duration_minutes: 67,
    segments: [
      { label: "warmup", duration_minutes: 15, ftp_pct: 65, cadence_rpm: 90 },
      {
        label: "repeat",
        repeats: 2,
        segments: [
          {
            label: "repeat",
            repeats: 3,
            segments: [
              { label: "work", duration_minutes: 1, ftp_pct: 110, cadence_rpm: 100 },
              { label: "recovery", duration_minutes: 3, ftp_pct: 95, cadence_rpm: 90 },
            ],
          },
        ],
        recovery: { label: "recovery", duration_minutes: 6, ftp_pct: 55, cadence_rpm: 85 },
      },
      { label: "cooldown", duration_minutes: 10, ftp_pct: 55, cadence_rpm: 85 },
    ],
  };

  const result = materialize(tpl);
  assertEquals(result.segments.length, 3);

  const outerRepeat = result.segments[1];
  assertEquals(outerRepeat.repeats, 2);
  assertExists(outerRepeat.recovery);
  assertEquals(outerRepeat.recovery!.target, { type: "ftp_pct", value: 55 });

  const innerRepeat = outerRepeat.segments![0];
  assertEquals(innerRepeat.repeats, 3);

  const overSeg = innerRepeat.segments![0];
  assertEquals(overSeg.label, "work");
  assertEquals(overSeg.target, { type: "ftp_pct", value: 110 });

  const underSeg = innerRepeat.segments![1];
  assertEquals(underSeg.label, "recovery");
  assertEquals(underSeg.target, { type: "ftp_pct", value: 95 });
});

// --- STRENGTH_NOTES_ONLY ---

Deno.test("STRENGTH_NOTES_ONLY: materialises to { segments: [] } without throwing", () => {
  const tpl: WorkoutTemplate = {
    template_id: "STRENGTH_NOTES_ONLY",
    duration_minutes: 30,
    segments: [],
  };
  const result = materialize(tpl);
  assertEquals(result.segments.length, 0, "segments must be empty");
});

// --- ftp_pct range form ---

Deno.test("ftp_pct: min+max range form produces { type, min, max }", () => {
  const tpl = simpleTemplate("BIKE_SS_RANGE_01", [
    { label: "work", duration_minutes: 6, ftp_pct_min: 88, ftp_pct_max: 93, cadence_rpm: 90 },
  ]);
  assertEquals(
    materialize(tpl).segments[0].target,
    { type: "ftp_pct", min: 88, max: 93 },
  );
});
