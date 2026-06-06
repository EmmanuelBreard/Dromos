# Coach Analysis — Emmanuel Breard, 6-month block (2025-12-01 → 2026-06-01)

Anchored to Nîmes 70.3 (2026-05-31). Goal race for the next block: TBD.

Anchors:
- HRmax: 193 bpm
- FTP: 275 W (set 2025-10-10; not stale)
- Run threshold pace: ~4:11/km (anchored on Garmin HM prediction 1:28:12)
- Sessions analyzed: 62 bikes, 73 runs (incl. Nîmes 70.3 run leg), 35 swims, 2 strength

---

## TL;DR — Verdict

You trained more like a polarized triathlete than the first pass suggested. Real numbers, computed lap-by-lap from FTP power zones and pace zones (not just session average HR):

- **Combined LIT / MIT / HIT = 82% / 9% / 9%** across 140 hours of bike+run
- **14 bike sessions** had ≥10 minutes inside Z4+ (true threshold-or-above work). The "0 hard bikes" claim from the avg-HR analysis was wrong.
- **14 run sessions** had ≥10 minutes inside Z4+. Most were race-pace/tempo blocks (Z3-Z4 sustained), with one true VO2 session (5×3min @ 3:30/km on 2026-05-05).
- Volume ramp into Nîmes was clean, fueling experiments worked (per athlete debrief), race execution validated the block.

Distribution looks polarized on paper. The shape of the HIT, however, is heavily weighted toward **sweet-spot / threshold continuous** rather than VO2max intervals — both on the bike (long 5km @ 260W blocks = ~95% FTP = Z4) and on the run (15-17km @ 4:40/km = Z3-Z4 sustained). That's fit-for-purpose for a 70.3, less ideal if next race is shorter and faster.

---

## §1 — Headline observations

- **You're a polarized aerobic athlete with a sweet-spot ceiling.** Plenty of HIT volume (~12.3h over 6 months), but the HIT shape is mostly sub-threshold / threshold continuous, not above-FTP / VO2. Only **2 sessions** of the entire block crossed clearly into Z5 power on the bike (6×3min @ 298W = IF 1.08), and only **1 run** had clean VO2-pace intervals (5×3min @ 3:30/km).
- **Endurance base is solid:** 115h of LIT across 73 runs and 62 bikes — that's an average of ~4.5h/wk pure aerobic. This is where 70.3 fitness lives.
- **Bike NP is reliable, outdoor rides aren't.** 51 of 62 bikes had power; 11 outdoor rides (incl. all big endurance rides) had no power. Best 3-month outdoor stretch was ~330W peak laps on indoor trainer with NP-averaged sessions running at 0.84 IF. The athlete has the engine for more if outdoor power data was captured.
- **Run pace zones are dictated by terrain.** Most "tempo" sessions are Boulogne-Billancourt loops at consistent 4:40/km = Z3 by Friel, which is exactly half-marathon race pace. This is intentional volume at race-specific intensity but lacks above-threshold stress.
- **Race result (Nîmes 70.3):** bike leg @ NP=178W (IF 0.65 = solid Z2), run leg @ 5:12/km avg with HR 168 → drift / fatigue showing. The HR was Z4 even though the pace was Z2 — classic aerobic-decoupling pattern at end of half.

---

## §2 — Volume & consistency

(Unchanged from prior analysis — restated here for completeness.)

- Run frequency: 73 runs in 26 weeks ≈ 2.8 runs/week, very consistent
- Bike frequency: 62 sessions ≈ 2.4/week, heavily indoor (49/62 indoor)
- Swim frequency: 35 sessions ≈ 1.3/week, room to grow
- Strength: 2 sessions ≈ near-zero. This is a gap.
- Volume ramp into Nîmes was clean; no major training gaps >5 days
- Last 4 weeks before race: appropriate taper signal in load data

---

## §3 — Intensity distribution (RECOMPUTED with FTP-based power zones & pace-based run zones)

### Methodology note (important — this is the key change)

