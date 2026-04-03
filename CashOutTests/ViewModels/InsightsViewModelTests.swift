import XCTest
@testable import CashOut

@MainActor
final class InsightsViewModelTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeSUT() -> (
        viewModel: InsightsViewModel,
        expenseRepo: MockExpenseRepository,
        categoryRepo: MockCategoryRepository
    ) {
        let expenseRepo = MockExpenseRepository()
        let categoryRepo = MockCategoryRepository()

        let viewModel = InsightsViewModel(
            repository: expenseRepo,
            categoryRepository: categoryRepo
        )

        return (viewModel, expenseRepo, categoryRepo)
    }

    private func makeExpense(
        id: UUID = UUID(),
        amount: Int64 = 1250,
        categoryID: UUID = UUID(),
        createdAt: Date = Date()
    ) -> ExpenseData {
        ExpenseData(
            id: id,
            amount: amount,
            note: nil,
            categoryID: categoryID,
            createdByUserID: "test-user",
            createdAt: createdAt,
            modifiedAt: createdAt
        )
    }

    // MARK: - Default State Tests (AC #1)

    func testDefaultSelectedPeriodIsWeekly() {
        let (viewModel, _, _) = makeSUT()

        XCTAssertEqual(
            viewModel.selectedPeriod, .weekly,
            "Default selectedPeriod should be .weekly"
        )
    }

    // MARK: - loadData Tests (AC #3, #5)

    func testLoadDataCallsFetchExpensesWithCorrectDateIntervals() async {
        let (viewModel, expenseRepo, _) = makeSUT()

        await viewModel.loadData()

        XCTAssertTrue(
            expenseRepo.fetchExpensesCalled,
            "loadData should call fetchExpenses"
        )
        XCTAssertEqual(
            expenseRepo.fetchPeriods.count, 2,
            "loadData should fetch current period + previous period"
        )

        // Verify current period is this week
        let thisWeek = Calendar.current.dateInterval(of: .weekOfYear, for: Date())!
        XCTAssertEqual(
            expenseRepo.fetchPeriods[0].start, thisWeek.start,
            "First fetch should be for current week start"
        )
        XCTAssertEqual(
            expenseRepo.fetchPeriods[0].end, thisWeek.end,
            "First fetch should be for current week end"
        )
    }

    func testLoadDataComputesTotalAmountAsSumOfExpenses() async {
        let (viewModel, expenseRepo, _) = makeSUT()
        let catID = UUID()
        expenseRepo.stubbedFetchResult = [
            makeExpense(amount: 1000, categoryID: catID),
            makeExpense(amount: 2500, categoryID: catID),
            makeExpense(amount: 500, categoryID: catID)
        ]

        await viewModel.loadData()

        XCTAssertEqual(
            viewModel.totalAmount, 4000,
            "totalAmount should be sum of all expense amounts (1000 + 2500 + 500)"
        )
    }

    func testLoadDataAggregatesCategoryTotalsGroupedByCategoryIDSortedDescending() async {
        let (viewModel, expenseRepo, _) = makeSUT()
        let foodID = UUID()
        let transportID = UUID()
        expenseRepo.stubbedFetchResult = [
            makeExpense(amount: 1000, categoryID: foodID),
            makeExpense(amount: 3000, categoryID: transportID),
            makeExpense(amount: 500, categoryID: foodID)
        ]

        await viewModel.loadData()

        XCTAssertEqual(
            viewModel.categoryTotals.count, 2,
            "Should have 2 category totals"
        )
        XCTAssertEqual(
            viewModel.categoryTotals[0].categoryID, transportID,
            "First category should be transport (highest total: 3000)"
        )
        XCTAssertEqual(
            viewModel.categoryTotals[0].total, 3000,
            "Transport total should be 3000"
        )
        XCTAssertEqual(
            viewModel.categoryTotals[1].categoryID, foodID,
            "Second category should be food (total: 1500)"
        )
        XCTAssertEqual(
            viewModel.categoryTotals[1].total, 1500,
            "Food total should be 1500 (1000 + 500)"
        )
    }

    func testLoadDataSetsPreviousPeriodTotalToNilWhenPreviousPeriodEmpty() async {
        let (viewModel, expenseRepo, _) = makeSUT()
        // stubbedFetchResult returns same array for both current and previous fetch
        // We need an empty previous period — since both calls get same stub,
        // we use empty stub (both return []) and verify nil
        expenseRepo.stubbedFetchResult = []

        await viewModel.loadData()

        XCTAssertNil(
            viewModel.previousPeriodTotal,
            "previousPeriodTotal should be nil when previous period returns empty"
        )
    }

    func testLoadDataSetsPreviousPeriodTotalToSumWhenPreviousPeriodHasData() async {
        let (viewModel, expenseRepo, _) = makeSUT()
        // Both current and previous fetch return the same stubbed data
        expenseRepo.stubbedFetchResult = [
            makeExpense(amount: 1000),
            makeExpense(amount: 2000)
        ]

        await viewModel.loadData()

        // Previous period uses same stub, so sum = 3000
        XCTAssertEqual(
            viewModel.previousPeriodTotal, 3000,
            "previousPeriodTotal should be sum when previous period has data"
        )
    }

    // MARK: - Comparison Text Tests (AC #6)

    func testComparisonTextShowsMoreWhenCurrentExceedsPrevious() async {
        let (viewModel, expenseRepo, _) = makeSUT()
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 5000)]

        await viewModel.loadData()

        // Both periods return same stub so current == previous → "Same as"
        // To test "more", we need to manipulate state directly
        viewModel.previousPeriodTotal = 2000
        // totalAmount is 5000 from loadData, difference = 3000

        let comparison = viewModel.comparisonText
        XCTAssertNotNil(comparison)
        XCTAssertTrue(
            comparison!.contains("more than"),
            "Should contain 'more than' when current > previous. Got: \(comparison!)"
        )
        XCTAssertTrue(
            comparison!.contains("last week"),
            "Should reference 'last week' for weekly period. Got: \(comparison!)"
        )
    }

    func testComparisonTextShowsLessWhenCurrentBelowPrevious() async {
        let (viewModel, expenseRepo, _) = makeSUT()
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 1000)]

        await viewModel.loadData()

        viewModel.previousPeriodTotal = 5000
        // totalAmount is 1000, difference = -4000

        let comparison = viewModel.comparisonText
        XCTAssertNotNil(comparison)
        XCTAssertTrue(
            comparison!.contains("less than"),
            "Should contain 'less than' when current < previous. Got: \(comparison!)"
        )
    }

    func testComparisonTextShowsSameWhenEqual() async {
        let (viewModel, expenseRepo, _) = makeSUT()
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 3000)]

        await viewModel.loadData()

        // Both periods return same data → totalAmount == previousPeriodTotal == 3000
        XCTAssertEqual(
            viewModel.comparisonText, "Same as last week",
            "Should show 'Same as last week' when current equals previous"
        )
    }

    func testComparisonTextReturnsNilWhenNoPreviousData() {
        let (viewModel, _, _) = makeSUT()

        XCTAssertNil(
            viewModel.comparisonText,
            "comparisonText should be nil when previousPeriodTotal is nil"
        )
    }

    // MARK: - Guard Tests (AC #8)

    func testLoadDataGuardsAgainstRedundantReload() async {
        let (viewModel, expenseRepo, _) = makeSUT()

        await viewModel.loadData()
        let firstCallCount = expenseRepo.fetchPeriods.count

        await viewModel.loadData()
        let secondCallCount = expenseRepo.fetchPeriods.count

        XCTAssertEqual(
            firstCallCount, secondCallCount,
            "Second loadData with same period should be guarded (no additional fetches)"
        )
    }

    func testLoadDataRefetchesAfterPeriodChange() async {
        let (viewModel, expenseRepo, _) = makeSUT()

        await viewModel.loadData()
        let firstCallCount = expenseRepo.fetchPeriods.count

        viewModel.selectedPeriod = .daily
        await viewModel.loadData()

        XCTAssertGreaterThan(
            expenseRepo.fetchPeriods.count, firstCallCount,
            "loadData should re-fetch after period change"
        )
    }

    func testInvalidateAndReloadForcesRefetchForSamePeriod() async {
        let (viewModel, expenseRepo, _) = makeSUT()

        await viewModel.loadData()
        let firstCallCount = expenseRepo.fetchPeriods.count

        await viewModel.invalidateAndReload()

        XCTAssertGreaterThan(
            expenseRepo.fetchPeriods.count, firstCallCount,
            "invalidateAndReload should force re-fetch even for same period"
        )
    }

    // MARK: - isEmpty Tests (AC #7)

    func testIsEmptyReturnsTrueWhenNoExpenses() {
        let (viewModel, _, _) = makeSUT()

        XCTAssertTrue(
            viewModel.isEmpty,
            "isEmpty should be true when totalAmount is 0 and categoryTotals is empty"
        )
    }

    func testIsEmptyReturnsFalseWhenPopulated() async {
        let (viewModel, expenseRepo, _) = makeSUT()
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 1000)]

        await viewModel.loadData()

        XCTAssertFalse(
            viewModel.isEmpty,
            "isEmpty should be false when expenses exist"
        )
    }

    // MARK: - Error Handling Tests

    func testLoadDataSetsErrorMessageOnFetchFailure() async {
        let (viewModel, expenseRepo, _) = makeSUT()
        expenseRepo.shouldThrow = true

        await viewModel.loadData()

        XCTAssertNotNil(
            viewModel.errorMessage,
            "errorMessage should be set when fetchExpenses throws"
        )
    }

    // MARK: - Empty State Text Tests

    func testEmptyStateTextMatchesPeriod() {
        let (viewModel, _, _) = makeSUT()

        viewModel.selectedPeriod = .daily
        XCTAssertEqual(viewModel.emptyStateText, "No entries this day")

        viewModel.selectedPeriod = .weekly
        XCTAssertEqual(viewModel.emptyStateText, "No entries this week")

        viewModel.selectedPeriod = .monthly
        XCTAssertEqual(viewModel.emptyStateText, "No entries this month")
    }

    // MARK: - Date Interval Tests (AC #3)

    func testLoadDataFetchesCorrectIntervalsForDailyPeriod() async {
        let (viewModel, expenseRepo, _) = makeSUT()
        viewModel.selectedPeriod = .daily

        await viewModel.loadData()

        let today = Calendar.current.dateInterval(of: .day, for: Date())!
        XCTAssertEqual(
            expenseRepo.fetchPeriods[0].start, today.start,
            "Daily period should fetch today's interval"
        )
    }

    func testLoadDataFetchesCorrectIntervalsForMonthlyPeriod() async {
        let (viewModel, expenseRepo, _) = makeSUT()
        viewModel.selectedPeriod = .monthly

        await viewModel.loadData()

        let thisMonth = Calendar.current.dateInterval(of: .month, for: Date())!
        XCTAssertEqual(
            expenseRepo.fetchPeriods[0].start, thisMonth.start,
            "Monthly period should fetch this month's interval"
        )
    }
}
