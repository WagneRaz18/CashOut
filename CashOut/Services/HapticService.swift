import UIKit

enum HapticEvent: Equatable {
    case numpadKey      // UIImpactFeedbackGenerator(.light)
    case categorySelect // UIImpactFeedbackGenerator(.light)
    case saveTap        // UINotificationFeedbackGenerator(.success)
    case deleteTap      // UINotificationFeedbackGenerator(.success)
    case error          // UINotificationFeedbackGenerator(.error)
}

@MainActor
protocol HapticServiceProtocol {
    func trigger(_ event: HapticEvent)
}

@MainActor
final class HapticService: HapticServiceProtocol {
    static let shared = HapticService()

    private var impactGenerator: UIImpactFeedbackGenerator
    private var notificationGenerator: UINotificationFeedbackGenerator

    init() {
        impactGenerator = UIImpactFeedbackGenerator(style: .light)
        notificationGenerator = UINotificationFeedbackGenerator()
        impactGenerator.prepare()
        notificationGenerator.prepare()
    }

    func configure(view: UIView) {
        impactGenerator = UIImpactFeedbackGenerator(style: .light, view: view)
        notificationGenerator = UINotificationFeedbackGenerator(view: view)
        impactGenerator.prepare()
        notificationGenerator.prepare()
    }

    func trigger(_ event: HapticEvent) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        switch event {
        case .numpadKey, .categorySelect:
            impactGenerator.impactOccurred()
            impactGenerator.prepare()
        case .saveTap, .deleteTap:
            notificationGenerator.notificationOccurred(.success)
            notificationGenerator.prepare()
        case .error:
            notificationGenerator.notificationOccurred(.error)
            notificationGenerator.prepare()
        }
    }
}
