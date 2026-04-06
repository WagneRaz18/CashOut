import XCTest
@testable import CashOut

@MainActor
final class ExpenseEntryViewModelTests: XCTestCase {

    // MARK: - appendDigit Tests (AC #3, #4)

    func testAppendDigitBuildsCorrectCentsValue() {
        let viewModel = ExpenseEntryViewModel()

        viewModel.appendDigit("1")
        viewModel.appendDigit("2")
        viewModel.appendDigit("5")
        viewModel.appendDigit("0")

        XCTAssertEqual(
            viewModel.amountInCents, 1250,
            "Typing '1250' should produce 1250 satang (฿12.50)"
        )
    }

    // MARK: - deleteLastDigit Tests (AC #5)

    func testDeleteLastDigitRemovesRightmostDigit() {
        let viewModel = ExpenseEntryViewModel()
        viewModel.amountInCents = 1250

        viewModel.deleteLastDigit()

        XCTAssertEqual(
            viewModel.amountInCents, 125,
            "Deleting from 1250 should produce 125 satang (฿1.25)"
        )
    }

    func testDeleteLastDigitFromZeroStaysZero() {
        let viewModel = ExpenseEntryViewModel()

        viewModel.deleteLastDigit()

        XCTAssertEqual(
            viewModel.amountInCents, 0,
            "Deleting from 0 should remain 0 (no crash)"
        )
    }

    // MARK: - Cap Tests

    func testAppendDigitEnforcesCap() {
        let viewModel = ExpenseEntryViewModel()
        viewModel.amountInCents = 1_000_000

        viewModel.appendDigit("5")

        XCTAssertEqual(
            viewModel.amountInCents, 1_000_000,
            "Should not append when amountInCents >= 1_000_000 (cap at ฿99,999.99)"
        )
    }

    func testAppendDigitAllowsLastValueBeforeCap() {
        let viewModel = ExpenseEntryViewModel()
        viewModel.amountInCents = 999_999

        viewModel.appendDigit("9")

        XCTAssertEqual(
            viewModel.amountInCents, 9_999_999,
            "999_999 is the last value that allows append; 999_999 * 10 + 9 = 9_999_999 (฿99,999.99)"
        )
    }

    // MARK: - resetAmount Tests

    func testResetAmountSetsToZero() {
        let viewModel = ExpenseEntryViewModel()
        viewModel.amountInCents = 5000

        viewModel.resetAmount()

        XCTAssertEqual(
            viewModel.amountInCents, 0,
            "Reset should set amountInCents to 0"
        )
    }

    // MARK: - isAmountZero Tests

    func testIsAmountZeroWhenZero() {
        let viewModel = ExpenseEntryViewModel()

        XCTAssertTrue(
            viewModel.isAmountZero,
            "isAmountZero should be true when amountInCents is 0"
        )
    }

    func testIsAmountZeroWhenNonZero() {
        let viewModel = ExpenseEntryViewModel()
        viewModel.amountInCents = 100

        XCTAssertFalse(
            viewModel.isAmountZero,
            "isAmountZero should be false when amountInCents > 0"
        )
    }

    // MARK: - appendDecimalPoint Tests

    func testAppendDecimalPointIsNoOp() {
        let viewModel = ExpenseEntryViewModel()
        viewModel.amountInCents = 500

        viewModel.appendDecimalPoint()

        XCTAssertEqual(
            viewModel.amountInCents, 500,
            "appendDecimalPoint should be a no-op (amount unchanged)"
        )
    }

    // MARK: - Save Flow Tests (Story 1.6)

    private static let testSuiteName = "com.cashout.tests.ExpenseEntryViewModelTests"

    private func makeSUT(
        currentUserID: String? = "test-user",
        expenseRepoShouldThrow: Bool = false
    ) -> (
        viewModel: ExpenseEntryViewModel,
        expenseRepo: MockExpenseRepository,
        categoryRepo: MockCategoryRepository,
        authService: MockAuthenticationService,
        userDefaults: UserDefaults,
        hapticService: MockHapticService
    ) {
        let expenseRepo = MockExpenseRepository()
        expenseRepo.shouldThrow = expenseRepoShouldThrow

        let categoryRepo = MockCategoryRepository()
        let authService = MockAuthenticationService()
        authService.currentUserID = currentUserID

        let defaults = UserDefaults(suiteName: Self.testSuiteName)!
        defaults.removePersistentDomain(forName: Self.testSuiteName)

        let hapticService = MockHapticService()

        let viewModel = ExpenseEntryViewModel(
            expenseRepository: expenseRepo,
            categoryRepository: categoryRepo,
            authService: authService,
            userDefaults: defaults,
            hapticService: hapticService
        )

        return (viewModel, expenseRepo, categoryRepo, authService, defaults, hapticService)
    }

    // MARK: - saveExpense Tests (AC #5, #8)

