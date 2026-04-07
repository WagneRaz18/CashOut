import Foundation
import os.log

enum ExpenseEntryError: Error {
    case notAuthenticated
}

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
            Logger(subsystem: "com.wagneraz.CashOut", category: "ExpenseEntryViewModel")
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
        guard let userID = authService.currentUserID else {
            throw ExpenseEntryError.notAuthenticated
        }

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
