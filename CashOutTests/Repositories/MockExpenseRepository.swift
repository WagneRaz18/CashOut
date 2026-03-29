import Foundation
@testable import CashOut

@MainActor
final class MockExpenseRepository: ExpenseRepositoryProtocol {

    // MARK: - Configurable Behavior

    var shouldThrow: Bool = false
    var throwError: Error = NSError(domain: "MockExpenseRepository", code: -1)

    // MARK: - Call Tracking

    var saveExpenseCalled = false
    var lastSavedExpense: ExpenseData?
    var fetchExpensesCalled = false
    var deleteExpenseCalled = false

    // MARK: - Protocol Methods

    func fetchExpenses(for period: DateInterval) async throws -> [ExpenseData] {
        fetchExpensesCalled = true
        if shouldThrow { throw throwError }
        return []
    }

    func saveExpense(_ data: ExpenseData) async throws {
        saveExpenseCalled = true
        if shouldThrow { throw throwError }
        lastSavedExpense = data
    }

    func deleteExpense(id: UUID) async throws {
        deleteExpenseCalled = true
        if shouldThrow { throw throwError }
    }
}
