// Phase 1 (PoC) validation harness for the Coach Chat V0 prompt (DRO-256).
//
// Purpose: render `ai/prompts/coach-chat-v0.txt` against fixture athlete contexts,
// call OpenAI gpt-4.1, and print responses for qualitative human review.
//
// Run:  node scripts/test-coach-chat.mjs
//       node scripts/test-coach-chat.mjs --only=interpretation   # filter by category
//       node scripts/test-coach-chat.mjs --case=4                # run a single case index
//
// No DB writes. No streaming. Single-turn (no chat history).

import fs from "node:fs";
import path from "node:path";

// ── Env loader (same shape as test-session-feedback.mjs) ──────────────────────
const ROOT = path.resolve(decodeURIComponent(new URL(".", import.meta.url).pathname), "..");
const envText = fs.readFileSync(path.join(ROOT, ".env"), "utf8");
for (const line of envText.split("\n")) {
  const m = line.match(/^([A-Z_]+)\s*=\s*"?([^"\n]*)"?\s*$/);
  if (m) process.env[m[1]] ??= m[2];
}
const KEY = process.env.OPENAI_API_KEY;
if (!KEY) { console.error("Missing OPENAI_API_KEY in .env"); process.exit(1); }

// ── Prompt load + split ───────────────────────────────────────────────────────
const promptPath = path.join(ROOT, "ai/prompts/coach-chat-v0.txt");
const promptRaw = fs.readFileSync(promptPath, "utf8");
const [STATIC, DYNAMIC_TEMPLATE] = promptRaw.split(/^--- DYNAMIC ---$/m);
if (!STATIC || !DYNAMIC_TEMPLATE) {
  console.error("Prompt file missing '--- DYNAMIC ---' delimiter");
  process.exit(1);
}

// ── Fixture: full context (today is Sat 2026-05-02, Week 6 Build) ─────────────
// Pulled from Supabase for ebreard4@gmail.com on 2026-05-02.
const FIXTURE_FULL = {
  athlete_profile: `Race objective: Ironman 70.3 on 2026-05-31 (29 days away)
Experience: 2 years
VMA: 18 km/h | FTP: 275W | CSS: 1:55/100m | Max HR: 192 bpm`,

  plan_summary: `Currently in Week 6 of 10 — Build phase.
Phase map: W1-3 Base, W4-5 Recovery, W6-7 Build, W8 Peak, W9-10 Taper.
4 weeks remaining: Build (W7), Peak (W8), Taper (W9-10).`,

  today_session: `Saturday: BIKE Tempo (BIKE_Tempo_19), 180min — "150min Z1 @175-185W + 30min @230W block at end". Already completed today.`,

  yesterday_session: `Friday: BIKE Easy 50min Z1 recovery (done) — actual: 38km in 1h01, avg HR 143 (no power meter)`,

  week_map: `Mon: SWIM Tempo 55min (done) — felt fast but cut short
Tue: RUN Intervals 60min (done) — strong execution, race-pace stimulus
Wed: BIKE Tempo 60min (done) — tempo intervals at 240W, HR drift in later reps
Thu: SWIM Easy 35min (done) + RUN Easy 45min (done)
Fri: BIKE Easy 50min Z1 recovery (done)
Sat (today): BIKE Tempo 180min (done)
Sun: RUN Tempo 90min brick (12k @5:30/km + 4k @4:30/km race pace) + SWIM Easy 45min (2k aerobic)`,

  recent_completed: `1) Sat (today): BIKE Tempo 180min — actual: 80km in 2h52, avg HR 132 (no power meter — watts unavailable).
   Lap-by-lap (5km laps, avg HR / max HR / km/h):
   L0  124/142 23   L1  130/136 25   L2  133/148 25   L3  128/142 29
   L4  132/143 28   L5  130/152 32   L6  132/142 25   L7  127/138 31
   L8  130/145 26   L9  139/147 33   L10 141/152 35   L11 141/154 25
   L12 135/161 27   L13 135/147 30   L14 130/147 29   L15 125/138 31
   Plan said "150min Z1 @175-185W + 30min @230W". Coach feedback noted: steady aerobic effort, slight pace variation from terrain, on target for endurance.

2) Wed: BIKE Tempo 60min — 3x12min @240W race-pace planned. Coach feedback: power consistent across work segments, HR rose in later intervals (mild fatigue accumulating).

3) Tue: RUN Intervals 60min — 5x3min @3:30/km HR>170, 2:30 jog recovery. Coach feedback: splits fast and consistent, race-pace stimulus ideal.`,

  tomorrow_session: `Sunday: 1) RUN Tempo brick 90min — "12k @5:30/km + last 4k @4:30/km race pace". 2) SWIM Easy 45min — 2k aerobic @2:15/100m.`,
};

