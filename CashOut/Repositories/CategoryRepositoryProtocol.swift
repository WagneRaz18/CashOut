import Foundation

@MainActor
protocol CategoryRepositoryProtocol {
    func fetchCategories() async throws -> [CategoryData]
    func saveCategory(_ data: CategoryData) async throws
}
