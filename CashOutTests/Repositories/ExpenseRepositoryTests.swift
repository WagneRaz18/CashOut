import XCTest
@testable import CashOut

final class ExpenseRepositoryTests: XCTestCase {
    private var repository: ExpenseRepository!
    private var categoryRepository: CategoryRepository!

    @MainActor
    override func setUp() async throws {
        let controller = TestPersistenceHelper.makeInMemoryController()
        repository = ExpenseRepository(persistence: controller)
        categoryRepository = CategoryRepository(persistence: controller)
        try await categoryRepository.seedDefaultCategoriesIfNeeded()
    }

    @MainActor
    private func makeSampleExpense(
        amount: Int64 = 1250,
        daysAgo: Int = 0
    ) async throws -> ExpenseData {
        let categories = try await categoryRepository.fetchCategories()
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return ExpenseData(
            id: UUID(),
            amount: amount,
            note: "Test expense",
            categoryID: categories[0].id,
            createdByUserID: "test-user",
            createdAt: date,
            modifiedAt: date
        )
    }

    @MainActor
    func testSaveExpensePersistsData() async throws {
        let expense = try await makeSampleExpense()
        try await repository.saveExpense(expense)

        let period = DateInterval(
            start: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            end: Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        )
        let results = try await repository.fetchExpenses(for: period)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.amount, 1250)
        XCTAssertEqual(results.first?.note, "Test expense")
        XCTAssertEqual(results.first?.createdByUserID, "test-user")
    }

    @MainActor
    func testDeleteExpenseRemovesData() async throws {
        let expense = try await makeSampleExpense()
        try await repository.saveExpense(expense)
        try await repository.deleteExpense(id: expense.id)

        let period = DateInterval(
            start: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            end: Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        )
        let results = try await repository.fetchExpenses(for: period)
        XCTAssertTrue(results.isEmpty)
    }

    @MainActor
    func testFetchExpensesFiltersbyDateInterval() async throws {
        let recentExpense = try await makeSampleExpense(amount: 500, daysAgo: 0)
        let oldExpense = try await makeSampleExpense(amount: 1000, daysAgo: 30)

        try await repository.saveExpense(recentExpense)
        try await repository.saveExpense(oldExpense)

        let lastWeek = DateInterval(
            start: Calendar.current.date(byAdding: .day, value: -7, to: Date())!,
            end: Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        )
        let results = try await repository.fetchExpenses(for: lastWeek)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.amount, 500)
    }

    @MainActor
    func testFetchExpensesReturnsSortedByCreatedAtDescending() async throws {
        let older = try await makeSampleExpense(amount: 100, daysAgo: 2)
        let newer = try await makeSampleExpense(amount: 200, daysAgo: 0)

        try await repository.saveExpense(older)
        try await repository.saveExpense(newer)

        let period = DateInterval(
            start: Calendar.current.date(byAdding: .day, value: -7, to: Date())!,
            end: Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        )
        let results = try await repository.fetchExpenses(for: period)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].amount, 200, "Newer expense should come first")
        XCTAssertEqual(results[1].amount, 100, "Older expense should come second")
    }

    @MainActor
    func testDeleteNonExistentExpenseDoesNotThrow() async throws {
        try await repository.deleteExpense(id: UUID())
    }
}
