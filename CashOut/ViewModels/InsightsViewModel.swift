import Foundation
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "InsightsViewModel")

@MainActor
@Observable
final class InsightsViewModel {

    // MARK: - Types

    enum TimePeriod: String, CaseIterable {
        case daily = "Day"
        case weekly = "Week"
        case monthly = "Month"

        var currentPeriodLabel: String {
            switch self {
            case .daily: "Today"
            case .weekly: "This Week"
            case .monthly: "This Month"
            }
        }

        var previousPeriodLabel: String {
            switch self {
            case .daily: "yesterday"
            case .weekly: "last week"
            case .monthly: "last month"
            }
        }

        var emptyStateLabel: String {
            switch self {
            case .daily: "day"
            case .weekly: "week"
            case .monthly: "month"
            }
        }

        fileprivate var calendarComponent: Calendar.Component {
            switch self {
            case .daily: .day
            case .weekly: .weekOfYear
            case .monthly: .month
            }
        }
    }

    struct CategoryTotal: Identifiable, Sendable {
        let categoryID: UUID
        let total: Int64
        var id: UUID { categoryID }
    }

    struct ChartSlice: Identifiable, Sendable {
        let categoryID: UUID
        let categoryName: String
        let colorName: String
        let iconName: String
        let total: Int64
        var id: UUID { categoryID }
    }

    struct BarEntry: Identifiable, Sendable {
        let label: String
        let total: Int64
        var id: String { label }
    }

    struct CategoryNavDestination: Hashable {
        let categoryID: UUID
        let interval: DateInterval
    }

    // MARK: - Observable Properties

    var selectedPeriod: TimePeriod = .weekly
    var totalAmount: Int64 = 0
    var previousPeriodTotal: Int64?
    var categoryTotals: [CategoryTotal] = []
    var chartSlices: [ChartSlice] = []
    var barEntries: [BarEntry] = []
    var selectedDestination: CategoryNavDestination?
    private(set) var currentPeriodInterval: DateInterval?
    private(set) var fetchedCategories: [CategoryData] = []
    var errorMessage: String?
    var syncStatus: SyncStatus = .healthy

    // MARK: - Computed Properties

    var isEmpty: Bool { totalAmount == 0 && categoryTotals.isEmpty }

    var headlineText: String { totalAmount.displayAmount }

    var periodLabel: String { selectedPeriod.currentPeriodLabel }

    var comparisonText: String? {
        guard let previous = previousPeriodTotal else { return nil }
        let difference = totalAmount - previous
        if difference > 0 {
            return "\(difference.displayAmount) more than \(selectedPeriod.previousPeriodLabel)"
        } else if difference < 0 {
            return "\((-difference).displayAmount) less than \(selectedPeriod.previousPeriodLabel)"
        } else {
            return "Same as \(selectedPeriod.previousPeriodLabel)"
        }
    }

    var currentUserID: String? { authService.currentUserID }

    var emptyStateText: String { "No entries this \(selectedPeriod.emptyStateLabel)" }

    var barChartAccessibilityLabel: String {
        guard !barEntries.isEmpty else { return "No spending data" }
        return barEntries.map { "\($0.label): \($0.total.displayAmount)" }.joined(separator: ". ")
    }

    var chartAccessibilityLabel: String {
        guard let largest = chartSlices.first else {
            return "No entries this \(selectedPeriod.emptyStateLabel)"
        }
        return "This \(selectedPeriod.emptyStateLabel) total: \(totalAmount.displayAmount). Largest category: \(largest.categoryName) at \(largest.total.displayAmount)."
    }

    // MARK: - Dependencies

    private let repository: ExpenseRepositoryProtocol

    private let categoryRepository: CategoryRepositoryProtocol

    private let authService: AuthenticationServiceProtocol

    @ObservationIgnored
    private var syncMonitorService: SyncMonitorServiceProtocol

    // MARK: - Calendar

    private static let calendar = Calendar(identifier: .gregorian)

    // MARK: - Guard State

    @ObservationIgnored
    private var loadedPeriod: TimePeriod?

    @ObservationIgnored
    private var isSubscribed = false

    // MARK: - Init

    init(
        repository: ExpenseRepositoryProtocol = ExpenseRepository.shared,
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository.shared,
        authService: AuthenticationServiceProtocol = AuthenticationService.shared,
        syncMonitorService: SyncMonitorServiceProtocol = SyncMonitorService.shared
    ) {
        self.repository = repository
        self.categoryRepository = categoryRepository
        self.authService = authService
        self.syncMonitorService = syncMonitorService

        self.syncStatus = syncMonitorService.syncStatus
    }

    // MARK: - Data Loading

    func loadData() async {
        guard loadedPeriod != selectedPeriod else {
            logger.debug("loadData: period \(self.selectedPeriod.rawValue) already loaded — skipped")
            return
        }
        logger.info("loadData: loading period \(self.selectedPeriod.rawValue)")
        await performLoad()
    }

    func invalidateAndReload() async {
        logger.debug("invalidateAndReload: resetting for fresh load")
        loadedPeriod = nil
        await performLoad()
    }

    func selectCategory(_ categoryID: UUID?) {
        guard let categoryID, let interval = currentPeriodInterval else {
            selectedDestination = nil
            return
        }
        logger.debug("selectCategory: \(categoryID)")
        selectedDestination = CategoryNavDestination(categoryID: categoryID, interval: interval)
    }

