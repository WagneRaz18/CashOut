import XCTest
@testable import CashOut

final class CashOutTests: XCTestCase {
    @MainActor func testPersistenceControllerPreviewInitializes() throws {
        let controller = PersistenceController(inMemory: true)
        XCTAssertNotNil(controller.container.viewContext)
    }
}
