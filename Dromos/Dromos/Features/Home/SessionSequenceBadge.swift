//
//  SessionSequenceBadge.swift
//  Dromos
//
//  Created by Emmanuel Breard on 26/04/2026.
//

import SwiftUI

/// Numbered circle used in multi-session days to indicate session order
/// (e.g., "1" on the morning swim card, "2" on the evening run card).
/// Inverted color treatment — `Color.primary` background, `Color.cardSurface` foreground —
/// so it punches above the card surface without adding a third hue to the screen.
struct SessionSequenceBadge: View {
    /// 1-based index of the session within the day's session list.
    let index: Int

    var body: some View {
        Text("\(index)")
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundColor(Color.cardSurface)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Color.primary))
            .accessibilityLabel("Session \(index)")
    }
}

#Preview("SessionSequenceBadge") {
    HStack(spacing: 8) {
        SessionSequenceBadge(index: 1)
        SessionSequenceBadge(index: 2)
        SessionSequenceBadge(index: 3)
    }
    .padding(16)
    .background(Color.cardSurface)
    .padding()
    .background(Color.pageSurface)
}
