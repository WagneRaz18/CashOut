import Foundation
@testable import CashOut

final class MockHapticService: HapticServiceProtocol {
    var triggeredEvents: [HapticEvent] = []

    var lastEvent: HapticEvent? { triggeredEvents.last }

    func trigger(_ event: HapticEvent) {
        triggeredEvents.append(event)
    }

    func reset() {
        triggeredEvents.removeAll()
    }
}
