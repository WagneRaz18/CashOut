import Foundation
import AuthenticationServices
import CloudKit
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "AuthenticationService")

// MARK: - Protocol

/// Protocol for authentication operations. NOTE: `isAuthenticated` is NOT on the protocol —
/// @Observable tracking does not propagate through protocol-typed references.
/// ViewModels own their own `isAuthenticated` state and update it after calling service methods.
@MainActor
protocol AuthenticationServiceProtocol {
    var currentUserID: String? { get }
    var onSessionInvalidated: [@MainActor @Sendable () -> Void] { get set }
    func checkCredentialState() async -> Bool
    func signIn() async throws
    func saveCredentials(userID: String, fullName: PersonNameComponents?, email: String?)
    func signOut()
}

// MARK: - Errors

enum AuthenticationError: Error, LocalizedError {
    case signInFailed(Error)
    case signInCancelled
    case credentialNotFound
    case unknownCredentialType

    var errorDescription: String? {
        switch self {
        case .signInFailed(let error):
            return "Sign in failed: \(error.localizedDescription)"
        case .signInCancelled:
            return "Sign in was cancelled"
        case .credentialNotFound:
            return "Apple ID credential not found"
        case .unknownCredentialType:
            return "Unsupported credential type"
        }
    }
}

// MARK: - AuthenticationService

@MainActor
@Observable
final class AuthenticationService: NSObject, AuthenticationServiceProtocol {

    static let shared = AuthenticationService()

    // MARK: - Public State

    private(set) var currentUserID: String?

    @ObservationIgnored
    var onSessionInvalidated: [@MainActor @Sendable () -> Void] = []

    // MARK: - Private State

    @ObservationIgnored
    private var signInContinuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    @ObservationIgnored
    private var revocationTask: Task<Void, Never>?

    @ObservationIgnored
    private var accountChangeTask: Task<Void, Never>?

    // MARK: - Keychain Constants

    private static let userIdentifierService = "com.wagneraz.CashOut.userIdentifier"
    private static let profileService = "com.wagneraz.CashOut.profile"
    private static let userIdentifierAccount = "appleUserIdentifier"
    private static let profileNameAccount = "appleProfileName"
    private static let profileEmailAccount = "appleProfileEmail"

    // MARK: - Init

    override init() {
        super.init()
        logger.debug("AuthenticationService.init — starting notification observers")
        startNotificationObservers()
    }

    // MARK: - Credential State Check (AC #4, #5, #6)

    func checkCredentialState() async -> Bool {
        logger.info("checkCredentialState: loading userID from Keychain")
        guard let userID = loadFromKeychain() else {
            logger.info("checkCredentialState: no userID in Keychain — not authenticated")
            currentUserID = nil
            return false
        }

        logger.debug("checkCredentialState: found userID in Keychain, checking Apple ID state")
        do {
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
            switch state {
            case .authorized:
                logger.info("checkCredentialState: authorized")
                currentUserID = userID
                return true
            case .revoked:
                // AC #5: Clear Keychain + profile, present sign-in
                logger.info("checkCredentialState: revoked — clearing Keychain")
                clearKeychain()
                clearProfileKeychain()
                currentUserID = nil
                return false
            case .notFound, .transferred:
                // AC #6: Present sign-in, no Keychain clearance
                logger.info("checkCredentialState: \(String(describing: state)) — presenting sign-in")
                currentUserID = nil
                return false
            @unknown default:
                logger.warning("checkCredentialState: unknown state — presenting sign-in")
                currentUserID = nil
                return false
            }
        } catch {
            logger.error("checkCredentialState: Apple ID check failed — \(error.localizedDescription)")
            currentUserID = nil
            return false
        }
    }

    // MARK: - Sign In (AC #2, #3)