The previous analysis used **session-average HR** to classify intensity. That approach systematically under-counts interval work: a 60-min indoor cycling session with 6×5min @ 270W (Z4) interleaved with 6×5min recovery (Z1) ends up averaging ~145 bpm = Z2 by HR. The session-average looks easy aerobic; the actual stress profile is threshold intervals.

This recompute uses:
- **Bike:** Normalized Power (NP) and FTP=275W for session IF; lap-level avg_power_watts classified against Coggan zones for the 29 sessions with high training_effect (≥3.0) or interval-suggesting structure. Outdoor rides without power (11/62) use avg-HR fallback.
- **Run:** Lap-level avg_moving_speed_mps classified against Friel-style pace zones anchored on 4:11/km threshold pace. Splits pulled for all 16 run sessions with either interval-suggesting names or session-level avg pace ≤5:00/km.

### Power zones (Coggan, FTP = 275 W)

| Zone | Description | % FTP | Watts |
|---|---|---|---|
| Z1 | Recovery | <55% | <151 |
| Z2 | Endurance | 55-75% | 151-206 |
| Z3 | Tempo | 76-90% | 209-247 |
| Z4 | Threshold | 91-105% | 250-289 |
| Z5 | VO2max | 106-120% | 291-330 |
| Z6 | Anaerobic | 121-150% | 333-412 |

### Run pace zones (Friel, threshold = 4:11/km)

| Zone | Description | Pace | Speed |
|---|---|---|---|
| Z1 | Recovery | >5:50/km | <2.86 m/s |
| Z2 | Easy aerobic | 5:00-5:50/km | 2.86-3.33 |
| Z3 | Tempo | 4:30-4:59/km | 3.34-3.70 |
| Z4 | Threshold | 4:10-4:29/km | 3.71-4.00 |
| Z5 | VO2max | 3:30-4:09/km | 4.01-4.76 |
| Z5+ | Anaerobic | <3:30/km | >4.76 |

### Bike intensity (corrected, lap-resolved)

Total bike time: **69.8 h** across 62 sessions.

| Zone | Hours | % Time |
|---|---|---|
| Z1 | 7.5h | 10.7% |
| Z2 | 45.1h | 64.6% |
| Z3 | 11.3h | 16.1% |
| Z4 | 5.1h | 7.3% |
| Z5 | 0.9h | 1.3% |
| Z6/Z7 | 0.0h | 0.0% |

**Bike sessions with ≥10 min in Z4+ (true threshold-or-above): 14 of 62.**

The original NP-of-whole-session calculation found 0 sessions at IF≥0.91. That metric is misleading because warm-up + recovery dilute the NP; the actual intervals within those sessions are clearly above FTP. Maximum lap power observed: **300W (5× and 6× 3min blocks)** = IF 1.09 = clean Z5 VO2max.

### Top 15 hardest bike sessions (by HIT minutes within session)

| Date | Name | Total | HIT min | Session NP | IF | TE |
|---|---|---|---|---|---|---|
| 2025-12-26 | Indoor Cycling | 69min | 40 | 232W | 0.84 | 4.4 |
| 2026-01-02 | Indoor Cycling | 65min | 33 | 230W | 0.84 | 4.2 |
| 2026-01-15 | Indoor Cycling | 50min | 30 | 235W | 0.85 | 3.9 |
| 2026-05-15 | Indoor Cycling | 54min | 30 | 229W | 0.83 | 3.6 |
| 2026-03-01 | Indoor Cycling | 60min | 30 | 226W | 0.82 | 4.1 |
| 2026-01-08 | Indoor Cycling | 43min | 30 | 240W | 0.87 | 3.8 |
| 2025-12-23 | Indoor Cycling | 65min | 29 | 226W | 0.82 | 4.1 |
| 2026-03-07 | Indoor Cycling | 58min | 24 | 221W | 0.80 | 4.0 |
| 2026-05-26 | Indoor Cycling | 22min | 22 | 249W | 0.91 | 2.6 |
| 2026-04-08 | Indoor Cycling | 48min | 21 | 243W | 0.88 | 3.5 |
| 2026-02-15 | Indoor Cycling | 50min | 20 | 215W | 0.78 | 3.7 |
| 2026-04-01 | Indoor Cycling | 48min | 18 | 233W | 0.85 | 3.8 |
| 2026-04-15 | Indoor Cycling | 43min | 18 | 241W | 0.88 | 3.5 |
| 2025-12-10 | Indoor Cycling | 49min | 15 | 218W | 0.79 | 3.7 |

