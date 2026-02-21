//
//  AuthComponents.swift
//  Dromos
//
//  Created by Emmanuel Breard on 21/02/2026.
//

import SwiftUI

// MARK: - DromosTextField

/// A styled text field for auth screens.
///
/// Renders a dark rounded-rect container with a leading SF Symbol icon,
/// gray placeholder, and optional secure input mode. Adapts correctly
/// to both light and dark appearance.
///
/// Usage:
/// ```swift
/// DromosTextField(icon: "envelope", placeholder: "Email", text: $email)
/// DromosTextField(icon: "lock", placeholder: "Password", text: $password, isSecure: true)
/// ```
struct DromosTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color(uiColor: .systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(uiColor: .systemGray4), lineWidth: 1)
        )
    }
}

// MARK: - DromosButton

/// A full-width primary action button for auth screens.
///
/// Shows a dark pill-shaped button with white title text and a trailing
/// chevron icon. When `isLoading` is `true`, a `ProgressView` replaces
/// the label and the button is automatically disabled.
///
/// Usage:
/// ```swift
/// DromosButton(title: "Sign In", isLoading: authService.isLoading) {
///     Task { try await authService.signIn(email: email, password: password) }
/// }
/// ```
struct DromosButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Loading state
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    // Default state: title + trailing chevron
                    HStack {
                        Text(title)
                            .font(.body)
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(uiColor: .systemGray2))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isLoading)
    }
}

// MARK: - Previews

#Preview("DromosTextField — variants") {
    VStack(spacing: 16) {
        DromosTextField(icon: "envelope", placeholder: "Email", text: .constant(""))
        DromosTextField(icon: "envelope", placeholder: "Email", text: .constant("user@example.com"))
        DromosTextField(icon: "lock", placeholder: "Password", text: .constant(""), isSecure: true)
        DromosTextField(icon: "lock", placeholder: "Password", text: .constant("secret"), isSecure: true)
    }
    .padding()
}

#Preview("DromosButton — variants") {
    VStack(spacing: 16) {
        DromosButton(title: "Sign In", isLoading: false) {}
        DromosButton(title: "Create Account", isLoading: false) {}
        DromosButton(title: "Loading…", isLoading: true) {}
    }
    .padding()
}
