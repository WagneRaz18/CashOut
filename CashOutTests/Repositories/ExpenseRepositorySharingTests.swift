import XCTest
@testable import CashOut

@MainActor
final class ExpenseRepositorySharingTests: XCTestCase {
    private var persistence: PersistenceController!
    private var categoryRepository: CategoryRepository!

    override func setUp() async throws {
        persistence = TestPersistenceHelper.makeInMemoryController()
        categoryRepository = CategoryRepository(persistence: persistence)
        try await categoryRepository.seedDefaultCategoriesIfNeeded()
    }

    private func makeSampleExpense() async throws -> ExpenseData {
        let categories = try await categoryRepository.fetchCategories()
        let now = Date()
        return ExpenseData(
            id: UUID(),
            amount: 1250,
            note: "Test expense",
            categoryID: categories[0].id,
            createdByUserID: "test-user",
            createdAt: now,
            modifiedAt: now
        )
    }

    // MARK: - Solo Mode (isShared = false)

    func testSaveInSoloModeCallsMethodsButGuardsReturnEarly() async throws {
        let mock = MockCloudSharingService()
        mock.isShared = false
        let repository = ExpenseRepository(
            persistence: persistence,
            cloudSharingService: mock
        )

        let expense = try await makeSampleExpense()
        try await repository.saveExpense(expense)
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))  // Allow fire-and-forget sharing task to complete

        // Repository delegates to service for new objects; the service's
        // guard clauses (isShared check) handle the no-op in solo mode.
        // Mock records calls but real implementation returns early.
        XCTAssertTrue(
            mock.prepareObjectForSharedSaveCalled,
            "prepareObjectForSharedSave should be called (service guards on isShared)"
        )
        XCTAssertTrue(
            mock.shareObjectsToHouseholdCalled,
            "shareObjectsToHouseholdIfNeeded should be called (service guards on isShared)"
        )
    }

    // MARK: - Owner Mode (isShared = true, isShareOwner = true)

    func testSaveAsOwnerCallsShareObjectsToHousehold() async throws {
        let mock = MockCloudSharingService()
        mock.isShared = true
        mock.isShareOwner = true
        let repository = ExpenseRepository(
            persistence: persistence,
            cloudSharingService: mock
        )

        let expense = try await makeSampleExpense()
        try await repository.saveExpense(expense)
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))  // Allow fire-and-forget sharing task to complete

        XCTAssertTrue(
            mock.shareObjectsToHouseholdCalled,
            "shareObjectsToHouseholdIfNeeded should be called for owner"
        )
    }

    // MARK: - Participant Mode (isShared = true, isShareOwner = false)

    func testSaveAsParticipantCallsPrepareObjectForSharedSave() async throws {
        let mock = MockCloudSharingService()
        mock.isShared = true
        mock.isShareOwner = false
        let repository = ExpenseRepository(
            persistence: persistence,
            cloudSharingService: mock
        )

        let expense = try await makeSampleExpense()
        try await repository.saveExpense(expense)

        XCTAssertTrue(
            mock.prepareObjectForSharedSaveCalled,
            "prepareObjectForSharedSave should be called for participant"
        )
    }

    // MARK: - Edit Path (existing object)

    func testEditExistingExpenseDoesNotCallSharingMethods() async throws {
        let mock = MockCloudSharingService()
        mock.isShared = true
        mock.isShareOwner = true
        let repository = ExpenseRepository(
            persistence: persistence,
            cloudSharingService: mock
        )

        // Save initial expense
        let expense = try await makeSampleExpense()
        try await repository.saveExpense(expense)
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))  // Allow fire-and-forget sharing task to complete

        // Reset call tracking
        mock.prepareObjectForSharedSaveCalled = false
        mock.shareObjectsToHouseholdCalled = false

        // Edit the same expense (same ID)
        let updated = ExpenseData(
            id: expense.id,
            amount: 9999,
            note: "Updated",
            categoryID: expense.categoryID,
            createdByUserID: expense.createdByUserID,
            createdAt: expense.createdAt,
            modifiedAt: Date()
        )
        try await repository.saveExpense(updated)

        XCTAssertFalse(
            mock.prepareObjectForSharedSaveCalled,
            "prepareObjectForSharedSave should NOT be called for edits"
        )
        XCTAssertFalse(
            mock.shareObjectsToHouseholdCalled,
            "shareObjectsToHouseholdIfNeeded should NOT be called for edits"
        )
    }

    // MARK: - Nil CloudSharingService (tests/inMemory)

    func testSaveWithNilCloudSharingServiceSucceeds() async throws {
        let repository = ExpenseRepository(
            persistence: persistence,
            cloudSharingService: nil
        )

        let expense = try await makeSampleExpense()
        try await repository.saveExpense(expense)

        let period = DateInterval(
            start: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            end: Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        )
        let results = try await repository.fetchExpenses(for: period)
        XCTAssertEqual(results.count, 1, "Save should succeed without cloud sharing service")
    }
}
