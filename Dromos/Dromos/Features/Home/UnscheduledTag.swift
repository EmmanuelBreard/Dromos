//
//  UnscheduledTag.swift
//  Dromos
//
//  Created by Mamma Aiuto Gang on 14/06/2026.
//  DRO-307: pill badge for unscheduled-activity cards.
//

import SwiftUI

/// Small secondary-colored tag that anchors the header of an unscheduled-activity card.
/// Uppercase, tracked, with the SF Symbols "bolt" glyph — visually distinct from
/// `CompletedTag` (green, checkmark) while sharing the same sizing idiom.
///
/// Uses `.secondary` foreground so the badge reads as a neutral informational label
/// rather than a positive/negative state signal — an unscheduled activity is neither
/// good nor bad; it's simply extra data outside the plan.
struct UnscheduledTag: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.caption)
            Text("UNSCHEDULED")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(1)
        }
        .foregroundColor(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unscheduled activity")
    }
}

#Preview("UnscheduledTag") {
    UnscheduledTag()
        .padding(16)
        .background(Color.cardSurface)
        .padding()
        .background(Color.pageSurface)
}
