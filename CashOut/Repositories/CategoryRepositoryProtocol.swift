import Foundation

@MainActor
protocol CategoryRepositoryProtocol {
    func fetchCategories() async throws -> [CategoryData]
    func saveCategory(_ data: CategoryData) async throws
    /// Share a newly-created category to the household. Fire-and-forget from the caller.
    func shareNewCategoryToHousehold(id: UUID) async
    /// Fire-and-forget wrapper owned by the repository. Unblocks the caller's main-actor
    /// continuation before the CloudKit share call grabs the actor for its synchronous prep.
    func enqueueShareForNewCategory(id: UUID)
    /// Delete a category by ID from both private and shared stores.
    /// Throws ``CategoryRepositoryError/categoryInUse`` if expenses reference this category.
    func deleteCategory(id: UUID) async throws
    /// Persist display order by writing `sortOrder` to each category in the given ID order.
    func reorderCategories(_ orderedIDs: [UUID]) async throws
}

// MARK: - Default no-op implementations (prevent breaking existing conformers)

extension CategoryRepositoryProtocol {
    func shareNewCategoryToHousehold(id: UUID) async { }
    func enqueueShareForNewCategory(id: UUID) { }
}

// MARK: - Repository Errors

enum CategoryRepositoryError: LocalizedError {
    case categoryInUse(expenseCount: Int)

    var errorDescription: String? {
        switch self {
        case .categoryInUse(let count):
            return "This category is used by \(count) expense\(count == 1 ? "" : "s"). Reassign them first."
        }
    }
}
