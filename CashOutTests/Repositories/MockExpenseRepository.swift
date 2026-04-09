import Foundation
@testable import CashOut

@MainActor
final class MockExpenseRepository: ExpenseRepositoryProtocol {

    // MARK: - Configurable Behavior

    var shouldThrow: Bool = false
    var throwError: Error = NSError(domain: "MockExpenseRepository", code: -1)

    // MARK: - Fetch Stubbing

    var stubbedFetchResult: [ExpenseData] = []
    var fetchPeriods: [DateInterval] = []

    // MARK: - Call Tracking

    var saveExpenseCalled = false
    var lastSavedExpense: ExpenseData?
    var fetchExpensesCalled = false
    var deleteExpenseCalled = false
    var lastDeletedExpenseID: UUID?
    var shareNewExpenseCalled = false
    var lastSharedExpenseID: UUID?

    // MARK: - FRC Observation (Story 2-1)

    var onExpensesChanged: (@MainActor ([ExpenseData]) -> Void)?
    var stubbedExpenses: [ExpenseData] = []
    var startObservingCalled = false
    var stopObservingCalled = false

    func startObservingExpenses() {
        startObservingCalled = true
        onExpensesChanged?(stubbedExpenses)
    }

    func stopObservingExpenses() {
        stopObservingCalled = true
        onExpensesChanged = nil
    }

    // MARK: - Protocol Methods

    func fetchExpenses(for period: DateInterval) async throws -> [ExpenseData] {
        fetchExpensesCalled = true
        fetchPeriods.append(period)
        if shouldThrow { throw throwError }
        return stubbedFetchResult
    }

    func saveExpense(_ data: ExpenseData) async throws {
        saveExpenseCalled = true
        if shouldThrow { throw throwError }
        lastSavedExpense = data
    }

    func deleteExpense(id: UUID) async throws {
        deleteExpenseCalled = true
        lastDeletedExpenseID = id
        if shouldThrow { throw throwError }
    }

    func shareNewExpenseToHousehold(id: UUID) async {
        shareNewExpenseCalled = true
        lastSharedExpenseID = id
    }
}
