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
    private let userDefaults: UserDefaults

    @ObservationIgnored
    private let hapticService: HapticServiceProtocol

    @ObservationIgnored
    private var shareTask: Task<Void, Never>?

    // MARK: - Constants

    private static let maxBeforeAppend: Int64 = 1_000_000
    private static let mruKey = "lastUsedCategoryID"

    // MARK: - Init

    init(
        expenseRepository: ExpenseRepositoryProtocol = ExpenseRepository.shared,
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository.shared,
        authService: AuthenticationServiceProtocol = AuthenticationService.shared,
        userDefaults: UserDefaults = .standard,
        hapticService: HapticServiceProtocol = HapticService.shared
    ) {
        self.expenseRepository = expenseRepository
        self.categoryRepository = categoryRepository
        self.authService = authService
        self.userDefaults = userDefaults
        self.hapticService = hapticService
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
        guard categories.isEmpty else {
            logger.debug("loadCategories: already loaded — skipped")
            return
        }

        categoryLoadFailed = false
        logger.info("loadCategories: fetching categories")
        do {
            var fetched = try await categoryRepository.fetchCategories()
            guard !Task.isCancelled else { return }

            // Auto-retry once if empty — seeding may still be completing
            if fetched.isEmpty {
                logger.info("loadCategories: empty result — retrying after delay")
                try await Task.sleep(nanoseconds: Self.autoRetryDelay)
                guard !Task.isCancelled else { return }
                fetched = try await categoryRepository.fetchCategories()
                guard !Task.isCancelled else { return }
            }

            categories = CategoryOrderStore().applyUserOrder(to: fetched)
            logger.info("loadCategories: loaded \(fetched.count) categories")

            if fetched.isEmpty {
                logger.warning("loadCategories: no categories after retry")
                categoryLoadFailed = true
                return
            }

            restoreMRUSelection(from: fetched)
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
        guard !categories.isEmpty else { return }
        categories = CategoryOrderStore().applyUserOrder(to: categories)
    }

    func retryLoadCategories() async {
        logger.info("retryLoadCategories: resetting state and retrying")
        categories = []
        selectedCategoryID = nil
        categoryLoadFailed = false
        await loadCategories()
    }

    private func restoreMRUSelection(from fetched: [CategoryData]) {
        if let mruString = userDefaults.string(forKey: Self.mruKey),
           let mruID = UUID(uuidString: mruString),
           fetched.contains(where: { $0.id == mruID }) {
            selectedCategoryID = mruID
            logger.debug("loadCategories: restored MRU category \(mruID, privacy: .private)")
        } else {
            selectedCategoryID = fetched.first?.id
            logger.debug("loadCategories: defaulting to first category")
        }
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

            // Persist MRU
            userDefaults.set(categoryID.uuidString, forKey: Self.mruKey)

            // Fire-and-forget sharing — doesn't block the save caller
            let repo = expenseRepository
            let expenseID = expense.id
            logger.debug("saveExpense: enqueuing share task — id=\(expenseID, privacy: .private)")
            shareTask = Task { await repo.shareNewExpenseToHousehold(id: expenseID) }
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("saveExpense: failed — \(error.localizedDescription, privacy: .public)")
            saveError = "Could not save entry. Please try again."
        }
    }

    func cancelPendingShare() {
        if shareTask != nil {
            logger.debug("cancelPendingShare: cancelling in-flight share task")
        }
        shareTask?.cancel()
        shareTask = nil
    }

    /// Resets the entry form for the next expense. Called by the View after the save animation completes.
    func resetForm() {
        logger.debug("resetForm: clearing amount and note (category preserved via MRU)")
        resetAmount()
        noteText = ""
        // selectedCategoryID stays — MRU principle
    }
}
