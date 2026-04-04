import Foundation

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

    // MARK: - Observable Properties

    var selectedPeriod: TimePeriod = .weekly
    var totalAmount: Int64 = 0
    var previousPeriodTotal: Int64?
    var categoryTotals: [CategoryTotal] = []
    var chartSlices: [ChartSlice] = []
    var barEntries: [BarEntry] = []
    var selectedCategoryID: UUID?
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

    // MARK: - Guard State

    @ObservationIgnored
    private var loadedPeriod: TimePeriod?

    // MARK: - Init

    init(
        repository: ExpenseRepositoryProtocol = ExpenseRepository(),
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository(),
        authService: AuthenticationServiceProtocol = AuthenticationService(),
        syncMonitorService: SyncMonitorServiceProtocol = SyncMonitorService.shared
    ) {
        self.repository = repository
        self.categoryRepository = categoryRepository
        self.authService = authService
        self.syncMonitorService = syncMonitorService

        self.syncMonitorService.onSyncStatusChanged = { [weak self] newStatus in
            self?.syncStatus = newStatus
        }
        self.syncStatus = syncMonitorService.syncStatus
    }

    // MARK: - Data Loading

    func loadData() async {
        guard loadedPeriod != selectedPeriod else { return }
        await performLoad()
    }

    func invalidateAndReload() async {
        loadedPeriod = nil
        await performLoad()
    }

    func selectCategory(_ categoryID: UUID?) {
        selectedCategoryID = categoryID
    }

    func subscribeToRemoteChanges() async {
        // Catch-up fetch for notifications missed while tab was hidden
        await invalidateAndReload()

        for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
            guard !Task.isCancelled else { break }
            await invalidateAndReload()
        }
    }

    // MARK: - Private

    private func performLoad() async {
        let period = selectedPeriod
        let now = Date()
        let currentInterval = dateInterval(for: period, referenceDate: now)
        let previousInterval = previousDateInterval(for: period, referenceDate: now)

        do {
            let currentExpenses = try await repository.fetchExpenses(for: currentInterval)
            guard !Task.isCancelled else { return }

            let previousExpenses = try await repository.fetchExpenses(for: previousInterval)
            guard !Task.isCancelled else { return }

            let categories = try await categoryRepository.fetchCategories()
            guard !Task.isCancelled else { return }

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
        } catch {
            guard !Task.isCancelled else { return }
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
        let calendar = Calendar.current

        switch period {
        case .daily:
            let total = expenses.reduce(Int64(0)) { $0 + $1.amount }
            return [BarEntry(label: "Today", total: total)]

        case .weekly:
            var entries: [BarEntry] = []
            var date = interval.start
            while date < interval.end {
                let dayTotal = expenses
                    .filter { calendar.isDate($0.createdAt, inSameDayAs: date) }
                    .reduce(Int64(0)) { $0 + $1.amount }
                entries.append(BarEntry(label: Self.weekdayFormatter.string(from: date), total: dayTotal))
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? interval.end
            }
            return entries

        case .monthly:
            guard let range = calendar.range(of: .weekOfMonth, in: .month, for: interval.start) else {
                return []
            }

            var weeklyTotals: [Int: Int64] = [:]
            for expense in expenses {
                let weekNum = calendar.component(.weekOfMonth, from: expense.createdAt)
                weeklyTotals[weekNum, default: 0] += expense.amount
            }

            return range.map { week in
                BarEntry(label: "W\(week)", total: weeklyTotals[week, default: 0])
            }
        }
    }

    // MARK: - Date Interval Helpers

    // Safe: .day/.weekOfYear/.month always produce a valid interval for any Date
    private func dateInterval(for period: TimePeriod, referenceDate: Date) -> DateInterval {
        Calendar.current.dateInterval(of: period.calendarComponent, for: referenceDate)!
    }

    // Safe: calendar arithmetic on .day/.weekOfYear/.month never returns nil
    private func previousDateInterval(for period: TimePeriod, referenceDate: Date) -> DateInterval {
        let previousDate = Calendar.current.date(byAdding: period.calendarComponent, value: -1, to: referenceDate)!
        return dateInterval(for: period, referenceDate: previousDate)
    }
}
