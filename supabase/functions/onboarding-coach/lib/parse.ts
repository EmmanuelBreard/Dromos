/**
 * Tolerant JSON parsing for onboarding-coach.
 *
 * Same idea as generate-plan: accept fenced JSON and a JSON object wrapped in
 * prose, then drop anything that is not a real answer for this step.
 */

export interface ParsedValue {
  race_objective?: "Olympic" | "Ironman 70.3";
  race_date?: string;
  just_finish?: boolean;
  time_objective_minutes?: number;
  experience_years?: number;
  current_weekly_hours?: number;
  vma?: number;
  run_distance?: "5k" | "10k";
  run_time_seconds?: number;
  css_seconds_per100m?: number;
  swim_distance?: "400" | "1500";
  swim_time_seconds?: number;
  typical_pace_seconds?: number;
  ftp?: number;
  twenty_min_watts?: number;
  no_power_meter?: boolean;
  max_hr?: number;
  birth_year?: number;
  limiters?: string;
  unknown_metric?: boolean;
  swim_days?: string[];
  bike_days?: string[];
  run_days?: string[];
}

export interface CoachTurn {
  reply: string;
  follow_up: boolean;
  parsed: ParsedValue | null;
}

const DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

const RETRYABLE = /timeout|timed out|rate limit|overloaded|ECONNRESET|EAI_AGAIN|network|fetch failed|socket hang up|terminated|empty response|cut off|truncated|Unexpected token|Unexpected end|Unterminated|invalid json/i;

export function isRetryableError(error: unknown): boolean {
  if (!error || typeof error !== "object") return RETRYABLE.test(String(error));
  const candidate = error as { retryable?: boolean; status?: number; message?: string };
  if (candidate.retryable === true) return true;
  if (candidate.retryable === false) return false;
  if (typeof candidate.status === "number" && [408, 409, 429, 500, 502, 503, 504].includes(candidate.status)) {
    return true;
  }
  return RETRYABLE.test(candidate.message ?? "");
}

export function retryable(message: string): Error {
  const error = new Error(message);
  (error as Error & { retryable: boolean }).retryable = true;
  return error;
}

export function stripFences(text: string): string {
  const trimmed = text.trim();
  const wrapped = trimmed.match(/^```[a-z]*\n([\s\S]*?)\n```$/i);
  if (wrapped) return wrapped[1].trim();
  return trimmed.replace(/```[a-z]*\n?/gi, "").replace(/```/g, "").trim();
}

export function parseModelJson(text: string): unknown {
  const stripped = stripFences(text);
  try {
    return JSON.parse(stripped);
  } catch {
    const start = stripped.indexOf("{");
    const end = stripped.lastIndexOf("}");
    if (start >= 0 && end > start) {
      return JSON.parse(stripped.slice(start, end + 1));
    }
    throw retryable("Model returned invalid JSON");
  }
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function numberIn(value: unknown, min: number, max: number): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) return undefined;
  if (value < min || value > max) return undefined;
  return value;
}

function intIn(value: unknown, min: number, max: number): number | undefined {
  const n = numberIn(value, min, max);
  if (n === undefined) return undefined;
  return Math.round(n);
}

function days(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  const found = value.filter((day): day is string => typeof day === "string" && DAYS.includes(day));
  return found.length > 0 ? DAYS.filter((day) => found.includes(day)) : undefined;
}

function cleanReply(value: unknown, fallback: string): string {
  const text = typeof value === "string" ? value.replace(/\s+/g, " ").trim() : "";
  if (!text) return fallback;
  return text.slice(0, 400);
}

/**
 * Turn a model object into a turn the app can trust.
 * A value outside the column checks becomes a follow-up and is not returned.
 */
export function interpretCoachPayload(value: unknown, step: string): CoachTurn {
  const record = asRecord(value);
  if (!record) {
    return { reply: "I didn't quite get that. Try once more, or use one of the buttons.", follow_up: true, parsed: null };
  }
  const followUp = record.follow_up === true;
  const reply = cleanReply(record.reply, followUp
    ? "I still need an answer I can train from."
    : "Got it.");
  if (followUp) return { reply, follow_up: true, parsed: null };

  const raw = asRecord(record.parsed);
  if (!raw) return { reply, follow_up: false, parsed: null };

  const parsed = pick(step, raw);
  if (!parsed) {
    return {
      reply: cleanReply(record.reply, "That doesn't fit what I can use. Try it once more."),
      follow_up: true,
      parsed: null,
    };
  }
  return { reply, follow_up: false, parsed };
}

