//
//  SupabaseClient.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import Foundation
import Supabase
import PostgREST

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
                db: .init(
                    encoder: {
                        // Note: PostgrestClient.Configuration.jsonEncoder is a static singleton.
                        // JSONEncoder is a reference type, so this mutates the shared instance.
                        // This is acceptable because:
                        // 1. SupabaseClient initialization happens once at app startup
                        // 2. The PostgREST client is the only consumer of this encoder
                        // 3. JSONEncoder.supabase() is package-scoped and inaccessible from app target
                        // If the SDK ever references its own default encoder internally after initialization,
                        // it would get snake_case encoding, but this is the most practical approach given SDK constraints.
                        let encoder = PostgrestClient.Configuration.jsonEncoder
                        encoder.keyEncodingStrategy = .convertToSnakeCase
                        return encoder
                    }(),
                    decoder: {
                        // Same note as encoder above — mutating shared singleton decoder
                        let decoder = PostgrestClient.Configuration.jsonDecoder
                        decoder.keyDecodingStrategy = .convertFromSnakeCase
                        return decoder
                    }()
                ),
                auth: SupabaseClientOptions.AuthOptions(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }()
}
