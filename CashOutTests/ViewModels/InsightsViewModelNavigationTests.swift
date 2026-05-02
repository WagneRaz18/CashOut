import XCTest
@testable import CashOut

@MainActor
final class InsightsViewModelNavigationTests: XCTestCase {

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

    // MARK: - Swipe Date Navigation Tests

    func testNavigatePreviousDecrementsOffset() {
        let (viewModel, _, _, _) = makeSUT()
        XCTAssertEqual(viewModel.dateOffset, 0)

        viewModel.navigatePrevious()
        XCTAssertEqual(viewModel.dateOffset, -1, "navigatePrevious should decrement dateOffset by 1")

        viewModel.navigatePrevious()
        XCTAssertEqual(viewModel.dateOffset, -2, "navigatePrevious again should decrement to -2")
    }

    func testNavigateNextAtOffsetZeroIsNoOp() {
        let (viewModel, _, _, _) = makeSUT()
        XCTAssertFalse(viewModel.canNavigateForward, "canNavigateForward should be false at offset 0")

        viewModel.navigateNext()
        XCTAssertEqual(viewModel.dateOffset, 0, "navigateNext at offset 0 should be a no-op")
    }

    func testNavigateNextFromNegativeOneReachesZero() {
        let (viewModel, _, _, _) = makeSUT()
        viewModel.navigatePrevious()
        XCTAssertEqual(viewModel.dateOffset, -1)
        XCTAssertTrue(viewModel.canNavigateForward)

        viewModel.navigateNext()
        XCTAssertEqual(viewModel.dateOffset, 0, "navigateNext from offset -1 should reach 0")
        XCTAssertFalse(viewModel.canNavigateForward, "canNavigateForward should be false after reaching 0")
    }

    func testResetToCurrentPeriodSetsOffsetToZero() {
        let (viewModel, _, _, _) = makeSUT()
        viewModel.navigatePrevious()
        viewModel.navigatePrevious()
        viewModel.navigatePrevious()
        XCTAssertEqual(viewModel.dateOffset, -3)

        viewModel.resetToCurrentPeriod()
        XCTAssertEqual(viewModel.dateOffset, 0, "resetToCurrentPeriod should set offset to 0")
    }

    func testResetToCurrentPeriodAtZeroIsNoOp() {
        let (viewModel, _, _, _) = makeSUT()
        XCTAssertEqual(viewModel.dateOffset, 0)

        viewModel.resetToCurrentPeriod()
        XCTAssertEqual(viewModel.dateOffset, 0, "resetToCurrentPeriod at offset 0 should be a no-op")
    }

    func testLoadDataReloadsWhenOffsetChanges() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        viewModel.selectedPeriod = .daily

        await viewModel.loadData()
        let countAfterFirstLoad = expenseRepo.fetchPeriods.count

        viewModel.navigatePrevious()  // offset = -1
        await viewModel.loadData()

