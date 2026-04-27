//
//  SportProgressStrip.swift
//  Dromos
//
//  Created by Emmanuel Breard on 26/04/2026.
//

import SwiftUI

/// Three-column weekly progress strip rendered at the top of the Home (Today) tab.
///
/// One column per sport (SWIM / BIKE / RUN). Each column shows:
///   - Sport label (caption, secondary, uppercase, 2pt tracking).
///   - Numbers `H:MM / H:MM` with `done` in primary semibold and `/total` in secondary.
///   - 4pt tall track with an accent fill capped at 100% (overshoot is visually clamped
///     but the numbers remain honest).
///
/// Pure presentational view — no Strava / PlanService dependency. The data layer
/// (`PlanService.weeklySportTotals`) computes the totals and the Home screen wires
/// them in.
struct SportProgressStrip: View {

    /// Per-sport totals keyed by lowercase sport name (`"swim"`, `"bike"`, `"run"`).
    /// Missing keys are treated as `(done: 0, total: 0)` so the parent doesn't have to
    /// pre-fill all three slots.
    let totals: [String: SportTotals]

    /// (done, total) in minutes for a single sport.
    struct SportTotals: Equatable {
        let doneMinutes: Int
        let totalMinutes: Int
    }

    /// Sports rendered, in fixed left-to-right order. Triathlon convention: swim → bike → run.
    private static let sportOrder: [(key: String, label: String)] = [
        ("swim", "SWIM"),
        ("bike", "BIKE"),
        ("run", "RUN"),
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Self.sportOrder, id: \.key) { sport in
                SportColumn(
                    label: sport.label,
                    totals: totals[sport.key] ?? SportTotals(doneMinutes: 0, totalMinutes: 0)
                )
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Column

/// Single sport column. Pulled out so the parent `HStack` stays declarative and each
/// column gets its own GeometryReader-driven progress track.
private struct SportColumn: View {
    let label: String
    let totals: SportProgressStrip.SportTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(2)

            // Numbers. Tabular nums prevent the column from jiggling as time ticks up.
            (
                Text(Self.formatHMM(totals.doneMinutes))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                + Text(" / \(Self.formatHMM(totals.totalMinutes))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            )
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            ProgressTrack(progress: Self.progress(done: totals.doneMinutes, total: totals.totalMinutes))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Clamped fill ratio. `total == 0` → 0 (empty case). Overshoot caps at 1.0 so the
    /// bar never overflows its track.
    private static func progress(done: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(Double(done) / Double(total), 1.0)
    }

    /// Formats an integer minute count as `H:MM` (e.g. 75 → "1:15", 0 → "0:00").
    /// Hours are unbounded — a 12h week renders as `12:00`, not clamped to 24h.
    private static func formatHMM(_ minutes: Int) -> String {
        let safe = max(0, minutes)
        let h = safe / 60
        let m = safe % 60
        return String(format: "%d:%02d", h, m)
    }
}

// MARK: - Track

/// 4pt-tall rounded track with an accent fill driven by `progress` (0...1).
/// GeometryReader is required because we need to translate a 0–1 ratio into a pixel
/// width — SwiftUI can't flex a child by a numeric weight inside a fixed-height track.
private struct ProgressTrack: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: max(0, geo.size.width * progress))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Previews

#Preview("Monday morning — zeros") {
    SportProgressStrip(totals: [
        "swim": .init(doneMinutes: 0, totalMinutes: 60),
        "bike": .init(doneMinutes: 0, totalMinutes: 240),
        "run":  .init(doneMinutes: 0, totalMinutes: 180),
    ])
    .padding()
    .background(Color(.systemBackground))
}

#Preview("Mid-week — mixed") {
    SportProgressStrip(totals: [
        "swim": .init(doneMinutes: 30, totalMinutes: 60),    // 50%
        "bike": .init(doneMinutes: 90, totalMinutes: 240),   // ~37%
        "run":  .init(doneMinutes: 120, totalMinutes: 180),  // ~67%
    ])
    .padding()
    .background(Color(.systemBackground))
}

#Preview("End of week — overshoot (cap)") {
    // Bike overshoots planned (270 / 240). Bar caps at 100% but numbers stay honest.
    SportProgressStrip(totals: [
        "swim": .init(doneMinutes: 60, totalMinutes: 60),
        "bike": .init(doneMinutes: 270, totalMinutes: 240),
        "run":  .init(doneMinutes: 180, totalMinutes: 180),
    ])
    .padding()
    .background(Color(.systemBackground))
}