Note: April 1, April 8, April 15 each had 6×3min @ 298W = **above-FTP VO2 intervals**. The session NP looks tame (~233W = 0.85) but those laps cross into Z5.

### Run intensity (corrected, lap-resolved)

Total run time: **70.7 h** across 73 sessions (incl. Nîmes 70.3 run leg).

| Zone | Hours | % Time |
|---|---|---|
| Z1 | 7.3h | 10.3% |
| Z2 | 55.5h | 78.5% |
| Z3 | 1.6h | 2.3% |
| Z4 | 4.3h | 6.0% |
| Z5 | 1.9h | 2.7% |
| Z5+ | 0.2h | 0.2% |

**Run sessions with ≥10 min in Z4+ (true threshold-or-above): 14 of 73.**

### Top 15 hardest run sessions (by HIT minutes within session)

| Date | Name | Total | HIT min | Overall pace |
|---|---|---|---|---|
| 2026-05-17 | Boulogne 17k | 80min | 53 | 4:40/km |
| 2026-05-10 | Boulogne 20k | 95min | 43 | 4:45/km |
| 2026-05-14 | Boulogne 14k | 67min | 40 | 4:46/km |
| 2026-05-07 | Boulogne 11k | 49min | 34 | 4:32/km |
| 2026-01-27 | Paris 12k | 57min | 30 | 4:39/km |
| 2025-12-09 | Paris 11k | 53min | 24 | 4:45/km |
| 2026-01-24 | Paris 12k | 58min | 23 | 4:43/km |
| 2026-05-03 | Tempo 12+4k (Dromos plan) | 87min | 21 | 4:58/km |
| 2026-03-19 | Boulogne 12k | 56min | 19 | 4:49/km |
| 2026-05-19 | Boulogne 9k | 44min | 18 | 4:52/km |
| 2026-05-24 | Pornic 8k | 38min | 17 | 4:43/km |
| 2026-03-03 | Boulogne 11k | 50min | 16 | 4:41/km |
| 2026-04-05 | Boulogne 10k | 46min | 16 | 4:37/km |
| 2026-05-05 | 5×3min @ 3:30/km (VO2) | 42min | 15 | 5:03/km avg |

**Pattern:** Most "HIT" runs are sustained threshold/tempo continuous (15-50 min @ ~4:40/km = Z3/Z4 boundary), not classic VO2 intervals. The only true VO2 session was May 5 (5×3min @ ~3:25/km = Z5+). The May 17 session was a 14×1km block at Z4 pace — that's race-specific tempo.

### Combined Seiler 3-zone (revised)

LIT = Z1+Z2, MIT = Z3, HIT = Z4+Z5+Z5+/Z6.

| | Bike | Run | Combined |
|---|---|---|---|
| LIT | 75.3% | 88.8% | **82.1%** (115.3h) |
| MIT | 16.1% | 2.3% | **9.2%** (12.9h) |
| HIT | 8.6% | 8.9% | **8.8%** (12.3h) |

**This is a polarized distribution** — 82% LIT, 9% HIT — close to Seiler's 80/20 ideal. The 12.3h of HIT across 6 months is real and well-distributed (~2h/month).

The MIT% is bike-heavy (16% of bike time is Z3 tempo). That's the "sweet spot" zone — productive for 70.3 but starts to look like the "junk middle" if you're trying to peak shorter races.

---

## §4 — Bike-specific notes

(Restated and expanded.)

