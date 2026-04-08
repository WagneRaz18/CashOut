import Foundation

@MainActor
protocol CategoryRepositoryProtocol {
    func fetchCategories() async throws -> [CategoryData]
    func saveCategory(_ data: CategoryData) async throws
    /// Share a newly-created category to the household. Fire-and-forget from the caller.
    func shareNewCategoryToHousehold(id: UUID) async
}

// MARK: - Default no-op implementations (prevent breaking existing conformers)

extension CategoryRepositoryProtocol {
    func shareNewCategoryToHousehold(id: UUID) async { }
}
