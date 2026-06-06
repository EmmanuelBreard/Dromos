/**
 * materialize-structure.ts
 *
 * Pure function that converts a legacy WorkoutTemplate (from workout-library.json)
 * into the canonical SessionStructure JSON shape used in plan_sessions.structure.
 *
 * IMPORTANT: No Deno.env, no Supabase client, no runtime dependencies.
 * This module is importable by:
 *   - Edge Functions (Deno runtime)
 *   - Standalone Deno CLI scripts (backfill script, tests) via relative path
 *
 * Design decisions encoded here:
 *   - duration_minutes XOR distance_meters: when both present, duration wins.
 *   - mas_pct is silently renamed to vma_pct at materialisation time so legacy
 *     JSON keys continue to work even if workout-library.json still has old names.
 *   - Swim pace tags map to RPE values (CSS resolution is deferred to Phase 2).
 *   - cadence_rpm and cue are preserved verbatim from the source segment.
 *   - Nested repeat segments are handled recursively (unlimited depth).
 */

// ---------------------------------------------------------------------------
// Types — SessionStructure shape (mirrors Swift model / DB schema)
// ---------------------------------------------------------------------------

export type Target =
  | { type: "ftp_pct"; value: number }
  | { type: "ftp_pct"; min: number; max: number }
  | { type: "vma_pct"; value: number }
  | { type: "vma_pct"; min: number; max: number }
  | { type: "css_pct"; value: number }
  | { type: "css_pct"; min: number; max: number }
  | { type: "rpe"; value: number }
  | { type: "hr_zone"; value: 1 | 2 | 3 | 4 | 5 }
  | { type: "hr_pct_max"; value: number }
  | { type: "hr_pct_max"; min: number; max: number }
  | { type: "power_watts"; value: number }
  | { type: "power_watts"; min: number; max: number }
  | { type: "pace_per_km"; value: string }
  | { type: "pace_per_100m"; value: string };

export type SegmentLabel =
  | "warmup"
  | "work"
  | "recovery"
  | "cooldown"
  | "repeat"
  | "rest"
  | "drill";

export interface StructureSegment {
  label: SegmentLabel;
  /** Exactly one of duration_minutes or distance_meters — never both. */
  duration_minutes?: number;
  distance_meters?: number;
  target?: Target;
  cadence_rpm?: number;
  cue?: string;
  /** For repeat segments: how many times to execute the children. */
  repeats?: number;
  /** Seconds of passive rest between repeat iterations. */
  rest_seconds?: number;
  /** Active recovery segment between repeat iterations (alternative to rest_seconds). */
  recovery?: StructureSegment;
  /** Child segments (present when repeats is set). */
  segments?: StructureSegment[];
}

export interface SessionStructure {
  segments: StructureSegment[];
}

// ---------------------------------------------------------------------------
// Source template types — shape from workout-library.json
// ---------------------------------------------------------------------------

interface SourceSegment {
  label: string;
  // Duration
  duration_minutes?: number;
  duration_seconds?: number;
  // Distance
  distance_meters?: number;
  // Intensity — legacy and new names
  ftp_pct?: number;
  /** Range form for ftp_pct (e.g. sweetspot 88-93%). Emits Target { min, max }. */
  ftp_pct_min?: number;
  ftp_pct_max?: number;
  mas_pct?: number;   // legacy name — materializer normalises to vma_pct
  vma_pct?: number;
  css_pct?: number;
  rpe?: number;
  pace?: string;      // swim pace tag: slow | easy | medium | quick | threshold | fast | very_quick
  hr_zone?: number;
  hr_pct_max?: number;
  /** Range form for hr_pct_max (cap range). Emits Target { min, max }. */
  hr_pct_max_min?: number;
  hr_pct_max_max?: number;
  /** Explicit watts targets — Phase 2. */
  power_watts?: number;
  power_watts_min?: number;
  power_watts_max?: number;
  /** Absolute run pace string e.g. "4:15" — Phase 2. */
  pace_per_km?: string;
  /** Absolute swim pace string e.g. "1:50" per 100m — Phase 2. */
  pace_per_100m?: string;
  // Cadence / coaching
  cadence_rpm?: number;
  cue?: string;
  // Repeats
  repeats?: number;
  rest_seconds?: number;
  recovery?: SourceSegment;
  segments?: SourceSegment[];
}

export interface WorkoutTemplate {
  template_id: string;
  duration_minutes: number;
  segments: SourceSegment[];
}

// ---------------------------------------------------------------------------
// Swim pace → RPE mapping (Phase 1 — CSS deferred to Phase 2)
// ---------------------------------------------------------------------------

const SWIM_PACE_TO_RPE: Record<string, number> = {
  slow: 3,
  easy: 3,
  medium: 6,
  quick: 7,
  threshold: 7,
  fast: 8,
  very_quick: 9,
};

// ---------------------------------------------------------------------------
// Core materialisation logic
// ---------------------------------------------------------------------------

const VALID_LABELS = new Set<SegmentLabel>([
  "warmup", "work", "recovery", "cooldown", "repeat", "rest", "drill"
]);

function validateLabel(raw: string): SegmentLabel {
  if (!VALID_LABELS.has(raw as SegmentLabel)) {
    throw new Error(`Invalid segment label: "${raw}". Valid: ${[...VALID_LABELS].join(", ")}`);
  }
  return raw as SegmentLabel;
}

/**
 * Converts a pace tag to an RPE target.
 * Throws on unknown tags — unknown pace indicates a data error in the template.
 */
function paceToRpe(pace: string): Target {
  const rpe = SWIM_PACE_TO_RPE[pace.toLowerCase()];
  if (rpe === undefined) {
    throw new Error(`Unknown swim pace tag: "${pace}". Valid: ${Object.keys(SWIM_PACE_TO_RPE).join(", ")}`);
  }
  return { type: "rpe", value: rpe };
}