// ── Fixture: no active plan ───────────────────────────────────────────────────
const FIXTURE_NO_PLAN = {
  athlete_profile: `No completed onboarding — minimal profile.
Race objective: not set | VMA: unknown | FTP: unknown | CSS: unknown`,
  plan_summary: `No active training plan.`,
  today_session: `No session scheduled (no plan).`,
  yesterday_session: `No session scheduled (no plan).`,
  week_map: `No plan generated yet.`,
  recent_completed: `No recent sessions.`,
  tomorrow_session: `No session scheduled (no plan).`,
};

// ── Fixture: today is rest day ────────────────────────────────────────────────
const FIXTURE_REST_DAY = {
  ...FIXTURE_FULL,
  today_session: `Saturday is a REST DAY (no scheduled training).`,
  week_map: FIXTURE_FULL.week_map.replace(
    "Sat (today): BIKE Tempo 180min (done)",
    "Sat (today): REST DAY"
  ),
};

// ── Render dynamic block ──────────────────────────────────────────────────────
function renderDynamic(fixture) {
  return DYNAMIC_TEMPLATE
    .replace("{{athlete_profile}}", fixture.athlete_profile)
    .replace("{{plan_summary}}", fixture.plan_summary)
    .replace("{{today_session}}", fixture.today_session)
    .replace("{{yesterday_session}}", fixture.yesterday_session)
    .replace("{{week_map}}", fixture.week_map)
    .replace("{{recent_completed}}", fixture.recent_completed)
    .replace("{{tomorrow_session}}", fixture.tomorrow_session);
}

// ── Test cases ────────────────────────────────────────────────────────────────
const CASES = [
  // Topic 1 — Session interpretation (≤5 sentences)
  { cat: "interpretation", fixture: FIXTURE_FULL, q: "what does 4x800 at threshold mean?" },
  { cat: "interpretation", fixture: FIXTURE_FULL, q: "can you explain tomorrow's brick run?" },
  { cat: "interpretation", fixture: FIXTURE_FULL, q: "what's a tempo bike supposed to feel like?" },

  // Topic 2 — Pre-session pacing (≤3 sentences)
  { cat: "pacing",         fixture: FIXTURE_FULL, q: "how hard should I go tomorrow?" },
  { cat: "pacing",         fixture: FIXTURE_FULL, q: "what target paces for tomorrow's run?" },
  { cat: "pacing",         fixture: FIXTURE_FULL, q: "should I push the long ride this weekend?" },

  // Topic 3 — Post-session feedback (≤3 sentences)
  { cat: "post-session",   fixture: FIXTURE_FULL, q: "felt brutal today, way harder than expected" },
  { cat: "post-session",   fixture: FIXTURE_FULL, q: "how did I do on today's bike?" },
  { cat: "post-session",   fixture: FIXTURE_FULL, q: "swim felt heavy this morning, normal?" },

  // Topic 10 — Plan rationale (≤5 sentences)
  { cat: "rationale",      fixture: FIXTURE_FULL, q: "why so much Z2 in this plan?" },
  { cat: "rationale",      fixture: FIXTURE_FULL, q: "why are these next 2 weeks Build and not Peak?" },
  { cat: "rationale",      fixture: FIXTURE_FULL, q: "why do I have so many tempo bike sessions?" },

  // V1 punts (≤3 sentences, advisory + Calendar pointer when reschedule wins)
  { cat: "punt-schedule",  fixture: FIXTURE_FULL, q: "got a family thing Sunday morning, can't do the long brick" },
  { cat: "punt-missed",    fixture: FIXTURE_FULL, q: "I skipped yesterday's bike, should I make it up?" },
  { cat: "punt-injury",    fixture: FIXTURE_FULL, q: "I have knee pain since Monday, runs are painful, biking and swimming feel fine" },
  { cat: "punt-equipment", fixture: FIXTURE_FULL, q: "pool is closed all week, what do I do?" },

  // Off-topic
  { cat: "offtopic-near",  fixture: FIXTURE_FULL, q: "what should I eat before tomorrow's brick?" },
  { cat: "offtopic-far",   fixture: FIXTURE_FULL, q: "should I buy aero bars before the race?" },

  // Edge cases — degraded context
  { cat: "edge-no-plan",   fixture: FIXTURE_NO_PLAN, q: "how should I train this week?" },
  { cat: "edge-rest-day",  fixture: FIXTURE_REST_DAY, q: "what's today's session?" },

  // Yesterday hallucination regression
  { cat: "yesterday",      fixture: FIXTURE_FULL, q: "how did yesterday's session go?" },
];

