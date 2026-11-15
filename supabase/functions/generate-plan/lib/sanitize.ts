/**
 * Make model output safe to run through the fixers and write to the database.
 *
 * One missing phase, a "Running" sport, or a block that renumbered its weeks
 * from 1 used to throw and discard the whole plan. The macro plan is the
 * source of truth for which weeks and sessions exist; step 3 only assigns
 * templates and days. Repair what we can, drop what we cannot.
 */

import {
  canonicalDay,
  canonicalPhase,
  canonicalSport,
  canonicalType,
  coerceDuration,
  WEEKDAYS,
  type Phase,
} from "./aliases.ts";
import { extractWeekArray } from "./macro-plan.ts";

export interface DayConstraints {
  dayCaps: Record<string, number>;
  sportEligibility: Record<string, string[]>;
}

interface LibraryEntry {
  id: string;
  dur: number;
}

interface NormalizedSession {
  sport: "swim" | "bike" | "run";
  type: "Easy" | "Tempo" | "Intervals";
  template_id: string;
  duration_minutes: number;
  day: string;
  is_brick: boolean;
  drop?: boolean;
}

function libraryIndex(library: Record<string, unknown> | null | undefined): {
  byId: Map<string, { sport: string; type: string; dur: number }>;
  byKey: Map<string, LibraryEntry[]>;
} {
  const byId = new Map<string, { sport: string; type: string; dur: number }>();
  const byKey = new Map<string, LibraryEntry[]>();
  for (const sport of ["swim", "bike", "run"]) {
    const templates = (library as Record<string, unknown[] | undefined> | null)?.[sport] ?? [];
    for (const raw of templates) {
      const template = raw as { template_id?: unknown; duration_minutes?: unknown };
      if (typeof template.template_id !== "string" || !template.template_id) continue;
      const type = template.template_id.split("_")[1] ?? "";
      const dur = coerceDuration(template.duration_minutes) ?? 0;
      byId.set(template.template_id, { sport, type, dur });
      const key = `${sport}_${type}`;
      const list = byKey.get(key) ?? [];
      list.push({ id: template.template_id, dur });
      byKey.set(key, list);
    }
  }
  return { byId, byKey };
}

function closest(options: LibraryEntry[], duration: number): LibraryEntry | null {
  if (options.length === 0) return null;
  return [...options].sort((a, b) => Math.abs(a.dur - duration) - Math.abs(b.dur - duration))[0];
}

function sessionsFromBucket(week: Record<string, unknown>): unknown[] {
  if (Array.isArray(week.sessions) && week.sessions.length > 0) return week.sessions;
  const collected: unknown[] = [];
  for (const sport of ["swim", "bike", "run"]) {
    const bucket = week[sport];
    if (!bucket || typeof bucket !== "object") continue;
    const list = (bucket as { sessions?: unknown }).sessions;
    if (!Array.isArray(list)) continue;
    for (const session of list) {
      if (session && typeof session === "object") {
        collected.push({ ...(session as Record<string, unknown>), sport });
      }
    }
  }
  return collected;
}

function normalizeSession(
  raw: unknown,
  index: ReturnType<typeof libraryIndex>,
): NormalizedSession | null {
  if (!raw || typeof raw !== "object") return null;
  const session = raw as Record<string, unknown>;
  const sport = canonicalSport(session.sport);
  if (!sport) return null;
  const type = canonicalType(session.type) ?? "Easy";

  let templateId = typeof session.template_id === "string" ? session.template_id : "";
  const known = templateId ? index.byId.get(templateId) : undefined;
  const templateOk = !!known && known.sport === sport && known.type === type;
  let duration = coerceDuration(session.duration_minutes);

  if (!templateOk) {
    const picked = closest(index.byKey.get(`${sport}_${type}`) ?? [], duration ?? 45);
    if (!picked) return null;
    templateId = picked.id;
    duration = duration ?? picked.dur;
    if (!duration) duration = picked.dur;
  } else if (!duration) {
    duration = known!.dur || null;
  }
  if (!duration || duration <= 0) return null;

  return {
    sport,
    type,
    template_id: templateId,
    duration_minutes: duration,
    day: canonicalDay(session.day) ?? "",
    is_brick: session.is_brick === true,
  };
}

