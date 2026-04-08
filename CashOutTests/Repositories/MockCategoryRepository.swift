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
    var fetchCategoriesCallCount = 0
    var saveCategoryCalled = false
    var savedCategory: CategoryData?
    var shareNewCategoryCalled = false
    var lastSharedCategoryID: UUID?

    // MARK: - Protocol Methods

    func fetchCategories() async throws -> [CategoryData] {
        fetchCategoriesCalled = true
        fetchCategoriesCallCount += 1
        if shouldThrow { throw throwError }
        return categoriesToReturn
    }

    func saveCategory(_ data: CategoryData) async throws {
        saveCategoryCalled = true
        savedCategory = data
        if shouldThrow { throw throwError }
    }

    func shareNewCategoryToHousehold(id: UUID) async {
        shareNewCategoryCalled = true
        lastSharedCategoryID = id
    }
}
