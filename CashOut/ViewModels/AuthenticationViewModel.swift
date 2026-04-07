import Foundation
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "AuthenticationViewModel")

@MainActor
@Observable
final class AuthenticationViewModel {

    // MARK: - Public State

    var isAuthenticated: Bool = false
    var isCheckingCredentials: Bool = true
    var errorMessage: String?

    /// Computed — never store as separate Bool (redundant state causes sync bugs)
    var showSignIn: Bool { !isAuthenticated && !isCheckingCredentials }

    /// Forwarded from service for downstream use (e.g., createdByUserID attribution)
    var currentUserID: String? { authService.currentUserID }

    // MARK: - Dependencies

    @ObservationIgnored
    private var authService: AuthenticationServiceProtocol

    // MARK: - Guards

    @ObservationIgnored
    private var hasCheckedAuth = false

    // MARK: - Init

    init(authService: AuthenticationServiceProtocol = AuthenticationService.shared) {
        self.authService = authService
        logger.debug("AuthenticationViewModel.init")
    }

    // MARK: - Session Invalidation (AC #7, #8)

    private func handleSessionInvalidated() {
        logger.info("Session invalidated — resetting auth state")
        isAuthenticated = false
        isCheckingCredentials = false
        errorMessage = nil
    }

    // MARK: - Actions

    /// Check cached credential state on launch. Guarded against re-firing
    /// (.task in TabView re-fires on every appear).
    func checkAuth() async {
        guard !hasCheckedAuth else {
            logger.debug("checkAuth: already checked — skipped")
            return
        }
        hasCheckedAuth = true
        isCheckingCredentials = true

        authService.onSessionInvalidated.append { [weak self] in
            self?.handleSessionInvalidated()
        }

        logger.info("checkAuth: checking cached credential state")
        let authorized = await authService.checkCredentialState()
        guard !Task.isCancelled else { return }

        isAuthenticated = authorized
        isCheckingCredentials = false
        logger.info("checkAuth: result — authenticated=\(authorized)")
    }

    /// Trigger Sign in with Apple flow (programmatic path via ASAuthorizationController)
    func performSignIn() async {
        logger.info("performSignIn: starting Sign in with Apple flow")
        errorMessage = nil
        do {
            try await authService.signIn()
            guard !Task.isCancelled else { return }
            logger.info("performSignIn: success")
            isAuthenticated = true
        } catch let error as AuthenticationError {
            guard !Task.isCancelled else { return }
            logger.error("performSignIn: AuthenticationError — \(error.localizedDescription)")
            switch error {
            case .signInCancelled:
                errorMessage = "CloudKit requires authentication to sync your data"
            default:
                errorMessage = error.localizedDescription
            }
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("performSignIn: unexpected error — \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Handle successful sign-in from SignInWithAppleButton
    func completeSignIn(userID: String, fullName: PersonNameComponents?, email: String?) {
        logger.info("completeSignIn: userID present")
        errorMessage = nil
        authService.saveCredentials(userID: userID, fullName: fullName, email: email)
        isAuthenticated = true
    }

    /// Handle sign-in failure from SignInWithAppleButton
    func failSignIn(cancelled: Bool, message: String) {
        logger.error("failSignIn: cancelled=\(cancelled), message=\(message)")
        if cancelled {
            errorMessage = "CloudKit requires authentication to sync your data"
        } else {
            errorMessage = message
        }
    }
}
