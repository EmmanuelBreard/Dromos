//
//  EmptyHomeHero.swift
//  Dromos
//
//  DRO-236 — Phase 4 of DRO-231.
//  Empty-state hero for the Home/Today tab when the user has no plan yet.
//  Centers the Dromos mark, a headline, supporting body copy, and a primary CTA
//  that triggers the plan-generation flow.
//

import SwiftUI

/// Empty-state hero shown on the Home tab when the user has no active plan.
///
/// Layout: vertically centered Dromos logo, headline, body copy, and a primary
/// "Generate plan" button. The CTA is wired through `onGeneratePlan` so the
/// caller decides what flow to present (sheet, navigation, etc.).
struct EmptyHomeHero: View {
    let onGeneratePlan: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            // Dromos mark — using the asset-catalog logo (light/dark adaptive).
            Image("DromosLogo")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundColor(.accentColor)

            // Headline
            Text("Generate your first plan")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            // Body copy
            Text("Tell us your race goal and we'll build a tailored plan around the time you have.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            // Primary CTA — uses DromosButton for visual consistency with Auth.
            DromosButton(title: "Generate plan", action: onGeneratePlan)
                .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

#Preview("EmptyHomeHero") {
    EmptyHomeHero(onGeneratePlan: {})
        .background(Color.pageSurface)
}
