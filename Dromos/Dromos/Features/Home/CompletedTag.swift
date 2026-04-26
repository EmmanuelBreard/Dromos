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
struct CompletedTag: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
            Text("COMPLETED TODAY")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(1)
        }
        .foregroundColor(.accentColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Completed today")
    }
}

#Preview("CompletedTag") {
    CompletedTag()
        .padding(16)
        .background(Color.cardSurface)
        .padding()
        .background(Color.pageSurface)
}
