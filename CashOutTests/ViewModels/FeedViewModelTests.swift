import XCTest
@testable import CashOut

@MainActor
final class FeedViewModelTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeSUT(
        currentUserID: String? = "test-user",
        syncMonitorService: MockSyncMonitorService? = nil
    ) -> (
        viewModel: FeedViewModel,
        expenseRepo: MockExpenseRepository,
        categoryRepo: MockCategoryRepository,
        authService: MockAuthenticationService,
        hapticService: MockHapticService,
        syncMonitorService: MockSyncMonitorService
    ) {
        let expenseRepo = MockExpenseRepository()
        let categoryRepo = MockCategoryRepository()
        let authService = MockAuthenticationService()
        let hapticService = MockHapticService()
        authService.currentUserID = currentUserID

        let cloudSharingService = MockCloudSharingService()
        let syncMonitor = syncMonitorService ?? MockSyncMonitorService()

        let viewModel = FeedViewModel(
            repository: expenseRepo,
            categoryRepository: categoryRepo,
            authService: authService,
            cloudSharingService: cloudSharingService,
            syncMonitorService: syncMonitor,
            hapticService: hapticService
        )

        return (viewModel, expenseRepo, categoryRepo, authService, hapticService, syncMonitor)
    }

    private func makeExpense(
        id: UUID = UUID(),
        amount: Int64 = 1250,
        note: String? = nil,
        categoryID: UUID = UUID(),
        createdByUserID: String = "test-user",
        createdAt: Date = Date()
    ) -> ExpenseData {
        ExpenseData(
            id: id,
            amount: amount,
            note: note,
            categoryID: categoryID,
            createdByUserID: createdByUserID,
            createdAt: createdAt,
            modifiedAt: createdAt
        )
    }

    private func makeCategory(
        id: UUID = UUID(),
        name: String = "Food & Drink",
        iconName: String = "fork.knife",
        colorName: String = "Sage"
    ) -> CategoryData {
        CategoryData(
            id: id,
            name: name,
            iconName: iconName,
            colorName: colorName,
            isDefault: true,
            sortOrder: 0
        )
    }

    // MARK: - startObserving Tests (AC #1, #4)

    func testStartObservingCallsRepositoryStartObservingExpenses() {
        let (viewModel, expenseRepo, _, _, _, _) = makeSUT()

        viewModel.startObserving()

        XCTAssertTrue(
            expenseRepo.startObservingCalled,
            "startObserving() should call repository.startObservingExpenses()"
        )
    }

    func testStartObservingFetchesCategories() {
        let (viewModel, expenseRepo, categoryRepo, _, _, _) = makeSUT()
        let categoryID = UUID()
        categoryRepo.categoriesToReturn = [makeCategory(id: categoryID)]
        expenseRepo.stubbedExpenses = [makeExpense(categoryID: categoryID)]

        viewModel.startObserving()

        // Category fetch happens via Task inside reloadCategories
        let expectation = expectation(description: "Categories loaded")
        Task {
            // Allow the async category fetch to complete
            try? await Task.sleep(for: .milliseconds(50))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(
            categoryRepo.fetchCategoriesCalled,
            "startObserving() should trigger category fetch via callback"
        )
    }

    func testStartObservingTwiceDoesNotCallRepositoryTwice() {
        let (viewModel, expenseRepo, _, _, _, _) = makeSUT()

        viewModel.startObserving()
        expenseRepo.startObservingCalled = false
        viewModel.startObserving()

        XCTAssertFalse(
            expenseRepo.startObservingCalled,
            "Second call to startObserving() should be guarded by isObserving"
        )
    }

    // MARK: - expenses Update Tests

    func testExpensesUpdateWhenRepositoryCallbackFires() {
        let (viewModel, expenseRepo, _, _, _, _) = makeSUT()
        let expense = makeExpense()
        expenseRepo.stubbedExpenses = [expense]

        viewModel.startObserving()

        XCTAssertEqual(viewModel.expenses.count, 1, "Expenses should update from callback")
        XCTAssertEqual(viewModel.expenses.first?.id, expense.id)
    }

    // MARK: - isEmpty Tests (AC #6)

    func testIsEmptyReturnsTrueWhenNoExpenses() {
        let (viewModel, _, _, _, _, _) = makeSUT()

        XCTAssertTrue(viewModel.isEmpty, "isEmpty should be true when no expenses")
    }

    func testIsEmptyReturnsFalseWhenExpensesExist() {
        let (viewModel, expenseRepo, _, _, _, _) = makeSUT()
        expenseRepo.stubbedExpenses = [makeExpense()]

        viewModel.startObserving()

        XCTAssertFalse(viewModel.isEmpty, "isEmpty should be false when expenses exist")
    }

    // MARK: - isCurrentUser Tests (AC #3)

    func testIsCurrentUserReturnsTrueForMatchingUserID() {
        let (viewModel, _, _, _, _, _) = makeSUT(currentUserID: "user-123")
        let expense = makeExpense(createdByUserID: "user-123")

        XCTAssertTrue(
            viewModel.isCurrentUser(expense),
            "isCurrentUser should return true when createdByUserID matches currentUserID"
        )
    }

    func testIsCurrentUserReturnsFalseForDifferentUserID() {
        let (viewModel, _, _, _, _, _) = makeSUT(currentUserID: "user-123")
        let expense = makeExpense(createdByUserID: "partner-456")

        XCTAssertFalse(
            viewModel.isCurrentUser(expense),
            "isCurrentUser should return false when createdByUserID differs from currentUserID"
        )
    }

    func testIsCurrentUserReturnsTrueForEmptyCreatedByUserID() {
        let (viewModel, _, _, _, _, _) = makeSUT(currentUserID: "user-123")
        let expense = makeExpense(createdByUserID: "")

        XCTAssertTrue(
            viewModel.isCurrentUser(expense),
            "isCurrentUser should return true for empty createdByUserID (unattributed fallback)"
        )
    }

    // MARK: - partnerInitials Tests (AC #3)

    func testPartnerInitialsReturnsMeForCurrentUser() {
        let (viewModel, _, _, _, _, _) = makeSUT(currentUserID: "user-123")
        let expense = makeExpense(createdByUserID: "user-123")

        XCTAssertEqual(
            viewModel.partnerInitials(for: expense), "Me",
            "partnerInitials should return 'Me' for current user's expenses"
        )
    }

    func testPartnerInitialsReturnsPForPartner() {
        let (viewModel, _, _, _, _, _) = makeSUT(currentUserID: "user-123")
        let expense = makeExpense(createdByUserID: "partner-456")

        XCTAssertEqual(
            viewModel.partnerInitials(for: expense), "P",
            "partnerInitials should return 'P' for partner's expenses"
        )
    }

    // MARK: - categoryFor Tests

    func testCategoryForReturnsMatchingCategory() {
        let (viewModel, expenseRepo, categoryRepo, _, _, _) = makeSUT()
        let categoryID = UUID()
        let category = makeCategory(id: categoryID, name: "Transport")
        categoryRepo.categoriesToReturn = [category]
        expenseRepo.stubbedExpenses = [makeExpense(categoryID: categoryID)]

        viewModel.startObserving()

        let expectation = expectation(description: "Categories loaded")
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        let expense = viewModel.expenses.first!
        let result = viewModel.categoryFor(expense)

        XCTAssertEqual(result?.id, categoryID, "categoryFor should return matching category by ID")
        XCTAssertEqual(result?.name, "Transport")
    }

    func testCategoryForReturnsNilForUnknownCategoryID() {
        let (viewModel, _, _, _, _, _) = makeSUT()
        let expense = makeExpense(categoryID: UUID())

        let result = viewModel.categoryFor(expense)

        XCTAssertNil(result, "categoryFor should return nil for unknown category ID")
    }

    // MARK: - isCurrentUser with nil currentUserID (Review P3)

    func testIsCurrentUserReturnsTrueWhenCurrentUserIDIsNil() {
        let (viewModel, _, _, _, _, _) = makeSUT(currentUserID: nil)
        let expense = makeExpense(createdByUserID: "partner-456")

        XCTAssertTrue(
            viewModel.isCurrentUser(expense),
            "isCurrentUser should return true when currentUserID is nil (unauthenticated fallback)"
        )
    }

    // MARK: - Error Handling Tests (Review P2)

    func testReloadCategoriesSetsErrorMessageOnFailure() {
        let (viewModel, expenseRepo, categoryRepo, _, _, _) = makeSUT()
        categoryRepo.shouldThrow = true
        expenseRepo.stubbedExpenses = [makeExpense()]

        viewModel.startObserving()

        let expectation = expectation(description: "Category fetch error handled")
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertNotNil(
            viewModel.errorMessage,
            "errorMessage should be set when categoryRepository.fetchCategories() throws"
        )
    }

    // MARK: - deleteExpense Tests (AC #2)

    func testDeleteExpenseCallsRepositoryWithCorrectID() async {
        let (viewModel, expenseRepo, _, _, _, _) = makeSUT()
        let expense = makeExpense()

        await viewModel.deleteExpense(expense)

        XCTAssertTrue(
            expenseRepo.deleteExpenseCalled,
            "deleteExpense should call repository.deleteExpense"
        )
        XCTAssertEqual(
            expenseRepo.lastDeletedExpenseID, expense.id,
            "deleteExpense should pass the correct expense ID to repository"
        )
    }

    func testDeleteExpenseTriggersDeleteTapHapticOnSuccess() async {
        let (viewModel, _, _, _, hapticService, _) = makeSUT()
        let expense = makeExpense()

        await viewModel.deleteExpense(expense)

        XCTAssertEqual(
            hapticService.lastEvent, .deleteTap,
            "deleteExpense should trigger .deleteTap haptic on success"
        )
    }

    func testDeleteExpenseDoesNotTriggerHapticOnFailure() async {
        let (viewModel, expenseRepo, _, _, hapticService, _) = makeSUT()
        expenseRepo.shouldThrow = true
        let expense = makeExpense()

        await viewModel.deleteExpense(expense)

        XCTAssertTrue(
            hapticService.triggeredEvents.isEmpty,
            "deleteExpense should not trigger haptic when repository throws"
        )
    }

    func testDeleteExpenseSetsErrorMessageOnFailure() async {
        let (viewModel, expenseRepo, _, _, _, _) = makeSUT()
        expenseRepo.shouldThrow = true
        let expense = makeExpense()

        await viewModel.deleteExpense(expense)

        XCTAssertTrue(
            expenseRepo.deleteExpenseCalled,
            "deleteExpense should attempt deletion even when it will fail"
        )
        XCTAssertNotNil(
            viewModel.errorMessage,
            "deleteExpense should set errorMessage when repository throws"
        )
    }

    // MARK: - Sync Status Tests (Story 4-3)

    func testSyncStatusStartsHealthy() {
        let (viewModel, _, _, _, _, _) = makeSUT()

        XCTAssertEqual(
            viewModel.syncStatus, .healthy,
            "syncStatus should start as .healthy"
        )
    }

    func testSyncStatusUpdatesOnCallbackSyncFailure() {
        let (viewModel, _, _, _, _, syncMonitor) = makeSUT()

        syncMonitor.syncStatus = .syncFailure
        for handler in syncMonitor.onSyncStatusChanged { handler(.syncFailure) }

        XCTAssertEqual(
            viewModel.syncStatus, .syncFailure,
            "syncStatus should update to .syncFailure when callback fires"
        )
    }

    func testSyncStatusUpdatesOnCallbackNoICloudAccount() {
        let (viewModel, _, _, _, _, syncMonitor) = makeSUT()

        syncMonitor.syncStatus = .noICloudAccount
        for handler in syncMonitor.onSyncStatusChanged { handler(.noICloudAccount) }

        XCTAssertEqual(
            viewModel.syncStatus, .noICloudAccount,
            "syncStatus should update to .noICloudAccount when callback fires"
        )
    }

    func testSyncStatusResetsToHealthyAfterFailure() {
        let (viewModel, _, _, _, _, syncMonitor) = makeSUT()

        syncMonitor.syncStatus = .syncFailure
        for handler in syncMonitor.onSyncStatusChanged { handler(.syncFailure) }
        XCTAssertEqual(viewModel.syncStatus, .syncFailure)

        syncMonitor.syncStatus = .healthy
        for handler in syncMonitor.onSyncStatusChanged { handler(.healthy) }

        XCTAssertEqual(
            viewModel.syncStatus, .healthy,
            "syncStatus should reset to .healthy when callback fires after failure"
        )
    }

    // MARK: - Initial Non-Healthy Status Snapshot (F7)

    func testSyncStatusSnapshotsNonHealthyInitialStatus() {
        let syncMonitor = MockSyncMonitorService()
        syncMonitor.syncStatus = .noICloudAccount

        let (viewModel, _, _, _, _, _) = makeSUT(syncMonitorService: syncMonitor)

        XCTAssertEqual(
            viewModel.syncStatus, .noICloudAccount,
            "syncStatus should snapshot non-healthy initial status from service"
        )
    }
}
