import XCTest
@testable import CashOut

@MainActor
final class FeedViewModelSharingTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeSUT(
        currentUserID: String? = "test-user",
        state: SharingState = .solo
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
        cloudSharingService.state = state

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
            state: .connected(partnerName: "Sarah")
        )
        let expense = makeExpense(createdByUserID: "partner-456")

        XCTAssertEqual(
            viewModel.partnerInitials(for: expense), "S",
            "partnerInitials should return first initial of partner name"
        )
    }

    func testPartnerInitialsReturnsPWhenConnectedWithNilName() {
        // Connected state but partner's name couldn't be resolved from userIdentity.
        // The view-layer fallback "P" kicks in.
        let (viewModel, _) = makeSUT(
            currentUserID: "user-123",
            state: .connected(partnerName: nil)
        )
        let expense = makeExpense(createdByUserID: "partner-456")

        XCTAssertEqual(
            viewModel.partnerInitials(for: expense), "P",
            "partnerInitials should return 'P' when connected but name is nil"
        )
    }

    func testPartnerInitialsReturnsPWhenSolo() {
        let (viewModel, _) = makeSUT(
            currentUserID: "user-123",
            state: .solo
        )
        let expense = makeExpense(createdByUserID: "partner-456")

        XCTAssertEqual(
            viewModel.partnerInitials(for: expense), "P",
            "partnerInitials should return 'P' when not connected"
        )
    }

    // MARK: - partnerDisplayName Tests

    func testPartnerDisplayNameReturnsRealNameWhenConnected() {
        let (viewModel, _) = makeSUT(state: .connected(partnerName: "Sarah"))

        XCTAssertEqual(
            viewModel.partnerDisplayName, "Sarah",
            "partnerDisplayName should return real name when connected"
        )
    }

    func testPartnerDisplayNameReturnsPartnerWhenConnectedWithNilName() {
        let (viewModel, _) = makeSUT(state: .connected(partnerName: nil))

        XCTAssertEqual(
            viewModel.partnerDisplayName, "Partner",
            "partnerDisplayName should return fallback 'Partner' when name is nil"
        )
    }

    func testPartnerDisplayNameReturnsPartnerWhenSolo() {
        let (viewModel, _) = makeSUT(state: .solo)

        XCTAssertEqual(
            viewModel.partnerDisplayName, "Partner",
            "partnerDisplayName should return fallback 'Partner' in solo mode"
        )
    }
}
