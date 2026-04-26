//
//  ProfileView.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import AuthenticationServices
import SwiftUI

/// User profile view displaying and editing user information in 4 organized sections.
///
/// Sections:
/// 1. Goals - Race objectives and targets
/// 2. Metrics - Performance metrics (VMA, CSS, FTP, experience)
/// 3. Settings - Personal information (name, email)
/// 4. Strava - OAuth connection status and sync controls
struct ProfileView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var profileService: ProfileService
    @ObservedObject var stravaService: StravaService

    /// Local copy of user for immediate UI updates during editing.
    /// Separate from profileService.user to avoid race conditions during save.
    @State private var user: User?
    @State private var isLoading = false
    @State private var isEditing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showValidationError = false
    @State private var validationMessage = ""
    @State private var showDisconnectAlert = false

    /// Provides the key UIWindow for ASWebAuthenticationSession presentation.
    private let authSessionContext = WebAuthPresentationContext()

    // MARK: - Edit State

    @State private var showDeleteAccountAlert = false
    @State private var editName: String = ""
    @State private var editRaceObjective: RaceObjective = .sprint
    @State private var editRaceDate: Date = Date()
    @State private var editTimeHours: String = ""
    @State private var editTimeMinutes: String = ""
    @State private var editVma: String = ""
    @State private var editCssMinutes: String = ""
    @State private var editCssSeconds: String = ""
    @State private var editFtp: String = ""
    @State private var editExperienceYears: String = ""
    @State private var editMaxHr: String = ""
    @State private var editBirthYear: String = ""

    // MARK: - Static Properties

    /// Reusable date formatter to avoid recreation on each call
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let user = user {
                    Form {
                        // SECTION 1: GOALS
                        Section("Goals") {
                            if isEditing {
                                goalsEditingView
                            } else {
                                goalsDisplayView(user: user)
                            }
                        }

                        // SECTION 2: METRICS
                        Section("Metrics") {
                            if isEditing {
                                metricsEditingView
                            } else {
                                metricsDisplayView(user: user)
                            }
                        }

                        // SECTION 3: SETTINGS
                        Section("Settings") {
                            if isEditing {
                                settingsEditingView
                            } else {
                                settingsDisplayView(user: user)
                            }
                        }

                        // SECTION 4: STRAVA
                        stravaSection

                        // Sign Out section
                        Section {
                            Button("Sign Out", role: .destructive) {
                                Task {
                                    do {
                                        try await authService.signOut()
                                        profileService.clearProfile()
                                    } catch {
                                        errorMessage = mapSaveError(error)
                                        showError = true
                                    }
                                }
                            }
                            Button("Delete Account", role: .destructive) {
                                showDeleteAccountAlert = true
                            }
                        }
                    }
                } else {
                    Text("Unable to load profile")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditing {
                        HStack {
                            Button("Cancel") {
                                isEditing = false
                                loadEditState()
                            }
                            Button("Save") {
                                saveProfile()
                            }
                        }
                    } else {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                }
            }
        }
        .task {
            await fetchProfile()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Validation Error", isPresented: $showValidationError) {
            Button("OK") { }
        } message: {
            Text(validationMessage)
        }
        .alert("Delete Account", isPresented: $showDeleteAccountAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    isLoading = true
                    do {
                        try await authService.deleteAccount()
                        profileService.clearProfile()
                    } catch {
                        isLoading = false
                        errorMessage = "Unable to delete account. Please try again."
                        showError = true
                    }
                }
            }
        } message: {
            Text("This will permanently delete your account and all data. This cannot be undone.")
        }
        .onChange(of: stravaService.isConnecting) { oldValue, newValue in
            // OAuth completed: isConnecting transitioned true → false
            if oldValue && !newValue && stravaService.errorMessage == nil {
                Task {
                    if let userId = authService.currentUserId {
                        do {
                            user = try await profileService.fetchProfile(userId: userId)
                        } catch {
                            errorMessage = mapSaveError(error)
                            showError = true
                        }
                    }
                    // Trigger first sync to pull activities after connecting
                    if profileService.user?.isStravaConnected == true {
                        await stravaService.syncActivities()
                    }
                }
            }
        }
        .alert("Disconnect Strava?", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                Task {
                    await stravaService.disconnect()
                    // Refresh profile so isStravaConnected reflects the cleared stravaAthleteId
                    if let userId = authService.currentUserId {
                        do {
                            user = try await profileService.fetchProfile(userId: userId)
                        } catch {
                            errorMessage = mapSaveError(error)
                            showError = true
                        }
                    }
                }
            }
        } message: {
            Text("Your Strava account will be unlinked and activity sync will stop.")
        }
    }

    // MARK: - Strava Section

    /// Strava integration section — shows connect button or connected status depending on state.
    @ViewBuilder
    private var stravaSection: some View {
        if profileService.user?.isStravaConnected == true {
            Section {
                HStack {
                    Image("StravaLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    if let result = stravaService.lastSyncResult {
                        Text("Connected (\(result.totalActivities) activities)")
                    } else {
                        Text("Connected")
                    }
                    Spacer()
                    if stravaService.isSyncing {
                        ProgressView()
                    }
                }

                Button(role: .destructive) {
                    showDisconnectAlert = true
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("Disconnect Strava")
                    }
                }
            } header: {
                Text("Strava")
            }
        } else {
            Section {
                Image("StravaConnectButton")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 48)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !stravaService.isConnecting {
                            stravaService.startOAuth(from: authSessionContext)
                        }
                    }
                    .opacity(stravaService.isConnecting ? 0.5 : 1.0)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                if stravaService.isConnecting {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 4)
                        Text("Connecting…")
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }

                if let error = stravaService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .listRowBackground(Color.clear)
                }
            } header: {
                Text("Strava")
            }
        }
    }

    // MARK: - Goals Section Views

    /// Display mode for Goals section
    private func goalsDisplayView(user: User) -> some View {
        Group {
            HStack {
                Text("Race Type")
                Spacer()
                Text(user.raceObjective?.rawValue ?? "Not set")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Race Date")
                Spacer()
                Text(formatDate(user.raceDate))
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Time Objective")
                Spacer()
                Text(formatTimeObjective(totalMinutes: user.timeObjectiveMinutes))
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Edit mode for Goals section
    private var goalsEditingView: some View {
        Group {
            Picker("Race Type", selection: $editRaceObjective) {
                ForEach(RaceObjective.allCases, id: \.self) { objective in
                    Text(objective.rawValue).tag(objective)
                }
            }

            DatePicker(
                "Race Date",
                selection: $editRaceDate,
                in: Date()...,
                displayedComponents: .date
            )

            HStack {
                Text("Time Objective")
                Spacer()
                TextField("H", text: $editTimeHours)
                    .keyboardType(.numberPad)
                    .frame(width: 40)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                Text(":")
                TextField("M", text: $editTimeMinutes)
                    .keyboardType(.numberPad)
                    .frame(width: 40)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Metrics Section Views

    /// Display mode for Metrics section
    private func metricsDisplayView(user: User) -> some View {
        Group {
            HStack {
                Text("VMA")
                Spacer()
                Text(formatVma(user.vma))
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("CSS")
                Spacer()
                Text(formatCss(totalSeconds: user.cssSecondsPer100m))
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("FTP")
                Spacer()
                Text(formatFtp(user.ftp))
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Experience")
                Spacer()
                Text(formatExperience(user.experienceYears))
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Max HR")
                Spacer()
                Text(formatMaxHr(user.maxHr))
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Birth Year")
                Spacer()
                Text(formatBirthYear(user.birthYear))
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Edit mode for Metrics section
    private var metricsEditingView: some View {
        Group {
            HStack {
                Text("VMA (km/h)")
                Spacer()
                TextField("e.g., 18.5", text: $editVma)
                    .keyboardType(.decimalPad)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Text("CSS (per 100m)")
                Spacer()
                TextField("M", text: $editCssMinutes)
                    .keyboardType(.numberPad)
                    .frame(width: 40)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                Text(":")
                TextField("S", text: $editCssSeconds)
                    .keyboardType(.numberPad)
                    .frame(width: 40)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Text("FTP (W)")
                Spacer()
                TextField("e.g., 250", text: $editFtp)
                    .keyboardType(.numberPad)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Text("Experience (years)")
                Spacer()
                TextField("e.g., 2", text: $editExperienceYears)
                    .keyboardType(.numberPad)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Text("Max HR (bpm)")
                Spacer()
                TextField("e.g., 184", text: $editMaxHr)
                    .keyboardType(.numberPad)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Text("Birth Year")
                Spacer()
                TextField("e.g., 1990", text: $editBirthYear)
                    .keyboardType(.numberPad)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    // MARK: - Settings Section Views

    /// Display mode for Settings section
    private func settingsDisplayView(user: User) -> some View {
        Group {
            HStack {
                Text("Name")
                Spacer()
                Text(user.name ?? "Not set")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Email")
                Spacer()
                Text(authService.currentUserEmail ?? "Not set")
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Edit mode for Settings section
    private var settingsEditingView: some View {
        Group {
            HStack {
                Text("Name")
                Spacer()
                TextField("Name", text: $editName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Text("Email")
                Spacer()
                Text(authService.currentUserEmail ?? "Not set")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Validation

    /// Validates all edit fields before save.
    /// Returns nil if valid, or an error message if invalid.
    private func validateEditFields() -> String? {
        // VMA validation (10-25 km/h)
        if !editVma.isEmpty {
            guard let vma = Double(editVma), vma >= 10, vma <= 25 else {
                return "VMA must be between 10 and 25 km/h"
            }
        }

        // FTP validation (50-500 watts)
        if !editFtp.isEmpty {
            guard let ftp = Int(editFtp), ftp >= 50, ftp <= 500 else {
                return "FTP must be between 50 and 500 watts"
            }
        }

        // CSS validation (25-300 total seconds, seconds component 0-59)
        if !editCssMinutes.isEmpty || !editCssSeconds.isEmpty {
            let minutes = Int(editCssMinutes) ?? 0
            let seconds = Int(editCssSeconds) ?? 0
            let totalSeconds = minutes * 60 + seconds

            if seconds < 0 || seconds > 59 {
                return "CSS seconds must be between 0 and 59"
            }

            if totalSeconds < 25 || totalSeconds > 300 {
                return "CSS must be between 0:25 and 5:00 per 100m"
            }
        }

        // Experience years validation (>= 0)
        if !editExperienceYears.isEmpty {
            guard let years = Int(editExperienceYears), years >= 0 else {
                return "Experience must be 0 or more years"
            }
        }

        // Max HR validation (100-220 bpm — matches DB CHECK constraint)
        if !editMaxHr.isEmpty {
            guard let maxHr = Int(editMaxHr), (100...220).contains(maxHr) else {
                return "Max HR must be between 100 and 220 bpm"
            }
        }

        // Birth year validation (1920-2030 — matches DB CHECK constraint)
        if !editBirthYear.isEmpty {
            guard let year = Int(editBirthYear), (1920...2030).contains(year) else {
                return "Birth year must be between 1920 and 2030"
            }
        }

        // Race date validation (not in the past)
        if editRaceDate < Calendar.current.startOfDay(for: Date()) {
            return "Race date cannot be in the past"
        }

        return nil
    }

    // MARK: - Data Methods

    /// Fetch the current user's profile from the database
    private func fetchProfile() async {
        guard let userId = authService.currentUserId else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            user = try await profileService.fetchProfile(userId: userId)
            loadEditState()
        } catch {
            errorMessage = mapSaveError(error)
            showError = true
        }
    }

    /// Load current user data into edit state variables
    private func loadEditState() {
        guard let user = user else { return }
        editName = user.name ?? ""
        editRaceObjective = user.raceObjective ?? .sprint
        editRaceDate = user.raceDate ?? Date()
        // Decompose total minutes into hours:minutes for display
        if let totalMinutes = user.timeObjectiveMinutes {
            editTimeHours = String(totalMinutes / 60)
            editTimeMinutes = String(totalMinutes % 60)
        } else {
            editTimeHours = ""
            editTimeMinutes = ""
        }
        editVma = user.vma.map { String(format: "%.1f", $0) } ?? ""
        // Decompose total seconds into min:sec for display
        if let totalSeconds = user.cssSecondsPer100m {
            editCssMinutes = String(totalSeconds / 60)
            editCssSeconds = String(totalSeconds % 60)
        } else {
            editCssMinutes = ""
            editCssSeconds = ""
        }
        editFtp = user.ftp.map(String.init) ?? ""
        editExperienceYears = user.experienceYears.map(String.init) ?? ""
        editMaxHr = user.maxHr.map(String.init) ?? ""
        editBirthYear = user.birthYear.map(String.init) ?? ""
    }

    /// Save profile changes to the database
    private func saveProfile() {
        guard let userId = authService.currentUserId else { return }

        // Validate all fields before attempting save
        if let validationError = validateEditFields() {
            validationMessage = validationError
            showValidationError = true
            return
        }

        isLoading = true

        Task {
            do {
                // Recompose hours:minutes UI into total minutes
                let timeObjectiveMinutes: Int? = {
                    let hours = Int(editTimeHours) ?? 0
                    let minutes = Int(editTimeMinutes) ?? 0
                    let total = hours * 60 + minutes
                    return total > 0 ? total : nil
                }()
                
                // Recompose min:sec UI into total seconds
                let cssSecondsPer100m: Int? = {
                    let minutes = Int(editCssMinutes) ?? 0
                    let seconds = Int(editCssSeconds) ?? 0
                    let total = minutes * 60 + seconds
                    return total > 0 ? total : nil
                }()
                
                try await profileService.updateProfile(
                    userId: userId,
                    name: editName.isEmpty ? nil : editName,
                    raceObjective: editRaceObjective,
                    raceDate: editRaceDate,
                    timeObjectiveMinutes: timeObjectiveMinutes,
                    vma: Double(editVma),
                    cssSecondsPer100m: cssSecondsPer100m,
                    ftp: Int(editFtp),
                    experienceYears: Int(editExperienceYears),
                    maxHr: Int(editMaxHr),
                    birthYear: Int(editBirthYear)
                )

                await MainActor.run {
                    user = profileService.user
                    isEditing = false
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = mapSaveError(error)
                    showError = true
                }
            }
        }
    }

    // MARK: - Error Handling

    /// Maps database and network errors to user-friendly messages.
    private func mapSaveError(_ error: Error) -> String {
        let errorString = error.localizedDescription.lowercased()

        // Database constraint violations
        if errorString.contains("check") || errorString.contains("constraint") {
            return "Some values are outside the valid range. Please check your entries and try again."
        }

        // Network errors
        if errorString.contains("network") || errorString.contains("connection") {
            return "Unable to connect. Please check your internet connection and try again."
        }

        // Generic fallback
        return "Unable to save your profile. Please try again."
    }

    // MARK: - Formatters

    /// Format date for display
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Not set" }
        return Self.dateFormatter.string(from: date)
    }

    /// Format time objective (hours:minutes) from total minutes
    private func formatTimeObjective(totalMinutes: Int?) -> String {
        guard let totalMinutes = totalMinutes else { return "Not set" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(minutes)m"
    }

    /// Format VMA (Vitesse Maximale Aérobie)
    private func formatVma(_ vma: Double?) -> String {
        guard let vma = vma else { return "Not set" }
        return String(format: "%.1f km/h", vma)
    }

    /// Format CSS (Critical Swim Speed) from total seconds
    private func formatCss(totalSeconds: Int?) -> String {
        guard let totalSeconds = totalSeconds else { return "Not set" }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d / 100m", minutes, seconds)
    }

    /// Format FTP (Functional Threshold Power)
    private func formatFtp(_ ftp: Int?) -> String {
        guard let ftp = ftp else { return "Not set" }
        return "\(ftp) W"
    }

    /// Format max HR
    private func formatMaxHr(_ maxHr: Int?) -> String {
        guard let maxHr = maxHr else { return "Not set" }
        return "\(maxHr) bpm"
    }

    /// Format birth year
    private func formatBirthYear(_ birthYear: Int?) -> String {
        guard let birthYear = birthYear else { return "Not set" }
        return "\(birthYear)"
    }

    /// Format experience years
    private func formatExperience(_ years: Int?) -> String {
        guard let years = years else { return "Not set" }
        return "\(years) year\(years == 1 ? "" : "s")"
    }
}

#Preview {
    ProfileView(
        authService: AuthService(),
        profileService: ProfileService(),
        stravaService: StravaService()
    )
}