    func testSaveExpenseCallsRepositoryWithCorrectData() async throws {
        let (viewModel, expenseRepo, _, _, _, _) = makeSUT()
        viewModel.amountInCents = 1250
        viewModel.selectedCategoryID = UUID()
        viewModel.noteText = "Lunch"

        try await viewModel.saveExpense()

        XCTAssertTrue(expenseRepo.saveExpenseCalled, "Should call repository saveExpense")
        let saved = try XCTUnwrap(expenseRepo.lastSavedExpense)
        XCTAssertEqual(saved.amount, 1250, "Amount should be 1250 satang")
        XCTAssertEqual(saved.categoryID, viewModel.selectedCategoryID)
        XCTAssertEqual(saved.createdByUserID, "test-user")
        XCTAssertEqual(saved.note, "Lunch")
    }

    func testSaveExpenseResetsAmountToZero() async throws {
        let (viewModel, _, _, _, _, _) = makeSUT()
        viewModel.amountInCents = 5000
        viewModel.selectedCategoryID = UUID()

        try await viewModel.saveExpense()

        XCTAssertEqual(viewModel.amountInCents, 0, "Amount should reset to 0 after save")
    }

    func testSaveExpenseClearsNoteText() async throws {
        let (viewModel, _, _, _, _, _) = makeSUT()
        viewModel.amountInCents = 1000
        viewModel.selectedCategoryID = UUID()
        viewModel.noteText = "Test note"

        try await viewModel.saveExpense()

        XCTAssertTrue(viewModel.noteText.isEmpty, "noteText should be cleared after save")
    }

    func testSaveExpenseDoesNotSaveWhenAmountIsZero() async throws {
        let (viewModel, expenseRepo, _, _, _, _) = makeSUT()
        viewModel.amountInCents = 0
        viewModel.selectedCategoryID = UUID()

        try await viewModel.saveExpense()

        XCTAssertFalse(expenseRepo.saveExpenseCalled, "Should not save when amount is zero")
    }

    func testSaveExpenseDoesNotSaveWhenCategoryIsNil() async throws {
        let (viewModel, expenseRepo, _, _, _, _) = makeSUT()
        viewModel.amountInCents = 1000
        viewModel.selectedCategoryID = nil

        try await viewModel.saveExpense()

        XCTAssertFalse(expenseRepo.saveExpenseCalled, "Should not save when no category selected")
    }

    // MARK: - loadCategories Tests (AC #1, #2)

    func testLoadCategoriesPopulatesArray() async {
        let (viewModel, _, categoryRepo, _, _, _) = makeSUT()
        let testCategories = [
            CategoryData(id: UUID(), name: "Food", iconName: "fork.knife", colorName: "Sage", isDefault: true, sortOrder: 0),
            CategoryData(id: UUID(), name: "Transport", iconName: "car.fill", colorName: "Slate", isDefault: true, sortOrder: 1),
        ]
        categoryRepo.categoriesToReturn = testCategories

        await viewModel.loadCategories()

        XCTAssertEqual(viewModel.categories.count, 2, "Should populate categories from repository")
        XCTAssertEqual(viewModel.categories.first?.name, "Food")
    }

    func testLoadCategoriesRestoresMRUFromUserDefaults() async {
        let mruID = UUID()
        let (viewModel, _, categoryRepo, _, defaults, _) = makeSUT()
        defaults.set(mruID.uuidString, forKey: "lastUsedCategoryID")
        categoryRepo.categoriesToReturn = [
            CategoryData(id: UUID(), name: "Food", iconName: "fork.knife", colorName: "Sage", isDefault: true, sortOrder: 0),
            CategoryData(id: mruID, name: "Transport", iconName: "car.fill", colorName: "Slate", isDefault: true, sortOrder: 1),
        ]

        await viewModel.loadCategories()

        XCTAssertEqual(viewModel.selectedCategoryID, mruID, "Should restore MRU category from UserDefaults")
    }

    func testSaveExpensePersistsMRUToUserDefaults() async throws {
        let categoryID = UUID()
        let (viewModel, _, _, _, defaults, _) = makeSUT()
        viewModel.amountInCents = 1000
        viewModel.selectedCategoryID = categoryID

        try await viewModel.saveExpense()

        let stored = defaults.string(forKey: "lastUsedCategoryID")
        XCTAssertEqual(stored, categoryID.uuidString, "Should persist categoryID as MRU to UserDefaults")
    }

    // MARK: - selectCategory Tests

    func testSelectCategoryUpdatesSelectedID() {
        let (viewModel, _, _, _, _, _) = makeSUT()
        let id = UUID()

        viewModel.selectCategory(id)

        XCTAssertEqual(viewModel.selectedCategoryID, id)
    }

    // MARK: - Double-tap Guard Test

    func testDoubleTapGuardPreventsSecondSave() async throws {
        let (viewModel, expenseRepo, _, _, _, _) = makeSUT()
        viewModel.amountInCents = 1000
        viewModel.selectedCategoryID = UUID()
        viewModel.isSaving = true

        try await viewModel.saveExpense()

        XCTAssertTrue(viewModel.isSaving, "isSaving should stay true (guard returned early, not this call's responsibility)")
        XCTAssertFalse(expenseRepo.saveExpenseCalled, "Should not save when already saving")
    }

