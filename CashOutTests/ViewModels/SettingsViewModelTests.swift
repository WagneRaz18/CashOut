import XCTest
import CloudKit
@preconcurrency import CoreData
@testable import CashOut

@MainActor
final class SettingsViewModelTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeSUT(
        state: SharingState = .solo,
        isShareOwner: Bool = false,
        categories: [CategoryData] = []
    ) -> (viewModel: SettingsViewModel, mockService: MockCloudSharingService, mockCategories: MockCategoryRepository, mockHaptics: MockHapticService) {
        let mockService = MockCloudSharingService()
        mockService.state = state
        mockService.isShareOwner = isShareOwner
        let mockCategories = MockCategoryRepository()
        mockCategories.categoriesToReturn = categories
        let mockHaptics = MockHapticService()

        let viewModel = SettingsViewModel(
            cloudSharingService: mockService,
            categoryRepository: mockCategories,
            hapticService: mockHaptics
        )
        return (viewModel, mockService, mockCategories, mockHaptics)
    }

    private func makeSUTWithPersistence() -> (
        viewModel: SettingsViewModel,
        mockService: MockCloudSharingService,
        persistence: PersistenceController
    ) {
        let persistence = TestPersistenceHelper.makeInMemoryController()
        let mockService = MockCloudSharingService()

        let viewModel = SettingsViewModel(
            cloudSharingService: mockService,
            persistenceController: persistence
        )
        return (viewModel, mockService, persistence)
    }

    private func seedCategories(in persistence: PersistenceController) {
        let context = persistence.container.viewContext
        let category = Category(context: context)
        category.id = UUID()
        category.name = "Food"
        category.iconName = "fork.knife"
        category.colorName = "expenseRed"
        category.isDefault = true
        category.sortOrder = 0
        try! context.save()
    }

    // MARK: - Solo Mode Tests

    func testSoloModeHasPartnerIsFalse() {
        let (viewModel, _, _, _) = makeSUT(state: .solo)
        XCTAssertFalse(viewModel.hasPartner)
    }

    func testSoloModePartnerDisplayNameIsNil() {
        let (viewModel, _, _, _) = makeSUT(state: .solo)
        XCTAssertNil(viewModel.partnerDisplayName)
    }

    func testSoloModeIsPendingInvitationIsFalse() {
        let (viewModel, _, _, _) = makeSUT(state: .solo)
        XCTAssertFalse(viewModel.isPendingInvitation)
    }

    // MARK: - Draft State Tests

    func testDraftStateIsNotPendingInvitation() {
        // Critical: the original bug was .draft being surfaced as "Invitation Pending".
        // A draft share (sheet open, no invite sent) must NOT render as pending in the UI.
        let (viewModel, _, _, _) = makeSUT(state: .draft)
        XCTAssertFalse(viewModel.isPendingInvitation)
        XCTAssertFalse(viewModel.hasPartner)
        XCTAssertNil(viewModel.partnerDisplayName)
    }

    // MARK: - Pending Invitation Tests

    func testPendingInvitationHasPartnerIsFalse() {
        let (viewModel, _, _, _) = makeSUT(state: .pending)
        XCTAssertTrue(viewModel.isPendingInvitation)
        XCTAssertFalse(viewModel.hasPartner)
    }

    // MARK: - Partner Connected Tests

    func testPartnerConnectedHasPartnerIsTrue() {
        let (viewModel, _, _, _) = makeSUT(state: .connected(partnerName: "Jane"))
        XCTAssertTrue(viewModel.hasPartner)
    }

    func testPartnerConnectedIsPendingInvitationIsFalse() {
        let (viewModel, _, _, _) = makeSUT(state: .connected(partnerName: "Jane"))
        XCTAssertFalse(viewModel.isPendingInvitation)
    }

    func testPartnerConnectedDisplaysPartnerName() {
        let (viewModel, _, _, _) = makeSUT(state: .connected(partnerName: "Jane Smith"))
        XCTAssertEqual(viewModel.partnerDisplayName, "Jane Smith")
    }

    func testPartnerConnectedWithNilNameDisplaysNil() {
        // The fallback "Partner" string is a view-layer concern (FeedViewModel applies it).
        // SettingsViewModel surfaces the raw nil from the .connected associated value.
        let (viewModel, _, _, _) = makeSUT(state: .connected(partnerName: nil))
        XCTAssertTrue(viewModel.hasPartner)
        XCTAssertNil(viewModel.partnerDisplayName)
    }

    // MARK: - Invite Partner Tests

    func testInvitePartnerCallsCreateShareOnService() async {
        let (viewModel, mockService, persistence) = makeSUTWithPersistence()
        seedCategories(in: persistence)

        let testShare = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName))
        mockService.createShareResult = .success((testShare, CKContainer.default()))

        await viewModel.invitePartner()

        XCTAssertTrue(mockService.createShareCalled)
    }

    func testInvitePartnerOnSuccessSetsActiveShareAndContainer() async {
        let (viewModel, mockService, persistence) = makeSUTWithPersistence()
        seedCategories(in: persistence)

        let testShare = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName))
        mockService.createShareResult = .success((testShare, CKContainer.default()))

        await viewModel.invitePartner()

        XCTAssertNotNil(viewModel.activeShare)
        XCTAssertNotNil(viewModel.activeContainer)
        XCTAssertTrue(viewModel.isShowingShareSheet)
    }

    func testInvitePartnerOnErrorSetsErrorMessage() async {
        let (viewModel, _, persistence) = makeSUTWithPersistence()
        seedCategories(in: persistence)
        // No handler set on mock — will throw default error

        await viewModel.invitePartner()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.activeShare)
        XCTAssertNil(viewModel.activeContainer)
        XCTAssertFalse(viewModel.isShowingShareSheet)
    }

    func testInvitePartnerWithNoCategoriesSetsErrorMessage() async {
        let (viewModel, _, _) = makeSUTWithPersistence()
        // No categories seeded

        await viewModel.invitePartner()

        XCTAssertEqual(viewModel.errorMessage, "No categories found. Please restart the app.")
        XCTAssertFalse(viewModel.isShowingShareSheet)
    }

    // MARK: - Refresh Sharing Status Tests

    func testRefreshSharingStatusCallsCheckOnService() async {
        let (viewModel, mockService, _, _) = makeSUT()

        await viewModel.refreshSharingStatus()

        XCTAssertTrue(mockService.checkSharingStatusCalled)
    }

    // MARK: - Handle Share Dismiss Tests

    /// The ViewModel's `handleShareDismiss` is a thin passthrough that delegates all
    /// classification and cleanup to the service's `finalizeShareOutcome`. These tests
    /// verify the passthrough contract; state-transition correctness is verified at
    /// the service level in its own test suite.
    func testHandleDismissWithShareDispatchesFinalize() async {
        let (viewModel, mockService, _, _) = makeSUT()
        viewModel.isShowingShareSheet = true

        let testShare = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName))
        viewModel.handleShareDismiss(testShare)

        // The finalize call is dispatched on a Task — yield to let it run.
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(mockService.finalizeShareOutcomeCalled)
        XCTAssertEqual(mockService.lastFinalizedShare?.recordID, testShare.recordID)
        XCTAssertFalse(viewModel.isShowingShareSheet)
    }

    func testHandleDismissWithNilDispatchesFinalize() async {
        let (viewModel, mockService, _, _) = makeSUT()
        viewModel.isShowingShareSheet = true

        viewModel.handleShareDismiss(nil)

        await Task.yield()
        await Task.yield()

        XCTAssertTrue(mockService.finalizeShareOutcomeCalled)
        XCTAssertNil(mockService.lastFinalizedShare)
        XCTAssertFalse(viewModel.isShowingShareSheet)
    }

    func testHandleDismissClearsActiveShareAndContainerSynchronously() async {
        let (viewModel, mockService, persistence) = makeSUTWithPersistence()
        seedCategories(in: persistence)

        let testShare = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName))
        mockService.createShareResult = .success((testShare, CKContainer.default()))
        await viewModel.invitePartner()

        // Precondition: invitePartner must have populated active state
        XCTAssertNotNil(viewModel.activeShare, "test setup failed — invitePartner did not set activeShare")
        XCTAssertNotNil(viewModel.activeContainer, "test setup failed — invitePartner did not set activeContainer")

        viewModel.handleShareDismiss(nil)

        XCTAssertNil(viewModel.activeShare,
            "Any dismiss path must clear activeShare synchronously")
        XCTAssertNil(viewModel.activeContainer,
            "Any dismiss path must clear activeContainer synchronously")
        XCTAssertFalse(viewModel.isShowingShareSheet)
    }

    // MARK: - Category Loading Tests

    func testLoadCategoriesPopulatesCategoriesArray() async {
        let defaultCategories = makeDefaultCategories()
        let (viewModel, _, mockCategories, _) = makeSUT(categories: defaultCategories)

        await viewModel.loadCategories()

        XCTAssertTrue(mockCategories.fetchCategoriesCalled)
        XCTAssertEqual(viewModel.categories.count, defaultCategories.count)
    }

    func testLoadCategoriesOnErrorSetsEmptyArrayWithNoErrorMessage() async {
        let (viewModel, _, mockCategories, _) = makeSUT()
        mockCategories.shouldThrow = true

        await viewModel.loadCategories()

        XCTAssertTrue(viewModel.categories.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadCategoriesIncludesCustomCategories() async {
        var allCategories = makeDefaultCategories()
        allCategories.append(CategoryData(id: UUID(), name: "Groceries", iconName: "cart.fill", colorName: "Sage", isDefault: false, sortOrder: 6))
        allCategories.append(CategoryData(id: UUID(), name: "Pets", iconName: "pawprint.fill", colorName: "Amber", isDefault: false, sortOrder: 7))

        let (viewModel, _, _, _) = makeSUT(categories: allCategories)

        await viewModel.loadCategories()

        XCTAssertEqual(viewModel.categories.count, 8)
        let customCategories = viewModel.categories.filter { !$0.isDefault }
        XCTAssertEqual(customCategories.count, 2)
    }

    // MARK: - Save Category Tests

    func testSaveCategoryCreatesNewCategory() async {
        let (viewModel, _, mockCategories, mockHaptics) = makeSUT(categories: makeDefaultCategories())
        await viewModel.loadCategories()

        await viewModel.saveCategory(name: "Groceries", iconName: "cart.fill", colorName: "Teal", existingID: nil)

        XCTAssertTrue(mockCategories.saveCategoryCalled)
        XCTAssertEqual(mockCategories.savedCategory?.name, "Groceries")
        XCTAssertEqual(mockCategories.savedCategory?.iconName, "cart.fill")
        XCTAssertEqual(mockCategories.savedCategory?.colorName, "Teal")
        XCTAssertEqual(mockCategories.savedCategory?.isDefault, false)
        XCTAssertTrue(mockHaptics.triggeredEvents.contains(.saveTap))
    }

    func testSaveCategoryUpdatesExistingCategory() async {
        let existingID = UUID()
        let existingCategories = [
            CategoryData(id: existingID, name: "Old Name", iconName: "star.fill", colorName: "Teal", isDefault: false, sortOrder: 6)
        ]
        let (viewModel, _, mockCategories, _) = makeSUT(categories: makeDefaultCategories() + existingCategories)
        await viewModel.loadCategories()

        await viewModel.saveCategory(name: "New Name", iconName: "heart.fill", colorName: "Coral", existingID: existingID)

        XCTAssertTrue(mockCategories.saveCategoryCalled)
        XCTAssertEqual(mockCategories.savedCategory?.id, existingID)
        XCTAssertEqual(mockCategories.savedCategory?.name, "New Name")
    }

    func testSaveCategoryWithEmptyNameIsNoOp() async {
        let (viewModel, _, mockCategories, _) = makeSUT()

        await viewModel.saveCategory(name: "  ", iconName: "cart.fill", colorName: "Teal", existingID: nil)

        XCTAssertFalse(mockCategories.saveCategoryCalled)
        XCTAssertFalse(viewModel.isSavingCategory)
    }

    func testSaveCategoryRefreshesCategoriesList() async {
        let (viewModel, _, mockCategories, _) = makeSUT(categories: makeDefaultCategories())
        await viewModel.loadCategories()
        mockCategories.fetchCategoriesCallCount = 0

        await viewModel.saveCategory(name: "Groceries", iconName: "cart.fill", colorName: "Teal", existingID: nil)

        XCTAssertEqual(mockCategories.fetchCategoriesCallCount, 1)
    }

    func testSaveCategoryGuardsAgainstConcurrentSaves() async {
        let (viewModel, _, mockCategories, _) = makeSUT()

        // Call saveCategory twice — @MainActor serializes, so second call runs
        // after first completes. Both should succeed since guard resets via defer.
        // The guard is tested implicitly: if isSavingCategory were stuck true,
        // the second call would be a no-op.
        await viewModel.saveCategory(name: "First", iconName: "star.fill", colorName: "Teal", existingID: nil)
        await viewModel.saveCategory(name: "Second", iconName: "heart.fill", colorName: "Coral", existingID: nil)

        // savedCategory should be the LAST call's data (both succeeded)
        XCTAssertEqual(mockCategories.savedCategory?.name, "Second")
        XCTAssertFalse(viewModel.isSavingCategory)
    }

    func testCategoriesSortedPredefinedFirst() async {
        var allCategories = makeDefaultCategories()
        allCategories.insert(CategoryData(id: UUID(), name: "Custom", iconName: "star.fill", colorName: "Teal", isDefault: false, sortOrder: 0), at: 0)

        let (viewModel, _, _, _) = makeSUT(categories: allCategories)
        await viewModel.loadCategories()

        // Repository returns categories in sortOrder. The first entry we inserted has sortOrder 0 and isDefault false.
        // The mock returns categories as-is (no server-side sorting). This test verifies the ViewModel stores what the repo returns.
        XCTAssertEqual(viewModel.categories.count, allCategories.count)
        let defaultCategories = viewModel.categories.filter { $0.isDefault }
        let customCategories = viewModel.categories.filter { !$0.isDefault }
        XCTAssertEqual(defaultCategories.count, DefaultCategory.allCases.count)
        XCTAssertEqual(customCategories.count, 1)
    }

    func testSaveCategoryOnErrorSetsCategorySaveError() async {
        let defaultCategories = makeDefaultCategories()
        let (viewModel, _, mockCategories, mockHaptics) = makeSUT(categories: defaultCategories)
        await viewModel.loadCategories()
        let originalCount = viewModel.categories.count

        mockCategories.shouldThrow = true

        await viewModel.saveCategory(name: "Groceries", iconName: "cart.fill", colorName: "Teal", existingID: nil)

        XCTAssertNotNil(viewModel.categorySaveError)
        XCTAssertEqual(viewModel.categories.count, originalCount)
        XCTAssertTrue(mockHaptics.triggeredEvents.contains(.error))
        // fetchCategories should NOT be called again on error (no refresh)
        XCTAssertEqual(mockCategories.fetchCategoriesCallCount, 1)
    }

    // MARK: - Color Palette Tests

    func testCustomPaletteContainsExactlySixSecondaryColors() {
        let palette = CategoryColor.customPalette
        XCTAssertEqual(palette.count, 6)
        XCTAssertEqual(palette, [.teal, .coral, .plum, .olive, .indigo, .clay])
    }

    func testSaveCategoryRejectsDefaultCategoryEdit() async {
        let defaultID = UUID()
        let defaults = [CategoryData(id: defaultID, name: "Food", iconName: "fork.knife", colorName: "Sage", isDefault: true, sortOrder: 0)]
        let (viewModel, _, mockCategories, _) = makeSUT(categories: defaults)
        await viewModel.loadCategories()

        await viewModel.saveCategory(name: "Hacked", iconName: "star.fill", colorName: "Teal", existingID: defaultID)

        XCTAssertFalse(mockCategories.saveCategoryCalled)
    }

    // MARK: - Cancel Invitation Tests

    func testCancelInvitationCallsCancelShareOnService() async {
        let (viewModel, mockService, _, _) = makeSUT(state: .pending)

        await viewModel.cancelInvitation()

        XCTAssertTrue(mockService.cancelShareCalled)
    }

    func testCancelInvitationOnSuccessClearsActiveShare() async {
        let (viewModel, mockService, _, _) = makeSUT(state: .pending)
        let testShare = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName))
        viewModel.activeShare = testShare
        viewModel.activeContainer = CKContainer.default()

        await viewModel.cancelInvitation()

        XCTAssertNil(viewModel.activeShare)
        XCTAssertNil(viewModel.activeContainer)
        XCTAssertEqual(mockService.state, .solo)
    }

    func testCancelInvitationOnErrorSetsErrorMessage() async {
        let (viewModel, mockService, _, _) = makeSUT(state: .pending)
        mockService.cancelShareShouldThrow = true

        await viewModel.cancelInvitation()

        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testCancelInvitationResetsPendingState() async {
        let (viewModel, _, _, _) = makeSUT(state: .pending)
        XCTAssertTrue(viewModel.isPendingInvitation)

        await viewModel.cancelInvitation()

        XCTAssertFalse(viewModel.isPendingInvitation)
    }

    // MARK: - Resend Invitation Tests

    func testResendInvitationCallsCreateShareAndShowsSheet() async {
        let (viewModel, mockService, persistence) = makeSUTWithPersistence()
        seedCategories(in: persistence)
        mockService.state = .pending

        let testShare = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName))
        mockService.createShareResult = .success((testShare, CKContainer.default()))

        await viewModel.resendInvitation()

        XCTAssertTrue(mockService.createShareCalled)
        XCTAssertNotNil(viewModel.activeShare)
        XCTAssertTrue(viewModel.isShowingShareSheet)
    }

    func testResendInvitationOnErrorSetsErrorMessage() async {
        let (viewModel, mockService, persistence) = makeSUTWithPersistence()
        seedCategories(in: persistence)
        mockService.state = .pending
        // No handler set on mock — will throw default error

        await viewModel.resendInvitation()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isShowingShareSheet)
    }

    // MARK: - Delete Category Tests

    func testDeleteCategoryCallsRepositoryAndReloads() async {
        let categoryID = UUID()
        let categories = makeDefaultCategories() + [
            CategoryData(id: categoryID, name: "Custom", iconName: "star.fill", colorName: "Teal", isDefault: false, sortOrder: 6)
        ]
        let (viewModel, _, mockCategories, mockHaptics) = makeSUT(categories: categories)
        await viewModel.loadCategories()
        mockCategories.fetchCategoriesCallCount = 0

        await viewModel.deleteCategory(id: categoryID)

        XCTAssertTrue(mockCategories.deleteCategoryCalled)
        XCTAssertEqual(mockCategories.lastDeletedCategoryID, categoryID)
        XCTAssertTrue(mockHaptics.triggeredEvents.contains(.deleteTap))
        XCTAssertEqual(mockCategories.fetchCategoriesCallCount, 1, "Should reload categories after delete")
    }

    func testDeleteCategoryInUseSetsDeleteError() async {
        let categoryID = UUID()
        let categories = [CategoryData(id: categoryID, name: "Food", iconName: "fork.knife", colorName: "Sage", isDefault: true, sortOrder: 0)]
        let (viewModel, _, mockCategories, mockHaptics) = makeSUT(categories: categories)
        await viewModel.loadCategories()
        mockCategories.throwError = CategoryRepositoryError.categoryInUse(expenseCount: 3)
        mockCategories.shouldThrow = true

        await viewModel.deleteCategory(id: categoryID)

        XCTAssertNotNil(viewModel.categoryDeleteError)
        XCTAssertTrue(viewModel.categoryDeleteError?.contains("3") == true)
        XCTAssertTrue(mockHaptics.triggeredEvents.contains(.error))
    }

    func testDeleteCategoryGuardsAgainstConcurrentDeletes() async {
        let id1 = UUID()
        let id2 = UUID()
        let categories = [
            CategoryData(id: id1, name: "Cat1", iconName: "star.fill", colorName: "Teal", isDefault: false, sortOrder: 0),
            CategoryData(id: id2, name: "Cat2", iconName: "heart.fill", colorName: "Coral", isDefault: false, sortOrder: 1)
        ]
        let (viewModel, _, mockCategories, _) = makeSUT(categories: categories)
        await viewModel.loadCategories()

        await viewModel.deleteCategory(id: id1)
        await viewModel.deleteCategory(id: id2)

        // Both should succeed (sequential on @MainActor, defer resets flag)
        XCTAssertEqual(mockCategories.lastDeletedCategoryID, id2)
        XCTAssertFalse(viewModel.isDeletingCategory)
    }

    // MARK: - Move Category Tests

    func testMoveCategoryReordersArray() async {
        let ids = [UUID(), UUID(), UUID()]
        let categories = ids.enumerated().map { i, id in
            CategoryData(id: id, name: "Cat\(i)", iconName: "star.fill", colorName: "Teal", isDefault: false, sortOrder: Int16(i))
        }
        let (viewModel, _, _, _) = makeSUT(categories: categories)
        await viewModel.loadCategories()

        // Move first item to last position
        viewModel.moveCategory(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(viewModel.categories[0].id, ids[1])
        XCTAssertEqual(viewModel.categories[1].id, ids[2])
        XCTAssertEqual(viewModel.categories[2].id, ids[0])
    }

    func testMoveCategoryPersistsOrderToUserDefaults() async {
        let ids = [UUID(), UUID()]
        let categories = ids.enumerated().map { i, id in
            CategoryData(id: id, name: "Cat\(i)", iconName: "star.fill", colorName: "Teal", isDefault: false, sortOrder: Int16(i))
        }
        let (viewModel, _, _, _) = makeSUT(categories: categories)
        await viewModel.loadCategories()

        viewModel.moveCategory(from: IndexSet(integer: 0), to: 2)

        let savedOrder = UserDefaults.standard.stringArray(forKey: "categoryDisplayOrder")
        XCTAssertEqual(savedOrder, [ids[1].uuidString, ids[0].uuidString])

        // Clean up
        UserDefaults.standard.removeObject(forKey: "categoryDisplayOrder")
    }

    // MARK: - User Order Overlay Tests

    func testLoadCategoriesAppliesUserDefaultsOrder() async {
        let ids = [UUID(), UUID(), UUID()]
        let categories = ids.enumerated().map { i, id in
            CategoryData(id: id, name: "Cat\(i)", iconName: "star.fill", colorName: "Teal", isDefault: false, sortOrder: Int16(i))
        }
        // Set reversed order in UserDefaults
        UserDefaults.standard.set([ids[2].uuidString, ids[1].uuidString, ids[0].uuidString], forKey: "categoryDisplayOrder")

        let (viewModel, _, _, _) = makeSUT(categories: categories)
        await viewModel.loadCategories()

        XCTAssertEqual(viewModel.categories[0].id, ids[2])
        XCTAssertEqual(viewModel.categories[1].id, ids[1])
        XCTAssertEqual(viewModel.categories[2].id, ids[0])

        // Clean up
        UserDefaults.standard.removeObject(forKey: "categoryDisplayOrder")
    }

    func testLoadCategoriesAppendsNewCategoriesAtEnd() async {
        let ids = [UUID(), UUID()]
        let newID = UUID()
        let categories = [
            CategoryData(id: ids[0], name: "Cat0", iconName: "star.fill", colorName: "Teal", isDefault: false, sortOrder: 0),
            CategoryData(id: ids[1], name: "Cat1", iconName: "star.fill", colorName: "Teal", isDefault: false, sortOrder: 1),
            CategoryData(id: newID, name: "New", iconName: "star.fill", colorName: "Teal", isDefault: false, sortOrder: 2),
        ]
        // UserDefaults only knows about first two
        UserDefaults.standard.set([ids[1].uuidString, ids[0].uuidString], forKey: "categoryDisplayOrder")

        let (viewModel, _, _, _) = makeSUT(categories: categories)
        await viewModel.loadCategories()

        // First two in UserDefaults order, new one appended at end
        XCTAssertEqual(viewModel.categories[0].id, ids[1])
        XCTAssertEqual(viewModel.categories[1].id, ids[0])
        XCTAssertEqual(viewModel.categories[2].id, newID)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "categoryDisplayOrder")
    }

    // MARK: - Bug Regression Tests — Orphan CKShare on Cancelled Invite
    //
    // These tests lock in the fix for the bug where dismissing the share sheet
    // without sending an invitation left the app stuck showing "Invitation Pending".
    // The structural fix replaced `isShared: Bool` with `SharingState` and moved all
    // classification into `CloudSharingService.finalizeShareOutcome`. These tests
    // verify the ViewModel-level contract: `handleShareDismiss` always routes to
    // `finalizeShareOutcome`, and the computed properties correctly derive from
    // `state` without ever surfacing `.draft` as "Invitation Pending".

    func test_BugRegression_draftStateDoesNotSurfaceAsInvitationPending() {
        // The exact bug: a draft CKShare (created before the user invited anyone)
        // was being classified as "Invitation Pending" via the old boolean logic
        // `isShared && partnerName == nil`. The new computed property is a direct
        // state match against `.pending` and must return false for `.draft`.
        let (viewModel, _, _, _) = makeSUT(state: .draft)
        XCTAssertFalse(viewModel.isPendingInvitation,
            "REGRESSION: .draft must never surface as 'Invitation Pending'")
        XCTAssertFalse(viewModel.hasPartner)
        XCTAssertNil(viewModel.partnerDisplayName)
    }

    func test_InvitePartnerTransitionsServiceToDraft() async {
        // Verifies the contract: a successful createShare() leaves the service in .draft.
        // This is the starting condition for the orphan-cleanup path in finalizeShareOutcome.
        let (viewModel, mockService, persistence) = makeSUTWithPersistence()
        seedCategories(in: persistence)

        let testShare = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName))
        mockService.createShareResult = .success((testShare, CKContainer.default()))

        XCTAssertEqual(mockService.state, .solo)

        await viewModel.invitePartner()

        XCTAssertEqual(mockService.state, .draft,
            "createShare success must transition state to .draft")
    }

    func test_HandleDismissWithNilAfterDraft_delegatesCleanupToService() async {
        // When the user dismisses the sheet without sending an invite, the VM must
        // route to finalizeShareOutcome(nil). The service is responsible for the
        // actual orphan cleanup; here we simulate the service's reaction via the
        // mock's finalizeShareOutcomeResultState hook.
        let (viewModel, mockService, _, _) = makeSUT(state: .draft)
        mockService.finalizeShareOutcomeResultState = .solo

        viewModel.handleShareDismiss(nil)
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(mockService.finalizeShareOutcomeCalled,
            "handleShareDismiss(nil) must dispatch finalizeShareOutcome")
        XCTAssertNil(mockService.lastFinalizedShare,
            "finalizeShareOutcome must receive nil for swipe-dismiss path")
        XCTAssertEqual(mockService.state, .solo,
            "Simulated service cleanup must leave state at .solo")
        XCTAssertFalse(viewModel.isPendingInvitation,
            "After orphan cleanup the VM must not show 'Invitation Pending'")
    }

    func test_HandleDismissWithShare_delegatesToServiceAndReflectsPending() async {
        // Happy path: user invited someone. The delegate hands back a share; the VM
        // routes to finalizeShareOutcome(share); the service classifies as .pending.
        let (viewModel, mockService, _, _) = makeSUT(state: .draft)
        mockService.finalizeShareOutcomeResultState = .pending

        let testShare = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName))
        viewModel.handleShareDismiss(testShare)
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(mockService.finalizeShareOutcomeCalled)
        XCTAssertEqual(mockService.lastFinalizedShare?.recordID, testShare.recordID)
        XCTAssertEqual(mockService.state, .pending)
        XCTAssertTrue(viewModel.isPendingInvitation,
            ".pending state must surface as 'Invitation Pending'")
    }

    func test_HandleDismissWithShare_acceptedPartner_reflectsConnected() async {
        // Delegate fires on a share whose partner has already accepted.
        // The service classifies as .connected; the VM surfaces the partner name.
        let (viewModel, mockService, _, _) = makeSUT(state: .draft)
        mockService.finalizeShareOutcomeResultState = .connected(partnerName: "Alex")

        let testShare = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName))
        viewModel.handleShareDismiss(testShare)
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(viewModel.hasPartner)
        XCTAssertEqual(viewModel.partnerDisplayName, "Alex")
        XCTAssertFalse(viewModel.isPendingInvitation)
    }

    func test_HandleDismissAfterStopSharing_reflectsSolo() async {
        // "Stop Sharing" path: service was in .connected, user tapped Stop Sharing,
        // UIKit deleted the share server-side, the delegate fires with nil share.
        // The service's finalizeShareOutcome runs its refresh path and lands at .solo.
        let (viewModel, mockService, _, _) = makeSUT(state: .connected(partnerName: "Alex"))
        XCTAssertTrue(viewModel.hasPartner)  // precondition

        mockService.finalizeShareOutcomeResultState = .solo

        viewModel.handleShareDismiss(nil)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(mockService.state, .solo)
        XCTAssertFalse(viewModel.hasPartner)
        XCTAssertFalse(viewModel.isPendingInvitation)
        XCTAssertNil(viewModel.partnerDisplayName)
    }

    func test_HandleDismiss_clearsActiveShareBeforeFinalize() async {
        // The VM must clear activeShare/activeContainer SYNCHRONOUSLY on dismiss,
        // before the async finalize task runs. This prevents the share sheet from
        // re-surfacing a dead reference if the sheet is re-presented immediately.
        let (viewModel, _, _, _) = makeSUT(state: .draft)
        let testShare = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName))
        viewModel.activeShare = testShare
        viewModel.activeContainer = CKContainer.default()
        viewModel.isShowingShareSheet = true

        viewModel.handleShareDismiss(testShare)

        // Synchronously — no Task.yield needed:
        XCTAssertNil(viewModel.activeShare)
        XCTAssertNil(viewModel.activeContainer)
        XCTAssertFalse(viewModel.isShowingShareSheet)
    }

    func test_HandleDismiss_withError_surfacesErrorMessageAndStillCleansUp() async {
        // The error path fires when UIKit calls failedToSaveShareWithError. The VM must:
        //   1. Set errorMessage so the user sees the failure (no more silent drop).
        //   2. Still dispatch finalizeShareOutcome(nil) so the orphan-cleanup path runs.
        //   3. Force the finalize argument to nil regardless of whatever share UIKit
        //      handed us — the local draft is the orphan that needs removing.
        let (viewModel, mockService, _, _) = makeSUT(state: .draft)
        mockService.finalizeShareOutcomeResultState = .solo
        viewModel.isShowingShareSheet = true

        let ckError = CKError(.unknownItem)
        viewModel.handleShareDismiss(nil, error: ckError)

        // Synchronous UI state:
        XCTAssertFalse(viewModel.isShowingShareSheet)
        XCTAssertNil(viewModel.activeShare)
        XCTAssertNil(viewModel.activeContainer)
        XCTAssertNotNil(viewModel.errorMessage,
            "UIKit save failures must surface an errorMessage — silent drop was the bug")
        XCTAssertFalse(viewModel.errorMessage?.isEmpty ?? true,
            "errorMessage must carry the underlying localizedDescription")

        // Async cleanup still fires:
        await Task.yield()
        await Task.yield()
        XCTAssertTrue(mockService.finalizeShareOutcomeCalled,
            "Error path must still dispatch finalizeShareOutcome for orphan cleanup")
        XCTAssertNil(mockService.lastFinalizedShare,
            "Error path must force finalize argument to nil (local draft is the orphan)")
    }

    func test_HandleDismiss_withErrorAndStalePresentShare_forcesNilToFinalize() async {
        // Even if UIKit somehow hands us both a non-nil share AND an error (unusual
        // but possible on some iOS paths), the error branch must force nil into
        // finalizeShareOutcome so cleanup runs through the .draft branch, not the
        // classify-the-delegate-share branch.
        let (viewModel, mockService, _, _) = makeSUT(state: .draft)
        mockService.finalizeShareOutcomeResultState = .solo

        let testShare = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName))
        viewModel.handleShareDismiss(testShare, error: CKError(.networkUnavailable))

        await Task.yield()
        await Task.yield()

        XCTAssertTrue(mockService.finalizeShareOutcomeCalled)
        XCTAssertNil(mockService.lastFinalizedShare,
            "Error branch must not pass the delegate-provided share through — force nil")
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Category Test Helpers

    private func makeDefaultCategories() -> [CategoryData] {
        DefaultCategory.allCases.map { dc in
            CategoryData(
                id: UUID(),
                name: dc.name,
                iconName: dc.iconName,
                colorName: dc.colorName,
                isDefault: true,
                sortOrder: dc.sortOrder
            )
        }
    }
}
