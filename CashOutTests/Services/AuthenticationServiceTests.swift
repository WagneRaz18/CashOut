import XCTest
import AuthenticationServices
@testable import CashOut

final class AuthenticationServiceTests: XCTestCase {

    // MARK: - Keychain Tests

    @MainActor
    func testCheckCredentialStateWithNoKeychainEntry() async throws {
        let service = AuthenticationService()
        // Ensure clean state
        service.signOut()

        let result = await service.checkCredentialState()

        XCTAssertFalse(result, "Should return false when no Keychain entry exists")
        XCTAssertNil(service.currentUserID, "currentUserID should be nil")
    }

    @MainActor
    func testSignOutClearsKeychainAndState() async throws {
        let service = AuthenticationService()

        service.signOut()

        XCTAssertNil(service.currentUserID, "currentUserID should be nil after sign out")
        XCTAssertNil(
            service.loadFromKeychain(),
            "Keychain should be cleared after sign out"
        )
        XCTAssertNil(
            service.loadProfileFromKeychain(),
            "Profile Keychain should be cleared after sign out"
        )
    }

    // MARK: - Notification Tests

    @MainActor
    func testCKAccountChangedClearsState() async throws {
        let service = AuthenticationService()
        // Seed non-nil state so we verify the handler actually clears it
        service.saveCredentials(userID: "test-user", fullName: nil, email: nil)
        XCTAssertNotNil(service.currentUserID, "Precondition: should have userID")

        // Yield to let observer Tasks start their async iteration
        await Task.yield()

        NotificationCenter.default.post(name: .CKAccountChanged, object: nil)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertNil(service.currentUserID, "currentUserID should be nil after CKAccountChanged")
        XCTAssertNil(
            service.loadFromKeychain(),
            "Keychain should be cleared after CKAccountChanged"
        )
    }

    @MainActor
    func testCredentialRevokedNotificationClearsState() async throws {
        let service = AuthenticationService()
        // Seed non-nil state so we verify the handler actually clears it
        service.saveCredentials(userID: "test-user", fullName: nil, email: nil)
        XCTAssertNotNil(service.currentUserID, "Precondition: should have userID")

        // Yield to let observer Tasks start their async iteration
        await Task.yield()

        NotificationCenter.default.post(
            name: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil
        )
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertNil(service.currentUserID, "currentUserID should be nil after revocation")
        XCTAssertNil(
            service.loadFromKeychain(),
            "Keychain should be cleared after revocation"
        )
    }

    // MARK: - Session Invalidation Callback Tests

    @MainActor
    func testCKAccountChangedCallsSessionInvalidated() async throws {
        let service = AuthenticationService()
        var callbackCalled = false
        service.onSessionInvalidated = { callbackCalled = true }

        // Yield to let observer Tasks start their async iteration
        await Task.yield()

        NotificationCenter.default.post(name: .CKAccountChanged, object: nil)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(callbackCalled, "onSessionInvalidated should fire on CKAccountChanged")
    }

    @MainActor
    func testCredentialRevokedCallsSessionInvalidated() async throws {
        let service = AuthenticationService()
        var callbackCalled = false
        service.onSessionInvalidated = { callbackCalled = true }

        // Yield to let observer Tasks start their async iteration
        await Task.yield()

        NotificationCenter.default.post(
            name: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil
        )
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(callbackCalled, "onSessionInvalidated should fire on credential revocation")
    }
}
