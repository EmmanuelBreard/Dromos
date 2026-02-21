//
//  LoginView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// Login form for existing users.
/// Handles email/password input with basic validation.
struct LoginView: View {
    @ObservedObject var authService: AuthService

    @State private var email = ""
    @State private var password = ""

    /// Callback when user wants to switch to sign up.
    var onSwitchToSignUp: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 8) {
                Image("DromosLogo")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 48)
                Text("Welcome back")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Sign in to continue your training")
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            // Form fields
            VStack(spacing: 16) {
                DromosTextField(icon: "envelope", placeholder: "Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)

                DromosTextField(icon: "lock", placeholder: "Password", text: $password, isSecure: true)
                    .textContentType(.password)
            }

            // Error message
            if let error = authService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            // Sign in button
            DromosButton(title: "Sign In", isLoading: authService.isLoading) {
                Task {
                    try? await authService.signIn(email: email, password: password)
                }
            }
            .disabled(!isFormValid || authService.isLoading)

            // Switch to sign up
            Button {
                onSwitchToSignUp()
            } label: {
                HStack(spacing: 4) {
                    Text("Don't have an account?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Sign up")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            .disabled(authService.isLoading)
        }
        .padding()
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        // Basic validation - server will handle detailed email format validation
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }
}

#Preview {
    LoginView(authService: AuthService()) {
        // No-op for preview
    }
}
