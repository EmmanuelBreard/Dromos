//
//  SignUpView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// Sign up form for new users.
/// Handles email/password/confirm input with validation.
struct SignUpView: View {
    @ObservedObject var authService: AuthService

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    /// Callback when user wants to switch to login.
    var onSwitchToLogin: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 8) {
                Image("DromosLogo")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 48)
                Text("Create account")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Start your triathlon training journey")
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
                    .textContentType(.newPassword)

                DromosTextField(icon: "lock", placeholder: "Confirm Password", text: $confirmPassword, isSecure: true)
                    .textContentType(.newPassword)
            }

            // Validation hints
            if !password.isEmpty && password.count < 6 {
                Text("Password must be at least 6 characters")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !confirmPassword.isEmpty && password != confirmPassword {
                Text("Passwords don't match")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Error message
            if let error = authService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            // Sign up button
            DromosButton(title: "Create Account", isLoading: authService.isLoading) {
                Task {
                    try? await authService.signUp(email: email, password: password)
                }
            }
            .disabled(!isFormValid || authService.isLoading)

            // Switch to login
            Button {
                onSwitchToLogin()
            } label: {
                HStack(spacing: 4) {
                    Text("Already have an account?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Sign in")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                }
            }
            .disabled(authService.isLoading)
        }
        .padding()
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        // Basic validation - server will handle detailed email format validation
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 6 &&
        password == confirmPassword
    }
}

#Preview {
    SignUpView(authService: AuthService()) {
        // No-op for preview
    }
}
