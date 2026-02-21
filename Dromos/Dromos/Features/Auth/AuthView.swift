//
//  AuthView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// Container view for authentication screens.
/// Manages switching between login and sign up forms.
struct AuthView: View {
    @ObservedObject var authService: AuthService

    /// Current authentication mode.
    @State private var isShowingSignUp = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                Group {
                    if isShowingSignUp {
                        SignUpView(authService: authService) {
                            withAnimation {
                                isShowingSignUp = false
                                authService.errorMessage = nil
                            }
                        }
                    } else {
                        LoginView(authService: authService) {
                            withAnimation {
                                isShowingSignUp = true
                                authService.errorMessage = nil
                            }
                        }
                    }
                }
                .frame(minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color(uiColor: .systemBackground))
        .ignoresSafeArea()
    }
}

#Preview {
    AuthView(authService: AuthService())
}
