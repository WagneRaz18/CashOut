import Foundation
import os.log

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
        expenseRepository: ExpenseRepositoryProtocol = ExpenseRepository(),
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository(),
        hapticService: HapticServiceProtocol = HapticService()
    ) {
        self.originalExpense = expense
        self.expenseRepository = expenseRepository
        self.categoryRepository = categoryRepository
        self.hapticService = hapticService

        // Pre-fill from existing expense (convert satang → whole Baht)
        self.amountInBaht = expense.amount / 100
        self.selectedCategoryID = expense.categoryID
        self.noteText = expense.note ?? ""
    }

    // MARK: - Numpad Actions

    func appendDigit(_ digit: String) {
        guard amountInBaht < Self.maxBeforeAppend else { return }
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
        guard categories.isEmpty else { return }

        do {
            let fetched = try await categoryRepository.fetchCategories()
            guard !Task.isCancelled else { return }
            categories = fetched
            // Do NOT set selectedCategoryID — already pre-filled from init
        } catch {
            Logger(subsystem: "com.wagneraz.CashOut", category: "EditExpenseViewModel")
                .error("loadCategories failed: \(error.localizedDescription)")
        }
    }

    func selectCategory(_ id: UUID) {
        hapticService.trigger(.categorySelect)
        selectedCategoryID = id
    }

    // MARK: - Save Action

    func saveExpense() async throws {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        guard amountInBaht > 0 else { return }
        guard let categoryID = selectedCategoryID else { return }

        let updatedExpense = ExpenseData(
            id: originalExpense.id,
            amount: amountInSatang,
            note: { let t = noteText.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }(),
            categoryID: categoryID,
            createdByUserID: originalExpense.createdByUserID,
            createdAt: originalExpense.createdAt,
            modifiedAt: Date()
        )

        try await expenseRepository.saveExpense(updatedExpense)
        guard !Task.isCancelled else { return }

        hapticService.trigger(.saveTap)
        // No form reset, no MRU update — sheet dismisses after save
    }
}