    // MARK: - Error Handling Tests

    func testSaveExpenseResetsIsSavingOnThrow() async {
        let (viewModel, _, _, _, _, hapticService) = makeSUT(expenseRepoShouldThrow: true)
        viewModel.amountInCents = 1000
        viewModel.selectedCategoryID = UUID()

        do {
            try await viewModel.saveExpense()
            XCTFail("Should have thrown")
        } catch {
            // Expected
        }

        XCTAssertFalse(viewModel.isSaving, "isSaving must reset to false even when repository throws")
        XCTAssertNil(hapticService.lastEvent, "Should NOT trigger .saveTap haptic when repository throws")
    }

    func testSaveExpenseThrowsWhenNotAuthenticated() async {
        let (viewModel, expenseRepo, _, _, _, _) = makeSUT(currentUserID: nil)
        viewModel.amountInCents = 1000
        viewModel.selectedCategoryID = UUID()

        do {
            try await viewModel.saveExpense()
            XCTFail("Should throw when currentUserID is nil")
        } catch {
            XCTAssertTrue(error is ExpenseEntryError, "Should throw ExpenseEntryError.notAuthenticated")
        }

        XCTAssertFalse(expenseRepo.saveExpenseCalled, "Should NOT call repository when not authenticated")
    }

    // MARK: - Haptic Tests (Story 1.7)

    func testAppendDigitTriggersNumpadKeyHaptic() {
        let (viewModel, _, _, _, _, hapticService) = makeSUT()

        viewModel.appendDigit("5")

        XCTAssertEqual(hapticService.triggeredEvents.count, 1, "Should trigger exactly one haptic event")
        XCTAssertEqual(hapticService.lastEvent, .numpadKey, "Should trigger .numpadKey haptic")
    }

    func testDeleteLastDigitTriggersNumpadKeyHaptic() {
        let (viewModel, _, _, _, _, hapticService) = makeSUT()

        viewModel.deleteLastDigit()

        XCTAssertEqual(hapticService.triggeredEvents.count, 1, "Should trigger exactly one haptic event")
        XCTAssertEqual(hapticService.lastEvent, .numpadKey, "Should trigger .numpadKey haptic")
    }

    func testAppendDecimalPointDoesNotTriggerHaptic() {
        let (viewModel, _, _, _, _, hapticService) = makeSUT()

        viewModel.appendDecimalPoint()

        XCTAssertEqual(hapticService.triggeredEvents.count, 0, "No-op decimal point should not trigger haptic")
    }

    func testSelectCategoryTriggersCategorySelectHaptic() {
        let (viewModel, _, _, _, _, hapticService) = makeSUT()

        viewModel.selectCategory(UUID())

        XCTAssertEqual(hapticService.triggeredEvents.count, 1, "Should trigger exactly one haptic event")
        XCTAssertEqual(hapticService.lastEvent, .categorySelect, "Should trigger .categorySelect haptic")
    }

    func testSaveExpenseTriggersSaveTapHaptic() async throws {
        let (viewModel, _, _, _, _, hapticService) = makeSUT()
        viewModel.amountInCents = 1250
        viewModel.selectedCategoryID = UUID()

        try await viewModel.saveExpense()

        XCTAssertEqual(hapticService.triggeredEvents.count, 1, "Should trigger exactly one haptic event")
        XCTAssertEqual(hapticService.lastEvent, .saveTap, "Should trigger .saveTap haptic on successful save")
    }

    func testSaveExpenseWithZeroAmountDoesNotTriggerSaveTapHaptic() async throws {
        let (viewModel, _, _, _, _, hapticService) = makeSUT()
        viewModel.amountInCents = 0
        viewModel.selectedCategoryID = UUID()

        try await viewModel.saveExpense()

        XCTAssertNil(hapticService.lastEvent, "Should NOT trigger .saveTap when amount is zero")
    }

    func testSaveExpenseWithNilCategoryDoesNotTriggerSaveTapHaptic() async throws {
        let (viewModel, _, _, _, _, hapticService) = makeSUT()
        viewModel.amountInCents = 1000
        viewModel.selectedCategoryID = nil

        try await viewModel.saveExpense()

        XCTAssertNil(hapticService.lastEvent, "Should NOT trigger .saveTap when no category selected")
    }

    func testAppendDigitAtMaxOverflowDoesNotTriggerHaptic() {
        let (viewModel, _, _, _, _, hapticService) = makeSUT()
        viewModel.amountInCents = 1_000_000

        viewModel.appendDigit("5")

        XCTAssertEqual(viewModel.amountInCents, 1_000_000, "Amount should not change at cap")
        XCTAssertEqual(hapticService.triggeredEvents.count, 0, "Rejected input should not trigger haptic")
    }
}
