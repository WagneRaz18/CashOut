import Foundation
@testable import CashOut

@MainActor
final class MockCategoryRepository: CategoryRepositoryProtocol {

    // MARK: - Configurable Behavior

    var categoriesToReturn: [CategoryData] = []
    var shouldThrow: Bool = false
    var throwError: Error = NSError(domain: "MockCategoryRepository", code: -1)

    // MARK: - Call Tracking

    var fetchCategoriesCalled = false
    var saveCategoryCalled = false

    // MARK: - Protocol Methods

    func fetchCategories() async throws -> [CategoryData] {
        fetchCategoriesCalled = true
        if shouldThrow { throw throwError }
        return categoriesToReturn
    }

    func saveCategory(_ data: CategoryData) async throws {
        saveCategoryCalled = true
        if shouldThrow { throw throwError }
    }
}
