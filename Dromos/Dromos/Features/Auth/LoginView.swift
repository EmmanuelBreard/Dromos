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
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "figure.run")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)
                Text("Welcome back")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Sign in to continue your training")
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
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
            }

            // Error message
            if let error = authService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            // Sign in button
            Button {
                Task {
                    try await authService.signIn(email: email, password: password)
                }
            } label: {
                if authService.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Sign In")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isFormValid || authService.isLoading)

            // Switch to sign up
            Button {
                onSwitchToSignUp()
            } label: {
                Text("Don't have an account? Sign up")
                    .font(.subheadline)
            }
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
