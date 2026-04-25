# Feature Implementation Plan — Dromos Website (getdromos.com)

**Overall Progress:** `0%`

## TLDR
Build a 3-page marketing website (landing, support, privacy) for Dromos v1.0, deployed to Cloudflare Pages at getdromos.com. Required for App Store submission (Support URL, Marketing URL, Privacy Policy URL). Stack: Astro + Tailwind CSS, new public GitHub repo `dromos-website` under `EmmanuelBreard`.

## Critical Decisions
- **Astro over plain HTML** — Component reuse for header/footer, Tailwind integration, outputs pure static HTML. No server needed.
- **Cloudflare Pages over Railway/Vercel** — Free, CDN-backed, auto-deploys from GitHub, domain already on Cloudflare (single dashboard, zero extra tools).
- **Cloudflare Email Routing** — Forward support@getdromos.com → personal inbox, free, no extra service.
- **Reuse existing privacy policy** — `docs/privacy-policy.html` already exists in the iOS repo. Adapt it with 3 targeted fixes rather than rewriting.
- **Dark hero, light body** — Hero section: charcoal/near-black background with amber or coral accent. Cards section and below: white background, dark text. Mobile-first.
- **No dark mode for v1** — Site-wide dark mode out of scope.

## Files to Touch

| File | Action | Changes |
|------|--------|---------|
| `dromos-website/package.json` | CREATE | Astro + Tailwind dependencies |
| `dromos-website/astro.config.mjs` | CREATE | Astro config with Tailwind integration |
| `dromos-website/tailwind.config.mjs` | CREATE | Tailwind config |
| `dromos-website/src/layouts/Layout.astro` | CREATE | Base HTML shell, head, meta tags |
| `dromos-website/src/components/Header.astro` | CREATE | Logo + nav (Home, Support) |
| `dromos-website/src/components/Footer.astro` | CREATE | © 2026 Emmanuel Breard · Support · Privacy |
| `dromos-website/src/components/FeatureCard.astro` | CREATE | Reusable outcome card (icon, headline, body, optional screenshot slot) |
| `dromos-website/src/components/ScreenshotMockup.astro` | CREATE | CSS-only Tailwind iPhone frame with PNG/WebP slot, no external library |
| `dromos-website/src/pages/index.astro` | CREATE | Landing page |
| `dromos-website/src/pages/support.astro` | CREATE | Support + FAQ |
| `dromos-website/src/pages/privacy.astro` | CREATE | Privacy policy (adapted from iOS repo) |
| `dromos-website/public/assets/logo-light.svg` | CREATE | Copied from iOS project |
| `dromos-website/public/assets/logo-dark.svg` | CREATE | Copied from iOS project |
| `dromos-website/public/assets/appicon.png` | CREATE | Copied from iOS project (1024×1024) |
| `dromos-website/public/assets/strava-compatible.svg` | CREATE | Copied from iOS project |
| `dromos-website/public/assets/appicon-200.webp` | CREATE | 200px WebP variant of app icon for hero (LCP optimisation) |
| `dromos-website/public/assets/og-image.png` | CREATE | 1200×630 OG/social preview image (app icon + headline on dark background) |
| `dromos-website/public/assets/screenshot-plan.png` | COPY | `miscellaneous/screenshots/IMG_7855.PNG` — Calendar week view (Week 3/10, Base phase) |
| `dromos-website/public/assets/screenshot-session.png` | COPY | `miscellaneous/screenshots/IMG_7854.PNG` — Home feed: session cards with intensity graphs |
| `dromos-website/public/assets/screenshot-coach.png` | COPY | `miscellaneous/screenshots/IMG_7856.PNG` — **Money shot**: completed swim, Strava metrics + coach feedback + planned workout overlay. Use this for the lead differentiator card. |
| `dromos-website/public/robots.txt` | CREATE | `User-agent: * / Allow: /` |

