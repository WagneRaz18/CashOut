import Foundation

@MainActor
protocol ExpenseRepositoryProtocol {
    func fetchExpenses(for period: DateInterval) async throws -> [ExpenseData]
    func saveExpense(_ data: ExpenseData) async throws
    func deleteExpense(id: UUID) async throws
}
