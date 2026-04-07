import XCTest
@testable import CashOut

@MainActor
final class InsightsViewModelTests: XCTestCase {

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

        let viewModel = InsightsViewModel(
            repository: expenseRepo,
            categoryRepository: categoryRepo,
            authService: authService,
            syncMonitorService: syncMonitor
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

    // MARK: - Default State Tests (AC #1)

    func testDefaultSelectedPeriodIsWeekly() {
        let (viewModel, _, _, _) = makeSUT()

        XCTAssertEqual(
            viewModel.selectedPeriod, .weekly,
            "Default selectedPeriod should be .weekly"
        )
    }

    // MARK: - loadData Tests (AC #3, #5)

    func testLoadDataCallsFetchExpensesWithCorrectDateIntervals() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()

        await viewModel.loadData()

        XCTAssertTrue(
            expenseRepo.fetchExpensesCalled,
            "loadData should call fetchExpenses"
        )
        XCTAssertEqual(
            expenseRepo.fetchPeriods.count, 2,
            "loadData should fetch current period + previous period"
        )

        // Capture now once to avoid midnight-straddling race
        let now = Date()

        // Verify current period is this week
        let thisWeek = Calendar.current.dateInterval(of: .weekOfYear, for: now)!
        XCTAssertEqual(
            expenseRepo.fetchPeriods[0].start, thisWeek.start,
            "First fetch should be for current week start"
        )
        XCTAssertEqual(
            expenseRepo.fetchPeriods[0].end, thisWeek.end,
            "First fetch should be for current week end"
        )

        // Verify previous period is last week
        let lastWeekDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: now)!
        let lastWeek = Calendar.current.dateInterval(of: .weekOfYear, for: lastWeekDate)!
        XCTAssertEqual(
            expenseRepo.fetchPeriods[1].start, lastWeek.start,
            "Second fetch should be for previous week start"
        )
        XCTAssertEqual(
            expenseRepo.fetchPeriods[1].end, lastWeek.end,
            "Second fetch should be for previous week end"
        )
    }

    func testLoadDataComputesTotalAmountAsSumOfExpenses() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
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
        let (viewModel, expenseRepo, _, _) = makeSUT()
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
        let (viewModel, expenseRepo, _, _) = makeSUT()
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
        let (viewModel, expenseRepo, _, _) = makeSUT()
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
        let (viewModel, expenseRepo, _, _) = makeSUT()
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
        let (viewModel, expenseRepo, _, _) = makeSUT()
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
        let (viewModel, expenseRepo, _, _) = makeSUT()
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 3000)]

        await viewModel.loadData()

        // Both periods return same data → totalAmount == previousPeriodTotal == 3000
        XCTAssertEqual(
            viewModel.comparisonText, "Same as last week",
            "Should show 'Same as last week' when current equals previous"
        )
    }

    func testComparisonTextReturnsNilWhenNoPreviousData() {
        let (viewModel, _, _, _) = makeSUT()

        XCTAssertNil(
            viewModel.comparisonText,
            "comparisonText should be nil when previousPeriodTotal is nil"
        )
    }

    // MARK: - Guard Tests (AC #8)

    func testLoadDataGuardsAgainstRedundantReload() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()

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
        let (viewModel, expenseRepo, _, _) = makeSUT()

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
        let (viewModel, expenseRepo, _, _) = makeSUT()

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
        let (viewModel, _, _, _) = makeSUT()

        XCTAssertTrue(
            viewModel.isEmpty,
            "isEmpty should be true when totalAmount is 0 and categoryTotals is empty"
        )
    }

    func testIsEmptyReturnsFalseWhenPopulated() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 1000)]

        await viewModel.loadData()

        XCTAssertFalse(
            viewModel.isEmpty,
            "isEmpty should be false when expenses exist"
        )
    }

    // MARK: - Error Handling Tests

    func testLoadDataSetsErrorMessageOnFetchFailure() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        expenseRepo.shouldThrow = true

        await viewModel.loadData()

        XCTAssertNotNil(
            viewModel.errorMessage,
            "errorMessage should be set when fetchExpenses throws"
        )
    }

    // MARK: - Empty State Text Tests

    func testEmptyStateTextMatchesPeriod() {
        let (viewModel, _, _, _) = makeSUT()

        viewModel.selectedPeriod = .daily
        XCTAssertEqual(viewModel.emptyStateText, "No entries this day")

        viewModel.selectedPeriod = .weekly
        XCTAssertEqual(viewModel.emptyStateText, "No entries this week")

        viewModel.selectedPeriod = .monthly
        XCTAssertEqual(viewModel.emptyStateText, "No entries this month")
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

    // MARK: - selectCategory Tests (Story 3-2, AC #2)

    func testSelectCategorySetsSelectedDestination() async {
        let (viewModel, _, _, _) = makeSUT()
        let id = UUID()

        // Load data first so currentPeriodInterval is set
        await viewModel.loadData()
        viewModel.selectCategory(id)

        XCTAssertNotNil(viewModel.selectedDestination, "selectCategory should set selectedDestination when interval is available")
        XCTAssertEqual(viewModel.selectedDestination?.categoryID, id, "selectedDestination should contain the selected categoryID")
    }

    func testSelectCategoryNilClearsSelection() async {
        let (viewModel, _, _, _) = makeSUT()

        await viewModel.loadData()
        viewModel.selectCategory(UUID())
        viewModel.selectCategory(nil)

        XCTAssertNil(viewModel.selectedDestination, "selectCategory(nil) should clear selectedDestination")
    }

    func testSelectCategoryWithoutIntervalDoesNotSetDestination() {
        let (viewModel, _, _, _) = makeSUT()
        let id = UUID()

        // Without loading data, currentPeriodInterval is nil
        viewModel.selectCategory(id)

        XCTAssertNil(viewModel.selectedDestination, "selectCategory should not set destination when interval is nil")
    }

    // MARK: - currentPeriodInterval Tests (Story 3-2, AC #2)

    func testCurrentPeriodIntervalSetAfterSuccessfulLoad() async {
        let (viewModel, _, _, _) = makeSUT()

        await viewModel.loadData()

        XCTAssertNotNil(viewModel.currentPeriodInterval, "currentPeriodInterval should be set after loadData")
        let gregorian = Calendar(identifier: .gregorian)
        let thisWeek = gregorian.dateInterval(of: .weekOfYear, for: Date())
        XCTAssertEqual(viewModel.currentPeriodInterval?.start, thisWeek?.start, "Should match current week start")
    }

    // MARK: - Date Interval Tests (AC #3)

    func testLoadDataFetchesCorrectIntervalsForDailyPeriod() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        viewModel.selectedPeriod = .daily

        await viewModel.loadData()

        let today = Calendar.current.dateInterval(of: .day, for: Date())!
        XCTAssertEqual(
            expenseRepo.fetchPeriods[0].start, today.start,
            "Daily period should fetch today's interval"
        )
    }

    func testLoadDataFetchesCorrectIntervalsForMonthlyPeriod() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        viewModel.selectedPeriod = .monthly

        await viewModel.loadData()

        let thisMonth = Calendar.current.dateInterval(of: .month, for: Date())!
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

    func testBarEntriesForMonthlyPeriodHasCorrectWeekCount() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        viewModel.selectedPeriod = .monthly
        expenseRepo.stubbedFetchResult = []

        await viewModel.loadData()

        let thisMonth = Calendar.current.dateInterval(of: .month, for: Date())!
        let expectedWeeks = Calendar.current.range(of: .weekOfMonth, in: .month, for: thisMonth.start)?.count ?? 0
        XCTAssertEqual(
            viewModel.barEntries.count, expectedWeeks,
            "Monthly period should have one entry per week in current month"
        )
        XCTAssertEqual(
            viewModel.barEntries.first?.label, "W1",
            "First monthly entry should be labeled 'W1'"
        )
    }

    func testBarEntriesForWeeklyPeriodAreInChronologicalOrder() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 500)]

        await viewModel.loadData()

        let labels = viewModel.barEntries.map(\.label)
        let calendar = Calendar.current
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: Date())!
        var expectedLabels: [String] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var date = weekInterval.start
        while date < weekInterval.end {
            expectedLabels.append(formatter.string(from: date))
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? weekInterval.end
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

    // MARK: - Sync Status Tests (Story 4-3)

    func testSyncStatusStartsHealthy() {
        let (viewModel, _, _, _) = makeSUT()

        XCTAssertEqual(
            viewModel.syncStatus, .healthy,
            "syncStatus should start as .healthy"
        )
    }

    func testSyncStatusUpdatesOnCallbackSyncFailure() async {
        let (viewModel, expenseRepo, _, syncMonitor) = makeSUT()
        expenseRepo.stubbedFetchResult = []
        let task = Task { await viewModel.subscribeToRemoteChanges() }
        await Task.yield()

        syncMonitor.syncStatus = .syncFailure
        for handler in syncMonitor.onSyncStatusChanged { handler(.syncFailure) }

        XCTAssertEqual(
            viewModel.syncStatus, .syncFailure,
            "syncStatus should update to .syncFailure when callback fires"
        )
        task.cancel()
    }

    func testSyncStatusUpdatesOnCallbackNoICloudAccount() async {
        let (viewModel, expenseRepo, _, syncMonitor) = makeSUT()
        expenseRepo.stubbedFetchResult = []
        let task = Task { await viewModel.subscribeToRemoteChanges() }
        await Task.yield()

        syncMonitor.syncStatus = .noICloudAccount
        for handler in syncMonitor.onSyncStatusChanged { handler(.noICloudAccount) }

        XCTAssertEqual(
            viewModel.syncStatus, .noICloudAccount,
            "syncStatus should update to .noICloudAccount when callback fires"
        )
        task.cancel()
    }

    func testSyncStatusResetsToHealthyAfterFailure() async {
        let (viewModel, expenseRepo, _, syncMonitor) = makeSUT()
        expenseRepo.stubbedFetchResult = []
        let task = Task { await viewModel.subscribeToRemoteChanges() }
        await Task.yield()

        syncMonitor.syncStatus = .syncFailure
        for handler in syncMonitor.onSyncStatusChanged { handler(.syncFailure) }
        XCTAssertEqual(viewModel.syncStatus, .syncFailure)

        syncMonitor.syncStatus = .healthy
        for handler in syncMonitor.onSyncStatusChanged { handler(.healthy) }

        XCTAssertEqual(
            viewModel.syncStatus, .healthy,
            "syncStatus should reset to .healthy when callback fires after failure"
        )
        task.cancel()
    }

    // MARK: - Initial Non-Healthy Status Snapshot (F7)

    func testSyncStatusSnapshotsNonHealthyInitialStatus() {
        let syncMonitor = MockSyncMonitorService()
        syncMonitor.syncStatus = .noICloudAccount

        let (viewModel, _, _, _) = makeSUT(syncMonitorService: syncMonitor)

        XCTAssertEqual(
            viewModel.syncStatus, .noICloudAccount,
            "syncStatus should snapshot non-healthy initial status from service"
        )
    }
}