    func subscribeToRemoteChanges() async {
        guard !isSubscribed else {
            logger.debug("subscribeToRemoteChanges: already subscribed — skipped")
            return
        }
        isSubscribed = true
        logger.debug("subscribeToRemoteChanges: starting listener")

        syncMonitorService.onSyncStatusChanged.append { [weak self] newStatus in
            logger.info("Sync status changed: \(String(describing: newStatus))")
            self?.syncStatus = newStatus
        }

        // Catch-up fetch for notifications missed while tab was hidden
        await invalidateAndReload()

        for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
            guard !Task.isCancelled else { break }
            logger.info("Remote change received — reloading insights")
            await invalidateAndReload()
        }
    }

    // MARK: - Private

    private func performLoad() async {
        let period = selectedPeriod
        let now = Date()
        let currentInterval = dateInterval(for: period, referenceDate: now)
        let previousInterval = previousDateInterval(for: period, referenceDate: now)

        logger.debug("performLoad: period=\(period.rawValue), interval=\(currentInterval.start) — \(currentInterval.end)")

        do {
            let currentExpenses = try await repository.fetchExpenses(for: currentInterval)
            guard !Task.isCancelled else { return }

            let previousExpenses = try await repository.fetchExpenses(for: previousInterval)
            guard !Task.isCancelled else { return }

            let categories = try await categoryRepository.fetchCategories()
            guard !Task.isCancelled else { return }

            logger.info("performLoad: \(currentExpenses.count) current, \(previousExpenses.count) previous, \(categories.count) categories")

            totalAmount = currentExpenses.reduce(Int64(0)) { $0 + $1.amount }

            var grouped: [UUID: Int64] = [:]
            for expense in currentExpenses {
                grouped[expense.categoryID, default: 0] += expense.amount
            }
            categoryTotals = grouped
                .map { CategoryTotal(categoryID: $0.key, total: $0.value) }
                .sorted { $0.total > $1.total }

            fetchedCategories = categories

            let categoryMap: [UUID: CategoryData] = Dictionary(
                categories.map { ($0.id, $0) },
                uniquingKeysWith: { _, last in last }
            )
            chartSlices = categoryTotals.map { ct in
                let category = categoryMap[ct.categoryID]
                return ChartSlice(
                    categoryID: ct.categoryID,
                    categoryName: category?.name ?? "Unknown",
                    colorName: category?.colorName ?? "CoolGray",
                    iconName: category?.iconName ?? "ellipsis.circle.fill",
                    total: ct.total
                )
            }

            barEntries = computeBarEntries(from: currentExpenses, period: period, interval: currentInterval)

            previousPeriodTotal = previousExpenses.isEmpty ? nil : previousExpenses.reduce(Int64(0)) { $0 + $1.amount }

            currentPeriodInterval = currentInterval
            errorMessage = nil
            loadedPeriod = period
            logger.info("performLoad: complete — total=\(self.totalAmount) satang, \(self.categoryTotals.count) categories")
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("performLoad: FAILED — \(error.localizedDescription)")
            totalAmount = 0
            categoryTotals = []
            chartSlices = []
            barEntries = []
            fetchedCategories = []
            previousPeriodTotal = nil
            currentPeriodInterval = nil
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Bar Entry Computation

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private func computeBarEntries(from expenses: [ExpenseData], period: TimePeriod, interval: DateInterval) -> [BarEntry] {
        let cal = Self.calendar

        switch period {
        case .daily:
            let total = expenses.reduce(Int64(0)) { $0 + $1.amount }
            return [BarEntry(label: "Today", total: total)]

        case .weekly:
            var entries: [BarEntry] = []
            var date = interval.start
            while date < interval.end {
                let dayTotal = expenses
                    .filter { cal.isDate($0.createdAt, inSameDayAs: date) }
                    .reduce(Int64(0)) { $0 + $1.amount }
                entries.append(BarEntry(label: Self.weekdayFormatter.string(from: date), total: dayTotal))
                date = cal.date(byAdding: .day, value: 1, to: date) ?? interval.end
            }
            return entries

        case .monthly:
            guard let range = cal.range(of: .weekOfMonth, in: .month, for: interval.start) else {
                return []
            }

            var weeklyTotals: [Int: Int64] = [:]
            for expense in expenses {
                let weekNum = cal.component(.weekOfMonth, from: expense.createdAt)
                weeklyTotals[weekNum, default: 0] += expense.amount
            }

            return range.map { week in
                BarEntry(label: "W\(week)", total: weeklyTotals[week, default: 0])
            }
        }
    }

    // MARK: - Date Interval Helpers

    // Uses Gregorian calendar — should never return nil, but defends against it with logged fallback
    private func dateInterval(for period: TimePeriod, referenceDate: Date) -> DateInterval {
        if let interval = Self.calendar.dateInterval(of: period.calendarComponent, for: referenceDate) {
            return interval
        }
        logger.fault("Gregorian dateInterval returned nil for \(period.rawValue)")
        return DateInterval(start: referenceDate, duration: 86400)
    }

    private func previousDateInterval(for period: TimePeriod, referenceDate: Date) -> DateInterval {
        if let previousDate = Self.calendar.date(byAdding: period.calendarComponent, value: -1, to: referenceDate) {
            return dateInterval(for: period, referenceDate: previousDate)
        }
        logger.fault("Gregorian date(byAdding:) returned nil for \(period.rawValue)")
        return dateInterval(for: period, referenceDate: referenceDate.addingTimeInterval(-86400))
    }
}
