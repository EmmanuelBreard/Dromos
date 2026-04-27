# DESIGN.md — Dromos design system

This file documents the design system both as it *exists today* in code and as it *should be*. When the two diverge, the **target state** wins — this is what `/design-critique` checks against and `/design-explore` generates from.

Read [PRODUCT.md](./PRODUCT.md) first. PRODUCT.md is the *why*; this file is the *what*.

---

## 0. Foundational rules

These are universal. Every screen, every component, every prototype.

1. **System font, always.** SF Pro / system. No custom font families. Editorial feel comes from *size and weight*, not from typeface.
2. **Asset-based colors with light + dark variants.** No hex literals in Swift code. Every color is a named asset that adapts to mode.
3. **Dynamic Type respected.** Use semantic font styles (`.title2`, `.headline`) by default. Custom point sizes only for hero numbers, and they must scale with `.dynamicTypeSize` modifiers.
4. **8-pt baseline grid.** All spacing, padding, and component dimensions are multiples of 4 (preferably 8).
5. **Native iOS chrome.** TabView, NavigationStack, sheets, toolbars — never re-implemented. We bend our content around the platform, not the other way around.

---

## 1. Color

### Palette (target state)

| Token | Light | Dark | Use |
|---|---|---|---|
| `Color.pageSurface` | `#F2F2F7` | `#000000` | Full-screen background |
| `Color.cardSurface` | `#FFFFFF` | `#1C1C1C` | Card / sheet background, one level above page |
| `Color.cardSurfaceElevated` | `#FFFFFF` | `#2C2C2E` | Card on top of card (rare — modal over sheet) |
| `Color.accent` | `#009B77` | `#0FAE89` *(new)* | The single brand color. Used sparingly. |
| `Color.textPrimary` | system `.primary` | system `.primary` | Headlines, hero numbers |
| `Color.textSecondary` | system `.secondary` | system `.secondary` | Body, metadata |
| `Color.textTertiary` | `#8E8E93` | `#8E8E93` | Captions, disabled, placeholder |
| `Color.divider` | system `.separator` | system `.separator` | Hairlines |
| `Color.successSubtle` | `accent @ 0.12` | `accent @ 0.18` | Completed-state backgrounds |
| `Color.warningSubtle` | `#FF9500 @ 0.12` | `#FF9F0A @ 0.18` | Edits, attention |
| `Color.errorSubtle` | `#FF3B30 @ 0.12` | `#FF453A @ 0.18` | Missed, failed |
| `Color.errorStrong` | `#FF3B30` | `#FF453A` | Missed-state tag glyph + label (`MissedTag`). Solid form of `errorSubtle`. |

### Decisions baked in

- **One brand color.** `#009B77` — a muted, confident green. *Not* Spotify-green. Closer to a Porsche dashboard accent. Used for: primary CTAs, the "completed" state, the active tab indicator, the coach-message accent. **Nowhere else.** If you find yourself reaching for accent for a third reason, it's wrong.
- **Add a dark-mode accent variant** (`#0FAE89`) — current `AccentColor.colorset` lacks one, which is a bug.
- **Phase colors get retired in their current form.** Today: blue/orange/red/purple/green for Base/Build/Peak/Taper/Recovery. This is Garmin-coded and violates "color is rare and meaningful." **Target:** phase is communicated by a small monochrome label + a position indicator (week N of M), not by hue. Intensity remains color-coded because effort *is* the data — phase is just metadata.
- **Intensity gradient survives** (HSL green→yellow→orange→red in `IntensityColorHelper.swift`). Effort *is* the content; color earns its place. But it's used only inside the workout-detail context, never on top-level cards.

### Current state vs. target

| Item | Current | Target | Action |
|---|---|---|---|
| Page/card surfaces | ✅ assets defined | Same | Done |
| Accent color | Defined, no dark variant | Add dark variant | Add to `AccentColor.colorset` |
| Phase colors | Hue-coded (5 colors) | Monochrome + label | Refactor `WeekHeaderView` |
| Hex literals in code | None found ✅ | Same | Done |
| Semantic state colors | Inline opacity values | Named tokens | Promote `successSubtle`, etc. |

---

## 2. Typography

### Scale (target state)

All sizes use the system font. Weights are explicit.

