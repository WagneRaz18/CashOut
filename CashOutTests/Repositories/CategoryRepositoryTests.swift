import XCTest
@testable import CashOut

final class CategoryRepositoryTests: XCTestCase {
    private var repository: CategoryRepository!

    @MainActor
    override func setUp() async throws {
        let controller = TestPersistenceHelper.makeInMemoryController()
        repository = CategoryRepository(persistence: controller)
    }

    @MainActor
    func testSeedDefaultCategoriesCreatesExactlySix() async throws {
        try await repository.seedDefaultCategoriesIfNeeded()
        let categories = try await repository.fetchCategories()
        XCTAssertEqual(categories.count, 6)
    }

    @MainActor
    func testSeedDefaultCategoriesIsIdempotent() async throws {
        try await repository.seedDefaultCategoriesIfNeeded()
        try await repository.seedDefaultCategoriesIfNeeded()
        let categories = try await repository.fetchCategories()
        XCTAssertEqual(categories.count, 6, "Calling seed twice should not create duplicates")
    }

    @MainActor
    func testFetchCategoriesReturnsSortedBySortOrder() async throws {
        try await repository.seedDefaultCategoriesIfNeeded()
        let categories = try await repository.fetchCategories()
        let sortOrders = categories.map(\.sortOrder)
        XCTAssertEqual(sortOrders, [0, 1, 2, 3, 4, 5])
    }

    @MainActor
    func testSeededCategoriesHaveCorrectData() async throws {
        try await repository.seedDefaultCategoriesIfNeeded()
        let categories = try await repository.fetchCategories()

        XCTAssertEqual(categories[0].name, "Food & Drink")
        XCTAssertEqual(categories[0].iconName, "fork.knife")
        XCTAssertEqual(categories[0].colorName, "Sage")
        XCTAssertTrue(categories[0].isDefault)

        XCTAssertEqual(categories[1].name, "Transport")
        XCTAssertEqual(categories[1].iconName, "car.fill")
        XCTAssertEqual(categories[1].colorName, "Slate")

        XCTAssertEqual(categories[2].name, "Entertainment")
        XCTAssertEqual(categories[2].iconName, "film.fill")
        XCTAssertEqual(categories[2].colorName, "Lavender")

        XCTAssertEqual(categories[3].name, "Household")
        XCTAssertEqual(categories[3].iconName, "house.fill")
        XCTAssertEqual(categories[3].colorName, "Amber")

        XCTAssertEqual(categories[4].name, "Shopping")
        XCTAssertEqual(categories[4].iconName, "bag.fill")
        XCTAssertEqual(categories[4].colorName, "DustyRose")

        XCTAssertEqual(categories[5].name, "Other")
        XCTAssertEqual(categories[5].iconName, "ellipsis.circle.fill")
        XCTAssertEqual(categories[5].colorName, "CoolGray")
    }

    @MainActor
    func testSaveCategoryPersistsData() async throws {
        let data = CategoryData(
            id: UUID(),
            name: "Custom",
            iconName: "star.fill",
            colorName: "Sage",
            isDefault: false,
            sortOrder: 10
        )
        try await repository.saveCategory(data)
        let categories = try await repository.fetchCategories()
        XCTAssertEqual(categories.count, 1)
        XCTAssertEqual(categories.first?.name, "Custom")
        XCTAssertEqual(categories.first?.isDefault, false)
    }

    @MainActor
    func testSaveCategoryUpdatesExisting() async throws {
        let id = UUID()
        let original = CategoryData(
            id: id,
            name: "Original",
            iconName: "star.fill",
            colorName: "Sage",
            isDefault: false,
            sortOrder: 10
        )
        try await repository.saveCategory(original)

        let updated = CategoryData(
            id: id,
            name: "Updated",
            iconName: "heart.fill",
            colorName: "Amber",
            isDefault: false,
            sortOrder: 10
        )
        try await repository.saveCategory(updated)

        let categories = try await repository.fetchCategories()
        XCTAssertEqual(categories.count, 1)
        XCTAssertEqual(categories.first?.name, "Updated")
        XCTAssertEqual(categories.first?.iconName, "heart.fill")
    }
}
