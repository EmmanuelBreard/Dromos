/**
 * Turn the step 1 markdown plan into the week JSON step 3 already expects.
 *
 * Step 2 exists only to translate a rigid markdown format into JSON. That
 * extra model call is slow, and a truncated JSON response fails the whole
 * plan. The format is specified exactly, so parse it directly and keep the
 * model conversion as a fallback for output that does not follow the format.
 */

import { canonicalPhase, canonicalSport, canonicalType, type Phase } from "./aliases.ts";

export interface MacroSession {
  type: string;
  duration_minutes: number;
}

export interface MacroSport {
  hours: number;
  sessions: MacroSession[];
}

export interface MacroWeek {
  week_number: number;
  start_date?: string;
  phase: Phase;
  total_hours: number;
  swim: MacroSport;
  bike: MacroSport;
  run: MacroSport;
  notes: string;
}

export interface MacroPlan {
  plan_summary: {
    total_weeks: number;
    race?: string;
    race_date?: string;
  };
  weeks: MacroWeek[];
}

const WEEK_HEADER = /^(?:#{1,3}\s*)?W(?:eek)?\s*(\d+)\b(.*)$/i;
const SPORT_LINE = /^[-*•]?\s*(swimming|swim|cycling|bike|running|run)\s*[:\-–—]\s*(.+)$/i;

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
    throw new Error("Model returned invalid JSON");
  }
}

function emptySport(): MacroSport {
  return { hours: 0, sessions: [] };
}

function parseHours(line: string): Partial<Record<"total" | "swim" | "bike" | "run", number>> {
  const grab = (label: string) => {
    const match = line.match(new RegExp(`${label}\\s*[:=]?\\s*(\\d+(?:\\.\\d+)?)\\s*h`, "i"));
    return match ? Number(match[1]) : undefined;
  };
  return {
    total: grab("Total"),
    swim: grab("Swim"),
    bike: grab("Bike"),
    run: grab("Run"),
  };
}

function parseSessionList(text: string): MacroSession[] {
  const sessions: MacroSession[] = [];
  const re =
    /(Race-pace|Race pace|Easy|Tempo|Intervals|Recovery|Brick|Long|Endurance|Threshold|VO2max|VO2|Interval|Opener|Primer|Shakeout)\s*[:x×]?\s*(\d+(?:\.\d+)?)\s*(?:min|mins|minutes)?|(\d+(?:\.\d+)?)\s*(?:min|mins|minutes)\s*(Easy|Tempo|Intervals|Recovery|Long|Threshold)/gi;
  let match: RegExpExecArray | null;
  while ((match = re.exec(text)) !== null) {
    const rawType = match[1] ?? match[4];
    const rawDuration = match[2] ?? match[3];
    const type = canonicalType(rawType);
    const duration = Math.round(Number(rawDuration));
    if (type && duration > 0) sessions.push({ type, duration_minutes: duration });
  }
  return sessions;
}

function sportHoursFromSessions(sessions: MacroSession[], stated?: number): number {
  if (stated != null && Number.isFinite(stated)) return stated;
  const minutes = sessions.reduce((sum, session) => sum + session.duration_minutes, 0);
  return Math.round((minutes / 60) * 10) / 10;
}

/**
 * Parse a compact macro plan. Returns whatever complete weeks it could read;
 * callers decide whether that is enough to skip the JSON model call.
 */
