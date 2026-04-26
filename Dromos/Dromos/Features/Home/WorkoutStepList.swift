//
//  WorkoutStepList.swift
//  Dromos
//
//  Created by Emmanuel Breard on 26/04/2026.
//

import SwiftUI

/// Vertical list of workout steps for use inside Today / session cards.
///
/// Differences vs. `WorkoutStepsView` (which is the legacy compact dot-list used elsewhere):
/// - Adds an accent left-border + indent treatment to **repeat blocks** so the canonical
///   `5× (3' work + 3' recovery)` style summary reads as the structural anchor of the workout
///   (matches the DRO-231 anchor-shape prototype).
/// - Pulls the multiplier prefix (`5×`) out of the rendered text and renders it in
///   accent-tinted bold so the eye lands on it first.
/// - Drops the colored intensity dot — the workout-shape above the list already
///   communicates intensity. The list now reads as quiet typography.
struct WorkoutStepList: View {
    let steps: [StepSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                row(for: step)
                    // Hairline separator between rows. Skipped above the first row so the list
                    // sits flush against the section divider above it (see TodayPlannedCard).
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle()
                                .fill(Color(.separator))
                                .frame(height: 0.5)
                        }
                    }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for step: StepSummary) -> some View {
        if step.isRepeatBlock {
            repeatRow(for: step)
        } else {
            simpleRow(for: step)
        }
    }

    /// Standard step row: name on the left, duration on the right.
    /// Splits `"15' warmup - 156 W"` into `"warmup"` (primary) + `"15'"` (right) + `"@ 156 W"` (target sub-line).
    private func simpleRow(for step: StepSummary) -> some View {
        let parts = parseStep(step.text)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(parts.name)
                    .font(.body)
                    .foregroundColor(.primary)
                Spacer(minLength: 8)
                Text(parts.duration)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }
            if let target = parts.target {
                Text(target)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    /// Repeat block row: 2pt accent left-border + 12pt left-padding + multiplier prefix in accent.
    /// `WorkoutLibraryService` always emits repeat-block text as `"N× [label] (...)"` so the
    /// multiplier + optional label extraction is deterministic.
    private func repeatRow(for step: StepSummary) -> some View {
        let split = splitMultiplier(step.text)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            // Two-line composition: multiplier + label on top, with the rest of the
            // collapsed parenthetical wrapping below at .secondary weight.
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let multiplier = split.multiplier {
                        Text(multiplier)
                            .font(.body.weight(.bold))
                            .foregroundColor(.accentColor)
                            .monospacedDigit()
                    }
                    Text(split.title)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                }
                Text(split.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.vertical, 6)
        .overlay(alignment: .leading) {
            // The accent left-border that visually groups the repeat block.
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2)
        }
    }

    // MARK: - Text parsing

    /// Parsed components of a non-repeat step string.
    /// Example: `"15' warmup - 156 W"` → name `"warmup"`, duration `"15'"`, target `"156 W"`.
    private struct ParsedStep {
        let name: String
        let duration: String
        let target: String?
    }

    /// `WorkoutLibraryService` formats steps consistently as `"<duration> <label>[ - <metric>]"`.
    /// This helper unpacks that into the three slots we render. Falls back to using the entire
    /// string as `name` if the format diverges, so we never crash on an unexpected template.
    private func parseStep(_ text: String) -> ParsedStep {
        // Split off the optional " - <target>" tail first so leading "<duration> <label>" stays intact.
        let (head, target): (String, String?) = {
            if let dashRange = text.range(of: " - ") {
                return (String(text[..<dashRange.lowerBound]), String(text[dashRange.upperBound...]))
            }
            return (text, nil)
        }()

        // Head is "<duration> <label>" — duration is the first whitespace-delimited token.
        let trimmed = head.trimmingCharacters(in: .whitespaces)
        if let firstSpace = trimmed.firstIndex(of: " ") {
            let duration = String(trimmed[..<firstSpace])
            let name = String(trimmed[trimmed.index(after: firstSpace)...])
                .trimmingCharacters(in: .whitespaces)
            return ParsedStep(name: name.isEmpty ? trimmed : name, duration: duration, target: target)
        }
        // Single token — render entire string as duration column for clarity.
        return ParsedStep(name: "", duration: trimmed, target: target)
    }

    /// Splits a repeat-block string of the form `"N× [label] (...)"` into the multiplier,
    /// an optional label clause (the text between `×` and the first `(`), and the inner
    /// body (without the surrounding parens). Returns `nil` multiplier if the format
    /// doesn't match — caller renders the full text as body. The `title` slot falls back
    /// to "Main set" when no label clause is present, so existing canonical strings like
    /// `"5× (3' work + 3' recovery)"` keep their familiar header.
    private func splitMultiplier(_ text: String) -> (multiplier: String?, title: String, body: String) {
        guard let xRange = text.range(of: "×"),
              let parenStart = text.range(of: "(", range: xRange.upperBound..<text.endIndex),
              let parenEnd = text.range(of: ")", options: .backwards)
        else {
            return (nil, "Main set", text)
        }

        let multiplier = String(text[..<xRange.upperBound])
            .trimmingCharacters(in: .whitespaces)

        // Anything between the `×` and the opening `(` is the human label for the block
        // (e.g. `"5× main set (...)"`, `"3× hill repeats (...)"`). Empty → fall back.
        let rawLabel = String(text[xRange.upperBound..<parenStart.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let title = rawLabel.isEmpty ? "Main set" : rawLabel.capitalizedFirstLetter

        let body = String(text[parenStart.upperBound..<parenEnd.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        return (multiplier, title, body)
    }
}

private extension String {
    /// Capitalize only the first character so we don't mangle pre-cased labels like
    /// `"VO2 intervals"` via Swift's full `.capitalized` (which would lowercase `VO2`).
    var capitalizedFirstLetter: String {
        guard let first = self.first else { return self }
        return first.uppercased() + self.dropFirst()
    }
}

// MARK: - Previews

#Preview("Tuesday VO2 5×3' (canonical)") {
    let steps: [StepSummary] = [
        StepSummary(
            text: "11' warmup - 9.0 km/h (6:40/km)",
            intensityPct: 50,
            isRepeatBlock: false
        ),
        StepSummary(
            text: "5× (3' work - 17.0 km/h (3:30/km) + 3' recovery jog)",
            intensityPct: 95,
            isRepeatBlock: true
        ),
        StepSummary(
            text: "11' cooldown - 9.0 km/h (6:40/km)",
            intensityPct: 50,
            isRepeatBlock: false
        )
    ]

    return WorkoutStepList(steps: steps)
        .padding(16)
        .background(Color.cardSurface)
        .padding()
        .background(Color.pageSurface)
}

#Preview("Bike intervals") {
    let steps: [StepSummary] = [
        StepSummary(text: "15' warmup - 120 W", intensityPct: 50, isRepeatBlock: false),
        StepSummary(text: "3× (6' work - 260 W + 4' recovery)", intensityPct: 95, isRepeatBlock: true),
        StepSummary(text: "10' cooldown - 100 W", intensityPct: 45, isRepeatBlock: false)
    ]
    return WorkoutStepList(steps: steps)
        .padding(16)
        .background(Color.cardSurface)
        .padding()
}

#Preview("Swim intervals") {
    let steps: [StepSummary] = [
        StepSummary(text: "300m warmup", intensityPct: nil, isRepeatBlock: false),
        StepSummary(text: "4× (100m medium + 50m easy)", intensityPct: 75, isRepeatBlock: true),
        StepSummary(text: "200m cooldown", intensityPct: nil, isRepeatBlock: false)
    ]
    return WorkoutStepList(steps: steps)
        .padding(16)
        .background(Color.cardSurface)
        .padding()
}