/**
 * Resolves the source segment's intensity into a Target object.
 *
 * Priority order (Phase 1 + Phase 2 extensions):
 *   ftp_pct (range or single) →
 *   vma_pct / mas_pct (legacy alias) →
 *   css_pct →
 *   rpe →
 *   hr_zone →
 *   hr_pct_max (range or single) →
 *   power_watts (range or single) →
 *   pace_per_km →
 *   pace_per_100m →
 *   swim pace tag → RPE.
 *
 * Phase 2 adds: range forms (ftp_pct_min/max, hr_pct_max_min/max,
 * power_watts / power_watts_min/max), pace_per_km, pace_per_100m.
 */
function resolveTarget(seg: SourceSegment): Target | undefined {
  // ftp_pct — range form takes priority over single value
  if (seg.ftp_pct_min !== undefined && seg.ftp_pct_max !== undefined) {
    return { type: "ftp_pct", min: seg.ftp_pct_min, max: seg.ftp_pct_max };
  }
  if (seg.ftp_pct !== undefined) {
    return { type: "ftp_pct", value: seg.ftp_pct };
  }

  // vma_pct — accept both the canonical key and the legacy mas_pct alias
  const vmaPct = seg.vma_pct ?? seg.mas_pct;
  if (vmaPct !== undefined) {
    return { type: "vma_pct", value: vmaPct };
  }

  if (seg.css_pct !== undefined) {
    return { type: "css_pct", value: seg.css_pct };
  }

  if (seg.rpe !== undefined) {
    return { type: "rpe", value: seg.rpe };
  }

  if (seg.hr_zone !== undefined) {
    // Round then clamp to valid 1-5 range (handles non-integer input gracefully)
    const z = Math.max(1, Math.min(5, Math.round(seg.hr_zone))) as 1 | 2 | 3 | 4 | 5;
    return { type: "hr_zone", value: z };
  }

  // hr_pct_max — range form takes priority over single value
  if (seg.hr_pct_max_min !== undefined && seg.hr_pct_max_max !== undefined) {
    return { type: "hr_pct_max", min: seg.hr_pct_max_min, max: seg.hr_pct_max_max };
  }
  if (seg.hr_pct_max !== undefined) {
    return { type: "hr_pct_max", value: seg.hr_pct_max };
  }

  // power_watts — range form takes priority over single value
  if (seg.power_watts_min !== undefined && seg.power_watts_max !== undefined) {
    return { type: "power_watts", min: seg.power_watts_min, max: seg.power_watts_max };
  }
  if (seg.power_watts !== undefined) {
    return { type: "power_watts", value: seg.power_watts };
  }

  // Absolute run pace — string passthrough e.g. "4:15"
  if (seg.pace_per_km !== undefined) {
    return { type: "pace_per_km", value: seg.pace_per_km };
  }

  // Absolute swim pace — string passthrough e.g. "1:50"
  if (seg.pace_per_100m !== undefined) {
    return { type: "pace_per_100m", value: seg.pace_per_100m };
  }

  // Swim pace tag → RPE
  if (seg.pace !== undefined) {
    return paceToRpe(seg.pace);
  }

  return undefined;
}

/**
 * Resolves the primary measure (duration XOR distance).
 * Rule: when both are present, duration wins and distance is dropped.
 * duration_seconds is converted to minutes and rounded up to nearest integer.
 */
function resolveMeasure(
  seg: SourceSegment
): { duration_minutes?: number; distance_meters?: number } {
  if (seg.duration_minutes !== undefined) {
    // duration_minutes takes precedence over everything else
    return { duration_minutes: seg.duration_minutes };
  }
  if (seg.duration_seconds !== undefined) {
    // Convert to minutes (ceiling so we never lose partial minutes)
    return { duration_minutes: Math.ceil(seg.duration_seconds / 60) };
  }
  if (seg.distance_meters !== undefined) {
    return { distance_meters: seg.distance_meters };
  }
  // No measure — valid for rest segments defined only by rest_seconds
  return {};
}

/**
 * Recursively converts a SourceSegment into a StructureSegment.
 */
function convertSegment(src: SourceSegment): StructureSegment {
  const label = validateLabel(src.label);
  const measure = resolveMeasure(src);

  // Repeat container segments must not carry a target — intensity belongs on
  // leaf children only. Only resolve the target for non-repeat segments.
  const target = src.repeats !== undefined ? undefined : resolveTarget(src);

  const out: StructureSegment = { label, ...measure };

  if (target !== undefined) {
    out.target = target;
  }
  if (src.cadence_rpm !== undefined) {
    out.cadence_rpm = src.cadence_rpm;
  }
  if (src.cue !== undefined) {
    out.cue = src.cue;
  }
  if (src.repeats !== undefined) {
    out.repeats = src.repeats;
  }
  if (src.rest_seconds !== undefined) {
    out.rest_seconds = src.rest_seconds;
  }
  if (src.recovery !== undefined) {
    out.recovery = convertSegment(src.recovery);
  }
  if (src.segments !== undefined && src.segments.length > 0) {
    out.segments = src.segments.map(convertSegment);
  }

  return out;
}

/**
 * Materialise a WorkoutTemplate into a SessionStructure.
 *
 * This is the single public entry point. It is pure — given the same template
 * it always returns the same output. Safe to call from Edge Functions and CLI.
 *
 * @param template - A template object from workout-library.json
 * @returns SessionStructure ready to store in plan_sessions.structure
 */
export function materialize(template: WorkoutTemplate): SessionStructure {
  return {
    segments: template.segments.map(convertSegment),
  };
}
