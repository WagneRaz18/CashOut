import XCTest
@testable import CashOut

final class CashOutTests: XCTestCase {
    func testPersistenceControllerPreviewInitializes() throws {
        let controller = PersistenceController(inMemory: true)
        XCTAssertNotNil(controller.container.viewContext)
    }
}
