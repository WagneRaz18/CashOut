import Foundation
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "ExpenseEntryViewModel")

@MainActor
@Observable
final class ExpenseEntryViewModel {

    // MARK: - Observable Properties

    var amountInBaht: Int64 = 0
    var categories: [CategoryData] = []
    var selectedCategoryID: UUID?
    var noteText: String = ""
    var isSaving: Bool = false
    var saveError: String?
    var categoryLoadFailed: Bool = false

    var isAmountZero: Bool {
        amountInBaht == 0
    }

    /// Whole Baht converted to satang for display and persistence.
    var amountInSatang: Int64 {
        amountInBaht * 100
    }

    // MARK: - Dependencies

    @ObservationIgnored
    private let expenseRepository: ExpenseRepositoryProtocol

    @ObservationIgnored
    private let categoryRepository: CategoryRepositoryProtocol

    @ObservationIgnored
    private let authService: AuthenticationServiceProtocol

    @ObservationIgnored
    private let hapticService: HapticServiceProtocol

    @ObservationIgnored
    private let categoryOrderStore: CategoryOrderStore

    /// Tracks whether the first-load auto-retry path has already run. Re-fetches on
    /// subsequent tab appears still execute to pick up categories added or deleted
    /// from Settings — the flag only suppresses the seeding-race retry, not the fetch.
    @ObservationIgnored
    private var hasLoadedOnce: Bool = false

    // MARK: - Constants

    private static let maxBeforeAppend: Int64 = 1_000_000

    // MARK: - Init

    init(
        expenseRepository: ExpenseRepositoryProtocol = ExpenseRepository.shared,
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository.shared,
        authService: AuthenticationServiceProtocol = AuthenticationService.shared,
        hapticService: HapticServiceProtocol = HapticService.shared,
        categoryOrderStore: CategoryOrderStore = CategoryOrderStore()
    ) {
        self.expenseRepository = expenseRepository
        self.categoryRepository = categoryRepository
        self.authService = authService
        self.hapticService = hapticService
        self.categoryOrderStore = categoryOrderStore
        logger.debug("ExpenseEntryViewModel.init")
    }

    // MARK: - Numpad Actions

    func appendDigit(_ digit: String) {
        guard amountInBaht < Self.maxBeforeAppend else {
            logger.debug("appendDigit: amount cap reached (\(Self.maxBeforeAppend) Baht) — skipped")
            return
        }
        guard let value = Int64(digit) else { return }
        hapticService.trigger(.numpadKey)
        amountInBaht = amountInBaht * 10 + value
    }

    func deleteLastDigit() {
        hapticService.trigger(.numpadKey)
        amountInBaht = amountInBaht / 10
    }

    func resetAmount() {
        amountInBaht = 0
    }

    // MARK: - Category Actions

    private static let autoRetryDelay: UInt64 = 500_000_000 // 500ms

    func loadCategories() async {
        categoryLoadFailed = false
        logger.info("loadCategories: fetching categories")
        do {
            var fetched = try await categoryRepository.fetchCategories()
            guard !Task.isCancelled else { return }

            // Seeding-race auto-retry — only on the very first load when the fetch
            // returns empty. Subsequent tab-appear fetches must NOT retry: an
            // empty result then legitimately means the user deleted all custom
            // categories and removed every default.
            if fetched.isEmpty && !hasLoadedOnce {
                logger.info("loadCategories: empty result — retrying after delay")
                try await Task.sleep(nanoseconds: Self.autoRetryDelay)
                guard !Task.isCancelled else { return }
                fetched = try await categoryRepository.fetchCategories()
                guard !Task.isCancelled else { return }
            }

            hasLoadedOnce = true
            let previousSelection = selectedCategoryID
            categories = categoryOrderStore.applyUserOrder(to: fetched)
            logger.info("loadCategories: loaded \(fetched.count) categories")

            if fetched.isEmpty {
                logger.warning("loadCategories: no categories after retry")
                categoryLoadFailed = true
                selectedCategoryID = nil
                return
            }

            // Preserve selection across tab-switch re-fetches; fall back to first
            // category if the previously-selected one was deleted elsewhere.
            if let prev = previousSelection, categories.contains(where: { $0.id == prev }) {
                selectedCategoryID = prev
            } else {
                selectedCategoryID = categories.first?.id
                logger.debug("loadCategories: selected first category")
            }
        } catch is CancellationError {
            return
        } catch {
            logger.error("loadCategories failed: \(error.localizedDescription)")
            categoryLoadFailed = true
        }
    }

    /// Re-apply UserDefaults order overlay without re-fetching from Core Data.
    /// Called on every tab appear to pick up order changes from Settings.
    func refreshCategoryOrder() {
        // Guard handles first-appear race: .onAppear fires while .task's
        // loadCategories is still in flight — ordering is applied there instead.
        guard !categories.isEmpty else { return }
        logger.debug("refreshCategoryOrder: re-applying order to \(self.categories.count) categories")
        categories = categoryOrderStore.applyUserOrder(to: categories)
    }

    func retryLoadCategories() async {
        logger.info("retryLoadCategories: resetting state and retrying")
        categories = []
        selectedCategoryID = nil
        categoryLoadFailed = false
        hasLoadedOnce = false
        await loadCategories()
    }

    func selectCategory(_ id: UUID) {
        hapticService.trigger(.categorySelect)
        selectedCategoryID = id
    }

    // MARK: - Save Action

    func saveExpense() async {
        guard !isSaving else {
            logger.debug("saveExpense: already saving — skipped")
            return
        }
        isSaving = true
        defer { isSaving = false }
        saveError = nil

        guard amountInBaht > 0 else {
            logger.debug("saveExpense: amount is zero — skipped")
            return
        }
        guard let categoryID = selectedCategoryID else {
            logger.warning("saveExpense: no category selected — skipped")
            return
        }
        guard let userID = authService.currentUserID else {
            logger.error("saveExpense: not authenticated")
            saveError = "Not signed in. Please sign in and try again."
            return
        }

        logger.info("saveExpense: saving \(self.amountInBaht, privacy: .private) Baht, category=\(categoryID, privacy: .private)")
        let saveStart = CFAbsoluteTimeGetCurrent()

        let now = Date()
        let expense = ExpenseData(
            id: UUID(),
            amount: amountInSatang,
            note: { let t = noteText.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }(),
            categoryID: categoryID,
            createdByUserID: userID,
            createdAt: now,
            modifiedAt: now
        )

        do {
            try await expenseRepository.saveExpense(expense)
            guard !Task.isCancelled else { return }

            let saveElapsed = (CFAbsoluteTimeGetCurrent() - saveStart) * 1000
            logger.info("saveExpense: saved successfully — id=\(expense.id, privacy: .private) — total \(saveElapsed, format: .fixed(precision: 1))ms")

            // Fire-and-forget sharing — owned by the repository singleton so the task
            // survives EntryView dismissal. The repo yields before calling container.share()
            // so the caller's @MainActor continuation (EntryView's saveTask) resumes first.
            logger.debug("saveExpense: enqueuing share task — id=\(expense.id, privacy: .private)")
            expenseRepository.enqueueShareForNewExpense(id: expense.id)
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("saveExpense: failed — \(error.localizedDescription, privacy: .public)")
            saveError = "Could not save entry. Please try again."
        }
    }

    /// Resets the entry form for the next expense. Called by the View after the save animation completes.
    func resetForm() {
        logger.debug("resetForm: clearing amount, note, and resetting to first category")
        resetAmount()
        noteText = ""
        selectedCategoryID = categories.first?.id
    }
}
