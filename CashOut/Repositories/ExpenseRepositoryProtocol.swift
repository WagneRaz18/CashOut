import Foundation

@MainActor
protocol ExpenseRepositoryProtocol {
    func fetchExpenses(for period: DateInterval) async throws -> [ExpenseData]
    func saveExpense(_ data: ExpenseData) async throws
    func deleteExpense(id: UUID) async throws

    // MARK: - FRC Observation

    var onExpensesChanged: (@MainActor ([ExpenseData]) -> Void)? { get set }
    func startObservingExpenses()
    func stopObservingExpenses()
    /// Rebuild the feed FRC with a fresh predicate — called after household-code changes.
    func reloadObservation()
}

// MARK: - Default no-op implementations (prevent breaking existing conformers)

extension ExpenseRepositoryProtocol {
    var onExpensesChanged: (@MainActor ([ExpenseData]) -> Void)? {
        get { nil }
        set { }
    }
    func startObservingExpenses() { }
    func stopObservingExpenses() { }
    func reloadObservation() { }
}
