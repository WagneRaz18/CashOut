import Foundation
@testable import CashOut

@MainActor
final class MockAuthenticationService: AuthenticationServiceProtocol {

    // MARK: - Configurable Results

    var currentUserID: String?
    var onSessionInvalidated: (() -> Void)?
    var checkCredentialStateResult: Bool = false
    var signInShouldSucceed: Bool = true
    var signInError: Error = AuthenticationError.signInCancelled
    var signInUserID: String = "mock-user-id"

    // MARK: - Call Tracking

    var checkCredentialStateCalled = false
    var signInCalled = false
    var saveCredentialsCalled = false
    var signOutCalled = false
    var lastSavedUserID: String?

    // MARK: - Protocol Methods

    func checkCredentialState() async -> Bool {
        checkCredentialStateCalled = true
        if checkCredentialStateResult {
            currentUserID = signInUserID
        } else {
            currentUserID = nil
        }
        return checkCredentialStateResult
    }

    func signIn() async throws {
        signInCalled = true
        if signInShouldSucceed {
            currentUserID = signInUserID
        } else {
            throw signInError
        }
    }

    func saveCredentials(userID: String, fullName: PersonNameComponents?, email: String?) {
        saveCredentialsCalled = true
        lastSavedUserID = userID
        currentUserID = userID
    }

    func signOut() {
        signOutCalled = true
        currentUserID = nil
    }
}