        XCTAssertGreaterThan(
            expenseRepo.fetchPeriods.count, countAfterFirstLoad,
            "loadData should fetch again when dateOffset changes"
        )
    }

    func testLoadDataSkipsWhenPeriodAndOffsetUnchanged() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        viewModel.selectedPeriod = .daily
        viewModel.navigatePrevious()  // offset = -1

        await viewModel.loadData()
        let countAfterFirstLoad = expenseRepo.fetchPeriods.count

        await viewModel.loadData()  // same period + offset

        XCTAssertEqual(
            expenseRepo.fetchPeriods.count, countAfterFirstLoad,
            "loadData should skip when both period and offset are unchanged"
        )
    }

    func testLoadDataAfterInvalidateAndReloadReloadsAtSameOffset() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        viewModel.selectedPeriod = .daily
        viewModel.navigatePrevious()  // offset = -1

        await viewModel.loadData()
        let countAfterFirstLoad = expenseRepo.fetchPeriods.count

        await viewModel.invalidateAndReload()

        XCTAssertGreaterThan(
            expenseRepo.fetchPeriods.count, countAfterFirstLoad,
            "invalidateAndReload should trigger a fresh fetch even at the same period+offset"
        )
    }

    func testPeriodLabelAtOffsetZeroReturnsCurrentLabel() {
        let (viewModel, _, _, _) = makeSUT()
        viewModel.selectedPeriod = .daily
        XCTAssertEqual(viewModel.periodLabel, "Today")

        viewModel.selectedPeriod = .weekly
        XCTAssertEqual(viewModel.periodLabel, "This Week")

        viewModel.selectedPeriod = .monthly
        XCTAssertEqual(viewModel.periodLabel, "This Month")
    }

    func testPeriodLabelAtOffsetNegativeOneReturnsSpecialLabel() {
        let (viewModel, _, _, _) = makeSUT()

        viewModel.selectedPeriod = .daily
        viewModel.navigatePrevious()
        XCTAssertEqual(viewModel.periodLabel, "Yesterday", "Daily offset -1 should return 'Yesterday'")

        viewModel.resetToCurrentPeriod()
        viewModel.selectedPeriod = .weekly
        viewModel.navigatePrevious()
        XCTAssertEqual(viewModel.periodLabel, "Last Week", "Weekly offset -1 should return 'Last Week'")

        viewModel.resetToCurrentPeriod()
        viewModel.selectedPeriod = .monthly
        viewModel.navigatePrevious()
        XCTAssertEqual(viewModel.periodLabel, "Last Month", "Monthly offset -1 should return 'Last Month'")
    }

    func testPeriodLabelAtLargerOffsetReturnsFormattedDate() {
        let (viewModel, _, _, _) = makeSUT()
        viewModel.selectedPeriod = .daily
        viewModel.dateOffset = -5

        let label = viewModel.periodLabel
        XCTAssertFalse(label.isEmpty, "periodLabel at offset -5 should return a non-empty formatted date")
        XCTAssertNotEqual(label, "Today", "periodLabel at offset -5 should not be 'Today'")
        XCTAssertNotEqual(label, "Yesterday", "periodLabel at offset -5 should not be 'Yesterday'")
    }

    func testComparisonTextIsNilWhenOffsetIsNonZeroWithNonNilPreviousTotal() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 5000)]

        await viewModel.loadData()
        // Ensure previousPeriodTotal is non-nil (both periods return same stub → 5000)
        XCTAssertNotNil(viewModel.previousPeriodTotal, "Precondition: previousPeriodTotal must be non-nil")

        viewModel.navigatePrevious()  // offset = -1
        XCTAssertNil(
            viewModel.comparisonText,
            "comparisonText should be nil when dateOffset != 0, even with non-nil previousPeriodTotal"
        )
    }

    // MARK: - navigateToDay Tests

    func testNavigateToDaySetsPeriodToDaily() throws {
        let (viewModel, _, _, _) = makeSUT()
        viewModel.selectedPeriod = .monthly
        let yesterday = try XCTUnwrap(Calendar.gregorian.date(byAdding: .day, value: -1, to: Date()))
        viewModel.navigateToDay(yesterday)
        XCTAssertEqual(viewModel.selectedPeriod, .daily)
    }

    func testNavigateToDaySetsCorrectOffset() throws {
        let (viewModel, _, _, _) = makeSUT()
        let fiveDaysAgo = try XCTUnwrap(Calendar.gregorian.date(byAdding: .day, value: -5, to: Date()))
        viewModel.navigateToDay(fiveDaysAgo)
        XCTAssertEqual(viewModel.dateOffset, -5)
    }

    func testNavigateToDayOnTodaySetsOffsetZero() {
        let (viewModel, _, _, _) = makeSUT()
        viewModel.dateOffset = -3
        viewModel.navigateToDay(Date())
        XCTAssertEqual(viewModel.dateOffset, 0)
        XCTAssertEqual(viewModel.selectedPeriod, .daily)
    }

    func testNavigateToDayFutureDateIsNoOp() throws {
        let (viewModel, _, _, _) = makeSUT()
        viewModel.selectedPeriod = .monthly
        viewModel.dateOffset = -1
        let tomorrow = try XCTUnwrap(Calendar.gregorian.date(byAdding: .day, value: 1, to: Date()))
        viewModel.navigateToDay(tomorrow)
        XCTAssertEqual(viewModel.selectedPeriod, .monthly, "Future date tap should not change period")
        XCTAssertEqual(viewModel.dateOffset, -1, "Future date tap should not change offset")
    }

    func testNavigateToDayWritesDateOffsetBeforeSelectedPeriod() throws {
        let (viewModel, _, _, _) = makeSUT()
        viewModel.selectedPeriod = .monthly
        let threeDaysAgo = try XCTUnwrap(Calendar.gregorian.date(byAdding: .day, value: -3, to: Date()))
        viewModel.navigateToDay(threeDaysAgo)
        XCTAssertEqual(viewModel.dateOffset, -3)
        XCTAssertEqual(viewModel.selectedPeriod, .daily)
        XCTAssertEqual(viewModel.loadKey, "Day--3", "loadKey must reflect final state, not intermediate")
    }

    // MARK: - dailyTotals Tests

    func testDailyTotalsAggregatesExpensesOnSameDay() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        viewModel.selectedPeriod = .daily
        let todayStart = Calendar.gregorian.startOfDay(for: Date())
        expenseRepo.stubbedFetchResult = [
            makeExpense(amount: 1000, createdAt: todayStart),
            makeExpense(amount: 2500, createdAt: todayStart)
        ]
        await viewModel.loadData()
        XCTAssertEqual(viewModel.dailyTotals[todayStart], 3500)
    }

    func testDailyTotalsKeepsDaysWithSpendingOnly() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        viewModel.selectedPeriod = .daily
        let todayStart = Calendar.gregorian.startOfDay(for: Date())
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 800, createdAt: todayStart)]
        await viewModel.loadData()
        XCTAssertEqual(viewModel.dailyTotals.count, 1, "Only days with spend should appear in dailyTotals")
    }

    func testDailyTotalsResetOnLoadError() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        viewModel.selectedPeriod = .daily
        let todayStart = Calendar.gregorian.startOfDay(for: Date())
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 500, createdAt: todayStart)]
        await viewModel.loadData()
        XCTAssertFalse(viewModel.dailyTotals.isEmpty, "Precondition: dailyTotals must have data")

        expenseRepo.stubbedFetchResult = []
        expenseRepo.shouldThrow = true
        await viewModel.invalidateAndReload()
        XCTAssertTrue(viewModel.dailyTotals.isEmpty, "dailyTotals must reset on load error")
    }

    func testDailyBarEntryLabelIsYesterdayAtOffsetNegativeOne() async {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        viewModel.selectedPeriod = .daily
        viewModel.navigatePrevious()  // offset = -1
        expenseRepo.stubbedFetchResult = [makeExpense(amount: 1000)]

        await viewModel.loadData()

        XCTAssertEqual(
            viewModel.barEntries.first?.label, "Yesterday",
            "Daily bar entry at offset -1 should be labeled 'Yesterday' (runs against real clock)"
        )
    }
}
