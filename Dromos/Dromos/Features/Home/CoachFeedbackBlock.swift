//
//  CoachFeedbackBlock.swift
//  Dromos
//
//  Created by Emmanuel Breard on 26/04/2026.
//

import SwiftUI

/// Soft accent-tinted block hosting the AI coach's post-session feedback inside
/// `TodayCompletedCard`. Three states:
///
/// 1. **Filled** — `feedback != nil`: render the body text.
/// 2. **Loading** — `feedback == nil && isLoading`: render the silent shimmer skeleton
///    (3 staggered accent-tinted bars, 2.6s ease-in-out loop). When the user has
///    `Reduce Motion` enabled the bars collapse to a static 0.55-opacity stack.
/// 3. **Missing** — `feedback == nil && !isLoading`: returns `EmptyView()` so the parent
///    card can omit the surrounding container entirely (no empty pill).
///
/// Container styling matches the prototype: `Color.accentColor.opacity(0.12)` fill,
/// 12pt corner radius, 12pt padding, with a tracked uppercase `COACH FEEDBACK` label.
struct CoachFeedbackBlock: View {
    /// The feedback body. `nil` means "not available yet" — combine with `isLoading` to
    /// disambiguate "still arriving" from "no feedback for this session".
    let feedback: String?

    /// True while the post-session feedback edge function is expected to write a row
    /// (i.e., the activity has just been matched). Caller computes this — the block doesn't
    /// know about Strava state.
    let isLoading: Bool

    /// Whether the feedback body is expanded beyond its 2-line clamp. Local state — resets
    /// on day swipe / card re-render, matching the calendar's `SessionCardView` toggle.
    @State private var showFeedback: Bool = false

    /// Cached clamped (visible, 2-line) text height — captured via `GeometryReader` background.
    /// Defaults to 0; first measurement settles within the first frame.
    @State private var clampedHeight: CGFloat = 0

    /// Cached full intrinsic text height — captured via the hidden ghost-text overlay.
    /// Compared to `clampedHeight` to decide whether the toggle is needed.
    @State private var fullHeight: CGFloat = 0

    /// True when the body actually overflows 2 lines. Recomputed on either height change.
    /// `+0.5` epsilon avoids float jitter producing a false-positive on exactly-2-line text.
    @State private var isTruncated: Bool = false

    var body: some View {
        if let feedback = feedback {
            container { filledBody(feedback) }
        } else if isLoading {
            container { loadingBody }
        } else {
            EmptyView()
        }
    }

    // MARK: - Container

    /// Single source of truth for the block's chrome (label + fill + radius + padding).
    /// All non-empty states share it so they read as the same component.
    @ViewBuilder
    private func container<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COACH FEEDBACK")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(1)
                .foregroundColor(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
    }

    // MARK: - Filled body

    /// Renders the feedback body with a 2-line clamp + a Show more / Show less toggle that
    /// appears **only when the text actually overflows**. Truncation detection uses a hidden
    /// ghost-text sibling: the visible `Text` is clamped (or unclamped when expanded) and its
    /// height is captured via `ClampedTextHeightKey`; the ghost renders the same text fully
    /// expanded (`lineLimit(nil)`) and emits its height via `FullTextHeightKey`. Both keys
    /// flow through `.onPreferenceChange` to local state, which recomputes `isTruncated`.
    ///
    /// First-render path: `isTruncated` defaults to `false`, so the button stays hidden until
    /// measurement settles. On overflowing text the button fades in within the first layout
    /// pass — acceptable jitter for this surface (per tech spec risk note).
    private func filledBody(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(showFeedback ? nil : 2)
                // NOTE: deliberately NOT applying `.fixedSize(vertical: true)` here —
                // doing so forces intrinsic height and overrides `lineLimit(2)`, which
                // would render the full body even in the collapsed state. The expanded
                // state already gets its full height from `lineLimit(nil)`.
                .background(
                    // Capture the rendered (clamped or expanded) height of the visible text.
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ClampedTextHeightKey.self, value: geo.size.height)
                    }
                )
                .background(
                    // Hidden ghost copy of the same text in the same width context, rendered
                    // fully expanded. Its intrinsic height is the "true" height of the body
                    // and lets us decide whether the visible (clamped) height is truncating.
                    Text(text)
                        .font(.body)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .preference(key: FullTextHeightKey.self, value: geo.size.height)
                            }
                        )
                )
                .accessibilityLabel("Coach feedback: \(text)")

            // Toggle is gated on actual overflow — short feedback never gets a dead affordance.
            if isTruncated {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFeedback.toggle()
                    }
                } label: {
                    Text(showFeedback ? "Show less" : "Show more")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showFeedback ? "Show less feedback" : "Show full feedback")
            }
        }
        .onPreferenceChange(ClampedTextHeightKey.self) { newValue in
            clampedHeight = newValue
            isTruncated = fullHeight > clampedHeight + 0.5
        }
        .onPreferenceChange(FullTextHeightKey.self) { newValue in
            fullHeight = newValue
            isTruncated = fullHeight > clampedHeight + 0.5
        }
    }

    // MARK: - Loading body

    private var loadingBody: some View {
        SkeletonStack()
            .accessibilityLabel("Coach feedback loading")
    }
}

