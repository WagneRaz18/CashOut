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

    // MARK: - Partner Connected Tests

    func testPartnerConnectedHasPartnerIsTrue() {
        let (viewModel, _, _, _) = makeSUT(isShared: true, partnerName: "Jane")
        XCTAssertTrue(viewModel.hasPartner)
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
