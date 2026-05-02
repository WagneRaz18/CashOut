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
        let position: Int
        let label: String
        let dateLabel: String?
        let total: Int64
        var id: Int { position }

        init(position: Int, label: String, total: Int64, dateLabel: String? = nil) {
            self.position = position
            self.label = label
            self.dateLabel = dateLabel
            self.total = total
        }
    }

    struct CategoryNavDestination: Hashable {
        let categoryID: UUID
        let interval: DateInterval
    }

    // MARK: - Observable Properties

    var selectedPeriod: TimePeriod = .weekly
    var dateOffset: Int = 0
    var isLoading: Bool = false
    var totalAmount: Int64 = 0
    var previousPeriodTotal: Int64?
    var categoryTotals: [CategoryTotal] = []
    var chartSlices: [ChartSlice] = []
    var barEntries: [BarEntry] = []
    var dailyTotals: [Date: Int64] = [:]
    var selectedDestination: CategoryNavDestination?
    private(set) var currentPeriodInterval: DateInterval?
    private(set) var fetchedCategories: [CategoryData] = []
    var errorMessage: String?
    var syncStatus: SyncStatus = .healthy

    // Ephemeral filter — never persisted, reset on every data load and tab appear.
    var excludedCategories: Set<UUID> = []

    // MARK: - Computed Properties

    var isEmpty: Bool { totalAmount == 0 && categoryTotals.isEmpty }

    // Bridge for .task(id:) — period + offset uniquely identify each data slice.
    var loadKey: String { "\(selectedPeriod.rawValue)-\(dateOffset)" }

    var canNavigateForward: Bool { dateOffset < 0 }

    var viewedMonthStart: Date {
        currentPeriodInterval?.start
            ?? Self.calendar.dateInterval(of: .month, for: Date())?.start
            ?? Date()
    }

    var visibleChartSlices: [ChartSlice] {
        chartSlices.filter { !excludedCategories.contains($0.categoryID) }
    }

    var filteredTotalAmount: Int64 {
        visibleChartSlices.reduce(Int64(0)) { $0 + $1.total }
    }

    var headlineText: String { filteredTotalAmount.displayAmount }

    var periodLabel: String {
        guard dateOffset != 0 else { return selectedPeriod.currentPeriodLabel }
        guard let shifted = Self.calendar.date(byAdding: selectedPeriod.calendarComponent, value: dateOffset, to: Date()),
              let interval = Self.calendar.dateInterval(of: selectedPeriod.calendarComponent, for: shifted) else {
            return selectedPeriod.currentPeriodLabel
        }
        switch selectedPeriod {
        case .daily:
            if dateOffset == -1 { return "Yesterday" }
            return Self.mediumDateFormatter.string(from: interval.start)
        case .weekly:
            if dateOffset == -1 { return "Last Week" }
            let lastDay = Self.calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return "\(Self.mediumDateFormatter.string(from: interval.start)) – \(Self.mediumDateFormatter.string(from: lastDay))"
        case .monthly:
            if dateOffset == -1 { return "Last Month" }
            return Self.monthYearFormatter.string(from: interval.start)
        }
    }

    var comparisonText: String? {
        guard dateOffset == 0 else { return nil }
        guard excludedCategories.isEmpty else { return nil }
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
        return barEntries.map { entry in
            let prefix = entry.dateLabel.map { "\(entry.label) (\($0))" } ?? entry.label
            return "\(prefix): \(entry.total.displayAmount)"
        }.joined(separator: ". ")
    }

    var chartAccessibilityLabel: String {
        guard let largest = visibleChartSlices.first else {
            return "No entries this \(selectedPeriod.emptyStateLabel)"
        }
        return "This \(selectedPeriod.emptyStateLabel) total: \(filteredTotalAmount.displayAmount). Largest category: \(largest.categoryName) at \(largest.total.displayAmount)."
    }

    // MARK: - Dependencies

    private let repository: ExpenseRepositoryProtocol
    private let categoryRepository: CategoryRepositoryProtocol
    private let authService: AuthenticationServiceProtocol
    private let hapticService: HapticServiceProtocol

    @ObservationIgnored
    private var syncMonitorService: SyncMonitorServiceProtocol

    // MARK: - Calendar

    private static let calendar = Calendar.gregorian

    // MARK: - Guard State

    @ObservationIgnored
    private var loadedPeriod: TimePeriod?

    @ObservationIgnored
    private var loadedOffset: Int?

    @ObservationIgnored
    private var isSubscribed = false

    @ObservationIgnored
    private var hasRegisteredSyncCallback = false

    @ObservationIgnored
    private var loadTask: Task<Void, Never>?

    // MARK: - Init

    init(
        repository: ExpenseRepositoryProtocol = ExpenseRepository.shared,
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository.shared,
        authService: AuthenticationServiceProtocol = AuthenticationService.shared,
        syncMonitorService: SyncMonitorServiceProtocol = SyncMonitorService.shared,
        hapticService: HapticServiceProtocol = HapticService.shared
    ) {
        self.repository = repository
        self.categoryRepository = categoryRepository
        self.authService = authService
        self.syncMonitorService = syncMonitorService
        self.hapticService = hapticService
        self.syncStatus = syncMonitorService.syncStatus
    }

    // MARK: - Data Loading

    func loadData() async {
        guard loadedPeriod != selectedPeriod || loadedOffset != dateOffset else {
            logger.debug("loadData: period=\(self.selectedPeriod.rawValue) offset=\(self.dateOffset) already loaded — skipped")
            return
        }
        logger.info("loadData: loading period=\(self.selectedPeriod.rawValue) offset=\(self.dateOffset)")
        loadTask?.cancel()
        let task = Task { await self.performLoad() }
        loadTask = task
        await task.value
    }

    func invalidateAndReload() async {
        logger.debug("invalidateAndReload: resetting for fresh load")
        loadedPeriod = nil
        loadedOffset = nil
        loadTask?.cancel()
        let task = Task { await self.performLoad() }
        loadTask = task
        await task.value
    }

    func navigatePrevious() {
        logger.debug("navigatePrevious: offset=\(self.dateOffset - 1)")
        hapticService.trigger(.dateNavigate)
        dateOffset -= 1
    }

    func navigateNext() {
        guard canNavigateForward else { return }
        logger.debug("navigateNext: offset=\(self.dateOffset + 1)")
        hapticService.trigger(.dateNavigate)
        dateOffset += 1
    }

    func resetToCurrentPeriod() {
        guard dateOffset != 0 else { return }
        dateOffset = 0
    }

    func navigateToDay(_ date: Date) {
        let todayStart = Self.calendar.startOfDay(for: Date())
        let tappedStart = Self.calendar.startOfDay(for: date)
        guard tappedStart <= todayStart else { return }
        let diff = Self.calendar.dateComponents([.day], from: tappedStart, to: todayStart).day ?? 0
        dateOffset = -diff
        selectedPeriod = .daily
    }

    func toggleCategoryFilter(_ categoryID: UUID) {
        if !excludedCategories.insert(categoryID).inserted {
            excludedCategories.remove(categoryID)
        }
    }

    func clearCategoryFilter() {
        guard !excludedCategories.isEmpty else { return }
        excludedCategories.removeAll()
    }

    func selectCategory(_ categoryID: UUID?) {
        guard let categoryID, let interval = currentPeriodInterval else {
            logger.debug("selectCategory: cleared (hasCategory=\(categoryID != nil), hasInterval=\(self.currentPeriodInterval != nil))")
            selectedDestination = nil
            return
        }
        logger.debug("selectCategory: navigating to \(categoryID, privacy: .private)")
        selectedDestination = CategoryNavDestination(categoryID: categoryID, interval: interval)
    }

    func subscribeToRemoteChanges() async {
        guard !isSubscribed else {
            logger.debug("subscribeToRemoteChanges: already subscribed — skipped")
            return
        }
        isSubscribed = true
        defer {
            isSubscribed = false
            logger.debug("subscribeToRemoteChanges: listener ended")
        }
        logger.debug("subscribeToRemoteChanges: starting listener")
        registerSyncCallbackIfNeeded()
        await invalidateAndReload()
        await startDebounceLoop()
    }

    // MARK: - Private (Data Loading)

    private func performLoad() async {
        let period = selectedPeriod
        let offset = dateOffset
        isLoading = true
        barEntries = []
        chartSlices = []
        totalAmount = 0
        categoryTotals = []
        dailyTotals = [:]
        previousPeriodTotal = nil
        defer { isLoading = false }
        let now = Date()
        let refDate = referenceDate(for: period, offset: offset, relativeTo: now)
        let currentInterval = dateInterval(for: period, referenceDate: refDate)
        let previousInterval = previousDateInterval(for: period, referenceDate: refDate)
        logger.debug("performLoad: period=\(period.rawValue), interval=\(currentInterval.start) — \(currentInterval.end)")
        do {
            let currentExpenses = try await repository.fetchExpenses(for: currentInterval)
            guard !Task.isCancelled else { return }
            let previousExpenses = try await repository.fetchExpenses(for: previousInterval)
            guard !Task.isCancelled else { return }
            let categories = try await categoryRepository.fetchCategories()
            guard !Task.isCancelled else { return }
            logger.info("performLoad: \(currentExpenses.count) current, \(previousExpenses.count) previous, \(categories.count) categories")
            applyLoadResults(
                currentExpenses: currentExpenses,
                previousExpenses: previousExpenses,
                categories: categories,
                period: period,
                interval: currentInterval,
                offset: offset
            )
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("performLoad: FAILED — \(error.localizedDescription)")
            clearLoadResults(error: error)
        }
    }

    private func applyLoadResults(
        currentExpenses: [ExpenseData],
        previousExpenses: [ExpenseData],
        categories: [CategoryData],
        period: TimePeriod,
        interval: DateInterval,
        offset: Int
    ) {
        clearCategoryFilter()
        totalAmount = currentExpenses.reduce(Int64(0)) { $0 + $1.amount }
        categoryTotals = buildCategoryTotals(from: currentExpenses)
        fetchedCategories = categories
        let categoryMap = buildCategoryMap(from: categories)
        chartSlices = buildChartSlices(from: categoryTotals, categoryMap: categoryMap)
        barEntries = computeBarEntries(from: currentExpenses, period: period, interval: interval)
        dailyTotals = currentExpenses.reduce(into: [:]) { map, expense in
            map[Self.calendar.startOfDay(for: expense.createdAt), default: 0] += expense.amount
        }
        previousPeriodTotal = previousExpenses.isEmpty ? nil : previousExpenses.reduce(Int64(0)) { $0 + $1.amount }
        currentPeriodInterval = interval
        errorMessage = nil
        loadedPeriod = period
        loadedOffset = offset
        logger.info("performLoad: complete — total=\(self.totalAmount, privacy: .private) satang, \(self.categoryTotals.count) categories")
    }

    private func clearLoadResults(error: Error) {
        totalAmount = 0
        categoryTotals = []
        chartSlices = []
        barEntries = []
        dailyTotals = [:]
        fetchedCategories = []
        previousPeriodTotal = nil
        currentPeriodInterval = nil
        errorMessage = error.localizedDescription
    }

    private func buildCategoryTotals(from expenses: [ExpenseData]) -> [CategoryTotal] {
        var grouped: [UUID: Int64] = [:]
        for expense in expenses {
            grouped[expense.categoryID, default: 0] += expense.amount
        }
        return grouped
            .map { CategoryTotal(categoryID: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    private func buildCategoryMap(from categories: [CategoryData]) -> [UUID: CategoryData] {
        Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    private func buildChartSlices(from totals: [CategoryTotal], categoryMap: [UUID: CategoryData]) -> [ChartSlice] {
        totals.map { ct in
            let category = categoryMap[ct.categoryID]
            return ChartSlice(
                categoryID: ct.categoryID,
                categoryName: category?.name ?? "Unknown",
                colorName: category?.colorName ?? "CoolGray",
                iconName: category?.iconName ?? "ellipsis.circle.fill",
                total: ct.total
            )
        }
    }

    // MARK: - Private (Subscription)

    private func registerSyncCallbackIfNeeded() {
        guard !hasRegisteredSyncCallback else { return }
        hasRegisteredSyncCallback = true
        syncMonitorService.onSyncStatusChanged.append { [weak self] newStatus in
            guard let self else { return }
            logger.info("Sync status changed: \(String(describing: newStatus))")
            self.syncStatus = newStatus
        }
    }

    private func startDebounceLoop() async {
        var debounceTask: Task<Void, Never>?
        defer { debounceTask?.cancel() }
        for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
            guard !Task.isCancelled else { break }
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 500_000_000)
                } catch is CancellationError { return } catch { return }
                guard !Task.isCancelled else { return }
                logger.info("Remote change (debounced) — reloading insights")
                await self.invalidateAndReload()
            }
        }
    }

    // MARK: - Bar Entry Computation

    private static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // en_US_POSIX ensures "d.M" is treated as a fixed-format template (e.g. "2.5"), not locale-substituted
    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d.M"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private func computeBarEntries(from expenses: [ExpenseData], period: TimePeriod, interval: DateInterval) -> [BarEntry] {
        switch period {
        case .daily: return computeDailyEntries(from: expenses, interval: interval)
        case .weekly: return computeWeeklyEntries(from: expenses, interval: interval)
        case .monthly: return computeMonthlyEntries(from: expenses, interval: interval)
        }
    }

    private func computeDailyEntries(from expenses: [ExpenseData], interval: DateInterval) -> [BarEntry] {
        let cal = Self.calendar
        let total = expenses.reduce(Int64(0)) { $0 + $1.amount }
        let label = cal.isDateInToday(interval.start) ? "Today"
            : cal.isDateInYesterday(interval.start) ? "Yesterday"
            : Self.dayMonthFormatter.string(from: interval.start)
        return [BarEntry(position: 0, label: label, total: total, dateLabel: Self.dayMonthFormatter.string(from: interval.start))]
    }

    private func computeWeeklyEntries(from expenses: [ExpenseData], interval: DateInterval) -> [BarEntry] {
        let cal = Self.calendar
        var entries: [BarEntry] = []
        var date = interval.start
        var position = 0
        while date < interval.end {
            let dayTotal = expenses
                .filter { cal.isDate($0.createdAt, inSameDayAs: date) }
                .reduce(Int64(0)) { $0 + $1.amount }
            entries.append(BarEntry(
                position: position,
                label: Self.weekdayFormatter.string(from: date),
                total: dayTotal,
                dateLabel: Self.dayMonthFormatter.string(from: date)
            ))
            date = cal.date(byAdding: .day, value: 1, to: date) ?? interval.end
            position += 1
        }
        return entries
    }

    private func computeMonthlyEntries(from expenses: [ExpenseData], interval: DateInterval) -> [BarEntry] {
        let cal = Self.calendar
        guard let range = cal.range(of: .weekOfMonth, in: .month, for: interval.start) else { return [] }
        var weeklyTotals: [Int: Int64] = [:]
        for expense in expenses {
            let weekNum = cal.component(.weekOfMonth, from: expense.createdAt)
            weeklyTotals[weekNum, default: 0] += expense.amount
        }
        return range.enumerated().map { idx, week in
            BarEntry(position: idx, label: "W\(week)", total: weeklyTotals[week, default: 0])
        }
    }

    // MARK: - Date Interval Helpers

    private func referenceDate(for period: TimePeriod, offset: Int, relativeTo base: Date) -> Date {
        guard offset != 0 else { return base }
        return Self.calendar.date(byAdding: period.calendarComponent, value: offset, to: base) ?? base
    }

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
