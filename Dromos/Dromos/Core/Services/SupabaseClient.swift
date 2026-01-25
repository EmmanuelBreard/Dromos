//
//  SupabaseClient.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import Foundation
import Supabase

/// Singleton providing access to the Supabase client.
/// Configured using values from Secrets.swift (gitignored).
///
/// Usage:
/// ```swift
/// let client = SupabaseClientProvider.client
/// ```
enum SupabaseClientProvider {

    /// Shared Supabase client instance.
    /// Lazily initialized with configuration from Secrets.swift.
    static let client: SupabaseClient = {
        guard let url = URL(string: Configuration.supabaseURL) else {
            fatalError("Invalid Supabase URL in configuration: \(Configuration.supabaseURL)")
        }
        let key = Configuration.supabaseAnonKey

        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }()
}
