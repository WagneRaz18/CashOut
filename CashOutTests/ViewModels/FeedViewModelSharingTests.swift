import XCTest
@testable import CashOut

@MainActor
final class FeedViewModelSharingTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeSUT(
        currentUserID: String? = "test-user",
        partnerName: String? = nil,
        isShared: Bool = false
    ) -> (
        viewModel: FeedViewModel,
        cloudSharingService: MockCloudSharingService
    ) {
        let expenseRepo = MockExpenseRepository()
        let categoryRepo = MockCategoryRepository()
        let authService = MockAuthenticationService()
        let cloudSharingService = MockCloudSharingService()
        let hapticService = MockHapticService()

        authService.currentUserID = currentUserID
        cloudSharingService.partnerName = partnerName
        cloudSharingService.isShared = isShared

        let viewModel = FeedViewModel(
            repository: expenseRepo,
            categoryRepository: categoryRepo,
            authService: authService,
            cloudSharingService: cloudSharingService,
            hapticService: hapticService
        )

        return (viewModel, cloudSharingService)
    }

    private func makeExpense(
        createdByUserID: String = "partner-456"
    ) -> ExpenseData {
        ExpenseData(
            id: UUID(),
            amount: 1250,
            note: nil,
            categoryID: UUID(),
            createdByUserID: createdByUserID,
            createdAt: Date(),
            modifiedAt: Date()
        )
    }

    // MARK: - partnerInitials Tests

    func testPartnerInitialsReturnsMeForCurrentUser() {
        let (viewModel, _) = makeSUT(currentUserID: "user-123")
        let expense = makeExpense(createdByUserID: "user-123")

        XCTAssertEqual(
            viewModel.partnerInitials(for: expense), "Me",
            "partnerInitials should return 'Me' for current user's expenses"
        )
    }

    func testPartnerInitialsReturnsFirstInitialOfPartnerName() {
        let (viewModel, _) = makeSUT(
            currentUserID: "user-123",
            partnerName: "Sarah"
        )
        let expense = makeExpense(createdByUserID: "partner-456")

        XCTAssertEqual(
            viewModel.partnerInitials(for: expense), "S",
            "partnerInitials should return first initial of partner name"
        )
    }

    func testPartnerInitialsReturnsPWhenPartnerNameIsNil() {
        let (viewModel, _) = makeSUT(
            currentUserID: "user-123",
            partnerName: nil
        )
        let expense = makeExpense(createdByUserID: "partner-456")

        XCTAssertEqual(
            viewModel.partnerInitials(for: expense), "P",
            "partnerInitials should return 'P' when partnerName is nil"
        )
    }

    // MARK: - partnerDisplayName Tests

    func testPartnerDisplayNameReturnsRealNameWhenAvailable() {
        let (viewModel, _) = makeSUT(partnerName: "Sarah")

        XCTAssertEqual(
            viewModel.partnerDisplayName, "Sarah",
            "partnerDisplayName should return real name when available"
        )
    }

    func testPartnerDisplayNameReturnsPartnerWhenNameIsNil() {
        let (viewModel, _) = makeSUT(partnerName: nil)

        XCTAssertEqual(
            viewModel.partnerDisplayName, "Partner",
            "partnerDisplayName should return 'Partner' when name is nil"
        )
    }
}