function pick(step: string, raw: Record<string, unknown>): ParsedValue | null {
  switch (step) {
    case "race_type": {
      if (raw.race_objective === "Sprint" || raw.race_objective === "Ironman") return null;
      if (raw.race_objective === "Olympic" || raw.race_objective === "Ironman 70.3") {
        return { race_objective: raw.race_objective };
      }
      return null;
    }
    case "race_date": {
      if (typeof raw.race_date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(raw.race_date)) {
        return { race_date: raw.race_date };
      }
      return null;
    }
    case "target_time": {
      if (raw.just_finish === true) return { just_finish: true };
      const minutes = intIn(raw.time_objective_minutes, 1, 1200);
      return minutes === undefined ? null : { time_objective_minutes: minutes };
    }
    case "experience": {
      const years = intIn(raw.experience_years, 0, 80);
      return years === undefined ? null : { experience_years: years };
    }
    case "weekly_hours": {
      const hours = numberIn(raw.current_weekly_hours, 0, 25);
      return hours === undefined ? null : { current_weekly_hours: Math.round(hours * 10) / 10 };
    }
    case "run": {
      if (raw.unknown_metric === true) return { unknown_metric: true };
      const distance = raw.run_distance === "5k" || raw.run_distance === "10k" ? raw.run_distance : undefined;
      const seconds = intIn(raw.run_time_seconds, 1, 20_000);
      if (distance && seconds !== undefined) return { run_distance: distance, run_time_seconds: seconds };
      const vma = numberIn(raw.vma, 10, 25);
      return vma === undefined ? null : { vma: Math.round(vma * 10) / 10 };
    }
    case "swim": {
      if (raw.unknown_metric === true) return { unknown_metric: true };
      const distance = raw.swim_distance === "400" || raw.swim_distance === "1500" ? raw.swim_distance : undefined;
      const seconds = intIn(raw.swim_time_seconds, 1, 20_000);
      if (distance && seconds !== undefined) return { swim_distance: distance, swim_time_seconds: seconds };
      const pace = intIn(raw.typical_pace_seconds ?? raw.css_seconds_per100m, 55, 300);
      if (raw.typical_pace_seconds != null && pace !== undefined) return { typical_pace_seconds: pace };
      return pace === undefined ? null : { css_seconds_per100m: pace };
    }
    case "bike": {
      if (raw.unknown_metric === true) return { unknown_metric: true };
      if (raw.no_power_meter === true) return { no_power_meter: true };
      const twenty = intIn(raw.twenty_min_watts, 50, 600);
      if (twenty !== undefined && raw.twenty_min_watts != null) return { twenty_min_watts: twenty };
      const ftp = intIn(raw.ftp, 50, 500);
      return ftp === undefined ? null : { ftp };
    }
    case "max_hr": {
      const year = intIn(raw.birth_year, 1920, 2030);
      if (year !== undefined && raw.birth_year != null) return { birth_year: year };
      const hr = intIn(raw.max_hr, 100, 220);
      return hr === undefined ? null : { max_hr: hr };
    }
    case "swim_days":
      return days(raw.swim_days) ? { swim_days: days(raw.swim_days) } : null;
    case "bike_days":
      return days(raw.bike_days) ? { bike_days: days(raw.bike_days) } : null;
    case "run_days":
      return days(raw.run_days) ? { run_days: days(raw.run_days) } : null;
    case "limiters": {
      if (typeof raw.limiters !== "string") return null;
      const text = raw.limiters.replace(/\s+/g, " ").trim();
      if (!text) return null;
      const lowered = text.toLowerCase();
      if (["none", "no", "nothing", "no injuries", "no injury"].includes(lowered)) return { limiters: "none" };
      return { limiters: text.slice(0, 500) };
    }
    default:
      return null;
  }
}