export function parseMacroMarkdown(markdown: string): MacroPlan {
  const text = stripFences(markdown);
  const lines = text.split(/\r?\n/);
  const chunks: string[][] = [];
  let current: string[] | null = null;

  for (const line of lines) {
    if (WEEK_HEADER.test(line.trim())) {
      current = [line];
      chunks.push(current);
    } else if (current) {
      current.push(line);
    }
  }

  const weeks: MacroWeek[] = [];
  let lastPhase: Phase = "Base";

  for (const chunk of chunks) {
    const header = WEEK_HEADER.exec(chunk[0].trim());
    if (!header) continue;
    const weekNumber = Number(header[1]);
    if (!Number.isFinite(weekNumber) || weekNumber <= 0) continue;

    const foundPhase = canonicalPhase(header[2]);
    if (foundPhase) lastPhase = foundPhase;
    const dateMatch = header[2].match(/(\d{4}-\d{2}-\d{2})/);

    const week: MacroWeek = {
      week_number: weekNumber,
      start_date: dateMatch?.[1],
      phase: lastPhase,
      total_hours: 0,
      swim: emptySport(),
      bike: emptySport(),
      run: emptySport(),
      notes: "",
    };

    let statedTotal: number | undefined;

    for (const rawLine of chunk.slice(1)) {
      const line = rawLine.trim();
      if (!line) continue;
      if (/^total\s*:/i.test(line)) {
        const hours = parseHours(line);
        statedTotal = hours.total;
        if (hours.swim != null) week.swim.hours = hours.swim;
        if (hours.bike != null) week.bike.hours = hours.bike;
        if (hours.run != null) week.run.hours = hours.run;
        continue;
      }
      const notes = line.match(/^notes\s*[:\-–—]\s*(.*)$/i);
      if (notes) {
        week.notes = notes[1].trim();
        continue;
      }
      const sportLine = line.match(SPORT_LINE);
      if (!sportLine) continue;
      const sport = canonicalSport(sportLine[1]);
      if (!sport) continue;
      week[sport].sessions.push(...parseSessionList(sportLine[2]));
    }

    week.swim.hours = sportHoursFromSessions(week.swim.sessions, week.swim.hours || undefined);
    week.bike.hours = sportHoursFromSessions(week.bike.sessions, week.bike.hours || undefined);
    week.run.hours = sportHoursFromSessions(week.run.sessions, week.run.hours || undefined);
    const summed = Math.round((week.swim.hours + week.bike.hours + week.run.hours) * 10) / 10;
    week.total_hours = statedTotal ?? summed;

    const sessionCount = week.swim.sessions.length + week.bike.sessions.length + week.run.sessions.length;
    if (sessionCount === 0) continue;
    weeks.push(week);
  }

  const byNumber = new Map<number, MacroWeek>();
  for (const week of weeks) byNumber.set(week.week_number, week);
  const ordered = [...byNumber.values()].sort((a, b) => a.week_number - b.week_number);

  return {
    plan_summary: { total_weeks: ordered.length },
    weeks: ordered,
  };
}

/**
 * Accept a parsed markdown plan when it covers most of the requested length.
 * A short parse means the model ignored the format — fall back to step 2.
 */
export function macroPlanFromMarkdown(
  markdown: string,
  expectedWeeks: number,
): MacroPlan | null {
  const plan = parseMacroMarkdown(markdown);
  if (plan.weeks.length === 0) return null;
  const minimum = Math.max(1, Math.ceil(expectedWeeks * 0.8));
  if (plan.weeks.length < minimum) return null;
  return plan;
}

/** Split a markdown plan into week-groups so a JSON conversion cannot overflow. */
export function splitMarkdownWeeks(markdown: string, chunkSize: number): string[] {
  const text = stripFences(markdown);
  const lines = text.split(/\r?\n/);
  const preamble: string[] = [];
  const weeks: string[][] = [];
  let current: string[] | null = null;

  for (const line of lines) {
    if (WEEK_HEADER.test(line.trim())) {
      current = [line];
      weeks.push(current);
    } else if (current) {
      current.push(line);
    } else {
      preamble.push(line);
    }
  }

  const prefix = preamble.join("\n").trim();
  if (weeks.length === 0) return text.trim() ? [text.trim()] : [];

  const size = Math.max(1, chunkSize);
  const chunks: string[] = [];
  for (let i = 0; i < weeks.length; i += size) {
    const body = weeks.slice(i, i + size).map((chunk) => chunk.join("\n").trim()).join("\n\n");
    chunks.push(prefix ? `${prefix}\n\n${body}` : body);
  }
  return chunks;
}

export function extractWeekArray(parsed: unknown): Record<string, unknown>[] {
  if (Array.isArray(parsed)) return parsed.filter((item) => item && typeof item === "object");
  if (!parsed || typeof parsed !== "object") return [];
  const record = parsed as Record<string, unknown>;
  for (const key of ["weeks", "plan_weeks", "block_weeks"]) {
    if (Array.isArray(record[key])) {
      return (record[key] as unknown[]).filter((item) => item && typeof item === "object") as
        Record<string, unknown>[];
    }
  }
  if (record.plan && typeof record.plan === "object") {
    return extractWeekArray(record.plan);
  }
  if (record.week_number != null || record.sessions != null) return [record];
  return [];
}