// ── CLI args ──────────────────────────────────────────────────────────────────
const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const m = a.match(/^--([^=]+)(?:=(.*))?$/);
    return m ? [m[1], m[2] ?? true] : [a, true];
  })
);

let cases = CASES;
if (args.only) cases = cases.filter((c) => c.cat.startsWith(args.only));
if (args.case) cases = [CASES[Number(args.case)]].filter(Boolean);

// ── Run ───────────────────────────────────────────────────────────────────────
console.log(`\nCoach Chat V0 — running ${cases.length} cases against gpt-4.1\n`);
console.log("=".repeat(80));

let totalIn = 0, totalOut = 0, totalCached = 0;

for (const [i, c] of cases.entries()) {
  const dynamic = renderDynamic(c.fixture);
  const t0 = Date.now();

  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${KEY}` },
    body: JSON.stringify({
      model: "gpt-4.1",
      temperature: 0.3,
      max_tokens: 400,
      messages: [
        { role: "system", content: STATIC.trim() },
        { role: "user", content: dynamic.trim() },
        { role: "user", content: c.q },
      ],
    }),
  });
  const data = await res.json();
  const dt = Date.now() - t0;

  if (data.error) {
    console.log(`\n[${i}] [${c.cat}] ${c.q}\n  ERROR: ${data.error.message}\n`);
    continue;
  }

  const reply = data?.choices?.[0]?.message?.content?.trim() ?? "";
  const u = data?.usage ?? {};
  const cached = u.prompt_tokens_details?.cached_tokens ?? 0;
  totalIn += u.prompt_tokens ?? 0;
  totalOut += u.completion_tokens ?? 0;
  totalCached += cached;

  // Sentence count (rough)
  const sentenceCount = (reply.match(/[.!?](?:\s|$)/g) ?? []).length;

  console.log(`\n[${i}] [${c.cat}]  user: ${c.q}`);
  console.log(`     ${dt}ms | in=${u.prompt_tokens} (cached=${cached}) | out=${u.completion_tokens} | sentences≈${sentenceCount}`);
  console.log(`     coach: ${reply.replace(/\n/g, "\n            ")}`);
}

console.log("\n" + "=".repeat(80));
console.log(`Totals: in=${totalIn} (cached=${totalCached}, ${totalIn ? Math.round(100*totalCached/totalIn) : 0}%) | out=${totalOut}`);
const cost = (totalIn - totalCached) * 2 / 1e6 + totalCached * 0.5 / 1e6 + totalOut * 8 / 1e6;
console.log(`Approx cost: $${cost.toFixed(4)}  (gpt-4.1: $2/$0.5/$8 per M for in/cached/out)`);
