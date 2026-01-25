//
//  ProfileView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import SwiftUI

/// User profile view.
/// Displays user info with edit capability and sign out option.
struct ProfileView: View {
    @ObservedObject var authService: AuthService
    @StateObject private var profileService = ProfileService()

    @State private var isEditing = false
    @State private var editableName = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var loadProfileTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                // Profile section
                Section {
                    if profileService.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if isEditing {
                        editingView
                    } else {
                        profileInfoView
                    }
                } header: {
                    Text("Profile")
                }

                // Actions section
                Section {
                    Button(role: .destructive) {
                        Task {
                            await signOut()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                        }
                    }
                }

                // Error display
                if let error = errorMessage ?? profileService.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        Button("Cancel") {
                            cancelEditing()
                        }
                    } else {
                        Button("Edit") {
                            startEditing()
                        }
                        .disabled(profileService.isLoading)
                    }
                }
            }
            .task {
                loadProfileTask = Task {
                    await loadProfile()
                }
            }
            .onDisappear {
                loadProfileTask?.cancel()
            }
        }
    }

    // MARK: - Subviews

    /// View for displaying profile info (non-editing state).
    private var profileInfoView: some View {
        Group {
            HStack {
                Text("Email")
                Spacer()
                Text(authService.currentUserEmail ?? "Unknown")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Name")
                Spacer()
                Text(profileService.user?.name ?? "No name set")
                    .foregroundStyle(profileService.user?.name == nil ? .secondary : .primary)
            }
        }
    }

    /// View for editing profile.
    private var editingView: some View {
        Group {
            HStack {
                Text("Email")
                Spacer()
                Text(authService.currentUserEmail ?? "Unknown")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Name")
                Spacer()
                TextField("Enter your name", text: $editableName)
                    .multilineTextAlignment(.trailing)
            }

            Button {
                Task {
                    await saveProfile()
                }
            } label: {
                if isSaving {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    Text("Save Changes")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(isSaving)
        }
    }

    // MARK: - Actions

    private func loadProfile() async {
        guard let userId = authService.currentUserId else { return }

        do {
            try await profileService.fetchProfile(userId: userId)
            editableName = profileService.user?.name ?? ""
        } catch {
            errorMessage = "Failed to load profile"
        }
    }

    private func startEditing() {
        editableName = profileService.user?.name ?? ""
        isEditing = true
    }

    private func cancelEditing() {
        isEditing = false
        editableName = profileService.user?.name ?? ""
    }

    private func saveProfile() async {
        guard let userId = authService.currentUserId else { return }

        isSaving = true
        errorMessage = nil

        do {
            try await profileService.updateProfile(
                userId: userId,
                name: editableName.isEmpty ? nil : editableName
            )
            isEditing = false
        } catch {
            errorMessage = "Failed to save profile"
        }

        isSaving = false
    }

    private func signOut() async {
        do {
            try await authService.signOut()
            profileService.clearProfile()
        } catch {
            errorMessage = "Failed to sign out"
        }
    }
}

#Preview {
    ProfileView(authService: AuthService())
}
