import Foundation

@MainActor
protocol CategoryRepositoryProtocol {
    func fetchCategories() async throws -> [CategoryData]
    func saveCategory(_ data: CategoryData) async throws
    /// Delete a category by ID. Soft-deletes (tombstones) so the partner sees the removal.
    /// Throws ``CategoryRepositoryError/categoryInUse`` if expenses reference this category.
    func deleteCategory(id: UUID) async throws
    /// Persist display order by writing `sortOrder` to each category in the given ID order.
    func reorderCategories(_ orderedIDs: [UUID]) async throws
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
