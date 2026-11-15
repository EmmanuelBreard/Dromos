/**
 * Errors the athlete can act on (bad profile) versus failures worth retrying
 * (model timeout, truncated JSON, rate limit).
 */

export class PlanInputError extends Error {
  readonly status = 400;

  constructor(message: string) {
    super(message);
    this.name = "PlanInputError";
  }
}

const RETRYABLE_STATUS = new Set([408, 409, 429, 500, 502, 503, 504]);

/**
 * True when another attempt might succeed. Profile errors and deterministic
 * bugs are not retryable — repeating them only burns the wall-clock budget.
 */
export function isRetryableError(error: unknown): boolean {
  if (error instanceof PlanInputError) return false;
  if (!error || typeof error !== "object") {
    return /timeout|rate limit|network|fetch failed/i.test(String(error));
  }
  const e = error as {
    retryable?: boolean;
    status?: number;
    message?: string;
    code?: string;
    name?: string;
  };
  if (e.retryable === true) return true;
  if (e.retryable === false) return false;
  if (typeof e.status === "number" && RETRYABLE_STATUS.has(e.status)) return true;
  const msg = `${e.name ?? ""} ${e.code ?? ""} ${e.message ?? ""}`;
  return /timeout|timed out|rate limit|overloaded|ECONNRESET|EAI_AGAIN|network|fetch failed|socket hang up|terminated|empty response|cut off|truncated|Unexpected token|Unexpected end|Unterminated|invalid json/i
    .test(msg);
}

export function retryable(message: string): Error {
  const error = new Error(message);
  (error as Error & { retryable: boolean }).retryable = true;
  return error;
}

/** Short, secret-free message safe to store on the plan row and show in the app. */
export function publicErrorMessage(error: unknown): string {
  const raw = error instanceof Error ? error.message : String(error ?? "");
  const cleaned = raw
    .replace(/sk-[A-Za-z0-9_\-]+/g, "[redacted]")
    .replace(/Bearer\s+\S+/gi, "Bearer [redacted]")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 300);
  if (!cleaned) return "Plan generation failed. Please try again.";
  if (
    cleaned.startsWith("Plan generation") ||
    cleaned.startsWith("Your ") ||
    cleaned.startsWith("Add ")
  ) {
    return cleaned;
  }
  return `Plan generation failed: ${cleaned}`;
}

export async function withRetry<T>(
  fn: (attempt: number) => Promise<T>,
  opts?: { attempts?: number; baseDelayMs?: number },
): Promise<T> {
  const attempts = opts?.attempts ?? 3;
  const baseDelayMs = opts?.baseDelayMs ?? 400;
  let last: unknown;
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      return await fn(attempt);
    } catch (error) {
      last = error;
      if (!isRetryableError(error) || attempt === attempts - 1) throw error;
      await new Promise((resolve) =>
        setTimeout(resolve, baseDelayMs * 2 ** attempt)
      );
    }
  }
  throw last;
}
