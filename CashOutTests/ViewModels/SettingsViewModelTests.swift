import XCTest
@testable import CashOut

@MainActor
final class SettingsViewModelTests: XCTestCase {

    // MARK: - Test Helpers

    /// Isolated UserDefaults suite so CategoryOrderStore writes don't leak across tests.
    private func makeOrderStore() -> CategoryOrderStore {
        let suiteName = "SettingsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return CategoryOrderStore(defaults: defaults)
    }

    private func makeSUT() -> (
        vm: SettingsViewModel,
        household: MockHouseholdService,
        categoryRepo: MockCategoryRepository,
        haptic: MockHapticService
    ) {
        let household = MockHouseholdService()
        let categoryRepo = MockCategoryRepository()
        let haptic = MockHapticService()
        let vm = SettingsViewModel(
            householdService: household,
            persistenceController: .preview,
            categoryRepository: categoryRepo,
            hapticService: haptic,
            categoryOrderStore: makeOrderStore()
        )
        return (vm, household, categoryRepo, haptic)
    }

    private func makeCategory(
        id: UUID = UUID(),
        name: String = "Food",
        isDefault: Bool = false,
        sortOrder: Int16 = 0
    ) -> CategoryData {
        CategoryData(
            id: id,
            name: name,
            iconName: "fork.knife",
            colorName: "Sage",
            isDefault: isDefault,
            sortOrder: sortOrder
        )
    }

    // MARK: - loadCategories

    func testLoadCategoriesPopulatesList() async {
        let (vm, _, repo, _) = makeSUT()
        repo.categoriesToReturn = [makeCategory(name: "A"), makeCategory(name: "B")]

        await vm.loadCategories()

        XCTAssertEqual(vm.categories.count, 2)
    }

    func testLoadCategoriesFailureEmptiesList() async {
        let (vm, _, repo, _) = makeSUT()
        repo.categoriesToReturn = [makeCategory()]
        await vm.loadCategories()
        XCTAssertEqual(vm.categories.count, 1)

        repo.shouldThrow = true
        await vm.loadCategories()

        XCTAssertTrue(vm.categories.isEmpty, "Failed load should empty the list")
    }

    // MARK: - saveCategory

    func testSaveCategoryCreatesNewCategory() async {
        let (vm, _, repo, haptic) = makeSUT()

        await vm.saveCategory(name: "Transport", iconName: "car", colorName: "Ocean", existingID: nil)

        XCTAssertTrue(repo.saveCategoryCalled)
        XCTAssertEqual(repo.savedCategory?.name, "Transport")
        XCTAssertEqual(repo.savedCategory?.isDefault, false, "New category must never be marked default")
        XCTAssertEqual(haptic.lastEvent, .saveTap)
    }

    func testSaveCategoryTrimsWhitespace() async {
        let (vm, _, repo, _) = makeSUT()

        await vm.saveCategory(name: "  Transport  ", iconName: "car", colorName: "Ocean", existingID: nil)

        XCTAssertEqual(repo.savedCategory?.name, "Transport")
    }

    func testSaveCategoryEmptyNameIsSkipped() async {
        let (vm, _, repo, _) = makeSUT()

        await vm.saveCategory(name: "   ", iconName: "car", colorName: "Ocean", existingID: nil)

        XCTAssertFalse(repo.saveCategoryCalled)
    }

    func testSaveCategoryBlocksModificationOfDefault() async {
        let (vm, _, repo, _) = makeSUT()
        let defaultID = UUID()
        repo.categoriesToReturn = [makeCategory(id: defaultID, name: "Food", isDefault: true)]
        await vm.loadCategories()

        await vm.saveCategory(name: "Renamed", iconName: "car", colorName: "Ocean", existingID: defaultID)

        XCTAssertFalse(repo.saveCategoryCalled, "Default categories must not be mutable")
    }

    func testSaveCategoryFailureSurfacesErrorMessageAndHaptic() async {
        let (vm, _, repo, haptic) = makeSUT()
        repo.shouldThrow = true

        await vm.saveCategory(name: "Transport", iconName: "car", colorName: "Ocean", existingID: nil)

        XCTAssertNotNil(vm.categorySaveError)
        XCTAssertEqual(haptic.lastEvent, .error)
    }

    // MARK: - deleteCategory

    func testDeleteCategoryHappyPath() async {
        let (vm, _, repo, haptic) = makeSUT()
        let id = UUID()
        repo.categoriesToReturn = [makeCategory(id: id, name: "X")]

        await vm.deleteCategory(id: id)

        XCTAssertTrue(repo.deleteCategoryCalled)
        XCTAssertEqual(repo.lastDeletedCategoryID, id)
        XCTAssertEqual(haptic.lastEvent, .deleteTap)
        XCTAssertNil(vm.categoryDeleteError)
    }

    func testDeleteCategoryBlockedByUsageSurfacesLocalizedError() async {
        let (vm, _, repo, haptic) = makeSUT()
        repo.shouldThrow = true
        repo.throwError = CategoryRepositoryError.categoryInUse(expenseCount: 3)

        await vm.deleteCategory(id: UUID())

        XCTAssertNotNil(vm.categoryDeleteError)
        XCTAssertTrue(
            vm.categoryDeleteError?.contains("3") ?? false,
            "Error message should include the blocking expense count"
        )
        XCTAssertEqual(haptic.lastEvent, .error)
    }

    func testDeleteCategoryGenericFailureUsesFallbackMessage() async {
        let (vm, _, repo, _) = makeSUT()
        repo.shouldThrow = true
        repo.throwError = NSError(domain: "Test", code: 1)

        await vm.deleteCategory(id: UUID())

        XCTAssertEqual(vm.categoryDeleteError, "Failed to delete category. Please try again.")
    }

    // MARK: - moveCategory

    func testMoveCategoryReordersLocallyAndPersists() async {
        let (vm, _, repo, _) = makeSUT()
        let a = makeCategory(name: "A", sortOrder: 0)
        let b = makeCategory(name: "B", sortOrder: 1)
        let c = makeCategory(name: "C", sortOrder: 2)
        repo.categoriesToReturn = [a, b, c]
        await vm.loadCategories()

        // Move C (index 2) to position 0 — expected order: C, A, B
        vm.moveCategory(from: IndexSet(integer: 2), to: 0)

        XCTAssertEqual(vm.categories.map(\.name), ["C", "A", "B"])

        // Give the reorder Task a tick to complete
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(repo.reorderCategoriesCalled)
        XCTAssertEqual(repo.lastReorderedIDs, [c.id, a.id, b.id])
    }

    // MARK: - isPaired

    func testIsPairedReflectsHouseholdService() {
        let (vm, household, _, _) = makeSUT()
        XCTAssertFalse(vm.isPaired)

        household.householdCode = "ABCD1234"
        XCTAssertTrue(vm.isPaired)

        household.householdCode = nil
        XCTAssertFalse(vm.isPaired)
    }
}
