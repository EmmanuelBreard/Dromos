//
//  WebAuthPresentationContext.swift
//  Dromos
//
//  Created by Emmanuel Breard on 22/02/2026.
//

import AuthenticationServices
import UIKit

/// Provides the key UIWindow for presenting ASWebAuthenticationSession.
/// Required by ASWebAuthenticationPresentationContextProviding.
/// Walks connected UIScenes to find the first active foreground window.
final class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Walk connected scenes to find the key window of the active foreground scene.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let window = scene?.keyWindow else {
            assertionFailure("No foreground window scene found for ASWebAuthenticationSession")
            return UIWindow()
        }
        return window
    }
}
