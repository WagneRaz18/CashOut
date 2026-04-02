import Foundation

enum ExpenseEntryError: Error {
    case notAuthenticated
}

@MainActor
@Observable
final class ExpenseEntryViewModel {

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
    private let authService: AuthenticationServiceProtocol

    @ObservationIgnored
    private let userDefaults: UserDefaults

    @ObservationIgnored
    private let hapticService: HapticServiceProtocol

    // MARK: - Constants

    private static let maxBeforeAppend: Int64 = 1_000_000
    private static let mruKey = "lastUsedCategoryID"

    // MARK: - Init

    init(
        expenseRepository: ExpenseRepositoryProtocol = ExpenseRepository(),
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository(),
        authService: AuthenticationServiceProtocol = AuthenticationService(),
        userDefaults: UserDefaults = .standard,
        hapticService: HapticServiceProtocol = HapticService()
    ) {
        self.expenseRepository = expenseRepository
        self.categoryRepository = categoryRepository
        self.authService = authService
        self.userDefaults = userDefaults
        self.hapticService = hapticService
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
        // Included for numpad grid visual completeness.
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

            // Restore MRU from UserDefaults
            if let mruString = userDefaults.string(forKey: Self.mruKey),
               let mruID = UUID(uuidString: mruString),
               fetched.contains(where: { $0.id == mruID }) {
                selectedCategoryID = mruID
            } else {
                // Default to first category (Food & Drink, sortOrder 0)
                selectedCategoryID = fetched.first?.id
            }
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
        guard let userID = authService.currentUserID else {
            throw ExpenseEntryError.notAuthenticated
        }

        let now = Date()
        let expense = ExpenseData(
            id: UUID(),
            amount: amountInCents,
            note: noteText.isEmpty ? nil : noteText,
            categoryID: categoryID,
            createdByUserID: userID,
            createdAt: now,
            modifiedAt: now
        )

        try await expenseRepository.saveExpense(expense)
        guard !Task.isCancelled else { return }

        hapticService.trigger(.saveTap)

        // Persist MRU
        userDefaults.set(categoryID.uuidString, forKey: Self.mruKey)

        // Reset for next entry
        resetAmount()
        noteText = ""
        // selectedCategoryID stays — MRU principle
    }
}
