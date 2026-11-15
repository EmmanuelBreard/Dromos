/** Canonical values the database will accept. */

export const PHASES = ["Base", "Build", "Peak", "Taper", "Recovery"] as const;
export const SESSION_TYPES = ["Easy", "Tempo", "Intervals"] as const;
export const SPORTS = ["swim", "bike", "run"] as const;
export const WEEKDAYS = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
] as const;

export type Phase = (typeof PHASES)[number];
export type SessionType = (typeof SESSION_TYPES)[number];
export type Sport = (typeof SPORTS)[number];

const PHASE_ALIASES: Record<string, Phase> = {
  base: "Base",
  aerobic: "Base",
  foundation: "Base",
  build: "Build",
  peak: "Peak",
  taper: "Taper",
  race: "Taper",
  "race week": "Taper",
  recovery: "Recovery",
  deload: "Recovery",
  rest: "Recovery",
  transition: "Recovery",
};

const TYPE_ALIASES: Record<string, SessionType> = {
  brick: "Easy",
  opener: "Easy",
  openers: "Easy",
  primer: "Easy",
  shakeout: "Easy",
  recovery: "Easy",
  endurance: "Easy",
  long: "Easy",
  aerobic: "Easy",
  race: "Tempo",
  racepace: "Tempo",
  "race-pace": "Tempo",
  threshold: "Tempo",
  sweetspot: "Tempo",
  "sweet-spot": "Tempo",
  vo2: "Intervals",
  vo2max: "Intervals",
  interval: "Intervals",
  intervals: "Intervals",
  speed: "Intervals",
  hard: "Intervals",
};

const DAY_NORM: Record<string, string> = {
  mon: "Monday",
  monday: "Monday",
  tue: "Tuesday",
  tues: "Tuesday",
  tuesday: "Tuesday",
  wed: "Wednesday",
  wednesday: "Wednesday",
  thu: "Thursday",
  thur: "Thursday",
  thurs: "Thursday",
  thursday: "Thursday",
  fri: "Friday",
  friday: "Friday",
  sat: "Saturday",
  saturday: "Saturday",
  sun: "Sunday",
  sunday: "Sunday",
};

export function canonicalPhase(raw: unknown, fallback?: Phase): Phase | null {
  const text = String(raw ?? "").trim();
  if ((PHASES as readonly string[]).includes(text)) return text as Phase;
  const key = text.toLowerCase().replace(/[_]+/g, " ").replace(/\s+/g, " ").trim();
  if (PHASE_ALIASES[key]) return PHASE_ALIASES[key];
  // Headers look like "— Base — 2026-11-16" or "Race week". Match a whole word,
  // longest alias first so "race week" beats "race".
  const aliases = Object.keys(PHASE_ALIASES).sort((a, b) => b.length - a.length);
  for (const alias of aliases) {
    const escaped = alias.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    if (new RegExp(`\\b${escaped}\\b`, "i").test(text)) return PHASE_ALIASES[alias];
  }
  return fallback ?? null;
}

export function canonicalType(raw: unknown): SessionType | null {
  const text = String(raw ?? "").trim();
  if (!text) return null;
  if ((SESSION_TYPES as readonly string[]).includes(text)) return text as SessionType;
  const key = text.toLowerCase().replace(/[\s_]+/g, "");
  const hyphenated = text.toLowerCase().trim();
  return TYPE_ALIASES[key] ?? TYPE_ALIASES[hyphenated] ?? "Easy";
}

export function canonicalSport(raw: unknown): Sport | null {
  const text = String(raw ?? "").trim().toLowerCase();
  if (!text) return null;
  if (text.startsWith("swim")) return "swim";
  if (text === "bike" || text === "cycling" || text === "cycle" || text === "ride" || text === "biking") {
    return "bike";
  }
  if (text === "run" || text === "running" || text === "jog") return "run";
  return null;
}

export function canonicalDay(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  return DAY_NORM[raw.trim().toLowerCase()] ?? null;
}

export function coerceDuration(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value) && value > 0) {
    return Math.round(value);
  }
  if (typeof value === "string") {
    const match = value.match(/(\d+(?:\.\d+)?)/);
    if (match) {
      const n = Math.round(Number(match[1]));
      if (n > 0) return n;
    }
  }
  return null;
}
