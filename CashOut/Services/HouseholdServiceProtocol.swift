import Foundation

@MainActor
protocol HouseholdServiceProtocol: AnyObject {
    var householdCode: String? { get }
    var displayName: String { get set }
    var isPaired: Bool { get }

    @discardableResult
    func generateCode() -> String

    @discardableResult
    func pair(code: String) -> Bool

    func unpair()
}