**Asset sources in iOS repo:**
- Logo light: `Dromos/Assets.xcassets/DromosLogo.imageset/DromosLogo-light.svg`
- Logo dark: `Dromos/Assets.xcassets/DromosLogo.imageset/DromosLogo-dark.svg`
- App icon: `Dromos/Assets.xcassets/AppIcon.appiconset/AppIcon-light.png`
- Strava badge: `miscellaneous/1.2-Strava-API-Logos/Compatible with Strava/` (SVG variant)
- Screenshots: real device screenshots in `miscellaneous/screenshots/` — copy directly, no cropping needed (will be placed inside CSS iPhone frame)

## Context Doc Updates
None — this is a standalone website repo, no iOS architecture or Supabase schema changes.

---

## Tasks

- [ ] 🟥 **Step 1: Create GitHub repo + scaffold Astro project** (DRO-187)
  - [ ] 🟥 Create public GitHub repo `dromos-website` under `EmmanuelBreard` via `gh repo create`
  - [ ] 🟥 Scaffold Astro project locally: `npm create astro@latest dromos-website -- --template minimal`
  - [ ] 🟥 Add Tailwind CSS integration: `npx astro add tailwind`
  - [ ] 🟥 Create `src/layouts/Layout.astro` — base HTML shell with meta tags, viewport, title slot; include `og:image`, `og:title`, `og:description`, `twitter:card` meta tags pointing to `og-image.png`
  - [ ] 🟥 Create `src/components/Header.astro` — logo + nav links (Home, Support)
  - [ ] 🟥 Create `src/components/Footer.astro` — copyright + Support + Privacy links
  - [ ] 🟥 Create `src/components/FeatureCard.astro` — props: `icon`, `headline`, `body`, `screenshotSrc?`
  - [ ] 🟥 Create `src/components/ScreenshotMockup.astro` — CSS Tailwind iPhone frame (rounded-[2.5rem] border shadow), accepts `src` + `alt` props; no external library
  - [ ] 🟥 Add `@astrojs/sitemap` integration to `astro.config.mjs` (one line)
  - [ ] 🟥 Copy brand assets + screenshots from iOS project into `public/assets/`
  - [ ] 🟥 Create `appicon-200.webp` (resize from 1024px PNG, use `sips` or `squoosh`)
  - [ ] 🟥 Create `og-image.png` (1200×630, app icon centred on `#111827` background + headline text)
  - [ ] 🟥 Add `public/robots.txt`: `User-agent: *\nAllow: /`
  - [ ] 🟥 Verify `npm run build` succeeds
  - [ ] 🟥 Initial commit + push to GitHub

- [ ] 🟥 **Step 2: Build landing page** (DRO-188)
  - [ ] 🟥 Create `src/pages/index.astro`
  - [ ] 🟥 **Hero section** (dark background: charcoal `#111827`, accent: amber `#F59E0B`):
    - Headline: "You have 10 hours a week and one triathlon to get right. Waste nothing."
    - Subhead: "AI-powered triathlon training plans — from Sprint to Ironman. Personalized to your race, your fitness, your schedule. Free."
    - App icon (`appicon-200.webp` in `<picture>` + 1024px PNG fallback) + App Store button (placeholder link)
    - `ScreenshotMockup` with `screenshot-coach.png` (the money shot: Strava actual + coach feedback)
  - [ ] 🟥 **3 outcome cards** via `FeatureCard.astro` (white section below hero):
    - **Card 1 — Lead differentiator**: "Other apps sell templates. Dromos builds your plan from scratch." — From your FTP, VMA, CSS, race date, and weekly hours. Not a template. Not a generic block. Your plan. Pair with `screenshot-plan.png` mockup.
    - **Card 2**: "See exactly how you trained vs. the plan." — Dromos auto-matches your Strava activities and shows where you're on track — or drifting. Pair with `screenshot-session.png` mockup. Include Strava Compatible badge inline.
    - **Card 3**: "Every session tells you why it's there." — Coaching notes for every workout. Know the purpose, trust the process. Pair with `screenshot-coach.png` mockup.
  - [ ] 🟥 **Credibility line** (below cards, centered): "Built by a triathlete preparing for Nîmes–Alpe d'Huez. Every feature exists because I needed it."
  - [ ] 🟥 **Race distances line** (above or below cards): "From Sprint to Ironman · Swim · Bike · Run · Strava sync · Free"
  - [ ] 🟥 ~~Separate Strava integration row~~ — merged into Card 2 above
  - [ ] 🟥 Footer via `Footer.astro` component
  - [ ] 🟥 Verify mobile layout (responsive)

