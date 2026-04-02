import Foundation

@MainActor
protocol ExpenseRepositoryProtocol {
    func fetchExpenses(for period: DateInterval) async throws -> [ExpenseData]
    func saveExpense(_ data: ExpenseData) async throws
    func deleteExpense(id: UUID) async throws

    // MARK: - FRC Observation (Story 2-1)

    var onExpensesChanged: (@MainActor ([ExpenseData]) -> Void)? { get set }
    func startObservingExpenses()
}

// MARK: - Default no-op implementations (prevent breaking existing conformers)

extension ExpenseRepositoryProtocol {
    var onExpensesChanged: (@MainActor ([ExpenseData]) -> Void)? {
        get { nil }
        set { }
    }
    func startObservingExpenses() { }
}
