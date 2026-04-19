import Foundation
@testable import CashOut

@MainActor
final class MockHouseholdService: HouseholdServiceProtocol {
    var householdCode: String?
    var displayName: String = ""

    var isPaired: Bool {
        householdCode != nil && !(householdCode?.isEmpty ?? true)
    }

    // Call tracking
    var generateCodeCallCount = 0
    var pairCallCount = 0
    var lastPairedCode: String?
    var unpairCallCount = 0

    // Configurable behavior
    var generateCodeResult: String = "ABCD1234"
    var pairResult: Bool = true

    @discardableResult
    func generateCode() -> String {
        generateCodeCallCount += 1
        householdCode = generateCodeResult
        return generateCodeResult
    }

    @discardableResult
    func pair(code: String) -> Bool {
        pairCallCount += 1
        lastPairedCode = code
        if pairResult {
            householdCode = code
        }
        return pairResult
    }

    func unpair() {
        unpairCallCount += 1
        householdCode = nil
    }
}
