import Foundation
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "EditExpenseViewModel")

@MainActor
@Observable
final class EditExpenseViewModel {

    // MARK: - Observable Properties

    var amountInBaht: Int64 = 0
    var categories: [CategoryData] = []
    var selectedCategoryID: UUID?
    var noteText: String = ""
    var isSaving: Bool = false
    var saveError: String?

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
    private let hapticService: HapticServiceProtocol

    // MARK: - Original Expense

    private let originalExpense: ExpenseData

    // MARK: - Constants

    private static let maxBeforeAppend: Int64 = 1_000_000

    // MARK: - Init

    init(
        expense: ExpenseData,
        expenseRepository: ExpenseRepositoryProtocol = ExpenseRepository.shared,
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository.shared,
        hapticService: HapticServiceProtocol = HapticService.shared
    ) {
        self.originalExpense = expense
        self.expenseRepository = expenseRepository
        self.categoryRepository = categoryRepository
        self.hapticService = hapticService

        // Pre-fill from existing expense (convert satang → whole Baht)
        self.amountInBaht = expense.amount / 100
        self.selectedCategoryID = expense.categoryID
        self.noteText = expense.note ?? ""
        logger.debug("EditExpenseViewModel.init — editing id=\(expense.id), amount=\(expense.amount) satang")
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

    func loadCategories() async {
        guard categories.isEmpty else {
            logger.debug("loadCategories: already loaded — skipped")
            return
        }

        logger.info("loadCategories: fetching")
        do {
            let fetched = try await categoryRepository.fetchCategories()
            guard !Task.isCancelled else { return }
            categories = fetched
            logger.info("loadCategories: loaded \(fetched.count) categories")
            // Do NOT set selectedCategoryID — already pre-filled from init
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("loadCategories failed: \(error.localizedDescription)")
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

        logger.info("saveExpense: updating id=\(self.originalExpense.id), amount=\(self.amountInBaht) Baht")
        let saveStart = CFAbsoluteTimeGetCurrent()

        let updatedExpense = ExpenseData(
            id: originalExpense.id,
            amount: amountInSatang,
            note: { let t = noteText.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }(),
            categoryID: categoryID,
            createdByUserID: originalExpense.createdByUserID,
            createdByDisplayName: originalExpense.createdByDisplayName,
            createdAt: originalExpense.createdAt,
            modifiedAt: Date()
        )

        do {
            try await expenseRepository.saveExpense(updatedExpense)
            guard !Task.isCancelled else { return }
            let saveElapsed = (CFAbsoluteTimeGetCurrent() - saveStart) * 1000
            logger.info("saveExpense: update saved successfully — \(saveElapsed, format: .fixed(precision: 1))ms")
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("saveExpense: failed — \(error.localizedDescription, privacy: .public)")
            saveError = "Could not save changes. Please try again."
        }
    }
}
