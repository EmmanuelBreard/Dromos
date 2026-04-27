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
/// Always renders the static `"COMPLETED"` label. The temporal anchor (e.g. "Today",
/// "Yesterday", "April 29th") is now rendered as an external section header above the
/// hero card, so this tag is purely a state badge.
struct CompletedTag: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
            Text("COMPLETED")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(1)
        }
        .foregroundColor(.accentColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Completed")
    }
}

#Preview("CompletedTag") {
    CompletedTag()
        .padding(16)
        .background(Color.cardSurface)
        .padding()
        .background(Color.pageSurface)
}
