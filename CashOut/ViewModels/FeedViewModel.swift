import Foundation
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "FeedViewModel")

@MainActor
@Observable
final class FeedViewModel {

    // MARK: - Observable Properties

    var expenses: [ExpenseData] = []
    var categories: [CategoryData] = []
    var errorMessage: String?
    var syncStatus: SyncStatus = .healthy

    var isEmpty: Bool { expenses.isEmpty }

    // MARK: - Dependencies

    @ObservationIgnored
    private var repository: ExpenseRepositoryProtocol

    @ObservationIgnored
    private let categoryRepository: CategoryRepositoryProtocol

    @ObservationIgnored
    private let authService: AuthenticationServiceProtocol

    @ObservationIgnored
    private let cloudSharingService: CloudSharingServiceProtocol

    @ObservationIgnored
    private var syncMonitorService: SyncMonitorServiceProtocol

    @ObservationIgnored
    private let hapticService: HapticServiceProtocol

    @ObservationIgnored
    private var isObserving = false

    @ObservationIgnored
    private var categoryTask: Task<Void, Never>?

    // MARK: - Init

    init(
        repository: ExpenseRepositoryProtocol = ExpenseRepository(),
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository(),
        authService: AuthenticationServiceProtocol = AuthenticationService(),
        cloudSharingService: CloudSharingServiceProtocol = CloudSharingService.shared,
        syncMonitorService: SyncMonitorServiceProtocol = SyncMonitorService.shared,
        hapticService: HapticServiceProtocol = HapticService()
    ) {
        self.repository = repository
        self.categoryRepository = categoryRepository
        self.authService = authService
        self.cloudSharingService = cloudSharingService
        self.syncMonitorService = syncMonitorService
        self.hapticService = hapticService

        self.syncMonitorService.onSyncStatusChanged.append { [weak self] newStatus in
            logger.info("Sync status changed: \(String(describing: newStatus))")
            self?.syncStatus = newStatus
        }
        self.syncStatus = syncMonitorService.syncStatus
        logger.debug("FeedViewModel.init — syncStatus: \(String(describing: self.syncStatus))")
    }

    // MARK: - Observation

    func startObserving() {
        guard !isObserving else {
            logger.debug("startObserving: already observing — skipped")
            return
        }
        logger.info("startObserving: setting up FRC observation")
        isObserving = true

        repository.onExpensesChanged = { [weak self] expenses in
            logger.info("onExpensesChanged: received \(expenses.count) expenses")
            self?.expenses = expenses
            self?.reloadCategories()
        }
        repository.startObservingExpenses()
        logger.info("startObserving: FRC observation started — \(self.expenses.count) initial expenses")
    }

    // MARK: - Category Lookup

    func categoryFor(_ expense: ExpenseData) -> CategoryData? {
        categories.first { $0.id == expense.categoryID }
    }

    // MARK: - Partner Attribution

    func isCurrentUser(_ expense: ExpenseData) -> Bool {
        // Treat unattributed expenses (empty createdByUserID) as current user's
        guard !expense.createdByUserID.isEmpty else { return true }
        guard let currentUserID = authService.currentUserID else { return true }
        return expense.createdByUserID == currentUserID
    }

    func partnerInitials(for expense: ExpenseData) -> String {
        if isCurrentUser(expense) {
            return "Me"
        }
        // Use real partner name from CloudSharingService
        if let name = cloudSharingService.partnerName {
            let initial = name.prefix(1).uppercased()
            return initial.isEmpty ? "P" : initial
        }
        return "P"
    }

    var partnerDisplayName: String {
        cloudSharingService.partnerName ?? "Partner"
    }

    // MARK: - Delete

    func deleteExpense(_ expense: ExpenseData) async {
        logger.info("deleteExpense: deleting id=\(expense.id)")
        do {
            try await repository.deleteExpense(id: expense.id)
            guard !Task.isCancelled else { return }
            logger.info("deleteExpense: success")
            hapticService.trigger(.deleteTap)
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("deleteExpense: failed — \(error.localizedDescription)")
            errorMessage = "Could not delete expense. Please try again."
        }
    }

    // MARK: - Private

    private func reloadCategories() {
        logger.debug("reloadCategories: starting category fetch")
        categoryTask?.cancel()
        categoryTask = Task {
            do {
                let fetched = try await categoryRepository.fetchCategories()
                guard !Task.isCancelled else {
                    logger.debug("reloadCategories: cancelled after fetch")
                    return
                }
                logger.debug("reloadCategories: fetched \(fetched.count) categories")
                categories = fetched
            } catch {
                guard !Task.isCancelled else {
                    logger.debug("reloadCategories: cancelled during error handling")
                    return
                }
                logger.error("reloadCategories: failed — \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }
}
