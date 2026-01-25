//
//  User.swift
//  Dromos
//
//  Created by Emmanuel Breard on 25/01/2026.
//

import Foundation

/// User profile model matching the public.users table in Supabase.
struct User: Codable, Identifiable, Equatable {
    let id: UUID
    let email: String
    var name: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Payload for updating user profile.
/// Only includes fields that can be updated by the user.
struct UserUpdate: Codable {
    var name: String?
}
