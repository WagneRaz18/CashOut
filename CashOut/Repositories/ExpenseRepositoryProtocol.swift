import Foundation

@MainActor
protocol ExpenseRepositoryProtocol {
    func fetchExpenses(for period: DateInterval) async throws -> [ExpenseData]
    func saveExpense(_ data: ExpenseData) async throws
    func deleteExpense(id: UUID) async throws
    /// Share a newly-created expense to the household. Fire-and-forget from the caller.
    func shareNewExpenseToHousehold(id: UUID) async

    // MARK: - FRC Observation (Story 2-1)

    var onExpensesChanged: (@MainActor ([ExpenseData]) -> Void)? { get set }
    func startObservingExpenses()
    func stopObservingExpenses()
}

// MARK: - Default no-op implementations (prevent breaking existing conformers)

extension ExpenseRepositoryProtocol {
    var onExpensesChanged: (@MainActor ([ExpenseData]) -> Void)? {
        get { nil }
        set { }
    }
    func startObservingExpenses() { }
    func stopObservingExpenses() { }
    func shareNewExpenseToHousehold(id: UUID) async { }
}
