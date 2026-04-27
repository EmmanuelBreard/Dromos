//
//  CompletedTag.swift
//  Dromos
//
//  Created by Emmanuel Breard on 26/04/2026.
//

import SwiftUI

/// Small accent-colored tag that anchors the header of a completed session card.
/// Uppercase, tracked, with the SF Symbols filled checkmark — same visual weight as
/// `MissedTag` so the two read as a paired family across Today states.
///
/// `label` defaults to `"COMPLETED TODAY"` for the today-hero use case. Callers
/// previewing a past day pass `"COMPLETED"` to drop the temporal word — the date
/// caption renders separately in that case (see `TodayCompletedCard`).
struct CompletedTag: View {
    var label: String = "COMPLETED TODAY"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(1)
        }
        .foregroundColor(.accentColor)
        .accessibilityElement(children: .combine)
        // Hardcoded sentence-case mapping for the two known labels — `.capitalized`
        // produces "Completed Today" (Title Case) which regresses VoiceOver tone.
        .accessibilityLabel(label == "COMPLETED" ? "Completed" : "Completed today")
    }
}

#Preview("CompletedTag — today (default)") {
    CompletedTag()
        .padding(16)
        .background(Color.cardSurface)
        .padding()
        .background(Color.pageSurface)
}

#Preview("CompletedTag — past day (shorter label)") {
    CompletedTag(label: "COMPLETED")
        .padding(16)
        .background(Color.cardSurface)
        .padding()
        .background(Color.pageSurface)
}
