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
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "figure.run")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)
                Text("Create account")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Start your triathlon training journey")
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            // Form fields
            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)

                SecureField("Confirm Password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
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
            Button {
                Task {
                    try await authService.signUp(email: email, password: password)
                }
            } label: {
                if authService.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Create Account")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isFormValid || authService.isLoading)

            // Switch to login
            Button {
                onSwitchToLogin()
            } label: {
                Text("Already have an account? Sign in")
                    .font(.subheadline)
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
