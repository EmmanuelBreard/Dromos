//
//  Configuration.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import Foundation

/// Centralized app configuration.
/// Reads values from Secrets.swift (gitignored).
enum Configuration {

    // MARK: - Supabase

    /// Supabase project URL
    static var supabaseURL: String {
        Secrets.supabaseURL
    }

    /// Supabase anonymous API key (safe for client-side use)
    static var supabaseAnonKey: String {
        Secrets.supabaseAnonKey
    }

    // MARK: - Strava

    /// Strava application client ID (public, safe for client-side use)
    static var stravaClientId: String {
        Secrets.stravaClientId
    }
}
