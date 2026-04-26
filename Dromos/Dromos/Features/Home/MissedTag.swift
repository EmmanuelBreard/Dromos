//
//  MissedTag.swift
//  Dromos
//
//  Created by Emmanuel Breard on 26/04/2026.
//

import SwiftUI

/// Paired counterpart to `CompletedTag` — used by `TodayMissedCard` to clearly state
/// "this session didn't happen" without a heavy red border / banner. The tag itself
/// is the sole color hit on the card; the rest of the missed card stays muted.
///
/// Color comes from `Color.errorStrong` (asset-backed, light + dark) per DESIGN.md.
struct MissedTag: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
            Text("NOT COMPLETED")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(1)
        }
        .foregroundColor(.errorStrong)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Not completed")
    }
}

#Preview("MissedTag") {
    MissedTag()
        .padding(16)
        .background(Color("CardSurface"))
        .padding()
        .background(Color("PageSurface"))
}
