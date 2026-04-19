import Foundation
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "FeedViewModel")

struct DateSection: Identifiable {
    let id: String
    let title: String
    let expenses: [ExpenseData]
}

@MainActor
@Observable
final class FeedViewModel {

    // MARK: - Observable Properties

    var expenses: [ExpenseData] = []
    var groupedExpenses: [DateSection] = []
    var categories: [CategoryData] = []
    var errorMessage: String?
    var syncStatus: SyncStatus = .healthy

    var isEmpty: Bool { expenses.isEmpty }

    // MARK: - Calendar & Formatting

    private static let calendar = Calendar(identifier: .gregorian)

    private static let sectionDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    // MARK: - Dependencies

    @ObservationIgnored
    private var repository: ExpenseRepositoryProtocol

    @ObservationIgnored
    private let categoryRepository: CategoryRepositoryProtocol

    @ObservationIgnored
    private let authService: AuthenticationServiceProtocol

    @ObservationIgnored
    private let householdService: HouseholdServiceProtocol

    @ObservationIgnored
    private let publicSync: PublicSyncServiceProtocol

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
        repository: ExpenseRepositoryProtocol = ExpenseRepository.shared,
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository.shared,
        authService: AuthenticationServiceProtocol = AuthenticationService.shared,
        householdService: HouseholdServiceProtocol = HouseholdService.shared,
        publicSync: PublicSyncServiceProtocol = PublicSyncService.shared,
        syncMonitorService: SyncMonitorServiceProtocol = SyncMonitorService.shared,
        hapticService: HapticServiceProtocol = HapticService.shared
    ) {
        self.repository = repository
        self.categoryRepository = categoryRepository
        self.authService = authService
        self.householdService = householdService
        self.publicSync = publicSync
        self.syncMonitorService = syncMonitorService
        self.hapticService = hapticService

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

        syncMonitorService.onSyncStatusChanged.append { [weak self] newStatus in
            logger.info("Sync status changed: \(String(describing: newStatus))")
            self?.syncStatus = newStatus
        }

        repository.onExpensesChanged = { [weak self] expenses in
            logger.info("onExpensesChanged: received \(expenses.count) expenses")
            self?.expenses = expenses
            self?.rebuildSections()
            self?.reloadCategories()
        }
        repository.startObservingExpenses()
        logger.info("startObserving: FRC observation started — \(self.expenses.count) initial expenses")
    }

    // MARK: - Manual Refresh

    /// Pull-to-refresh handler. The feed is always live against Core Data via FRC, so this is
    /// primarily a UX acknowledgment (haptic + minimum spinner dwell) plus a sharing-status
    /// nudge that prods CloudKit to reconcile any pending state. Live timestamps update
    /// automatically on the next `TimelineView` tick — no explicit clock bump needed.
    func refresh() async {
        logger.info("refresh: manual pull-to-refresh triggered")
        hapticService.trigger(.refresh)
        do {
            try await Task.sleep(nanoseconds: 400_000_000)
        } catch is CancellationError {
            logger.debug("refresh: cancelled during minimum dwell")
            return
        } catch {
            logger.error("refresh: unexpected sleep error — \(error.localizedDescription, privacy: .public)")
            return
        }
        // In the household-code model, refresh prods the public-DB sync service to
        // pull any changes the partner has made. Live timestamps update automatically
        // via TimelineView on the next tick — no explicit clock bump needed here.
        await publicSync.fetchChanges()
        logger.info("refresh: completed")
    }

    // MARK: - Category Lookup

    func categoryFor(_ expense: ExpenseData) -> CategoryData? {
        categories.first { $0.id == expense.categoryID }
    }

    // MARK: - Partner Attribution

    /// True iff the expense was created on THIS device (display names match, or the
    /// record predates the household-code model and has no display name attached).
    func isCurrentUser(_ expense: ExpenseData) -> Bool {
        // Legacy rows with no display name belong to this device by default —
        // they were created before pairing existed.
        guard !expense.createdByDisplayName.isEmpty else { return true }
        return expense.createdByDisplayName == householdService.displayName
    }

    func partnerInitials(for expense: ExpenseData) -> String {
        if isCurrentUser(expense) {
            return "Me"
        }
        let initial = expense.createdByDisplayName.prefix(1).uppercased()
        return initial.isEmpty ? "P" : initial
    }

    /// Display name to render for a NON-current-user expense. Falls back to "Partner"
    /// if the record was synced without an attribution.
    func partnerDisplayName(for expense: ExpenseData) -> String {
        expense.createdByDisplayName.isEmpty ? "Partner" : expense.createdByDisplayName
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
            logger.error("deleteExpense: failed — \(error.localizedDescription, privacy: .public)")
            errorMessage = "Could not delete expense. Please try again."
        }
    }

    // MARK: - Private

    private func rebuildSections() {
        let cal = Self.calendar
        let grouped = Dictionary(grouping: expenses) { expense in
            cal.startOfDay(for: expense.createdAt)
        }
        let sortedKeys = grouped.keys.sorted(by: >)
        groupedExpenses = sortedKeys.map { date in
            let title: String
            if cal.isDateInToday(date) {
                title = "Today"
            } else if cal.isDateInYesterday(date) {
                title = "Yesterday"
            } else {
                title = Self.sectionDateFormatter.string(from: date)
            }
            let sectionExpenses = grouped[date] ?? []
            let key = date.formatted(.iso8601.year().month().day())
            return DateSection(id: key, title: title, expenses: sectionExpenses)
        }
        logger.debug("rebuildSections: \(self.groupedExpenses.count) sections")
    }

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
                logger.error("reloadCategories: failed — \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }
}
