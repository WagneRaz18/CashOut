import XCTest
@testable import CashOut

final class AuthenticationViewModelTests: XCTestCase {

    // MARK: - checkAuth Tests

    @MainActor
    func testCheckAuthDelegatesToService() async {
        let mock = MockAuthenticationService()
        let viewModel = AuthenticationViewModel(authService: mock)

        await viewModel.checkAuth()

        XCTAssertTrue(mock.checkCredentialStateCalled, "Should delegate to service")
    }

    @MainActor
    func testCheckAuthWithValidCredentialSetsAuthenticated() async {
        let mock = MockAuthenticationService()
        mock.checkCredentialStateResult = true
        let viewModel = AuthenticationViewModel(authService: mock)

        await viewModel.checkAuth()

        XCTAssertTrue(viewModel.isAuthenticated, "Should be authenticated with valid credential")
        XCTAssertFalse(viewModel.isCheckingCredentials, "Should not be checking credentials")
        XCTAssertFalse(viewModel.showSignIn, "Should not show sign-in")
    }

    @MainActor
    func testCheckAuthWithNoCredentialShowsSignIn() async {
        let mock = MockAuthenticationService()
        mock.checkCredentialStateResult = false
        let viewModel = AuthenticationViewModel(authService: mock)

        await viewModel.checkAuth()

        XCTAssertFalse(viewModel.isAuthenticated, "Should not be authenticated")
        XCTAssertFalse(viewModel.isCheckingCredentials, "Should not be checking credentials")
        XCTAssertTrue(viewModel.showSignIn, "Should show sign-in")
    }

    @MainActor
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

    @MainActor
    func testPerformSignInSuccessUpdatesState() async {
        let mock = MockAuthenticationService()
        mock.signInShouldSucceed = true
        let viewModel = AuthenticationViewModel(authService: mock)

        await viewModel.performSignIn()

        XCTAssertTrue(mock.signInCalled, "Should call signIn on service")
        XCTAssertTrue(viewModel.isAuthenticated, "Should be authenticated after sign-in")
        XCTAssertNil(viewModel.errorMessage, "Should have no error message")
    }

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
    func testFailSignInErrorShowsMessage() {
        let viewModel = AuthenticationViewModel(
            authService: MockAuthenticationService()
        )

        viewModel.failSignIn(cancelled: false, message: "Network error")

        XCTAssertFalse(viewModel.isAuthenticated, "Should remain unauthenticated")
        XCTAssertEqual(viewModel.errorMessage, "Network error", "Should show error message")
    }

    // MARK: - Session Invalidation Tests (AC #7, #8)

    @MainActor
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

    // MARK: - Initial State

    @MainActor
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
