import SwiftUI

/// Direction of a horizontal slide transition. `next` is forward navigation
/// (incoming content from the trailing edge); `previous` is backward.
enum SlideDirection {
    case next
    case previous
}

extension AnyTransition {
    /// Pure horizontal push-slide — no opacity component. Used by Today's
    /// hero-card swap and Calendar's week swap so both tabs share the
    /// same direction-aware transition feel.
    static func horizontalSlide(direction: SlideDirection) -> AnyTransition {
        switch direction {
        case .next:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        case .previous:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        }
    }
}