- **FTP estimate is probably conservative.** Multiple sessions show 6×3min @ 298W = IF 1.08 with HR peaks at 184 bpm (95% HRmax) — feasible but suggests true FTP is closer to 285W. Recommend a fresh 20-min test in early next block.
- **Indoor work is high-quality:** 49 indoor sessions, several at 60min+ with NP 226-235W = sustained low-Z4. These are doing the work.
- **Outdoor power is missing.** 11 outdoor rides represent ~27h of bike time with no power data. These are likely Z2 endurance rides but you can't confirm or use them in TSS planning. Adding a power meter on the road bike would close this gap.

---

## §5 — Run-specific notes

- **Threshold pace anchor (4:11/km) is consistent** with Garmin HM prediction (1:28:12). Race prediction confidence: high.
- **Tempo continuous dominates HIT.** Of the 14 "HIT" runs, only 1 (May 5 VO2) was true above-threshold intervals. The rest are 15-50 min sustained at Z3-Z4 boundary.
- **No track / structured speedwork** beyond the May 5 session. This is the biggest run-side gap for distances shorter than 70.3.
- **Long-run discipline is strong:** 18-20km runs at 4:40-4:50/km — that's race-pace endurance, which is exactly what 70.3 needed.

---

## §6 — Swim notes

(Unchanged — limited data.)

- 35 sessions ≈ 1.3/wk, mostly pool. Nîmes 70.3 swim leg was 1.7km in 32min (lake/sea) — solid for the discipline.
- Open-water exposure is low (1 OWS session in window). For next race build, increase OWS frequency if open-water is the format.

---

## §7 — Limiters & coach-facing questions (REVISED)

### Limiters (corrected)

1. **VO2max stimulus is light.** ~2h of clear Z5 work across 6 months. For 70.3 this is OK; for shorter races (10k, sprint tri, Olympic), this would be the gap to close.
2. **No outdoor power.** Closes the loop between training prescription and execution for big endurance rides.
3. **Strength is near-zero.** 2 sessions in 26 weeks. This is a durability + injury-prevention gap, not a fitness gap — but the next 6 months should include 1-2 strength sessions/wk.
4. **Run intensity is monotonic.** Most hard run work is at the same pace (4:40/km). Adding pace variance (true VO2 + threshold continuous + race-pace) would diversify the stimulus.
5. **MIT bias on the bike.** 16% of bike time is Z3 tempo — productive for 70.3 but worth watching if next race is shorter. Z3 is hard enough to require recovery but doesn't push the top end.

### Coach-facing questions for next block

1. **Next race target?** Short-course (10k, Sprint, Olympic) or another 70.3 / Ironman? Answer dictates whether VO2 work or threshold-continuous should dominate.
2. **Outdoor power solution?** Pedal-based meter, or rely on indoor as primary structured work?
3. **Strength tolerance & history?** Setting baseline before prescribing 2×/wk.
4. **Recovery between bike-run "brick" sessions?** Volume of brick work is implicit — would benefit from explicit programming.
5. **Confirm: no Alpe d'Huez 2026.** Per current scope.

---

## §8 — Data quality notes

- 51 of 62 bike sessions had Normalized Power (indoor)
- 11 outdoor bike sessions lack power data (17.7% of bike sessions, ~27h of training time) — analyzed via HR fallback
- 16 of 73 run sessions had lap-by-lap splits pulled for HIT identification (all session-avg pace ≤5:00/km or interval-named)
- All numbers above use lap-resolved zones where possible; whole-session NP/pace fallback where laps were ambiguous
- 29 bike sessions had splits analyzed; 16 run sessions had splits analyzed
- Pace zones treat the steady "Boulogne 4:40/km tempo" as Z3-Z4 — by Friel definition this is correct, but the athlete may consider these "easy quality" rather than "HIT"; the methodology preserves transparency

---

## Appendix — Source data
- Garmin MCP: `mcp__garmin__get_activities_by_date`, `get_activity`, `get_activity_splits`, `get_activity_power_in_timezones`
- Activity window: 2025-12-01 → 2026-06-01 (inclusive of Nîmes 70.3 race)
- Race: Nîmes 70.3, 2026-05-31 (Vers-Pont-du-Gard)