// MARK: - Preference keys (truncation detection)

/// Carries the rendered height of the visible (clamped) feedback `Text`.
/// `reduce` keeps the larger value because heights only ever grow as layout settles —
/// e.g. width changes or font scaling can extend a clamped 2-line block to its final size.
private struct ClampedTextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Carries the intrinsic height of the hidden ghost `Text` (rendered with `lineLimit(nil)`).
/// `reduce` keeps the larger value for the same reason as `ClampedTextHeightKey`.
private struct FullTextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Shimmer skeleton

/// 3-bar accent-tinted shimmer. Each bar's width and animation phase is staggered to feel
/// natural — never landing all three highlights on the same beat. Honors
/// `accessibilityReduceMotion` by rendering static dim bars instead of an animated gradient.
private struct SkeletonStack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Bar widths as fractions of the container (matches the prototype's 92 / 84 / 56 %).
    private let widths: [CGFloat] = [0.92, 0.84, 0.56]

    /// Per-bar phase delay (seconds). Same cascade as the prototype.
    private let delays: [Double] = [0.0, 0.18, 0.36]

    /// Full shimmer loop duration. Long enough that it reads as breathing, not pulsing.
    private let loopDuration: Double = 2.6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(widths.indices, id: \.self) { i in
                SkeletonBar(
                    widthFraction: widths[i],
                    delay: delays[i],
                    loopDuration: loopDuration,
                    reduceMotion: reduceMotion
                )
            }
        }
        .padding(.vertical, 2)
    }
}

// TODO(follow-up): Consider containerRelativeFrame(.horizontal) { width, _ in width * widthFraction }
// to avoid the GeometryReader per bar. Acceptable for now since this is not rendered inside a List.
/// A single shimmer bar. Animates a moving accent-tinted gradient across an 11pt-tall pill.
/// In Reduce Motion mode it collapses to a static 0.55-opacity fill — same height/width,
/// no movement, so the skeleton's footprint stays identical for screen layout.
private struct SkeletonBar: View {
    let widthFraction: CGFloat
    let delay: Double
    let loopDuration: Double
    let reduceMotion: Bool

    @State private var phase: CGFloat = -1.0

    /// Bar height — 11pt matches the prototype and aligns with `.body` text leading.
    private let barHeight: CGFloat = 11

    /// Pill radius — kept small so the bar reads as a placeholder, not a button.
    private let barRadius: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let barWidth = geo.size.width * widthFraction

            ZStack(alignment: .leading) {
                if reduceMotion {
                    // Static dim fill — same color rest as the animated path's middle stop.
                    RoundedRectangle(cornerRadius: barRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.22))
                        .frame(width: barWidth, height: barHeight)
                        .opacity(0.55)
                } else {
                    RoundedRectangle(cornerRadius: barRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.accentColor.opacity(0.10), location: 0.0),
                                    .init(color: Color.accentColor.opacity(0.30), location: 0.5),
                                    .init(color: Color.accentColor.opacity(0.10), location: 1.0)
                                ],
                                startPoint: UnitPoint(x: phase,       y: 0.5),
                                endPoint:   UnitPoint(x: phase + 1.0, y: 0.5)
                            )
                        )
                        .frame(width: barWidth, height: barHeight)
                }
            }
            // Push to leading edge of the row.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: barHeight)
        // `.task` runs after the view is on-screen and is Apple's documented pattern for
        // kicking off `.repeatForever` animations cleanly — it sidesteps the same-runloop
        // race that `.onAppear { withAnimation … }` can hit. The phase reset stays inside
        // the guard so it only happens when motion is enabled (avoids a dead store).
        .task {
            guard !reduceMotion else { return }
            phase = -1.0
            withAnimation(
                Animation
                    .easeInOut(duration: loopDuration)
                    .repeatForever(autoreverses: false)
                    .delay(delay)
            ) {
                phase = 1.0
            }
        }
    }
}

// MARK: - Previews

#Preview("All three states") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Filled — long (truncated, Show more visible)").font(.caption).foregroundColor(.secondary)
                CoachFeedbackBlock(
                    feedback: "Solid VO2 effort — your final two intervals held the same pace as the first, which is the hard part. Recovery jogs stayed honest. Tomorrow: easy spin only.",
                    isLoading: false
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Filled — short (no Show more button)").font(.caption).foregroundColor(.secondary)
                CoachFeedbackBlock(
                    feedback: "Nice easy spin. Recovery on point.",
                    isLoading: false
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Loading (silent skeleton)").font(.caption).foregroundColor(.secondary)
                CoachFeedbackBlock(feedback: nil, isLoading: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Missing (renders as EmptyView)").font(.caption).foregroundColor(.secondary)
                CoachFeedbackBlock(feedback: nil, isLoading: false)
                Text("(nothing rendered above this line)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }
    .background(Color.pageSurface)
}

#Preview("Loading — long-form") {
    CoachFeedbackBlock(feedback: nil, isLoading: true)
        .padding(16)
        .background(Color.cardSurface)
        .padding()
        .background(Color.pageSurface)
}
