# Competitive Landscape

> **Last updated:** 2026-05-02
> **Maintained by:** Fio (CTO) + Donald (CMO research)
> **Purpose:** Single source of truth for who Dromos competes with, where the threat is real, and where the wedge is. Read before any positioning, pricing, or roadmap decision.

---

## TL;DR — The Threat Map

| Tier | Players | Why they matter |
|---|---|---|
| **Tier 1 — Direct, must out-position** | TriDot, Stamina, Humango, Athletica.ai, Runna, AI Endurance, Garmin Coach | Same ICP or same AI-coaching claim. These shape how users frame the category. |
| **Tier 2 — Adjacent, structurally dangerous** | Strava (+ Runna + Breakaway), Garmin Connect+, TrainingPeaks, Coopah | Distribution, hardware lock-in, or incumbent default. Won't kill us tomorrow; could box us in over 12-24 months. |
| **Tier 3 — Funnel feeders / integration targets** | Nike Run Club, Apple Fitness+ / Watch, Coros, Suunto, Polar, Wahoo SYSTM, Adidas Running, Whoop, Oura, Campus Coach (US) | Different jobs-to-be-done. Integrate with, graduate from, or ignore. |

**Working positioning hypothesis (to stress-test):**
> *"Dromos is the iOS triathlon coach that reads your Garmin and rewrites your plan — the way a real coach would, every day."*