| Token | SwiftUI | Use |
|---|---|---|
| `.heroNumber` | `.system(size: 56, weight: .bold, design: .rounded)` | The single hero metric on a screen (today's session duration, race countdown). Max **one per screen.** |
| `.titleLarge` | `.largeTitle.weight(.bold)` | Screen titles when no nav bar |
| `.title` | `.title2.weight(.bold)` | Section headers |
| `.headline` | `.headline` | Card titles, list-row primary text |
| `.body` | `.body` | Paragraph text, descriptions, rationale lines |
| `.bodyEmphasis` | `.body.weight(.semibold)` | Buttons, emphasized inline text |
| `.caption` | `.subheadline.foregroundStyle(.secondary)` | Metadata under headlines |
| `.metaSmall` | `.caption.foregroundStyle(.secondary)` | Timestamps, footnotes |
| `.numericMono` | `.body.monospacedDigit()` | Any number that updates in real time (timers, paces) |

### Rules

- **Bold is a tool, not a default.** Audit shows 18 `.bold` calls vs. 7 `.semibold` — we're over-bolding. New rule: only `.heroNumber`, `.titleLarge`, `.title`, and `.bodyEmphasis` are bold/semibold. Everything else is regular weight.
- **Numbers are first-class.** Use `.monospacedDigit()` on any number that may change so layout doesn't jitter. Use `.rounded` design for hero numbers (warmer, more editorial).
- **Never use `.font(.system(size:))` inline.** Always reach for a token. Audit found 4 inline 60pt usages — those become `.heroNumber`.
- **Dynamic Type:** every token must work at `.large` through `.accessibility3` without breaking layout. Test in previews.

### Current state vs. target

| Item | Current | Target | Action |
|---|---|---|---|
| Centralized scale | None | This table | Create `Typography.swift` |
| Bold over-use | 18 occurrences | Limited per scale | Sweep on adoption |
| Hero numbers | Inline `.system(size: 60)` | `.heroNumber` token | Promote |
| Monospaced digits | Not used | `numericMono` for live values | Adopt in workout views |

---

## 3. Spacing

### Scale (target state)

Single source of truth. All spacing references this enum.

```swift
enum Space {
    static let xs:  CGFloat = 4   // tight inline (icon + label)
    static let sm:  CGFloat = 8   // default tight
    static let md:  CGFloat = 12  // default within a card
    static let lg:  CGFloat = 16  // default container padding
    static let xl:  CGFloat = 24  // section separation
    static let xxl: CGFloat = 32  // major break between conceptual blocks
    static let xxxl: CGFloat = 48 // hero spacing (rare — onboarding, empty states)
}
```

### Rules

- **No raw numbers in `.padding`, `.frame`, `VStack(spacing:)`, `HStack(spacing:)`.** Always `Space.lg`, never `16`.
- **`.padding()` (no argument) is banned.** Always specify edges and a token: `.padding(.horizontal, Space.lg)`.
- **Default screen-edge inset is `Space.lg` (16pt).** Same as iOS standard list inset.
- **Inside a card: `Space.lg` padding, `Space.md` between elements.**
- **Between sections on a screen: `Space.xl` (24pt).**

### Current state

Audit shows the right values are *already in use* — 8/12/16/24 dominate — but they're hardcoded everywhere. Promote to `Space` enum, then sweep.

---

## 4. Shape & elevation

### Corner radius

| Token | Value | Use |
|---|---|---|
| `Radius.sm` | 8 | Small badges, capsule alternatives |
| `Radius.md` | 12 | Buttons, text fields, small cards |
| `Radius.lg` | 16 | Standard cards, sheets-within-sheets |
| `Radius.xl` | 24 | Large hero cards (next session) |
| `Radius.full` | 999 | Pills, circular |

**Decision:** drop the current 10pt radius (most-used today). 12pt is the modern iOS-19 default and reads slightly softer/more current. Migrate during sweeps.

### Elevation

**Flat by default.** The audit found exactly one shadow in the entire codebase — that's correct.

If we ever need elevation:
- `Elevation.subtle` — `.shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)` — for sheet edges, sticky headers
- `Elevation.lifted` — `.shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 4)` — for floating CTAs

**Never both shadow + border on the same surface.** Pick one. Default to neither.

### Borders

- Hairline: `0.5pt` `Color.divider` — graph grids, top of sticky toolbars
- Standard: `1pt` `Color.divider` — text field outline, segmented controls

---

## 5. Motion

### Rules

- **Default easing:** `.spring(response: 0.35, dampingFraction: 0.86)` — iOS-native feel, no bounce.
- **Default duration:** 200–300ms. Never longer than 400ms unless it's a hero entrance.
- **Motion confirms an action.** Press → tap-down → release → settle. No autonomous animation, no looping, no attention-grabbing.
- **Respect `.accessibilityReduceMotion`.** Replace transforms with crossfades.

### Banned

- Bounce springs (`dampingFraction < 0.7`)
- Scale-in entrance for content (only for sheets/modals)
- Looping animations on data displays
- Anything described as "playful," "delightful," or "fun"

---

## 6. Components

### Primitives that exist (and are correct)

| Component | Location | Notes |
|---|---|---|
| `DromosTextField` | `Features/Auth/AuthComponents.swift` | ✅ Move to `Core/Components/` |
| `DromosButton` | `Features/Auth/AuthComponents.swift` | ✅ Move to `Core/Components/`. Add `.secondary` and `.tertiary` variants. |

### Primitives that should exist (and don't yet)

| Component | Why we need it | Priority |
|---|---|---|
| `Card` | Standard padded surface. Replaces 5+ ad-hoc card layouts. | P0 |
| `SectionHeader` | Title + optional action button. Replaces inline headers. | P0 |
| `MetricLabel` | Number + unit + caption. The atom of every workout view. | P0 |
| `Pill` | Small capsule label (sport tag, type tag). Replaces inline `Capsule()` styling. | P1 |
| `RationaleText` | Italic-leaning body text used for "why this session." Per Stance #9, every prescribed thing has one. | P1 |
| `EmptyState` | Icon + title + body + optional CTA. For empty home, no plan, etc. | P2 |

### Composite components (extract from existing code)

| Component | Currently | Target |
|---|---|---|
| `SessionCard` | 200+ line view with 4 conditional layouts in `SessionCardView.swift` | Split: `SessionCard.Planned`, `SessionCard.Completed`, `SessionCard.Missed` — three sibling components, each <80 lines |
| `WeekHeader` | `WeekHeaderView.swift` with hue-coded phase | Refactor: monochrome label, kill phase color |
| `WorkoutGraph` | `WorkoutGraphView.swift` | Keep, but replace inline shadow with `Elevation.subtle` token |

---

## 7. iOS-specific rules

- **TabView** is the primary navigation. Never replaced with custom tabs.
- **NavigationStack** for hierarchical flows. Sheets for modal tasks. Full-screen covers for blocking flows (onboarding only).
- **Toolbar items** for screen-level actions (Edit, Filter). Never floating buttons unless creating a new entity (FAB-equivalent only on Calendar to add a session).
- **Safe-area is sacred.** Content respects safe area; only background colors extend.
- **Haptics:** `.sensoryFeedback(.selection, ...)` for tab switches and toggles. `.success` for completing a session. Nothing else.
- **Pull-to-refresh** on every list view backed by remote data.

---

## 8. Anti-patterns (what `/design-critique` flags)

These are automatic fails, not subjective.

- ❌ Hex literal `Color(hex:...)` or `Color(red:...)` in any view file (use asset).
- ❌ Raw number in `.padding(N)` (use `Space.*`).
- ❌ `.font(.system(size: N))` inline (use typography token).
- ❌ `cornerRadius(10)` (legacy value — use `Radius.md`).
- ❌ More than one bold weight on a single screen *unless* the screen is intentionally typographic (hero/marketing).
- ❌ More than 3 colors visible on a single screen (excluding photos and intensity gradient).
- ❌ Phase color used as background or large fill (it's metadata, not data).
- ❌ Multi-color line chart with >2 series (Garmin smell).
- ❌ Shadow + border on the same surface.
- ❌ Bounce spring (`dampingFraction < 0.7`).
- ❌ Custom tab bar / custom modal / custom segmented control.
- ❌ Lorem ipsum, "Workout 1," "Test session," or any placeholder content in committed code.
- ❌ A prescribed session card with no rationale line (violates Stance #9).
- ❌ Emoji in user-facing copy (per voice rules).

---

## 9. How to evolve this file

1. When the answer is "it depends," the **Stance section in PRODUCT.md** wins.
2. When you reject a generated design, capture *what was wrong* here as either a token, a rule, or an anti-pattern.
3. Do not add a token "for completeness." Only add when a real screen needs it twice.
4. Versioning: this is v0. We expect it to churn for 4–6 weeks. After the first /design-explore + /design-critique cycle on a real feature, schedule a v1 pass.
