import XCTest
@testable import CashOut

@MainActor
final class EditExpenseViewModelTests: XCTestCase {

    // MARK: - Test Helpers

    private static func makeExpense(
        id: UUID = UUID(),
        amount: Int64 = 12300,
        note: String? = "Test note",
        categoryID: UUID = UUID(),
        createdByUserID: String = "original-user",
        createdAt: Date = Date(timeIntervalSince1970: 1_000_000),
        modifiedAt: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> ExpenseData {
        ExpenseData(
            id: id,
            amount: amount,
            note: note,
            categoryID: categoryID,
            createdByUserID: createdByUserID,
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
    }

    private func makeSUT(
        expense: ExpenseData? = nil,
        expenseRepoShouldThrow: Bool = false
    ) -> (
        viewModel: EditExpenseViewModel,
        expenseRepo: MockExpenseRepository,
        categoryRepo: MockCategoryRepository,
        hapticService: MockHapticService
    ) {
        let expenseRepo = MockExpenseRepository()
        expenseRepo.shouldThrow = expenseRepoShouldThrow

        let categoryRepo = MockCategoryRepository()
        let hapticService = MockHapticService()

        let testExpense = expense ?? Self.makeExpense()

        let viewModel = EditExpenseViewModel(
            expense: testExpense,
            expenseRepository: expenseRepo,
            categoryRepository: categoryRepo,
            hapticService: hapticService
        )

        return (viewModel, expenseRepo, categoryRepo, hapticService)
    }

    // MARK: - Init Pre-fill Tests (AC #1)

    func testInitPrefillsAmountFromExpense() {
        let expense = Self.makeExpense(amount: 45600)
        let (viewModel, _, _, _) = makeSUT(expense: expense)

        XCTAssertEqual(viewModel.amountInCents, 45600, "Should pre-fill amountInCents from expense")
    }

    func testInitPrefillsSelectedCategoryIDFromExpense() {
        let categoryID = UUID()
        let expense = Self.makeExpense(categoryID: categoryID)
        let (viewModel, _, _, _) = makeSUT(expense: expense)

        XCTAssertEqual(viewModel.selectedCategoryID, categoryID, "Should pre-fill selectedCategoryID from expense")
    }

    func testInitPrefillsNoteTextFromExpense() {
        let expense = Self.makeExpense(note: "Lunch with Bob")
        let (viewModel, _, _, _) = makeSUT(expense: expense)

        XCTAssertEqual(viewModel.noteText, "Lunch with Bob", "Should pre-fill noteText from expense")
    }

    func testInitPrefillsNoteTextAsEmptyWhenNil() {
        let expense = Self.makeExpense(note: nil)
        let (viewModel, _, _, _) = makeSUT(expense: expense)

        XCTAssertEqual(viewModel.noteText, "", "Should pre-fill noteText as empty string when expense note is nil")
    }

    // MARK: - Save Preserves Original Fields (AC #3, #4)

    func testSaveExpensePreservesOriginalID() async throws {
        let originalID = UUID()
        let expense = Self.makeExpense(id: originalID)
        let (viewModel, expenseRepo, _, _) = makeSUT(expense: expense)

        try await viewModel.saveExpense()

        let saved = try XCTUnwrap(expenseRepo.lastSavedExpense)
        XCTAssertEqual(saved.id, originalID, "Should preserve original expense ID on save")
    }

    func testSaveExpensePreservesOriginalCreatedAt() async throws {
        let originalDate = Date(timeIntervalSince1970: 500_000)
        let expense = Self.makeExpense(createdAt: originalDate)
        let (viewModel, expenseRepo, _, _) = makeSUT(expense: expense)

        try await viewModel.saveExpense()

        let saved = try XCTUnwrap(expenseRepo.lastSavedExpense)
        XCTAssertEqual(saved.createdAt, originalDate, "Should preserve original createdAt on save")
    }

    func testSaveExpensePreservesOriginalCreatedByUserID() async throws {
        let expense = Self.makeExpense(createdByUserID: "partner-user-123")
        let (viewModel, expenseRepo, _, _) = makeSUT(expense: expense)

        try await viewModel.saveExpense()

        let saved = try XCTUnwrap(expenseRepo.lastSavedExpense)
        XCTAssertEqual(saved.createdByUserID, "partner-user-123", "Should preserve original createdByUserID on save")
    }

    func testSaveExpenseSetsModifiedAtToCurrentTime() async throws {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        let beforeSave = Date()

        try await viewModel.saveExpense()

        let saved = try XCTUnwrap(expenseRepo.lastSavedExpense)
        let afterSave = Date()
        XCTAssertGreaterThanOrEqual(saved.modifiedAt, beforeSave, "modifiedAt should be >= time before save")
        XCTAssertLessThanOrEqual(saved.modifiedAt, afterSave, "modifiedAt should be <= time after save")
    }

    // MARK: - Save Uses Current Form Values (AC #3)

    func testSaveExpenseUsesCurrentAmount() async throws {
        let expense = Self.makeExpense(amount: 10000)
        let (viewModel, expenseRepo, _, _) = makeSUT(expense: expense)
        viewModel.amountInCents = 25000

        try await viewModel.saveExpense()

        let saved = try XCTUnwrap(expenseRepo.lastSavedExpense)
        XCTAssertEqual(saved.amount, 25000, "Should use current amountInCents, not original")
    }

    func testSaveExpenseUsesCurrentCategoryID() async throws {
        let originalCategoryID = UUID()
        let newCategoryID = UUID()
        let expense = Self.makeExpense(categoryID: originalCategoryID)
        let (viewModel, expenseRepo, _, _) = makeSUT(expense: expense)
        viewModel.selectedCategoryID = newCategoryID

        try await viewModel.saveExpense()

        let saved = try XCTUnwrap(expenseRepo.lastSavedExpense)
        XCTAssertEqual(saved.categoryID, newCategoryID, "Should use current selectedCategoryID, not original")
    }

    func testSaveExpenseUsesCurrentNoteText() async throws {
        let expense = Self.makeExpense(note: "Original note")
        let (viewModel, expenseRepo, _, _) = makeSUT(expense: expense)
        viewModel.noteText = "Updated note"

        try await viewModel.saveExpense()

        let saved = try XCTUnwrap(expenseRepo.lastSavedExpense)
        XCTAssertEqual(saved.note, "Updated note", "Should use current noteText, not original")
    }

    // MARK: - Save Haptic Tests (AC #3)

    func testSaveExpenseTriggersSaveTapHaptic() async throws {
        let (viewModel, _, _, hapticService) = makeSUT()

        try await viewModel.saveExpense()

        XCTAssertEqual(hapticService.lastEvent, .saveTap, "Should trigger .saveTap haptic on successful save")
    }

    func testSaveExpenseDoesNotTriggerHapticOnFailure() async {
        let (viewModel, _, _, hapticService) = makeSUT(expenseRepoShouldThrow: true)

        do {
            try await viewModel.saveExpense()
            XCTFail("Should have thrown")
        } catch {
            // Expected
        }

        XCTAssertNil(hapticService.lastEvent, "Should NOT trigger haptic when repository throws")
    }

    // MARK: - Save Guard Tests

    func testSaveExpenseReturnsSilentlyWhenAmountIsZero() async throws {
        let expense = Self.makeExpense(amount: 0)
        let (viewModel, expenseRepo, _, _) = makeSUT(expense: expense)
        viewModel.amountInCents = 0

        try await viewModel.saveExpense()

        XCTAssertFalse(expenseRepo.saveExpenseCalled, "Should not save when amount is zero")
    }

    func testSaveExpenseReturnsSilentlyWhenCategoryIsNil() async throws {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        viewModel.selectedCategoryID = nil

        try await viewModel.saveExpense()

        XCTAssertFalse(expenseRepo.saveExpenseCalled, "Should not save when selectedCategoryID is nil")
    }

    func testIsSavingGuardPreventsConcurrentSaves() async throws {
        let (viewModel, expenseRepo, _, _) = makeSUT()
        viewModel.isSaving = true

        try await viewModel.saveExpense()

        XCTAssertTrue(viewModel.isSaving, "isSaving should stay true (guard returned early)")
        XCTAssertFalse(expenseRepo.saveExpenseCalled, "Should not save when already saving")
    }

    // MARK: - Numpad Tests

    func testAppendDigitModifiesPrefilledAmount() {
        let expense = Self.makeExpense(amount: 12300)
        let (viewModel, _, _, _) = makeSUT(expense: expense)

        viewModel.appendDigit("5")

        XCTAssertEqual(viewModel.amountInCents, 123005, "Appending '5' to 12300 should produce 123005")
    }

    func testResetAmountClearsToZero() {
        let expense = Self.makeExpense(amount: 50000)
        let (viewModel, _, _, _) = makeSUT(expense: expense)

        viewModel.resetAmount()

        XCTAssertEqual(viewModel.amountInCents, 0, "resetAmount should set to zero")
    }

    // MARK: - loadCategories Tests

    func testLoadCategoriesFetchesAndDoesNotOverwriteSelectedCategoryID() async {
        let originalCategoryID = UUID()
        let expense = Self.makeExpense(categoryID: originalCategoryID)
        let (viewModel, _, categoryRepo, _) = makeSUT(expense: expense)
        categoryRepo.categoriesToReturn = [
            CategoryData(id: UUID(), name: "Food", iconName: "fork.knife", colorName: "Sage", isDefault: true, sortOrder: 0),
            CategoryData(id: originalCategoryID, name: "Transport", iconName: "car.fill", colorName: "Slate", isDefault: true, sortOrder: 1),
        ]

        await viewModel.loadCategories()

        XCTAssertEqual(viewModel.categories.count, 2, "Should populate categories from repository")
        XCTAssertEqual(viewModel.selectedCategoryID, originalCategoryID, "Should NOT overwrite selectedCategoryID from init")
    }

    // MARK: - selectCategory Haptic Test

    func testSelectCategoryTriggersCategorySelectHaptic() {
        let (viewModel, _, _, hapticService) = makeSUT()

        viewModel.selectCategory(UUID())

        XCTAssertEqual(hapticService.lastEvent, .categorySelect, "Should trigger .categorySelect haptic")
    }
}
