import UIKit

enum HapticEvent: Equatable {
    case numpadKey      // UIImpactFeedbackGenerator(.light)
    case categorySelect // UIImpactFeedbackGenerator(.light)
    case saveTap        // UINotificationFeedbackGenerator(.success)
    case deleteTap      // UINotificationFeedbackGenerator(.success) — reserved for Story 2.4
    case error          // UINotificationFeedbackGenerator(.error)
}

protocol HapticServiceProtocol {
    func trigger(_ event: HapticEvent)
}

final class HapticService: HapticServiceProtocol {
    func trigger(_ event: HapticEvent) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        switch event {
        case .numpadKey, .categorySelect:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .saveTap, .deleteTap:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
