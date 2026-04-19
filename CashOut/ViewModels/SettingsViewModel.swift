import Foundation
@preconcurrency import CoreData
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "SettingsViewModel")

@MainActor
@Observable
final class SettingsViewModel {
    var errorMessage: String?
    var categories: [CategoryData] = []
    private(set) var isSavingCategory = false
    var categorySaveError: String?
    private(set) var isDeletingCategory = false
    var categoryDeleteError: String?

    @ObservationIgnored
    private let householdService: HouseholdServiceProtocol
    @ObservationIgnored
    private let persistenceController: PersistenceController
    @ObservationIgnored
    private let categoryRepository: CategoryRepositoryProtocol
    @ObservationIgnored
    private let hapticService: HapticServiceProtocol
    @ObservationIgnored
    private let categoryOrderStore: CategoryOrderStore
    @ObservationIgnored
    private var reorderTask: Task<Void, Never>?

    /// True iff a household code is stored locally. Proxies
    /// `HouseholdService.isPaired` so the Settings UI can observe pairing state.
    var isPaired: Bool {
        householdService.isPaired
    }

    init(
        householdService: HouseholdServiceProtocol = HouseholdService.shared,
        persistenceController: PersistenceController = .shared,
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository.shared,
        hapticService: HapticServiceProtocol = HapticService.shared,
        categoryOrderStore: CategoryOrderStore = CategoryOrderStore()
    ) {
        self.householdService = householdService
        self.persistenceController = persistenceController
        self.categoryRepository = categoryRepository
        self.hapticService = hapticService
        self.categoryOrderStore = categoryOrderStore
        logger.debug("SettingsViewModel.init")
    }

    func loadCategories() async {
        logger.debug("loadCategories: fetching")
        do {
            let result = try await categoryRepository.fetchCategories()
            guard !Task.isCancelled else { return }
            logger.info("loadCategories: loaded \(result.count) categories")
            categories = categoryOrderStore.applyUserOrder(to: result)
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("loadCategories: FAILED — \(error.localizedDescription)")
            categories = []
        }
    }

    func saveCategory(name: String, iconName: String, colorName: String, existingID: UUID?) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            logger.debug("saveCategory: empty name — skipped")
            return
        }

        // Prevent accidental demotion of default categories
        if let existingID, categories.first(where: { $0.id == existingID })?.isDefault == true {
            logger.warning("saveCategory: attempted to modify default category — blocked")
            return
        }

        guard !isSavingCategory else {
            logger.debug("saveCategory: already saving — skipped")
            return
        }
        isSavingCategory = true
        defer { isSavingCategory = false }
        categorySaveError = nil

        let id = existingID ?? UUID()
        let sortOrder: Int16 = existingID != nil
            ? (categories.first { $0.id == existingID }?.sortOrder ?? Int16(categories.count))
            : Int16(categories.count)

        logger.info("saveCategory: \(existingID != nil ? "updating" : "creating") '\(trimmedName)' id=\(id)")

        let data = CategoryData(
            id: id,
            name: trimmedName,
            iconName: iconName,
            colorName: colorName,
            isDefault: false,
            sortOrder: sortOrder
        )

        do {
            try await categoryRepository.saveCategory(data)
            guard !Task.isCancelled else { return }
            logger.info("saveCategory: success")
            hapticService.trigger(.saveTap)
            await loadCategories()
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("saveCategory: FAILED — \(error.localizedDescription)")
            hapticService.trigger(.error)
            categorySaveError = "Failed to save category. Please try again."
        }
    }

    // MARK: - Category Reorder & Delete

    func deleteCategory(id: UUID) async {
        guard !isDeletingCategory else {
            logger.debug("deleteCategory: already deleting — skipped")
            return
        }
        isDeletingCategory = true
        defer { isDeletingCategory = false }
        categoryDeleteError = nil

        logger.info("deleteCategory: id=\(id)")
        do {
            try await categoryRepository.deleteCategory(id: id)
            logger.info("deleteCategory: success")
            categoryOrderStore.removeFromOrder(id: id)
            hapticService.trigger(.deleteTap)
            await loadCategories()
        } catch let error as CategoryRepositoryError {
            guard !Task.isCancelled else { return }
            logger.warning("deleteCategory: blocked — \(error.localizedDescription)")
            hapticService.trigger(.error)
            categoryDeleteError = error.localizedDescription
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("deleteCategory: FAILED — \(error.localizedDescription)")
            hapticService.trigger(.error)
            categoryDeleteError = "Failed to delete category. Please try again."
        }
    }

    func moveCategory(from source: IndexSet, to destination: Int) {
        logger.info("moveCategory: from=\(source.map { $0 }) to=\(destination) (\(self.categories.count) categories)")
        categories.move(fromOffsets: source, toOffset: destination)
        categoryOrderStore.persistOrder(categories)

        let orderedIDs = categories.map(\.id)
        let repo = categoryRepository
        if reorderTask != nil {
            logger.debug("moveCategory: cancelling prior reorder task (coalescing)")
        }
        reorderTask?.cancel()
        reorderTask = Task {
            do {
                try await repo.reorderCategories(orderedIDs)
                logger.debug("moveCategory: Core Data reorder complete")
            } catch {
                logger.error("moveCategory: reorder FAILED — \(error.localizedDescription)")
            }
        }
    }
}