function assignDays(
  sessions: NormalizedSession[],
  constraints: DayConstraints,
  preservePlaced: boolean,
): void {
  const remaining: Record<string, number> = { ...constraints.dayCaps };
  const sportCount: Record<string, number> = {};

  const openDays = WEEKDAYS.filter((day) => (constraints.dayCaps[day] ?? 0) > 0);
  const ordered = [...sessions].sort((a, b) => b.duration_minutes - a.duration_minutes);

  for (const session of ordered) {
    // After the fixers have placed sessions, keep those days even if a cap is
    // tight — moving them again would undo brick and intensity repairs.
    if (preservePlaced && session.day) {
      remaining[session.day] = (remaining[session.day] ?? 0) - session.duration_minutes;
      sportCount[session.day] = (sportCount[session.day] ?? 0) + 1;
      continue;
    }
    const dayOk = session.day &&
      (constraints.sportEligibility[session.day] ?? []).includes(session.sport) &&
      (remaining[session.day] ?? 0) >= session.duration_minutes;
    if (dayOk) {
      remaining[session.day] -= session.duration_minutes;
      sportCount[session.day] = (sportCount[session.day] ?? 0) + 1;
      continue;
    }

    const eligible = openDays.filter((day) =>
      (constraints.sportEligibility[day] ?? []).includes(session.sport)
    );
    if (eligible.length === 0) {
      session.drop = true;
      continue;
    }
    eligible.sort((a, b) => {
      const aFits = (remaining[a] ?? 0) >= session.duration_minutes ? 0 : 1;
      const bFits = (remaining[b] ?? 0) >= session.duration_minutes ? 0 : 1;
      if (aFits !== bFits) return aFits - bFits;
      const aBusy = sportCount[a] ?? 0;
      const bBusy = sportCount[b] ?? 0;
      if (aBusy !== bBusy) return aBusy - bBusy;
      return (remaining[b] ?? 0) - (remaining[a] ?? 0);
    });
    session.day = eligible[0];
    remaining[session.day] -= session.duration_minutes;
    sportCount[session.day] = (sportCount[session.day] ?? 0) + 1;
  }
}

/**
 * When a block answers with week numbers 1..4 for an input block of weeks
 * 5..8, map them back in order. Matching numbers are left alone.
 */
export function alignBlockWeeks(
  parsed: unknown,
  macroBlock: Array<{ week_number?: unknown; phase?: unknown }>,
): Record<string, unknown>[] {
  const weeks = extractWeekArray(parsed);
  if (weeks.length === 0 || macroBlock.length === 0) return weeks;

  const expected = macroBlock
    .map((week) => Number(week.week_number))
    .filter((n) => Number.isFinite(n) && n > 0);
  const expectedSet = new Set(expected);
  const returned = weeks.map((week) => Number(week.week_number));
  const aligned = returned.length > 0 &&
    returned.every((n) => Number.isFinite(n) && expectedSet.has(n));
  if (aligned) return weeks;

  return weeks.slice(0, macroBlock.length).map((week, index) => {
    const macro = macroBlock[index];
    if (!macro) return week;
    return {
      ...week,
      week_number: Number(macro.week_number),
      phase: week.phase ?? macro.phase,
    };
  });
}

function macroSessions(week: Record<string, unknown> | undefined, index: ReturnType<typeof libraryIndex>): NormalizedSession[] {
  if (!week) return [];
  return sessionsFromBucket(week)
    .map((session) => normalizeSession(session, index))
    .filter((session): session is NormalizedSession => session !== null);
}

/**
 * Produce fixer-ready weeks: valid phase, sport, type, duration, day, and
 * template id. Missing step 3 weeks are filled from the macro plan.
 */
export function preparePlanWeeks(
  blockWeeks: unknown[],
  macroWeeks: Array<Record<string, unknown>>,
  library: Record<string, unknown> | null | undefined,
  constraints: DayConstraints,
  options?: { preserveDays?: boolean; fillGaps?: boolean },
): Array<Record<string, unknown>> {
  const index = libraryIndex(library);
  const macroByNumber = new Map<number, Record<string, unknown>>();
  for (const week of macroWeeks) {
    const n = Number(week.week_number);
    if (Number.isFinite(n) && n > 0) macroByNumber.set(n, week);
  }

  const bestByNumber = new Map<number, Record<string, unknown>>();
  for (const raw of blockWeeks) {
    if (!raw || typeof raw !== "object") continue;
    const week = raw as Record<string, unknown>;
    const n = Number(week.week_number);
    if (!Number.isFinite(n) || n <= 0) continue;
    const sessions = sessionsFromBucket(week);
    const existing = bestByNumber.get(n);
    const existingCount = existing ? sessionsFromBucket(existing).length : -1;
    if (!existing || sessions.length > existingCount) bestByNumber.set(n, week);
  }

  // The first pass fills weeks step 3 skipped. The pass after the fixers must
  // not put those sessions back — the fixers removed them on purpose.
  const fillGaps = options?.fillGaps !== false;
  const numbers = (fillGaps
    ? [...new Set([...macroByNumber.keys(), ...bestByNumber.keys()])]
    : [...bestByNumber.keys()])
    .sort((a, b) => a - b);

  let previousPhase: Phase = "Base";
  const prepared = [];

  for (const weekNumber of numbers) {
    const macro = macroByNumber.get(weekNumber);
    const raw = bestByNumber.get(weekNumber) ?? {};
    const macroPhase: Phase = canonicalPhase(macro?.phase, previousPhase) ?? previousPhase;
    const phase: Phase = canonicalPhase(raw.phase, macroPhase) ?? macroPhase;
    previousPhase = phase;

    let sessions = macroSessions(raw, index);
    if (sessions.length === 0 && fillGaps) sessions = macroSessions(macro, index);
    assignDays(sessions, constraints, options?.preserveDays === true);

    prepared.push({
      week_number: weekNumber,
      phase,
      notes: typeof raw.notes === "string"
        ? raw.notes
        : typeof macro?.notes === "string"
        ? macro.notes
        : null,
      sessions: sessions
        .filter((session) => !session.drop && canonicalDay(session.day))
        .map(({ drop: _drop, ...session }) => session),
    });
  }

  return prepared;
}
