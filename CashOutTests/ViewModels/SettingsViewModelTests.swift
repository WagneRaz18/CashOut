import XCTest
import CloudKit
@preconcurrency import CoreData
@testable import CashOut

@MainActor
final class SettingsViewModelTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeSUT(
        isShared: Bool = false,
        partnerName: String? = nil
    ) -> (viewModel: SettingsViewModel, mockService: MockCloudSharingService) {
        let mockService = MockCloudSharingService()
        mockService.isShared = isShared
        mockService.partnerName = partnerName

        let viewModel = SettingsViewModel(cloudSharingService: mockService)
        return (viewModel, mockService)
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
        let (viewModel, _) = makeSUT(isShared: false)
        XCTAssertFalse(viewModel.hasPartner)
    }

    func testSoloModePartnerDisplayNameIsNil() {
        let (viewModel, _) = makeSUT(isShared: false)
        XCTAssertNil(viewModel.partnerDisplayName)
    }

    // MARK: - Partner Connected Tests

    func testPartnerConnectedHasPartnerIsTrue() {
        let (viewModel, _) = makeSUT(isShared: true, partnerName: "Jane")
        XCTAssertTrue(viewModel.hasPartner)
    }

    func testPartnerConnectedDisplaysPartnerName() {
        let (viewModel, _) = makeSUT(isShared: true, partnerName: "Jane Smith")
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
        let (viewModel, mockService) = makeSUT()

        await viewModel.refreshSharingStatus()

        XCTAssertTrue(mockService.checkSharingStatusCalled)
    }

    // MARK: - Handle Share Dismiss Tests

    func testHandleDismissWithShareCallsPersistAndRefresh() {
        let (viewModel, mockService) = makeSUT()
        viewModel.isShowingShareSheet = true

        let testShare = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName))
        viewModel.handleShareDismiss(testShare)

        XCTAssertTrue(mockService.persistUpdatedShareCalled)
        XCTAssertFalse(viewModel.isShowingShareSheet)
    }

    func testHandleDismissWithNilDoesNotCallPersist() {
        let (viewModel, mockService) = makeSUT()
        viewModel.isShowingShareSheet = true

        viewModel.handleShareDismiss(nil)

        XCTAssertFalse(mockService.persistUpdatedShareCalled)
        XCTAssertFalse(viewModel.isShowingShareSheet)
    }
}
