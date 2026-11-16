//
//  OnboardingFlowView.swift
//  Dromos
//
//  New users onboard in a coach chat. The old six-screen form is retired.
//

import SwiftUI

struct OnboardingFlowView: View {
    @ObservedObject var authService: AuthService
    @Binding var autoStartPlan: Bool

    var body: some View {
        OnboardingChatView(authService: authService, autoStartPlan: $autoStartPlan)
    }
}

#Preview {
    OnboardingFlowView(authService: AuthService(), autoStartPlan: .constant(false))
}
