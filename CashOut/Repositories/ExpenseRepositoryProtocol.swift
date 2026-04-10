import Foundation

@MainActor
protocol ExpenseRepositoryProtocol {
    func fetchExpenses(for period: DateInterval) async throws -> [ExpenseData]
    func saveExpense(_ data: ExpenseData) async throws
    func deleteExpense(id: UUID) async throws
    /// Share a newly-created expense to the household. Fire-and-forget from the caller.
    func shareNewExpenseToHousehold(id: UUID) async

    /// Fire-and-forget wrapper owned by the repository. Unblocks the caller's main-actor
    /// continuation before the CloudKit share call grabs the actor for its synchronous prep.
    func enqueueShareForNewExpense(id: UUID)

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
    func enqueueShareForNewExpense(id: UUID) { }
}
