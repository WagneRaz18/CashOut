import Foundation

@MainActor
@Observable
final class EditExpenseViewModel {

    // MARK: - Observable Properties

    var amountInCents: Int64 = 0
    var categories: [CategoryData] = []
    var selectedCategoryID: UUID?
    var noteText: String = ""
    var isSaving: Bool = false

    var isAmountZero: Bool {
        amountInCents == 0
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

        // Pre-fill from existing expense
        self.amountInCents = expense.amount
        self.selectedCategoryID = expense.categoryID
        self.noteText = expense.note ?? ""
    }

    // MARK: - Numpad Actions

    func appendDigit(_ digit: String) {
        hapticService.trigger(.numpadKey)
        guard amountInCents < Self.maxBeforeAppend else { return }
        guard let value = Int64(digit) else { return }
        amountInCents = amountInCents * 10 + value
    }

    func deleteLastDigit() {
        hapticService.trigger(.numpadKey)
        amountInCents = amountInCents / 10
    }

    func appendDecimalPoint() {
        hapticService.trigger(.numpadKey)
        // No-op: decimal is implicit in fixed-point satang model.
    }

    func resetAmount() {
        amountInCents = 0
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
            // Categories failed to load — UI will show empty picker
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

        guard amountInCents > 0 else { return }
        guard let categoryID = selectedCategoryID else { return }

        let updatedExpense = ExpenseData(
            id: originalExpense.id,
            amount: amountInCents,
            note: noteText.isEmpty ? nil : noteText,
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
