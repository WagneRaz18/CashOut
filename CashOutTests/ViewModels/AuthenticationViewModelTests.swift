import XCTest
@testable import CashOut

@MainActor
final class AuthenticationViewModelTests: XCTestCase {

    // MARK: - checkAuth Tests

    func testCheckAuthDelegatesToService() async {
        let mock = MockAuthenticationService()
        let viewModel = AuthenticationViewModel(authService: mock)

        await viewModel.checkAuth()

        XCTAssertTrue(mock.checkCredentialStateCalled, "Should delegate to service")
    }

    func testCheckAuthWithValidCredentialSetsAuthenticated() async {
        let mock = MockAuthenticationService()
        mock.checkCredentialStateResult = true
        let viewModel = AuthenticationViewModel(authService: mock)

        await viewModel.checkAuth()

        XCTAssertTrue(viewModel.isAuthenticated, "Should be authenticated with valid credential")
        XCTAssertFalse(viewModel.isCheckingCredentials, "Should not be checking credentials")
        XCTAssertFalse(viewModel.showSignIn, "Should not show sign-in")
    }

    func testCheckAuthWithNoCredentialShowsSignIn() async {
        let mock = MockAuthenticationService()
        mock.checkCredentialStateResult = false
        let viewModel = AuthenticationViewModel(authService: mock)

        await viewModel.checkAuth()

        XCTAssertFalse(viewModel.isAuthenticated, "Should not be authenticated")
        XCTAssertFalse(viewModel.isCheckingCredentials, "Should not be checking credentials")
        XCTAssertTrue(viewModel.showSignIn, "Should show sign-in")
    }

    func testCheckAuthDoesNotRefire() async {
        let mock = MockAuthenticationService()
        mock.checkCredentialStateResult = true
        let viewModel = AuthenticationViewModel(authService: mock)

        await viewModel.checkAuth()
        mock.checkCredentialStateCalled = false // Reset

        await viewModel.checkAuth() // Second call

        XCTAssertFalse(
            mock.checkCredentialStateCalled,
            "Should not re-check credentials on second call"
        )
    }

    // MARK: - performSignIn Tests

    func testPerformSignInSuccessUpdatesState() async {
        let mock = MockAuthenticationService()
        mock.signInShouldSucceed = true
        let viewModel = AuthenticationViewModel(authService: mock)

        await viewModel.performSignIn()

        XCTAssertTrue(mock.signInCalled, "Should call signIn on service")
        XCTAssertTrue(viewModel.isAuthenticated, "Should be authenticated after sign-in")
        XCTAssertNil(viewModel.errorMessage, "Should have no error message")
    }

    func testPerformSignInFailurePreservesUnauthenticated() async {
        let mock = MockAuthenticationService()
        mock.signInShouldSucceed = false
        mock.signInError = AuthenticationError.signInFailed(
            NSError(domain: "test", code: -1)
        )
        let viewModel = AuthenticationViewModel(authService: mock)

        await viewModel.performSignIn()

        XCTAssertTrue(mock.signInCalled, "Should attempt signIn")
        XCTAssertFalse(viewModel.isAuthenticated, "Should remain unauthenticated on failure")
        XCTAssertNotNil(viewModel.errorMessage, "Should have error message")
    }

    func testPerformSignInCancelledShowsExplanation() async {
        let mock = MockAuthenticationService()
        mock.signInShouldSucceed = false
        mock.signInError = AuthenticationError.signInCancelled
        let viewModel = AuthenticationViewModel(authService: mock)

        await viewModel.performSignIn()

        XCTAssertFalse(viewModel.isAuthenticated, "Should remain unauthenticated on cancel")
        XCTAssertEqual(
            viewModel.errorMessage,
            "CloudKit requires authentication to sync your data",
            "Should show CloudKit explanation on cancel"
        )
    }

    // MARK: - currentUserID forwarding

    func testCurrentUserIDForwardsFromService() async {
        let mock = MockAuthenticationService()
        mock.signInUserID = "test-user-123"
        mock.signInShouldSucceed = true
        let viewModel = AuthenticationViewModel(authService: mock)

        await viewModel.performSignIn()

        XCTAssertEqual(
            viewModel.currentUserID,
            "test-user-123",
            "Should forward currentUserID from service"
        )
    }

    // MARK: - completeSignIn Tests (SignInWithAppleButton flow)

    func testCompleteSignInSavesCredentialsAndSetsAuthenticated() {
        let mock = MockAuthenticationService()
        let viewModel = AuthenticationViewModel(authService: mock)

        viewModel.completeSignIn(userID: "apple-user-456", fullName: nil, email: nil)

        XCTAssertTrue(mock.saveCredentialsCalled, "Should call saveCredentials on service")
        XCTAssertEqual(mock.lastSavedUserID, "apple-user-456", "Should save correct userID")
        XCTAssertTrue(viewModel.isAuthenticated, "Should be authenticated after completeSignIn")
        XCTAssertNil(viewModel.errorMessage, "Should clear error message")
    }

    // MARK: - failSignIn Tests

