import XCTest
@testable import CashOut

@MainActor
final class InsightsViewModelChartTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeSUT(
        currentUserID: String? = "test-user",
        syncMonitorService: MockSyncMonitorService? = nil
    ) -> (
        viewModel: InsightsViewModel,
        expenseRepo: MockExpenseRepository,
        categoryRepo: MockCategoryRepository,
        syncMonitorService: MockSyncMonitorService
    ) {
        let expenseRepo = MockExpenseRepository()
        let categoryRepo = MockCategoryRepository()
        let authService = MockAuthenticationService()
        authService.currentUserID = currentUserID
        let syncMonitor = syncMonitorService ?? MockSyncMonitorService()
        let hapticService = MockHapticService()

        let viewModel = InsightsViewModel(
            repository: expenseRepo,
            categoryRepository: categoryRepo,
            authService: authService,
            syncMonitorService: syncMonitor,
            hapticService: hapticService
        )

        return (viewModel, expenseRepo, categoryRepo, syncMonitor)
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

    // MARK: - ChartSlice Tests (Story 3-2, AC #1)

    func testChartSlicesPopulatedWithCorrectCategoryNamesColorsAndTotals() async {
        let (viewModel, expenseRepo, categoryRepo, _) = makeSUT()
        let foodID = UUID()
        let transportID = UUID()
        expenseRepo.stubbedFetchResult = [
            makeExpense(amount: 2000, categoryID: foodID),
            makeExpense(amount: 3000, categoryID: transportID)
        ]
        categoryRepo.categoriesToReturn = [
            CategoryData(id: foodID, name: "Food & Drink", iconName: "fork.knife", colorName: "Sage", isDefault: true, sortOrder: 0),
            CategoryData(id: transportID, name: "Transport", iconName: "car.fill", colorName: "Slate", isDefault: true, sortOrder: 1)
        ]

        await viewModel.loadData()

        XCTAssertEqual(viewModel.chartSlices.count, 2, "Should have 2 chart slices")
        XCTAssertEqual(viewModel.chartSlices[0].categoryName, "Transport", "First slice should be Transport (highest total)")
        XCTAssertEqual(viewModel.chartSlices[0].colorName, "Slate")
        XCTAssertEqual(viewModel.chartSlices[0].total, 3000)
        XCTAssertEqual(viewModel.chartSlices[1].categoryName, "Food & Drink", "Second slice should be Food & Drink")
        XCTAssertEqual(viewModel.chartSlices[1].colorName, "Sage")
        XCTAssertEqual(viewModel.chartSlices[1].total, 2000)
    }

    func testChartSlicesSortedDescendingByTotal() async {
        let (viewModel, expenseRepo, categoryRepo, _) = makeSUT()
        let smallID = UUID()
        let largeID = UUID()
        let medID = UUID()
        expenseRepo.stubbedFetchResult = [
            makeExpense(amount: 100, categoryID: smallID),
            makeExpense(amount: 5000, categoryID: largeID),
            makeExpense(amount: 1000, categoryID: medID)
        ]
        categoryRepo.categoriesToReturn = [
            CategoryData(id: smallID, name: "Small", iconName: "circle", colorName: "CoolGray", isDefault: true, sortOrder: 0),
            CategoryData(id: largeID, name: "Large", iconName: "circle", colorName: "Sage", isDefault: true, sortOrder: 1),
            CategoryData(id: medID, name: "Medium", iconName: "circle", colorName: "Slate", isDefault: true, sortOrder: 2)
        ]

        await viewModel.loadData()

        XCTAssertEqual(viewModel.chartSlices.map(\.total), [5000, 1000, 100], "Slices should be sorted descending by total")
    }

    func testChartSlicesEmptyWhenNoExpenses() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        expenseRepo.stubbedFetchResult = []

        await viewModel.loadData()

        XCTAssertTrue(viewModel.chartSlices.isEmpty, "chartSlices should be empty when no expenses")
    }

    func testChartSlicesClearedOnError() async {
        let (viewModel, expenseRepo, categoryRepo, _) = makeSUT()
        let catID = UUID()
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 1000, categoryID: catID)]
        categoryRepo.categoriesToReturn = [
            CategoryData(id: catID, name: "Food", iconName: "fork.knife", colorName: "Sage", isDefault: true, sortOrder: 0)
        ]
        await viewModel.loadData()
        XCTAssertFalse(viewModel.chartSlices.isEmpty, "Precondition: slices should be populated")

        // Force reload with error
        expenseRepo.shouldThrow = true
        await viewModel.invalidateAndReload()

        XCTAssertTrue(viewModel.chartSlices.isEmpty, "chartSlices should be cleared on error")
        XCTAssertNil(viewModel.currentPeriodInterval, "currentPeriodInterval should be nil on error")
        XCTAssertTrue(viewModel.fetchedCategories.isEmpty, "fetchedCategories should be cleared on error")
    }

    // MARK: - Chart Accessibility Label Tests (Story 3-2, AC #5)

    func testChartAccessibilityLabelContainsTotalAndLargestCategory() async {
        let (viewModel, expenseRepo, categoryRepo, _) = makeSUT()
        let foodID = UUID()
        let transportID = UUID()
        expenseRepo.stubbedFetchResult = [
            makeExpense(amount: 12000, categoryID: foodID),
            makeExpense(amount: 3000, categoryID: transportID)
        ]
        categoryRepo.categoriesToReturn = [
            CategoryData(id: foodID, name: "Food & Drink", iconName: "fork.knife", colorName: "Sage", isDefault: true, sortOrder: 0),
            CategoryData(id: transportID, name: "Transport", iconName: "car.fill", colorName: "Slate", isDefault: true, sortOrder: 1)
        ]

        await viewModel.loadData()

        let label = viewModel.chartAccessibilityLabel
        XCTAssertTrue(label.contains("Food & Drink"), "Accessibility label should name the largest category")
        XCTAssertTrue(label.contains("total:"), "Accessibility label should contain total")
    }

    func testChartAccessibilityLabelReturnsEmptyStateTextWhenNoData() {
        let (viewModel, _, _, _) = makeSUT()

        XCTAssertEqual(
            viewModel.chartAccessibilityLabel,
            "No entries this week",
            "Should return empty state text when no chart slices"
        )
    }

    // MARK: - ChartSlice iconName Tests (Story 3-3, AC #3)

    func testChartSliceIncludesIconName() async {
        let (viewModel, expenseRepo, categoryRepo, _) = makeSUT()
        let foodID = UUID()
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 1000, categoryID: foodID)]
        categoryRepo.categoriesToReturn = [
            CategoryData(id: foodID, name: "Food & Drink", iconName: "fork.knife", colorName: "Sage", isDefault: true, sortOrder: 0)
        ]

        await viewModel.loadData()

        XCTAssertEqual(
            viewModel.chartSlices.first?.iconName, "fork.knife",
            "ChartSlice should include iconName from category data"
        )
    }

    // MARK: - Date Interval Tests (AC #3)

    func testLoadDataFetchesCorrectIntervalsForDailyPeriod() async throws {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        viewModel.selectedPeriod = .daily

        await viewModel.loadData()

        let gregorian = Calendar.gregorian
        let today = try XCTUnwrap(gregorian.dateInterval(of: .day, for: Date()), "Gregorian calendar must return today's interval")
        XCTAssertEqual(
            expenseRepo.fetchPeriods[0].start, today.start,
            "Daily period should fetch today's interval"
        )
    }

    func testLoadDataFetchesCorrectIntervalsForMonthlyPeriod() async throws {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        viewModel.selectedPeriod = .monthly

        await viewModel.loadData()

        let gregorian = Calendar.gregorian
        let thisMonth = try XCTUnwrap(gregorian.dateInterval(of: .month, for: Date()), "Gregorian calendar must return this month's interval")
        XCTAssertEqual(
            expenseRepo.fetchPeriods[0].start, thisMonth.start,
            "Monthly period should fetch this month's interval"
        )
    }

    // MARK: - Bar Entry Tests (Story 3-3, AC #1)

    func testBarEntriesPopulatedAfterLoadData() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 1000)]

        await viewModel.loadData()

        XCTAssertFalse(
            viewModel.barEntries.isEmpty,
            "barEntries should be populated after loadData with expenses"
        )
    }

    func testBarEntriesAllZeroTotalWhenNoExpenses() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        expenseRepo.stubbedFetchResult = []

        await viewModel.loadData()

        // Default period is .weekly → should have 7 entries, all zero
        XCTAssertEqual(
            viewModel.barEntries.count, 7,
            "Weekly period should have 7 bar entries even with no expenses"
        )
        XCTAssertTrue(
            viewModel.barEntries.allSatisfy { $0.total == 0 },
            "All bar entries should have zero total when no expenses"
        )
    }

    func testBarEntriesForWeeklyPeriodHasSevenEntries() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 500)]

        await viewModel.loadData()

        XCTAssertEqual(
            viewModel.barEntries.count, 7,
            "Weekly period should produce exactly 7 bar entries"
        )
    }

    func testBarEntriesForDailyPeriodHasOneEntry() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        viewModel.selectedPeriod = .daily
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 2500)]

        await viewModel.loadData()

        XCTAssertEqual(
            viewModel.barEntries.count, 1,
            "Daily period should produce exactly 1 bar entry"
        )
        XCTAssertEqual(
            viewModel.barEntries.first?.label, "Today",
            "Daily bar entry label should be 'Today'"
        )
        XCTAssertEqual(
            viewModel.barEntries.first?.total, 2500,
            "Daily bar entry total should match expense sum"
        )
    }

    func testBarEntriesForMonthlyPeriodHasCorrectWeekCount() async throws {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        viewModel.selectedPeriod = .monthly
        expenseRepo.stubbedFetchResult = []

        await viewModel.loadData()

        let gregorian = Calendar.gregorian
        let thisMonth = try XCTUnwrap(gregorian.dateInterval(of: .month, for: Date()), "Gregorian calendar must return this month's interval")
        let expectedWeeks = gregorian.range(of: .weekOfMonth, in: .month, for: thisMonth.start)?.count ?? 0
        XCTAssertEqual(
            viewModel.barEntries.count, expectedWeeks,
            "Monthly period should have one entry per week in current month"
        )
        XCTAssertEqual(
            viewModel.barEntries.first?.label, "W1",
            "First monthly entry should be labeled 'W1'"
        )
    }

    func testBarEntriesForWeeklyPeriodAreInChronologicalOrder() async throws {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 500)]

        await viewModel.loadData()

        let labels = viewModel.barEntries.map(\.label)
        let gregorian = Calendar.gregorian
        let weekInterval = try XCTUnwrap(gregorian.dateInterval(of: .weekOfYear, for: Date()), "Gregorian calendar must return this week's interval")
        var expectedLabels: [String] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var date = weekInterval.start
        while date < weekInterval.end {
            expectedLabels.append(formatter.string(from: date))
            date = gregorian.date(byAdding: .day, value: 1, to: date) ?? weekInterval.end
        }

        XCTAssertEqual(
            labels, expectedLabels,
            "Weekly bar entries should be in chronological order (first weekday to last)"
        )
    }

    func testBarEntriesClearedOnError() async {
        let (viewModel, expenseRepo, categoryRepo, _) = makeSUT()
        let catID = UUID()
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 1000, categoryID: catID)]
        categoryRepo.categoriesToReturn = [
            CategoryData(id: catID, name: "Food", iconName: "fork.knife", colorName: "Sage", isDefault: true, sortOrder: 0)
        ]
        await viewModel.loadData()
        XCTAssertFalse(viewModel.barEntries.isEmpty, "Precondition: barEntries should be populated")

        expenseRepo.shouldThrow = true
        await viewModel.invalidateAndReload()

        XCTAssertTrue(
            viewModel.barEntries.isEmpty,
            "barEntries should be cleared on error"
        )
    }

    // MARK: - Bar Chart Accessibility Label Tests

    func testBarChartAccessibilityLabelContainsEntryLabels() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        viewModel.selectedPeriod = .daily
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 3000)]

        await viewModel.loadData()

        let label = viewModel.barChartAccessibilityLabel
        XCTAssertTrue(
            label.contains("Today"),
            "Bar chart accessibility label should contain entry label. Got: \(label)"
        )
    }

    func testBarChartAccessibilityLabelReturnsNoDataWhenEmpty() {
        let (viewModel, _, _, _) = makeSUT()

        XCTAssertEqual(
            viewModel.barChartAccessibilityLabel,
            "No spending data",
            "Should return 'No spending data' when barEntries is empty"
        )
    }
}
