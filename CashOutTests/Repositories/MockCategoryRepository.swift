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
    var deleteCategoryCalled = false
    var lastDeletedCategoryID: UUID?
    var reorderCategoriesCalled = false
    var lastReorderedIDs: [UUID]?

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

    func deleteCategory(id: UUID) async throws {
        deleteCategoryCalled = true
        lastDeletedCategoryID = id
        if shouldThrow { throw throwError }
        categoriesToReturn.removeAll { $0.id == id }
    }

    func reorderCategories(_ orderedIDs: [UUID]) async throws {
        reorderCategoriesCalled = true
        lastReorderedIDs = orderedIDs
        if shouldThrow { throw throwError }
    }
}