    /// Programmatic sign-in via ASAuthorizationController (used when not triggered by SignInWithAppleButton)
    func signIn() async throws {
        guard signInContinuation == nil else {
            logger.warning("signIn: already in progress — rejecting duplicate call")
            throw AuthenticationError.signInFailed(
                NSError(domain: "AuthenticationService", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Sign-in already in progress"])
            )
        }

        logger.info("signIn: presenting ASAuthorizationController")

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        let credential: ASAuthorizationAppleIDCredential = try await withCheckedThrowingContinuation { continuation in
            self.signInContinuation = continuation
            controller.performRequests()
        }

        logger.info("signIn: credential received — saving")
        saveCredentials(
            userID: credential.user,
            fullName: credential.fullName,
            email: credential.email
        )
    }

    /// Save credentials from a completed authorization (used by SignInWithAppleButton flow)
    func saveCredentials(userID: String, fullName: PersonNameComponents?, email: String?) {
        logger.info("saveCredentials: userID present")
        // AC #2: Cache userIdentifier in Keychain
        saveToKeychain(userIdentifier: userID)
        currentUserID = userID

        // AC #3: Cache name/email on first sign-in (only non-nil on very first auth)
        let name: String? = [fullName?.givenName, fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
            .nilIfEmpty

        saveProfileToKeychain(name: name, email: email)
        logger.debug("saveCredentials: profile saved (hasName=\(name != nil), hasEmail=\(email != nil))")

        // Restart observers if they were cancelled by a prior signOut()
        restartObserversIfNeeded()
    }

    // MARK: - Sign Out (AC #7)

    func signOut() {
        logger.info("signOut: clearing credentials and cancelling observers")
        clearKeychain()
        clearProfileKeychain()
        currentUserID = nil
        revocationTask?.cancel()
        revocationTask = nil
        accountChangeTask?.cancel()
        accountChangeTask = nil
    }

    // MARK: - Notification Observers (AC #7, #8)

    private func restartObserversIfNeeded() {
        if revocationTask == nil || accountChangeTask == nil {
            logger.debug("Restarting notification observers")
            startNotificationObservers()
        }
    }

    private func startNotificationObservers() {
        // AC #7: Credential revocation mid-session
        revocationTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: ASAuthorizationAppleIDProvider.credentialRevokedNotification
            )
            for await _ in notifications {
                guard !Task.isCancelled else { break }
                logger.info("Credential revoked notification received — signing out")
                self?.signOut()
                self?.onSessionInvalidated.forEach { $0() }
            }
        }

        // AC #8: iCloud account change
        accountChangeTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: .CKAccountChanged
            )
            for await _ in notifications {
                guard !Task.isCancelled else { break }
                logger.info("CKAccountChanged received — clearing credentials")
                self?.clearKeychain()
                self?.clearProfileKeychain()
                self?.currentUserID = nil
                self?.onSessionInvalidated.forEach { $0() }
                // NOTE: PersistenceController.observeAccountChanges() runs in parallel
                // for persistence-side handling. No ordering guarantee between the two.
            }
        }
    }

    // MARK: - Keychain Helpers (Private)

    private func saveToKeychain(userIdentifier: String) {
        guard let data = userIdentifier.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.userIdentifierService,
            kSecAttrAccount as String: Self.userIdentifierAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Re-auth after revocation: update existing item
            let searchQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.userIdentifierService,
                kSecAttrAccount as String: Self.userIdentifierAccount
            ]
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            SecItemUpdate(searchQuery as CFDictionary, updateAttributes as CFDictionary)
        }
    }

    /// Internal for @testable access in unit tests
    func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.userIdentifierService,
            kSecAttrAccount as String: Self.userIdentifierAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func clearKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.userIdentifierService,
            kSecAttrAccount as String: Self.userIdentifierAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func saveProfileToKeychain(name: String?, email: String?) {
        if let name, let data = name.data(using: .utf8) {
            saveKeychainItem(
                service: Self.profileService,
                account: Self.profileNameAccount,
                data: data
            )
        }
        if let email, let data = email.data(using: .utf8) {
            saveKeychainItem(
                service: Self.profileService,
                account: Self.profileEmailAccount,
                data: data
            )
        }
    }

    /// Internal for @testable access in unit tests
    func loadProfileFromKeychain() -> (name: String?, email: String?)? {
        let name = loadKeychainItem(
            service: Self.profileService,
            account: Self.profileNameAccount
        )
        let email = loadKeychainItem(
            service: Self.profileService,
            account: Self.profileEmailAccount
        )
        guard name != nil || email != nil else { return nil }
        return (name: name, email: email)
    }

    private func clearProfileKeychain() {
        deleteKeychainItem(service: Self.profileService, account: Self.profileNameAccount)
        deleteKeychainItem(service: Self.profileService, account: Self.profileEmailAccount)
    }

    // MARK: - Generic Keychain Operations

    private func saveKeychainItem(service: String, account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let searchQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            SecItemUpdate(searchQuery as CFDictionary, updateAttributes as CFDictionary)
        }
    }

    private func loadKeychainItem(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychainItem(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - ASAuthorizationControllerDelegate (Task 5)

extension AuthenticationService: ASAuthorizationControllerDelegate {

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        MainActor.assumeIsolated {
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                signInContinuation?.resume(returning: credential)
                signInContinuation = nil
            } else {
                // ASPasswordCredential (iCloud Keychain autofill) — unsupported
                signInContinuation?.resume(throwing: AuthenticationError.unknownCredentialType)
                signInContinuation = nil
            }
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        MainActor.assumeIsolated {
            let authError = (error as? ASAuthorizationError)?.code == .canceled
                ? AuthenticationError.signInCancelled
                : AuthenticationError.signInFailed(error)
            signInContinuation?.resume(throwing: authError)
            signInContinuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding (Task 5)

extension AuthenticationService: ASAuthorizationControllerPresentationContextProviding {

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first!
            return windowScene.keyWindow ?? UIWindow(windowScene: windowScene)
        }
    }
}

// MARK: - String Extension

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
