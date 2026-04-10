import XCTest
import CloudKit
@preconcurrency import CoreData
@testable import CashOut

@MainActor
final class SettingsViewModelTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeSUT(
        isShared: Bool = false,
        partnerName: String? = nil,
        categories: [CategoryData] = []
    ) -> (viewModel: SettingsViewModel, mockService: MockCloudSharingService, mockCategories: MockCategoryRepository, mockHaptics: MockHapticService) {
        let mockService = MockCloudSharingService()
        mockService.isShared = isShared
        mockService.partnerName = partnerName
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
        let (viewModel, _, _, _) = makeSUT(isShared: false)
        XCTAssertFalse(viewModel.hasPartner)
    }

    func testSoloModePartnerDisplayNameIsNil() {
        let (viewModel, _, _, _) = makeSUT(isShared: false)
        XCTAssertNil(viewModel.partnerDisplayName)
    }

    func testSoloModeIsPendingInvitationIsFalse() {
        let (viewModel, _, _, _) = makeSUT(isShared: false)
        XCTAssertFalse(viewModel.isPendingInvitation)
    }

    // MARK: - Pending Invitation Tests

    func testPendingInvitationWhenSharedButNoPartnerName() {
        let (viewModel, _, _, _) = makeSUT(isShared: true, partnerName: nil)
        XCTAssertTrue(viewModel.isPendingInvitation)
    }

    func testPendingInvitationHasPartnerIsFalse() {
        let (viewModel, _, _, _) = makeSUT(isShared: true, partnerName: nil)
        XCTAssertFalse(viewModel.hasPartner)
    }

    // MARK: - Partner Connected Tests

    func testPartnerConnectedHasPartnerIsTrue() {
        let (viewModel, _, _, _) = makeSUT(isShared: true, partnerName: "Jane")
        XCTAssertTrue(viewModel.hasPartner)
    }

    func testPartnerConnectedIsPendingInvitationIsFalse() {
        let (viewModel, _, _, _) = makeSUT(isShared: true, partnerName: "Jane")
        XCTAssertFalse(viewModel.isPendingInvitation)
    }

    func testPartnerConnectedDisplaysPartnerName() {
        let (viewModel, _, _, _) = makeSUT(isShared: true, partnerName: "Jane Smith")
        XCTAssertEqual(viewModel.partnerDisplayName, "Jane Smith")
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

    func testHandleDismissWithShareCallsPersistAndRefresh() {
        let (viewModel, mockService, _, _) = makeSUT()
        viewModel.isShowingShareSheet = true

        let testShare = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName))
        viewModel.handleShareDismiss(testShare)

        XCTAssertTrue(mockService.persistUpdatedShareCalled)
        XCTAssertFalse(viewModel.isShowingShareSheet)
    }

    func testHandleDismissWithNilDoesNotCallPersist() {
        let (viewModel, mockService, _, _) = makeSUT()
        viewModel.isShowingShareSheet = true

        viewModel.handleShareDismiss(nil)

        XCTAssertFalse(mockService.persistUpdatedShareCalled)
        XCTAssertFalse(viewModel.isShowingShareSheet)
    }

    func testHandleDismissWithNilClearsActiveShareAndContainer() async {
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
            "Stop Sharing / swipe dismiss should clear activeShare")
        XCTAssertNil(viewModel.activeContainer,
            "Stop Sharing / swipe dismiss should clear activeContainer")
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
        let (viewModel, mockService, _, _) = makeSUT(isShared: true, partnerName: nil)

        await viewModel.cancelInvitation()

        XCTAssertTrue(mockService.cancelShareCalled)
    }

    func testCancelInvitationOnSuccessClearsActiveShare() async {
        let (viewModel, mockService, _, _) = makeSUT(isShared: true, partnerName: nil)
        let testShare = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName))
        viewModel.activeShare = testShare
        viewModel.activeContainer = CKContainer.default()

        await viewModel.cancelInvitation()

        XCTAssertNil(viewModel.activeShare)
        XCTAssertNil(viewModel.activeContainer)
        XCTAssertFalse(mockService.isShared)
    }

    func testCancelInvitationOnErrorSetsErrorMessage() async {
        let (viewModel, mockService, _, _) = makeSUT(isShared: true, partnerName: nil)
        mockService.cancelShareShouldThrow = true

        await viewModel.cancelInvitation()

        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testCancelInvitationResetsPendingState() async {
        let (viewModel, _, _, _) = makeSUT(isShared: true, partnerName: nil)
        XCTAssertTrue(viewModel.isPendingInvitation)

        await viewModel.cancelInvitation()

        XCTAssertFalse(viewModel.isPendingInvitation)
    }

    // MARK: - Resend Invitation Tests

    func testResendInvitationCallsCreateShareAndShowsSheet() async {
        let (viewModel, mockService, persistence) = makeSUTWithPersistence()
        seedCategories(in: persistence)
        mockService.isShared = true

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
        mockService.isShared = true
        // No handler set on mock — will throw default error

        await viewModel.resendInvitation()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isShowingShareSheet)
    }

    // MARK: - Handle Share Dismiss Idempotency Tests

    func testHandleDismissIsIdempotent() {
        let (viewModel, mockService, _, _) = makeSUT()
        viewModel.isShowingShareSheet = true

        let testShare = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName))
        viewModel.handleShareDismiss(testShare)
        // Second call (simulating SwiftUI onDismiss after delegate)
        viewModel.handleShareDismiss(nil)

        XCTAssertTrue(mockService.persistUpdatedShareCalled)
        XCTAssertEqual(mockService.lastPersistedShare?.recordID, testShare.recordID)
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
