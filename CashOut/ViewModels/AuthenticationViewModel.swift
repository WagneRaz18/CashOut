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

    @ObservationIgnored
    private var syncMonitorService: SyncMonitorServiceProtocol

    @ObservationIgnored
    private var householdService: HouseholdServiceProtocol

    @ObservationIgnored
    private var publicSync: PublicSyncServiceProtocol

    @ObservationIgnored
    private var expenseRepository: ExpenseRepositoryProtocol

    // MARK: - Guards

    @ObservationIgnored
    private var hasCheckedAuth = false

    @ObservationIgnored
    private var hasBootstrappedSync = false

    // MARK: - Init

    init(
        authService: AuthenticationServiceProtocol = AuthenticationService.shared,
        syncMonitorService: SyncMonitorServiceProtocol = SyncMonitorService.shared,
        householdService: HouseholdServiceProtocol = HouseholdService.shared,
        publicSync: PublicSyncServiceProtocol = PublicSyncService.shared,
        expenseRepository: ExpenseRepositoryProtocol = ExpenseRepository.shared
    ) {
        self.authService = authService
        self.syncMonitorService = syncMonitorService
        self.householdService = householdService
        self.publicSync = publicSync
        self.expenseRepository = expenseRepository
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

    /// Bootstraps the household-code sync path on app launch. Registers CloudKit
    /// subscriptions and pulls any changes the partner made while offline. Guarded so
    /// repeated `.task` invocations (TabView re-appearance) are cheap. Separated from
    /// `checkAuth` so the ContentView does not import services directly — business
    /// logic stays in the ViewModel.
    func bootstrapSyncIfPaired() async {
        guard !hasBootstrappedSync else {
            logger.debug("bootstrapSyncIfPaired: already bootstrapped — skipped")
            return
        }
        hasBootstrappedSync = true

        syncMonitorService.startMonitoring()
        guard householdService.isPaired else {
            logger.info("bootstrapSyncIfPaired: not paired — skipped public-DB init")
            return
        }
        logger.info("bootstrapSyncIfPaired: registering subscriptions and fetching changes")
        await publicSync.registerSubscriptions()
        await publicSync.fetchChanges()
        logger.info("bootstrapSyncIfPaired: complete")
    }

    /// Re-fetches on iCloud account change. Exposed here so ContentView's listener does
    /// not need to reach into PublicSyncService directly.
    func refetchOnAccountChange() async {
        guard householdService.isPaired else { return }
        logger.info("refetchOnAccountChange: refetching public DB changes")
        await publicSync.fetchChanges()
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

    /// User-initiated sign out — clears credentials and resets all session state.
    /// Household pairing is preserved across sign-out: the user's household code
    /// represents a device-level pairing, not an auth-session property.
    func signOut() {
        logger.info("signOut: user-initiated sign out")
        syncMonitorService.stopMonitoring()
        expenseRepository.stopObservingExpenses()
        authService.signOut()
        isAuthenticated = false
        isCheckingCredentials = false
        errorMessage = nil
        logger.info("signOut: complete — showing sign-in")
    }
}
