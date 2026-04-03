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

    // MARK: - Observable Properties

    var selectedPeriod: TimePeriod = .weekly
    var totalAmount: Int64 = 0
    var previousPeriodTotal: Int64?
    var categoryTotals: [CategoryTotal] = []
    var errorMessage: String?

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

    var emptyStateText: String { "No entries this \(selectedPeriod.emptyStateLabel)" }

    // MARK: - Dependencies

    private let repository: ExpenseRepositoryProtocol

    private let categoryRepository: CategoryRepositoryProtocol

    // MARK: - Guard State

    @ObservationIgnored
    private var loadedPeriod: TimePeriod?

    // MARK: - Init

    init(
        repository: ExpenseRepositoryProtocol = ExpenseRepository(),
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository()
    ) {
        self.repository = repository
        self.categoryRepository = categoryRepository
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

            totalAmount = currentExpenses.reduce(Int64(0)) { $0 + $1.amount }

            var grouped: [UUID: Int64] = [:]
            for expense in currentExpenses {
                grouped[expense.categoryID, default: 0] += expense.amount
            }
            categoryTotals = grouped
                .map { CategoryTotal(categoryID: $0.key, total: $0.value) }
                .sorted { $0.total > $1.total }

            previousPeriodTotal = previousExpenses.isEmpty ? nil : previousExpenses.reduce(Int64(0)) { $0 + $1.amount }

            errorMessage = nil
            loadedPeriod = period
        } catch {
            guard !Task.isCancelled else { return }
            totalAmount = 0
            categoryTotals = []
            previousPeriodTotal = nil
            errorMessage = error.localizedDescription
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