- [ ] 🟥 **Step 3: Build support page** (DRO-189)
  - [ ] 🟥 Create `src/pages/support.astro`
  - [ ] 🟥 Title: "Support"
  - [ ] 🟥 FAQ — 6 questions:
    1. How do I get started?
    2. How is my training plan generated?
    3. How does Strava sync work?
    4. Can I modify my training plan?
    5. What data does Dromos store?
    6. How do I delete my account?
  - [ ] 🟥 Contact section: support@getdromos.com
  - [ ] 🟥 Link back to home

- [ ] 🟥 **Step 4: Build privacy page** (DRO-190)
  - [ ] 🟥 Create `src/pages/privacy.astro`
  - [ ] 🟥 Port content from `docs/privacy-policy.html` (iOS repo) into Astro component
  - [ ] 🟥 **Fix 1 — Section 4 (Data Sharing)**: Add Strava (activity sync via OAuth) and OpenAI (plan generation, server-side, no data retained) as third-party processors alongside Supabase
  - [ ] 🟥 **Fix 2 — Section 11 (Contact)**: Change `ebreard4@gmail.com` → `support@getdromos.com`
  - [ ] 🟥 **Fix 3 — Last updated date**: Update from "February 14, 2026" → "April 2026"
  - [ ] 🟥 Update `docs/privacy-policy.html` in iOS repo with the same 3 fixes (keep in sync)

- [ ] 🟥 **Step 5: Deploy to Cloudflare Pages** (DRO-191) — *Manual steps*
  - [ ] 🟥 Cloudflare Pages: Connect `dromos-website` GitHub repo → build command `npm run build` → output dir `dist`
  - [ ] 🟥 Custom domain: Add `getdromos.com` in Cloudflare Pages settings (DNS auto-configured — domain already on Cloudflare)
  - [ ] 🟥 Email Routing: Cloudflare dashboard → Email → Email Routing → Add `support@getdromos.com` → forward to personal email
  - [ ] 🟥 Verify all 3 routes resolve: `getdromos.com`, `getdromos.com/support`, `getdromos.com/privacy`
  - [ ] 🟥 Enable **Cloudflare Web Analytics** (Cloudflare dashboard → Analytics → Web Analytics → Add site) — one `<script>` tag injected in `Layout.astro`. Cookie-free, GDPR-clean, free.

- [ ] 🟥 **Step 6: Fill in App Store Connect metadata** (DRO-192)
  - [ ] 🟥 Support URL: `https://getdromos.com/support`
  - [ ] 🟥 Marketing URL: `https://getdromos.com`
  - [ ] 🟥 Privacy Policy URL: `https://getdromos.com/privacy`
  - [ ] 🟥 Copyright: `© 2026 Emmanuel Breard`
  - [ ] 🟥 Version: `1.0`
  - [ ] 🟥 Promotional Text (170 chars): "AI-powered triathlon training plans from Sprint to Ironman. Built from your data — not a template. Every session explained. Syncs with Strava. Free."
  - [ ] 🟥 Keywords (100 chars): `triathlon,training plan,triathlon coach,ironman,half ironman,swim bike run,triathlon training,strava`
  - [ ] 🟥 Draft App Store Description (4000 chars) — separate task, to be done in this session

---

## Verification

1. `npm run build` in `dromos-website/` succeeds with no errors
2. All 3 pages render correctly locally (`npm run dev`): `/`, `/support`, `/privacy`
3. Cloudflare Pages build log shows green
4. `getdromos.com`, `getdromos.com/support`, `getdromos.com/privacy` all resolve
5. Mobile layout looks correct on iPhone viewport
6. App Store Connect: all URL fields filled before submission
