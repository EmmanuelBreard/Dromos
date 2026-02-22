//
//  StravaService.swift
//  Dromos
//
//  Created by Emmanuel Breard on 22/02/2026.
//

import AuthenticationServices
import Combine
import Foundation
import Supabase

/// Service handling all Strava interactions: OAuth connection, sync, and activity fetch.
/// Follows the @MainActor ObservableObject pattern used across Dromos services.
@MainActor
final class StravaService: ObservableObject {

    // MARK: - Published Properties

    /// Whether a Strava activity sync is currently in progress.
    @Published var isSyncing = false

    /// Whether the OAuth connection flow is currently in progress.
    @Published var isConnecting = false

    /// Result of the most recent sync operation, nil if no sync has run yet.
    @Published var lastSyncResult: SyncResult?

    /// Last error message from any Strava operation, nil if no error.
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let client = SupabaseClientProvider.client

    // MARK: - OAuth Flow

    /// Opens an ASWebAuthenticationSession for the Strava OAuth authorization flow.
    /// On success, exchanges the authorization code via the `strava-auth` Edge Function.
    /// After completion, the caller should refetch the user profile to get the updated `stravaAthleteId`.
    /// - Parameter contextProvider: The presentation context for the auth session (typically the hosting window scene)
    func startOAuth(from contextProvider: ASWebAuthenticationPresentationContextProviding) {
        let clientId = Configuration.stravaClientId
        let redirectUri = "dromos://strava-callback"
        let scope = "activity:read_all"

        var components = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "approval_prompt", value: "auto"),
        ]
        guard let authURL = components.url else { return }

        isConnecting = true

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "dromos"
        ) { [weak self] callbackURL, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    // User-cancelled is not an error worth surfacing
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        self.isConnecting = false
                        return
                    }
                    self.errorMessage = error.localizedDescription
                    self.isConnecting = false
                    return
                }
                guard
                    let callbackURL,
                    let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    self.errorMessage = "Failed to get authorization code"
                    self.isConnecting = false
                    return
                }
                await self.exchangeCode(code)
            }
        }
        session.prefersEphemeralWebBrowserSession = true
        session.presentationContextProvider = contextProvider
        session.start()
    }

    /// Exchanges the OAuth authorization code for tokens via the `strava-auth` Edge Function.
    /// The Edge Function stores the tokens and updates `strava_athlete_id` on the user row.
    private func exchangeCode(_ code: String) async {
        // isConnecting is already true — set in startOAuth before the browser phase
        errorMessage = nil
        defer { isConnecting = false }

        do {
            // The Edge Function reads the code, exchanges it with Strava, and stores tokens.
            // No response body needed — success means tokens were stored.
            try await client.functions.invoke(
                "strava-auth",
                options: FunctionInvokeOptions(body: ["code": code])
            )
        } catch {
            errorMessage = "Failed to connect Strava: \(error.localizedDescription)"
        }
    }

    // MARK: - Disconnect

    /// Disconnects the user's Strava account by calling the `strava-auth` Edge Function with DELETE.
    /// The Edge Function revokes the Strava token and clears `strava_athlete_id` on the user row.
    func disconnect() async {
        errorMessage = nil

        do {
            try await client.functions.invoke(
                "strava-auth",
                options: FunctionInvokeOptions(method: .delete)
            )
        } catch {
            errorMessage = "Failed to disconnect Strava: \(error.localizedDescription)"
        }
    }

    // MARK: - Sync

    /// Triggers a Strava activity sync via the `strava-sync` Edge Function.
    /// Updates `lastSyncResult` on success with the count of synced activities.
    func syncActivities() async {
        guard !isSyncing else { return }
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            // The Edge Function returns { synced_count, total_activities, rate_limited }
            // Using the Decodable overload of invoke — SyncResponse uses explicit CodingKeys
            // because Edge Function responses bypass the PostgREST snake_case decoder.
            let response: SyncResponse = try await client.functions.invoke("strava-sync")
            lastSyncResult = response.toSyncResult
        } catch {
            errorMessage = "Sync failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Fetch Activities from DB

    /// Fetches Strava activities from the `strava_activities` table.
    /// Optionally filtered by a date range. Results are ordered by `start_date` descending.
    /// - Parameters:
    ///   - startDate: Optional lower bound for `start_date` (inclusive)
    ///   - endDate: Optional upper bound for `start_date` (inclusive)
    /// - Returns: Array of `StravaActivity`, empty on error (error set in `errorMessage`)
    func fetchActivities(from startDate: Date? = nil, to endDate: Date? = nil) async -> [StravaActivity] {
        do {
            var query = client
                .from("strava_activities")
                .select()

            if let startDate {
                query = query.gte("start_date", value: startDate.ISO8601Format())
            }
            if let endDate {
                query = query.lte("start_date", value: endDate.ISO8601Format())
            }

            let activities: [StravaActivity] = try await query
                .order("start_date", ascending: false)
                .execute().value
            return activities
        } catch {
            errorMessage = "Failed to fetch activities: \(error.localizedDescription)"
            return []
        }
    }
}
