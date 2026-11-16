/**
 * Parsing tests for onboarding-coach.
 *
 * Run from the repo root:
 *   deno test supabase/functions/onboarding-coach/__tests__/parse.test.ts
 */

import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  interpretCoachPayload,
  isRetryableError,
  parseModelJson,
  retryable,
} from "../lib/parse.ts";

Deno.test("parseModelJson reads fenced JSON", () => {
  const parsed = parseModelJson('```json\n{"reply":"Hi","follow_up":false,"parsed":null}\n```');
  assertEquals((parsed as { reply: string }).reply, "Hi");
});

Deno.test("parseModelJson reads a JSON object wrapped in prose", () => {
  const parsed = parseModelJson('Sure. {"reply":"Olympic","follow_up":false,"parsed":{"race_objective":"Olympic"}} Thanks');
  assertEquals((parsed as { parsed: { race_objective: string } }).parsed.race_objective, "Olympic");
});

Deno.test("parseModelJson rejects text with no object", () => {
  assertThrows(() => parseModelJson("I am not json"));
});

Deno.test("invalid JSON is retryable", () => {
  try {
    parseModelJson("nope");
  } catch (error) {
    assertEquals(isRetryableError(error), true);
  }
  assertEquals(isRetryableError(retryable("empty response")), true);
  assertEquals(isRetryableError(new Error("Choose a race")), false);
});

Deno.test("olympic answer is kept", () => {
  const turn = interpretCoachPayload({
    reply: "Olympic it is.",
    follow_up: false,
    parsed: { race_objective: "Olympic" },
  }, "race_type");
  assertEquals(turn.follow_up, false);
  assertEquals(turn.parsed, { race_objective: "Olympic" });
});

Deno.test("sprint is not stored", () => {
  const turn = interpretCoachPayload({
    reply: "I coach Olympic and 70.3 for now.",
    follow_up: false,
    parsed: { race_objective: "Sprint" },
  }, "race_type");
  assertEquals(turn.follow_up, true);
  assertEquals(turn.parsed, null);
});

Deno.test("follow_up drops any parsed value", () => {
  const turn = interpretCoachPayload({
    reply: "Love the enthusiasm, but I still need your race date.",
    follow_up: true,
    parsed: { race_date: "2020-01-01" },
  }, "race_date");
  assertEquals(turn.follow_up, true);
  assertEquals(turn.parsed, null);
  assertEquals(turn.reply.includes("race date"), true);
});

Deno.test("vma outside 10-25 is dropped", () => {
  const turn = interpretCoachPayload({
    reply: "That VMA is too high.",
    follow_up: false,
    parsed: { vma: 40 },
  }, "run");
  assertEquals(turn.follow_up, true);
  assertEquals(turn.parsed, null);
});

Deno.test("a 5K time is passed through raw", () => {
  const turn = interpretCoachPayload({
    reply: "Thanks.",
    follow_up: false,
    parsed: { run_distance: "5k", run_time_seconds: 1200, vma: 99 },
  }, "run");
  assertEquals(turn.parsed, { run_distance: "5k", run_time_seconds: 1200 });
});

Deno.test("20-minute power is not converted here", () => {
  const turn = interpretCoachPayload({
    reply: "Noted.",
    follow_up: false,
    parsed: { twenty_min_watts: 200 },
  }, "bike");
  assertEquals(turn.parsed, { twenty_min_watts: 200 });
});

Deno.test("limiters none is normalized and a real note is kept", () => {
  const none = interpretCoachPayload({
    reply: "Good.",
    follow_up: false,
    parsed: { limiters: "No injuries" },
  }, "limiters");
  assertEquals(none.parsed, { limiters: "none" });

  const note = interpretCoachPayload({
    reply: "I'll plan around that. Please see a physio if it gets worse.",
    follow_up: false,
    parsed: { limiters: "  left knee on long runs  " },
  }, "limiters");
  assertEquals(note.parsed, { limiters: "left knee on long runs" });
});

Deno.test("day names are ordered and unknown names dropped", () => {
  const turn = interpretCoachPayload({
    reply: "Those days work.",
    follow_up: false,
    parsed: { swim_days: ["Friday", "Funday", "Monday"] },
  }, "swim_days");
  assertEquals(turn.parsed, { swim_days: ["Monday", "Friday"] });
});

Deno.test("a react payload does not need a parsed value", () => {
  const turn = interpretCoachPayload({
    reply: "A 70.3 on 5 hours a week is ambitious but doable.",
    follow_up: false,
    parsed: null,
  }, "weekly_hours");
  assertEquals(turn.follow_up, false);
  assertEquals(turn.parsed, null);
  assertEquals(turn.reply.includes("70.3"), true);
});
