//
//  OnboardingChatView.swift
//  Dromos
//
//  New-user onboarding. The order of questions is fixed. Quick replies sit
//  above a text field, and a failed coach call never blocks the buttons.
//

import SwiftUI

struct OnboardingChatView: View {
    @ObservedObject var authService: AuthService
    @Binding var autoStartPlan: Bool
    @StateObject private var profileService = ProfileService()
    @StateObject private var session = OnboardingSession()
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if session.isLoading {
                    Spacer()
                    ProgressView("Loading your answers…")
                    Spacer()
                } else if session.loadFailed {
                    Spacer()
                    VStack(spacing: 12) {
                        Text("I couldn't load your saved answers.")
                            .multilineTextAlignment(.center)
                        Button("Try again") {
                            Task { await session.load() }
                        }
                        .buttonStyle(OnboardingPrimaryButton())
                    }
                    .padding(24)
                    Spacer()
                } else {
                    transcript
                    if let error = session.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                            .padding(.top, 4)
                    }
                    quickReplies
                    inputBar
                }
            }
            .navigationTitle("Your coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign Out") {
                        Task { try? await authService.signOut() }
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .task {
            session.bind(auth: authService, profile: profileService) {
                autoStartPlan = true
            }
            await session.load()
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(session.lines) { line in
                        lineView(line)
                            .id(line.id)
                    }
                    if session.state.editing == nil {
                        activeCard
                            .id("active-card")
                    }
                    if session.isThinking {
                        ProgressView()
                            .padding(.horizontal, 16)
                            .id("thinking")
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: session.lines.count) { _, _ in
                scrollToEnd(proxy)
            }
            .onChange(of: session.isThinking) { _, _ in
                scrollToEnd(proxy)
            }
            .onTapGesture { inputFocused = false }
        }
    }

    @ViewBuilder
    private func lineView(_ line: OnboardingLine) -> some View {
        switch line.role {
        case .coach:
            bubble(line.text, isAthlete: false)
        case .athlete:
            bubble(line.text, isAthlete: true)
        case .summary(let step):
            if session.state.editing == step {
                VStack(alignment: .leading, spacing: 8) {
                    bubble(line.text, isAthlete: true)
                    editorCard(for: step)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(line.text)
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    Button("Edit") { session.edit(step) }
                        .font(.caption.weight(.semibold))
                }
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
            }
        }
    }

    private func bubble(_ text: String, isAthlete: Bool) -> some View {
        HStack {
            if isAthlete { Spacer(minLength: 48) }
            Text(text)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isAthlete ? Color.accentColor : Color(.systemGray6))
                .foregroundStyle(isAthlete ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if !isAthlete { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var activeCard: some View {
        editorCard(for: session.state.activeStep)
    }

    @ViewBuilder
    private func editorCard(for step: OnboardingStep) -> some View {
        switch session.state.mode {
        case .pickTime:
            OnboardingTimeCard(defaultMinutes: session.state.answers.raceObjective == .olympic ? 150 : 360) { minutes in
                Task { await session.confirmMinutes(minutes) }
            }
        case .enterVma:
            OnboardingValueCard(
                title: "VMA",
                initial: 14,
                range: 10...25,
                step: 0.1,
                format: { "\(OnboardingCopy.formatVma($0)) km/h" }
            ) { value in Task { await session.confirmVma(value) } }
        case .enterRunTime(let distance):
            OnboardingClockEntryCard(
                title: distance.title,
                initialSeconds: distance == .fiveK ? 25 * 60 : 50 * 60,
                minuteRange: distance == .fiveK ? 13...80 : 27...150
            ) { seconds in Task { await session.confirmRunTime(distance, seconds: seconds) } }
        case .enterCss, .enterTypicalPace:
            OnboardingClockEntryCard(title: "Per 100m", initialSeconds: 120, minuteRange: 1...4) { seconds in
                Task { await session.confirmCss(seconds) }
            }
        case .enterSwimTime(let distance):
            OnboardingClockEntryCard(
                title: distance.title,
                initialSeconds: distance == .fourHundred ? 8 * 60 : 30 * 60,
                minuteRange: distance == .fourHundred ? 4...18 : 15...60
            ) { seconds in Task { await session.confirmSwimTime(distance, seconds: seconds) } }
        case .enterFtp:
            OnboardingValueCard(
                title: "FTP",
                initial: 180,
                range: 50...500,
                step: 5,
                format: { "\(Int($0)) W" }
            ) { value in Task { await session.confirmFtp(Int(value)) } }
        case .enterTwenty:
            OnboardingValueCard(
                title: "20-minute power",
                initial: 200,
                range: 50...525,
                step: 5,
                format: { "\(Int($0)) W" }
            ) { value in Task { await session.confirmTwenty(Int(value)) } }
        case .enterMaxHr:
            OnboardingValueCard(
                title: "Max heart rate",
                initial: 180,
                range: 100...220,
                step: 1,
                format: { "\(Int($0)) bpm" }
            ) { value in Task { await session.confirmMaxHr(Int(value)) } }
        case .enterBirthYear:
            OnboardingBirthYearCard { year in Task { await session.confirmBirthYear(year) } }
        case .ask, .pickRunDistance, .pickSwimDistance, .confirmSuggestion, .confirmLimitersNote:
            askCard(for: step)
        }
    }

    @ViewBuilder
    private func askCard(for step: OnboardingStep) -> some View {
        switch step {
        case .raceDate where session.state.mode == .ask:
            OnboardingDateCard(minimum: PlanHorizon.earliestLocalDay(now: Date(), calendar: .current)) { date in
                Task { await session.confirmDate(date) }
            }
        case .weeklyHours where session.state.mode == .ask:
            OnboardingHoursCard(initial: session.state.answers.currentWeeklyHours ?? 4) { hours in
                Task { await session.confirmHours(hours) }
            }
        case .swimDays, .bikeDays, .runDays:
            if let sport = OnboardingSport.from(step: step) {
                OnboardingAvailabilityCard(
                    title: sport.title,
                    selected: session.dayDraft,
                    hinted: hintedDays(except: sport),
                    onToggle: { session.toggleDay($0) },
                    onAnyDay: { Task { await session.tap(.anyDay) } },
                    onDone: { Task { await session.confirmDays() } }
                )
            }
        case .dailyDuration where session.state.mode == .ask:
            OnboardingDurationCard(
                days: session.state.answers.trainingDays,
                values: session.durationDraft,
                onChange: { session.setDuration($1, for: $0) },
                onDone: { Task { await session.tap(.keepDurations) } }
            )
        case .recap where session.state.mode == .ask && session.state.editing == nil:
            OnboardingRecapCard(rows: OnboardingCopy.recapRows(session.state.answers)) { step in
                session.edit(step)
            }
        default:
            EmptyView()
        }
    }

    private func hintedDays(except sport: OnboardingSport) -> [String] {
        let answers = session.state.answers
        switch sport {
        case .swim: return []
        case .bike: return answers.swimDays
        case .run: return Weekday.union(answers.swimDays, answers.bikeDays)
        }
    }

    private var quickReplies: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(session.replies) { reply in
                    Button(reply.title) {
                        inputFocused = false
                        Task { await session.tap(reply.id) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                    .disabled(session.isBusy)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var inputBar: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("Or type an answer…", text: $session.draft, axis: .vertical)
                .focused($inputFocused)
                .lineLimit(1...4)
                .padding(.leading, 16)
                .padding(.vertical, 10)
            Button {
                inputFocused = false
                Task { await session.sendDraft() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
            .disabled(session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isBusy)
            .padding(.trailing, 8)
        }
        .background(Capsule().fill(Color(.secondarySystemBackground)))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation {
            if session.isThinking {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if session.state.editing == nil {
                proxy.scrollTo("active-card", anchor: .bottom)
            } else if let last = session.lines.last?.id {
                proxy.scrollTo(last, anchor: .bottom)
            }
        }
    }
}