That sentence is engineered to defeat:
- **Stamina** (no physiology) — they adapt to your calendar, we adapt to your body.
- **Athletica** (web-first, multi-sport) — we are iOS-native, triathlon-only.
- **TriDot** (opaque, expensive, legacy UX) — we are transparent, modern, mobile-first.
- **Humango** (chatbot-y) — we show reasoning, not personality.
- **TrainingPeaks** (no AI, needs a human coach) — we are autonomous.
- **Garmin Coach** (Garmin owns the data but doesn't use it) — we use it the way Garmin should.

---

# 1. Triathlon-Focused Apps (Top 5)

## 1.1 Stamina — **HIGH threat (most direct analog)**
- **Positioning:** "The simplest way to train for a triathlon." Beginner-friendly personalized plans, Sprint to Ironman.
- **Target user:** First-timers and busy intermediates, 20–40, digitally-native. Sprint–70.3 sweet spot. Not chasing elites.
- **Key features:** Onboarding captures race/time/discipline background, 650+ workouts, Garmin + Apple Watch + Strava sync, swap-session ("easier/harder") flow, coach comments explain rationale.
- **AI / adaptivity:** Rule-based plan gen co-designed with pro coaches (Greg Harper swim, Ari Klau bike/run). Adapts to **schedule**, not physiology.
- **Pricing:** $14.99/mo or $119.99/yr. 14-day free trial.
- **Platform:** iOS only. Apple Watch + Garmin + Strava.
- **Strengths:** Cleanest UX in the category. Pro-coach pedigree without pro-coach price. Strong content (TikTok/IG/YT @joinstamina). Ex-PM founders who get consumer mobile.
- **Weaknesses:** Light on adaptivity intelligence. No HRV/readiness-driven adjustments. No race prediction. Brand new (late 2024) — small dataset.
- **Dromos wedge:** **Physiological adaptivity.** Stamina adapts to your calendar; Dromos adapts to your *body*. That "AI coach that actually reads your data" pitch is unclaimed.

## 1.2 TriDot — **MEDIUM-HIGH threat (owns "AI tri" mindshare)**
- **Positioning:** "AI-powered triathlon training. Less training, better results." 20 years of "FitLogic" data.
- **Target user:** Serious age-groupers, intermediate-to-advanced, long-course (70.3/IM) heavy. Now official IRONMAN partner; took over IRONMAN University in 2024.
- **Key features:** Race time prediction (well-regarded), workout library + video, gamification/XP, multi-discipline load balancing, optional human coach add-on.
- **AI / adaptivity:** Proprietary ML on historical data. "Minimum effective dose." Methodology opaque.
- **Pricing:** $14.99 → $29 → $89 → $129 → $199/mo Premium with coach. No free tier.
- **Platform:** iOS, Android, web. Garmin/Wahoo.
- **Strengths:** Race prediction accuracy. Brand recognition + IRONMAN partnership. Comprehensive feature breadth.
- **Weaknesses:** Expensive, confusing 5-tier pricing. "Clunky app" on Slowtwitch. Aggressive billing/marketing complaints (Trustpilot, Reddit). Black-box methodology.
- **Dromos wedge:** **Transparent, modern, mobile-native, fairly priced.** "TriDot for people who don't want a 5-tier subscription and a cluttered dashboard." Lean into real-time wearable adaptivity over historical-dataset claims.

## 1.3 Athletica.ai — **MEDIUM-HIGH threat (closest physiology story)**
- **Positioning:** "Train Smarter. Finish Stronger. Live Healthier." Sports-science-driven; built by physiologists.
- **Target user:** Self-coached, intellectually curious intermediate-to-advanced. Multi-sport: tri, run, cycling, rowing, HYROX, XC ski.
- **Key features:** Adaptive plans w/ cross-discipline load mgmt. Conversational AI Coach grounded in curated sport-science KB. Nightly HRV + RHR vs RPE cross-check. Suggests lighter/similar/harder alternatives. 52-week plans.
- **AI / adaptivity:** Hybrid — rule-based sport-science engine + LLM coach layer. **Suggests, doesn't auto-modify** (athlete keeps control).
- **Pricing:** $19.90/mo, $99/6mo, $189/yr. Single tier.
- **Platform:** iOS, Android, web. Garmin, Wahoo, Coros, Polar, Suunto, Apple Watch (via Strava/Intervals.icu), Concept2.
- **Strengths:** Methodology transparency (founder Paul Laursen, published physiologist). Single-price simplicity. Best-in-class AI Coach interaction per Slowtwitch. Multi-sport breadth.
- **Weaknesses:** "Limited customization beyond delete/reschedule." No race prediction. iOS app newer than web — desktop feels primary. Interface is more analyst than consumer.
- **Dromos wedge:** **Mobile-first, triathlon-only, schedule-aware.** Athletica is a multi-sport platform retrofitted to mobile. Beat them on UX polish and tri-specific depth.

## 1.4 Humango — **HIGH threat (closest functional overlap)**
- **Positioning:** AI-powered, multi-sport personalized training planner; official partner of Challenge Family.
- **Target user:** Experienced age-groupers wanting flexibility. Olympic to full IM.
- **Key features:** Plan gen across tri/run/cycling. "Hugo" conversational coach (ChatGPT-backed). HRV/recovery integration (Garmin Body Battery, WHOOP) — proactively backs off when recovery tanks. Strong reschedule logic. Zwift workout push for cycling.
- **AI / adaptivity:** Heavy ML + wearable-data driven. Auto-adjusts intensity based on recovery.
- **Pricing:** $19/mo (single sport), $29/mo tri tier. 30-day free trial, no CC required.
- **Platform:** iOS, Android, web.
- **Strengths:** Genuinely adaptive to physiological state — exactly Dromos's wedge. Generous free trial. Challenge Family distribution.
- **Weaknesses:** "Fallacious AI behavior" reported in forums. Methodology opacity. UI less polished than Stamina/Athletica. Lower US brand awareness than TriDot.
- **Dromos wedge:** **Out-execute on iOS UX + trust/transparency.** Hugo feels gimmicky to many users. Show *reasoning* behind every adjustment, not just a chat bubble.

## 1.5 TrainingPeaks — **LOW-MEDIUM threat (different category, but the fallback)**
- **Positioning:** "The world's most complete training platform." Industry-standard coach-athlete workspace.
- **Target user:** Serious athletes working *with* a human coach + self-coached buying plans. Default tool of the coaching profession.
- **Key features:** Calendar, structured workout builder, PMC/TSS/CTL, plan marketplace (1000s of tri plans), workout sync everywhere, coach-athlete messaging.
- **AI / adaptivity:** Essentially none. TP is a *platform*, not a coach.
- **Pricing:** Free basic (heavily nerfed). Premium $19.99/mo or $119.99/yr. Plans $20–$50.
- **Platform:** iOS, Android, web. Best-in-class device integrations.
- **Strengths:** Coach network effects — if your coach uses TP, you use TP. Deepest analytics. Most plan inventory. Reliability + integrations.
- **Weaknesses:** Dated UI. Plans don't auto-adapt. "Useless without a coach" sentiment on Reddit/Slowtwitch. Steep curve. Free tier crippled.
- **Dromos wedge:** **TP is the spreadsheet of triathlon training.** Dromos is the opposite: opinionated, adaptive, mobile-first, no coach required. Frame the choice as "rent a TP coach for $250/mo + pay for TP + manage two apps" vs "open Dromos, train, race."

---

# 2. Running-Focused Apps (Top 10)

## 2.1 Runna — **HIGH threat (category-defining brand + Strava distribution)**
- **Tagline:** "#1 rated personalized training plans for running" — Strava-owned (April 2025).
- **Target user:** Intermediate runners, 5K → marathon. Younger, gear-aware, social.
- **Key features:** ML-generated personalized plans, daily pace adaptation, structured workouts to Garmin/Apple Watch/COROS/Suunto/Fitbit, in-app real-coach Q&A, strength sessions, race-day pacing.
- **AI / adaptivity:** ML adjusts pace targets from completed-workout performance. Not deeply physiological.
- **Pricing:** £15.99/mo or ~£9.99/mo annual ($17.99/mo or $112.99/yr). 1-week free.
- **Platform:** iOS, Android, web; broad watch support.
- **Strengths:** Polished UX. Apple App of the Year 2024 finalist. Strava distribution moat. 2M+ MAU.
- **Weaknesses:** **Growing injury reputation** — "Runna plans get you injured" meme on r/Marathon_Training; PT clinics report multiple cases weekly. Aggressive defaults, weak sick/injury pause flow, ignores weather/heat, support criticized.
- **Dromos wedge:** **"Adapts before you break."** Lead with HRV/sleep/readiness-driven *de-loading* — solve Runna's #1 weakness (overtraining). Triathlon coverage is a structural moat Runna won't enter.

## 2.2 Campus Coach (campus.coach, by MWM) — **MEDIUM-HIGH in EU, LOW in US**
> ⚠️ **Note:** No verified link to Steve Magness. campus.coach is a French/European product from MWM (600K runners). If we meant a different "Campus Coach," confirm.
- **Target user:** Europe-skewing road and trail runners, 5K → 300K ultras. Beginner-to-advanced.
- **Key features:** Goal-based plan gen, adjusts to missed sessions, Garmin/Suunto/Coros/Strava/Apple Watch sync, in-app real-coach chat, nutrition + recovery content, strong community.
- **AI / adaptivity:** Rule-based + 5 years of coach methodology + human-coach-in-the-loop. Self-reports 3.7x lower injury risk vs. comparators.
- **Pricing:** Freemium (~€10–15/mo).
- **Platform:** iOS + Android.
- **Strengths:** Trail/ultra coverage (rare). Strong community. Real coach access. 600K user base.
- **Weaknesses:** France/EU-centric. Light wearable physiology depth. Less polished EN positioning.
- **Dromos wedge:** Win the **"data-native" runner**. Campus is methodology + community; Dromos is physiology + AI. In English markets, beat them to mindshare.

## 2.3 Nike Run Club — **MEDIUM (owns top of funnel)**
- **Target user:** Beginner-to-intermediate, casual-to-aspirational. Couch-to-5K through marathon.
- **Key features:** 6 plan templates, ~300 audio-guided runs, milestone unlocks, leaderboards, weather/safety, location sharing. 2026 added light AI for difficulty adjustment.
- **Pricing:** **Free** (Nike-funded).
- **Strengths:** Free + Nike brand. ~400K new iOS DLs in early 2026 (US). Best-in-class audio runs. Gamification.
- **Weaknesses:** Plans static-ish, weak watch integration, no recovery/HRV, no triathlon.
- **Dromos wedge:** **Position as the "graduation" app.** "Started with NRC? Outgrew it? Dromos is what comes next." Feed off NRC's funnel.

## 2.4 Garmin Coach — **HIGH for top-of-funnel Garmin runners**
- **Target user:** Garmin owners training for 5K/10K/half. Beginner-intermediate.
- **Key features:** Free adaptive plans from named coaches (Galloway, McMillan, Parkerson-Mitchell). Auto-push to watch. Light pace adaptation.
- **Pricing:** **Free** with any Garmin watch.
- **Strengths:** Zero friction. Free. Watch-native execution. Trusted coach names.
- **Weaknesses:** Pace targets unrealistic (LSD set 80sec/mi too fast per Garmin Forums). No consecutive rest days. No injury pause. Ignores off-plan runs. No marathon plan. **No HRV-driven adjustment despite Garmin owning the data.** UX Collective viral piece: "Garmin has all my data — so why did Runna build me a better plan?"
- **Dromos wedge:** **This is the perfect attack surface.** "We use your Garmin data the way Garmin should." HRV + readiness + race predictor become *training inputs*, not just dashboard widgets.

## 2.5 TrainingPeaks (running side) — see §1.5

## 2.6 Adidas Running (Runtastic) — **LOW-MEDIUM**
- Casual to intermediate runners; lifestyle/fitness crossover.
- GPS + voice coach + adaptive plans + community + Adidas brand integration.
- $9.99/mo or $49.99/yr. Cheapest premium tier.
- Personalization shallow vs. Runna/Dromos. No HRV.
- **Don't bother attacking** — different ICP (fitness, not racing).

## 2.7 Strava (Premium / Training) — see §3.1

## 2.8 Coopah — **MEDIUM (wins value-seekers; "Runna alternative" search)**
- Beginners and value-seekers. Tom's Guide called it "better than Runna for beginners."
- Personalized plans w/ dynamic pacing, real-coach Q&A (<1hr), strength sessions, Race Day Confidence Score, syncs to Apple Watch/Garmin/Suunto/Coros.
- £14.99/mo or £79.99/yr. 2-week free trial.
- **Dromos wedge:** Position higher: "Coopah is human coach + simple AI. Dromos is autonomous coach driven by your physiology." Don't compete on price.

## 2.9 AI Endurance — **HIGH (closest direct competitor — study most carefully)**
- "AI Running, Cycling, and Triathlon Coach." Direct multi-sport overlap.
- AI plan gen + adaptation from HRV, training load, recovery. Race predictor, nutrition tool, AI assistant chat.
- $12.99/mo annual; $25.89/mo monthly. 14-day free trial.
- iOS, Android, web; Garmin/Strava/Polar.
- Strong cycling testimonials (FTP gains). HRV-informed adaptation. Triathlon support.
- Smaller user base, weaker brand, running side less mature than cycling, UI dated.
- **They beat us to the category claim.** Dromos wedge: **iOS-native polish, modern UX, Garmin race-prediction integration, triathlon/running-native** (vs. their cycling-rooted, web-first DNA).

## 2.10 Humango (running side) — see §1.4

---

# 3. Major Platforms (Strava, Garmin, Coros, Apple, Polar, Suunto, Wahoo, Whoop, Oura)

## 3.1 Strava — **HIGH threat (the primary one)**
- **Coaching ambition:** Was tracker + social feed. Pivoted hard 2024-25. **Athlete Intelligence** (gen-AI workout summaries) GA Feb 2025. Acquired **Runna** April 2025 (running AI plans). Acquired **The Breakaway** May 2025 (cycling AI). Shipped "Instant Workouts" 2026 (DC Rainmaker called the implementation "problematic"). Subscription $11.99/mo or $79.99/yr; Runna kept separate at $19.99.
- **DC Rainmaker's read:** Strava's in-house AI wasn't good enough, so they bought it. Strategy: "one-stop shop for weekend endurance warriors."
- **Strengths vs Dromos:** 150M+ users. Owned distribution. Social graph. Running + cycling AI plan tech now in-house. Brand = endurance.
- **Weaknesses vs Dromos:** **No swim coaching. No triathlon multisport plan integration.** Apps deliberately separate (Runna ≠ Strava ≠ Breakaway) — no unified triathlete experience. AI is generic-by-design — built for the median runner, not periodized A-race prep.
- **Strategic implication:** **Out-execute on triathlon depth NOW.** Dromos = "what Strava can never be: a single brain that periodizes all three sports against your A-race." **Integrate with Strava** (export workouts to feed) — don't fight the social graph, ride it.
- **🚨 Watch trigger:** If Strava acquires **MySwimPro** or similar swim coaching app in the next 12 months, our window narrows fast. **Set a Google Alert.**

## 3.2 Garmin — **HIGH threat (structural, slow-moving)**
- **Coaching ambition:** Garmin Coach (run, bike) + **Daily Suggested Workouts** (DSW, since 2020) — adjusts daily on training load, recovery, VO2 max. **March 2025: Garmin Connect+** launched ($6.99/mo / $69.99/yr) — first paid tier — including **Active Intelligence** (AI insights), expert training guidance, exclusive coach content. CEO confirmed Nov 2025 paywall keeps growing. DSW upgrades on Fenix 8 / Forerunner 970.
- **Strengths vs Dromos:** **Hardware lock-in is brutal.** Forerunner/Fenix owners get watch face, workout queue, recovery, training readiness — native integration we can never match. Free tier still rich.
- **Weaknesses vs Dromos:** **No true triathlon-specific adaptive plan that integrates swim + bike + run periodization** (confirmed ChiliTri 2025). Garmin Coach is single-sport. DSW is single-sport. Connect+ training guidance is video content, not a personalized multisport plan. Algorithm is a black box — no rationale, no coach voice.
- **Strategic implication:** **Integrate deeply (we already do). Position on transparency + triathlon depth.** Messaging: "Your Garmin tells you what your body did. Dromos tells you what to do next, across all three sports, and why." Watch the next two Connect+ feature drops.

## 3.3 Coros — **MEDIUM**
- **EvoLab** (adaptive sports-science layer, 6 weeks of data) + **Training Hub** (free web platform with predictive analytics, drag-and-drop plan building, two-way coach comms).
- Free. Strategy: give software away to sell watches.
- Tools oriented to **human coaches**, not autonomous AI. EvoLab analyzes — doesn't prescribe a tri plan. No real GenAI play yet.
- **Action:** Ignore for now. Coros users are an ICP segment we can win — they bought hardware on the cheap and need a brain.

## 3.4 Apple Fitness+ / Apple Watch — **LOW today, MEDIUM long-term**
- watchOS 11 (June 2024) added **Training Load** + **Vitals app** (overnight HR, respiration, wrist temp, SpO2, sleep). Custom workouts with swim intervals shipped. Fitness+ is class-based content, not adaptive coaching.
- Apple does not do periodized plans. No race goal. No adaptive coaching. Apple Watch hardware sub-par for serious tri (battery, swim accuracy).
- **Action:** **Distribution + data source, not competitor.** Use HealthKit. Surface Vitals + Training Load inside Dromos so users feel native.

## 3.5 Polar — **LOW**
- FitSpark (free, daily 2-4 suggestions on Nightly Recharge). April 2025: **Polar Fitness Program** ($8.99/mo) — adaptive plans, rest day planning, calendar. DC Rainmaker: "hold my beer" — Polar fighting for relevance.
- Hardware install base shrinking. No tri focus. No AI story.
- **Action:** Ignore.

## 3.6 Suunto — **LOW-MEDIUM (open ecosystem opportunity)**
- **SuuntoPlus Guides** = open API for third-party coaching apps (Humango, RunMotion, AIEndurance, Runna). Q4 2025 / Jan 2026: launched own **AI Coach** (AI plans, ZoneSense intensity, Recovery State combining HRV + sleep + subjective + history).
- Small install base. Open ecosystem is interesting.
- **Action:** **Build a SuuntoPlus Guide for Dromos.** Cheap distribution to a high-intent endurance user base. Suunto users match our ICP profile (premium, serious).

## 3.7 Wahoo / SYSTM — **LOW-MEDIUM (different ICP)**
- Indoor/structured cycling training; multisport plans bolted on. **4DP power profiling**, rider-type classification, structured workouts. **SYSTM Plan Builder** offers tri plans with run/swim. Mid-2025: Zwift integration. $17.99/mo.
- Cycling-first DNA, not adaptive AI. More similar to TrainerRoad than to us.
- **Action:** Avoid. Wahoo SYSTM users are gear-heads optimizing the bike leg. Our ICP is the time-crunched age-grouper who wants the brain to do the work.

## 3.8 Whoop — **MEDIUM (only wellness wearable building prescriptive coaching)**
- **Strain Coach** (real-time intensity guidance). **WHOOP Coach** (OpenAI-powered chat over your data, persistent memory as of 2025). 2025: revamped Weekly Plan (adaptive targets), Daily Outlook (push/rest each morning), AI guidance integrating strain + sleep + stress + lab results.
- **Strategic implication:** **Differentiate on goal-orientation.** Whoop optimizes for daily recovery. Dromos optimizes for race day. "Whoop tells you if you should train hard today. Dromos tells you what specific session to do this week to be ready in 14 weeks." Also: **integration opportunity** — Whoop recovery into our adjustment engine.

## 3.9 Oura — **LOW (integration target)**
- **Oura Advisor** (AI health coach with persistent "Memories"). Conversational, not prescriptive.
- Wellness, not endurance training. Will not periodize a triathlon plan.
- **Action:** Integrate Oura readiness as input to Dromos's daily adjustment.

---

# 4. Strategic Takeaways

## 4.1 The hardest competitors, ranked
1. **Stamina** — same ICP, same DNA, same price band. The most direct analog.
2. **Strava + Runna bundle** — distribution + AI plan tech together. Most dangerous combo in the market.
3. **TriDot** — owns "AI tri" mindshare and IRONMAN partnership.
4. **Humango + Athletica** — hardest physiology/adaptivity comparisons.
5. **Garmin Coach** — free default for any Garmin owner.
6. **AI Endurance** — closest direct multi-sport AI competitor; got there first on category claim.

## 4.2 Pick the enemy publicly
Right now we're either-or on Strava/Garmin/TriDot positioning. **Pick one to define against in messaging** — Donald's vote: **TriDot** ("the modern, mobile-first triathlon brain") with **Strava as the distribution layer we feed.**

## 4.3 Whitespace
**iOS-native + triathlon-only + Garmin-deep + transparent reasoning, all at once.** No competitor combines all four.

## 4.4 Open questions to sharpen positioning
1. What's Dromos's actual price point and free trial structure?
2. Is there a human-coach option, or pure software?
3. Planned non-Garmin support (Apple Watch native? Wahoo? Coros?)
4. All distances at launch (Sprint → IM), or pick a wedge?
5. Confirm which "Campus Coach" we're tracking (campus.coach MWM vs. another).

## 4.5 Things to do
- **Build Suunto + Garmin Connect IQ + (eventually) Coros integrations** — cheap distribution into our ICP and creates switching cost back to a watch ecosystem alone.
- **Set a Google Alert for Strava swim acquisitions** (MySwimPro especially).
- **Stress-test the positioning hypothesis** in user interviews before locking it in.

---

# 5. Sources

**Triathlon (§1):**
- [Stamina](https://www.joinstamina.com/) · [App Store](https://apps.apple.com/us/app/stamina-triathlon-training/id6737915514) · [Fitt Insider launch](https://insider.fitt.co/press-release/stamina-launches-personalized-triathlon-training-app-for-beginners/)
- [TriDot](https://tridot.com/) · [Pricing](https://www.tridot.com/pricing) · [Slowtwitch user thread](https://forum.slowtwitch.com/t/any-tridot-users/794702) · [Trustpilot](https://www.trustpilot.com/review/tridot.com)
- [Athletica.ai](https://athletica.ai/) · [Pricing](https://athletica.ai/pricing) · [App Store](https://apps.apple.com/us/app/athletica-ai-training-plans/id6737747559)
- [Humango](https://humango.ai/) · [App Store](https://apps.apple.com/us/app/humango-ai-training-planner/id1554430755) · [Slowtwitch thread](https://forum.slowtwitch.com/t/humango-ai-training/811880)
- [TrainingPeaks pricing](https://www.trainingpeaks.com/pricing/for-athletes/)
- [Slowtwitch — Triathlon AI thoughts](https://forum.slowtwitch.com/t/triathlon-ai-training-thoughts-tridot-humango-athletica-2peaks-triq/831893)
- [Triathlete — 8 AI Triathlon Apps Reviewed](https://www.triathlete.com/gear/tech-wearables/ai-triathlon-training-apps/)
- [220 Triathlon — Best apps 2026](https://www.220triathlon.com/gear/tri-tech/best-triathlon-training-apps-review)

**Running (§2):**
- [Runna](https://www.runna.com/) · [the5krunner injury piece](https://the5krunner.com/2026/02/21/runna-ai-marathon-training-injury/) · [Tom's Guide review](https://www.tomsguide.com/reviews/runna-app)
- [Campus Coach](https://www.campus.coach/en) · [Trustpilot](https://www.trustpilot.com/review/campus.coach) · [App Store](https://apps.apple.com/ca/app/campus-coach-running-trail/id6446962176)
- [Nike Run Club](https://apps.apple.com/us/app/nike-run-club-running-coach/id387771637) · [Nike newsroom](https://about.nike.com/en/newsroom/releases/nike-run-club-app-new-features)
- [Garmin Coach](https://www.garmin.com/en-US/garmin-coach/running/) · [UX Collective: Garmin vs Runna](https://uxdesign.cc/garmin-has-all-my-data-so-why-did-runna-build-me-a-better-training-plan-915f4ff316b5) · [Garmin Forums complaints](https://forums.garmin.com/sports-fitness/running-multisport/f/forerunner-955-series/435530/garmin-coach-plan)
- [Coopah](https://coopah.com/) · [Tom's Guide](https://www.tomsguide.com/wellness/fitness/im-using-the-coopah-running-app-to-train-for-a-marathon-and-its-better-than-runna-for-beginners) · [TechRadar](https://www.techradar.com/health-fitness/coopah-app-review-an-ideal-reasonably-priced-running-companion-app)
- [AI Endurance](https://aiendurance.com/en) · [AIChief review](https://aichief.com/ai-productivity-tools/ai-endurance/)
- [Adidas Running review (Tom's Guide)](https://www.tomsguide.com/reviews/adidas-running-app)

**Platforms (§3):**
- [Strava → Runna acquisition](https://press.strava.com/articles/strava-to-acquire-runna-a-leading-running-training-app) · [DC Rainmaker thoughts](https://www.dcrainmaker.com/2025/04/strava-acquires-runna-thoughts-forward.html) · [TechCrunch on Breakaway](https://techcrunch.com/2025/05/22/strava-is-buying-up-athletic-training-apps-first-runna-and-now-the-breakaway/) · [Athlete Intelligence](https://stories.strava.com/articles/meet-athlete-intelligence-personalized-ai-insights-that-help-you-reach-your) · [DC Rainmaker — Instant Workouts](https://www.dcrainmaker.com/2026/01/stravas-instant-workouts-actually.html) · [TechRadar — Garmin should panic](https://www.techradar.com/health-fitness/strava-acquires-powerhouse-ai-training-platform-runna-and-garmin-should-be-panicking)
- [Garmin Connect+ launch](https://www.garmin.com/en-US/newsroom/press-release/wearables-health/elevate-your-health-and-fitness-goals-with-garmin-connect/) · [DC Rainmaker walkthrough](https://www.dcrainmaker.com/2025/03/garmin-connect-plus-subscription-walkthrough.html) · [Tom's Guide $6.99 paywall](https://www.tomsguide.com/wellness/smartwatches/garmin-launches-a-paywall-here-are-all-the-premium-connect-features-that-will-cost-you-usd6-99-a-month) · [ChiliTri Garmin vs Polar for triathletes](https://chilitri.com/blog/karenparnell01@hotmail.com/garmin-connect-vs-polar-fitness-program-which-subscription-is-best-for-triathletes-in-2025) · [Garmin DSW](https://www.garmin.com/en-US/garmin-technology/cycling-science/physiological-measurements/daily-suggested-workouts/) · [the5krunner — CEO confirms more paywall](https://the5krunner.com/2025/11/06/garmin-connect-plus-paywall-new-features/)
- [COROS Training Hub](https://coros.com/traininghub) · [EvoLab](https://support.coros.com/hc/en-us/articles/4412789816724-EvoLab)
- [Apple watchOS 11](https://www.apple.com/newsroom/2024/06/watchos-11-brings-powerful-health-and-fitness-insights/) · [DC Rainmaker — Training Load 30 days](https://www.dcrainmaker.com/2024/07/apples-training-load-vitals-watchos11.html)
- [DC Rainmaker — Polar Premium](https://www.dcrainmaker.com/2025/04/polar-launches-premium-subscription-service-says-hold-my-beer.html) · [the5krunner — Polar details](https://the5krunner.com/2025/04/10/new-polar-subscription-fitness-program-details/)
- [Suunto Coach AI](https://www.suunto.com/News/level-up-your-training-with-suunto-coach--now-smarter-with-ai/) · [SuuntoPlus Guides partners](https://www.suunto.com/Support/faq-articles/suuntoplus/which-partners-offer-suuntoplus-guides/) · [Gadgets & Wearables Q4](https://gadgetsandwearables.com/2026/01/07/suunto-q4-2025-update/)
- [Wahoo SYSTM](https://www.wahoofitness.com/blog/what-is-systm/) · [TriDot vs Wahoo SYSTM](https://www.mymottiv.com/compare/tridot-vs-wahoo-systm)
- [WHOOP Coach + OpenAI](https://www.whoop.com/us/en/thelocker/whoop-unveils-the-new-whoop-coach-powered-by-openai/) · [WHOOP 2025 launches](https://www.whoop.com/us/en/thelocker/everything-whoop-launched-in-2025/) · [New AI Guidance](https://www.whoop.com/us/en/thelocker/new-ai-guidance-from-whoop/)
- [Oura Advisor](https://ouraring.com/blog/oura-advisor/) · [Fitt Insider](https://insider.fitt.co/oura-launches-ai-health-coach/)
