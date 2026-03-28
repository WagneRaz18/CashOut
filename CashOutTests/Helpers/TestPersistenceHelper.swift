@preconcurrency import CoreData
@testable import CashOut

enum TestPersistenceHelper {
    @MainActor
    static func makeInMemoryController() -> PersistenceController {
        PersistenceController(inMemory: true)
    }
}
