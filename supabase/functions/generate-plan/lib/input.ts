/**
 * Stable input for plan generation.
 *
 * Today the onboarding flow writes these fields onto `public.users` and the
 * edge function loads them. A later conversational onboarding can build the
 * same object and call generation without changing the pipeline.
 */

import { PlanInputError } from "./errors.ts";

export interface AthletePlanInput {
  race_objective: string;
  /** ISO timestamp or YYYY-MM-DD. */
  race_date: string;
  experience_years: number | null;
  current_weekly_hours: number | null;
  ftp: number | null;
  vma: number | null;
  css_seconds_per100m: number | null;
  limiters: string | null;
  swim_days: string[];
  bike_days: string[];
  run_days: string[];
  mon_duration: number | null;
  tue_duration: number | null;
  wed_duration: number | null;
  thu_duration: number | null;
  fri_duration: number | null;
  sat_duration: number | null;
  sun_duration: number | null;
}

export interface PlanHorizon {
  totalWeeks: number;
  /** UTC midnight on the day the plan starts (tomorrow). */
  planStartDate: Date;
  /** UTC midnight of the race day. */
  raceDate: Date;
  planStartISO: string;
  raceISO: string;
}

const DURATION_KEYS = [
  "mon_duration",
  "tue_duration",
  "wed_duration",
  "thu_duration",
  "fri_duration",
  "sat_duration",
  "sun_duration",
] as const;

/** How long a `generating` row is treated as still in flight. */
export const IN_FLIGHT_WINDOW_MS = 8 * 60 * 1000;

function asDayList(value: unknown): string[] {
  if (Array.isArray(value)) {
    return value.filter((day): day is string => typeof day === "string" && day.length > 0);
  }
  if (typeof value === "string" && value.trim()) {
    try {
      const parsed = JSON.parse(value);
      if (Array.isArray(parsed)) return asDayList(parsed);
    } catch {
      // Not JSON — ignore and treat as no days.
    }
  }
  return [];
}

function asNullableNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? n : null;
}

/**
 * Rest days are stored as NULL. Some callers (and older fixtures) use 0.
 * Both mean "do not train" — a 0-minute day must not be described to the
 * model as an available slot.
 */
function asDuration(value: unknown): number | null {
  const n = asNullableNumber(value);
  if (n === null || n <= 0) return null;
  return Math.round(n);
}

export function toAthletePlanInput(row: Record<string, unknown>): AthletePlanInput {
  const raceObjective = typeof row.race_objective === "string" ? row.race_objective.trim() : "";
  const raceDate = row.race_date == null ? "" : String(row.race_date);
  return {
    race_objective: raceObjective,
    race_date: raceDate,
    experience_years: asNullableNumber(row.experience_years),
    current_weekly_hours: asNullableNumber(row.current_weekly_hours),
    ftp: asNullableNumber(row.ftp),
    vma: asNullableNumber(row.vma),
    css_seconds_per100m: asNullableNumber(row.css_seconds_per100m),
    limiters: row.limiters == null ? null : String(row.limiters),
    swim_days: asDayList(row.swim_days),
    bike_days: asDayList(row.bike_days),
    run_days: asDayList(row.run_days),
    mon_duration: asDuration(row.mon_duration),
    tue_duration: asDuration(row.tue_duration),
    wed_duration: asDuration(row.wed_duration),
    thu_duration: asDuration(row.thu_duration),
    fri_duration: asDuration(row.fri_duration),
    sat_duration: asDuration(row.sat_duration),
    sun_duration: asDuration(row.sun_duration),
  };
}

export function weeklyTrainingMinutes(athlete: AthletePlanInput): number {
  return DURATION_KEYS.reduce((sum, key) => sum + (athlete[key] ?? 0), 0);
}

export function assertGeneratable(athlete: AthletePlanInput): void {
  if (!athlete.race_objective) {
    throw new PlanInputError("Choose a race distance before generating a plan.");
  }
  if (!athlete.race_date) {
    throw new PlanInputError("Choose a race date before generating a plan.");
  }
  if (weeklyTrainingMinutes(athlete) <= 0) {
    throw new PlanInputError(
      "Add at least one day you can train before generating a plan.",
    );
  }
}

export function formatISODate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/**
 * Plan starts tomorrow so today is never scheduled. Weeks are counted in
 * whole UTC days so a timestamptz race date cannot drift the length by one.
 */
export function computePlanHorizon(raceDateRaw: string, now = new Date()): PlanHorizon {
  const raceInstant = new Date(raceDateRaw);
  if (Number.isNaN(raceInstant.getTime())) {
    throw new PlanInputError("Your race date is invalid. Update it and try again.");
  }
  const startInstant = new Date(now.getTime() + 86_400_000);
  const planStartISO = formatISODate(startInstant);
  const raceISO = formatISODate(raceInstant);
  const startUTC = Date.parse(`${planStartISO}T00:00:00.000Z`);
  const raceUTC = Date.parse(`${raceISO}T00:00:00.000Z`);
  const days = Math.round((raceUTC - startUTC) / 86_400_000);
  const totalWeeks = Math.ceil(days / 7);
  if (!Number.isFinite(totalWeeks) || totalWeeks < 1) {
    throw new PlanInputError(
      "Your race is too soon to build a training plan. Choose a date at least a week away.",
    );
  }
  return {
    totalWeeks,
    planStartDate: new Date(startUTC),
    raceDate: new Date(raceUTC),
    planStartISO,
    raceISO,
  };
}

export type RestartDecision = "attach" | "replace" | "create";

/**
 * A second tap while generation is still running must not delete the row the
 * first run is writing. Only a missing plan, a finished plan, or a stale
 * `generating` row (the worker died) starts a new one.
 */
export function shouldRestartPlan(
  existing: { status?: string | null; created_at?: string | null } | null | undefined,
  nowMs: number,
  windowMs = IN_FLIGHT_WINDOW_MS,
): RestartDecision {
  if (!existing) return "create";
  if (existing.status === "generating" && existing.created_at) {
    const created = Date.parse(existing.created_at);
    if (Number.isFinite(created)) {
      const age = nowMs - created;
      if (age >= 0 && age < windowMs) return "attach";
    }
  }
  return "replace";
}