    func testFailSignInCancelledShowsExplanation() {
        let viewModel = AuthenticationViewModel(
            authService: MockAuthenticationService()
        )

        viewModel.failSignIn(cancelled: true, message: "User cancelled")

        XCTAssertFalse(viewModel.isAuthenticated, "Should remain unauthenticated")
        XCTAssertEqual(
            viewModel.errorMessage,
            "CloudKit requires authentication to sync your data",
            "Should show CloudKit explanation on cancel"
        )
    }

    func testFailSignInErrorShowsMessage() {
        let viewModel = AuthenticationViewModel(
            authService: MockAuthenticationService()
        )

        viewModel.failSignIn(cancelled: false, message: "Network error")

        XCTAssertFalse(viewModel.isAuthenticated, "Should remain unauthenticated")
        XCTAssertEqual(viewModel.errorMessage, "Network error", "Should show error message")
    }

    // MARK: - Session Invalidation Tests (AC #7, #8)

    func testSessionInvalidatedResetsAuthState() async {
        let mock = MockAuthenticationService()
        mock.checkCredentialStateResult = true
        let viewModel = AuthenticationViewModel(authService: mock)

        // Authenticate first
        await viewModel.checkAuth()
        XCTAssertTrue(viewModel.isAuthenticated, "Should be authenticated")

        // Simulate service-side session invalidation via callback
        mock.onSessionInvalidated.forEach { $0() }

        XCTAssertFalse(viewModel.isAuthenticated, "Should be unauthenticated after session invalidated")
        XCTAssertFalse(viewModel.isCheckingCredentials, "Should not be checking credentials")
        XCTAssertTrue(viewModel.showSignIn, "Should show sign-in after session invalidated")
        XCTAssertNil(viewModel.errorMessage, "Should have no error message after session invalidated")
    }

    // MARK: - signOut Tests

    func testSignOutCallsServiceSignOut() async {
        let mockAuth = MockAuthenticationService()
        mockAuth.checkCredentialStateResult = true
        let viewModel = AuthenticationViewModel(authService: mockAuth)

        await viewModel.checkAuth()
        viewModel.signOut()

        XCTAssertTrue(mockAuth.signOutCalled, "Should call signOut on auth service")
    }

    func testSignOutStopsSyncMonitoring() {
        let mockSync = MockSyncMonitorService()
        let viewModel = AuthenticationViewModel(
            authService: MockAuthenticationService(),
            syncMonitorService: mockSync
        )

        viewModel.signOut()

        XCTAssertTrue(mockSync.stopMonitoringCalled, "Should stop sync monitoring on sign-out")
    }

    func testSignOutStopsExpenseObservation() {
        let mockRepo = MockExpenseRepository()
        let viewModel = AuthenticationViewModel(
            authService: MockAuthenticationService(),
            expenseRepository: mockRepo
        )

        viewModel.signOut()

        XCTAssertTrue(mockRepo.stopObservingCalled, "Should stop expense observation on sign-out")
    }

    func testSignOutResetsCloudSharingState() {
        let mockSharing = MockCloudSharingService()
        mockSharing.state = .connected(partnerName: "Partner")
        mockSharing.isShareOwner = true
        let viewModel = AuthenticationViewModel(
            authService: MockAuthenticationService(),
            cloudSharingService: mockSharing
        )

        viewModel.signOut()

        XCTAssertTrue(mockSharing.resetStateCalled, "Should reset cloud sharing state on sign-out")
        XCTAssertEqual(mockSharing.state, .solo, "Sharing state should return to .solo")
        XCTAssertFalse(mockSharing.isShareOwner, "Share owner state should be cleared")
    }

    func testSignOutSetsIsAuthenticatedFalse() async {
        let mockAuth = MockAuthenticationService()
        mockAuth.checkCredentialStateResult = true
        let viewModel = AuthenticationViewModel(authService: mockAuth)

        await viewModel.checkAuth()
        XCTAssertTrue(viewModel.isAuthenticated, "Should be authenticated before sign-out")

        viewModel.signOut()

        XCTAssertFalse(viewModel.isAuthenticated, "Should not be authenticated after sign-out")
        XCTAssertTrue(viewModel.showSignIn, "Should show sign-in after sign-out")
    }

    func testSignOutClearsErrorMessage() {
        let viewModel = AuthenticationViewModel(
            authService: MockAuthenticationService()
        )
        viewModel.failSignIn(cancelled: false, message: "Some error")
        XCTAssertNotNil(viewModel.errorMessage, "Should have error before sign-out")

        viewModel.signOut()

        XCTAssertNil(viewModel.errorMessage, "Should clear error message on sign-out")
    }

    // MARK: - Initial State

    func testInitialState() {
        let viewModel = AuthenticationViewModel(
            authService: MockAuthenticationService()
        )

        XCTAssertFalse(viewModel.isAuthenticated, "Should start unauthenticated")
        XCTAssertTrue(viewModel.isCheckingCredentials, "Should start checking credentials")
        XCTAssertFalse(viewModel.showSignIn, "Should not show sign-in while checking")
        XCTAssertNil(viewModel.errorMessage, "Should have no error initially")
    }
}
