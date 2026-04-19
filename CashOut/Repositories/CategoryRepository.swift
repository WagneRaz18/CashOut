@preconcurrency import CoreData
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "CategoryRepository")

@MainActor
final class CategoryRepository: CategoryRepositoryProtocol {
    static let shared = CategoryRepository()

    private let persistence: PersistenceController
    private let householdService: HouseholdServiceProtocol
    private let publicSync: PublicSyncServiceProtocol

    init(
        persistence: PersistenceController = .shared,
        householdService: HouseholdServiceProtocol = HouseholdService.shared,
        publicSync: PublicSyncServiceProtocol = PublicSyncService.shared
    ) {
        self.persistence = persistence
        self.householdService = householdService
        self.publicSync = publicSync
    }

    func fetchCategories() async throws -> [CategoryData] {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.predicate = NSPredicate(format: "isSoftDeleted == NO OR isSoftDeleted == nil")
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "id", ascending: true),
        ]

        // Single-store model post-CKShare-removal: everything lives in the private store.
        if let privateStore = persistence.privatePersistentStore {
            request.affectedStores = [privateStore]
        }

        let results = try persistence.container.viewContext.fetch(request)
        logger.debug("fetchCategories: found \(results.count) categories (pre-dedup)")

        // Defense-in-depth dedup: guards against transient duplicate defaults that can
        // surface during post-seed imports and initial pairing merges.
        var seenDefaultNames = Set<String>()
        var seenDefaultIDs = Set<UUID>()
        let unique = results.compactMap { category -> CategoryData? in
            if category.isDefault {
                let name = category.wrappedName
                let id = category.wrappedID
                guard !seenDefaultNames.contains(name),
                      !seenDefaultIDs.contains(id) else { return nil }
                seenDefaultNames.insert(name)
                seenDefaultIDs.insert(id)
            }
            return CategoryData(
                id: category.wrappedID,
                name: category.wrappedName,
                iconName: category.wrappedIconName,
                colorName: category.wrappedColorName,
                isDefault: category.isDefault,
                sortOrder: category.sortOrder
            )
        }
        logger.debug("fetchCategories: returning \(unique.count) categories (post-dedup)")
        return unique
    }

    func saveCategory(_ data: CategoryData) async throws {
        logger.info("saveCategory: '\(data.name)' id=\(data.id)")
        let context = persistence.container.viewContext

        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", data.id as NSUUID)
        request.fetchLimit = 1

        let existing = try context.fetch(request).first
        let category = existing ?? Category(context: context)
        logger.debug("saveCategory: \(existing != nil ? "updating" : "creating")")

        category.id = data.id
        category.name = data.name
        category.iconName = data.iconName
        category.colorName = data.colorName
        category.isDefault = data.isDefault
        category.sortOrder = data.sortOrder
        category.isSoftDeleted = false
        category.modifiedAt = Date()
        category.householdCode = householdService.householdCode

        do {
            try context.save()
            logger.info("saveCategory: saved successfully")
        } catch {
            logger.error("saveCategory: context.save() FAILED — \(error.localizedDescription)")
            context.rollback()
            throw error
        }

        if householdService.isPaired {
            publicSync.upsert(category: category)
        }
    }

    func deleteCategory(id: UUID) async throws {
        logger.info("deleteCategory: id=\(id)")
        let context = persistence.container.viewContext

        // Block deletion if any expenses reference this category.
        let expenseRequest: NSFetchRequest<Expense> = Expense.fetchRequest()
        expenseRequest.predicate = NSPredicate(
            format: "categoryID == %@ AND (isSoftDeleted == NO OR isSoftDeleted == nil)",
            id as NSUUID
        )
        let expenseCount = try context.count(for: expenseRequest)
        if expenseCount > 0 {
            logger.warning("deleteCategory: blocked — \(expenseCount) expenses reference this category")
            throw CategoryRepositoryError.categoryInUse(expenseCount: expenseCount)
        }

        // Soft-delete: tombstone instead of hard delete so the partner sees the removal.
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        if let privateStore = persistence.privatePersistentStore {
            request.affectedStores = [privateStore]
        }
        guard let category = try context.fetch(request).first else {
            logger.warning("deleteCategory: id=\(id) not found — already deleted")
            return
        }
        category.isSoftDeleted = true
        category.modifiedAt = Date()

        do {
            try context.save()
            logger.info("deleteCategory: tombstoned successfully")
        } catch {
            logger.error("deleteCategory: context.save() FAILED — \(error.localizedDescription)")
            context.rollback()
            throw error
        }

        if householdService.isPaired {
            publicSync.upsert(category: category)
        }
    }

    func reorderCategories(_ orderedIDs: [UUID]) async throws {
        logger.info("reorderCategories: \(orderedIDs.count) categories")
        let context = persistence.container.viewContext

        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", orderedIDs as [NSUUID])
        if let privateStore = persistence.privatePersistentStore {
            request.affectedStores = [privateStore]
        }
        let results = try context.fetch(request)
        if results.count != orderedIDs.count {
            logger.warning("reorderCategories: fetched \(results.count) but expected \(orderedIDs.count) — some categories missing from store")
        }

        let lookup = Dictionary(grouping: results, by: { $0.wrappedID })
        let now = Date()
        for (index, id) in orderedIDs.enumerated() {
            guard let categories = lookup[id] else { continue }
            for category in categories {
                category.sortOrder = Int16(index)
                category.modifiedAt = now
            }
        }

        do {
            try context.save()
            logger.info("reorderCategories: saved successfully")
        } catch {
            logger.error("reorderCategories: context.save() FAILED — \(error.localizedDescription)")
            context.rollback()
            throw error
        }

        // Mirror reorder to partner via public DB (one upsert per category).
        if householdService.isPaired {
            for category in results {
                publicSync.upsert(category: category)
            }
        }
    }

    /// Best-effort cleanup that deletes duplicate default category records from the
    /// private store, keeping the first (by sortOrder, then id) for each name.
    func purgeDuplicateDefaults() throws {
        guard let privateStore = persistence.privatePersistentStore else {
            logger.error("purgeDuplicateDefaults: no private store — skipping")
            return
        }

        let context = persistence.container.viewContext
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.predicate = NSPredicate(format: "isDefault == YES")
        request.affectedStores = [privateStore]
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "id", ascending: true),
        ]

        let defaults = try context.fetch(request)
        var seenIDs = Set<UUID>()
        var seenNames = Set<String>()
        var duplicates: [Category] = []

        for category in defaults {
            let id = category.wrappedID
            let name = category.wrappedName
            if seenIDs.contains(id) || seenNames.contains(name) {
                duplicates.append(category)
            } else {
                seenIDs.insert(id)
                seenNames.insert(name)
            }
        }

        guard !duplicates.isEmpty else { return }
        logger.info("purgeDuplicateDefaults: deleting \(duplicates.count) duplicate default categories")
        for dup in duplicates {
            context.delete(dup)
        }
        do {
            try context.save()
            logger.info("purgeDuplicateDefaults: purge complete")
        } catch {
            logger.error("purgeDuplicateDefaults: save FAILED — \(error.localizedDescription)")
            context.rollback()
            throw error
        }
    }

    func seedDefaultCategoriesIfNeeded() async throws {
        let context = persistence.container.viewContext

        guard let privateStore = persistence.privatePersistentStore else {
            logger.error("seedDefaultCategoriesIfNeeded: no persistent stores — skipping")
            return
        }

        guard !UserDefaults.standard.bool(forKey: "categoriesHaveBeenSeeded") else {
            logger.debug("seedDefaultCategoriesIfNeeded: already seeded — skipped")
            return
        }

        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.predicate = NSPredicate(format: "isDefault == YES")
        request.affectedStores = [privateStore]
        let count = try context.count(for: request)

        guard count == 0 else {
            logger.debug("seedDefaultCategoriesIfNeeded: \(count) categories exist — setting flag and skipping")
            UserDefaults.standard.set(true, forKey: "categoriesHaveBeenSeeded")
            return
        }

        logger.info("seedDefaultCategoriesIfNeeded: seeding \(DefaultCategory.allCases.count) default categories")
        for defaultCategory in DefaultCategory.allCases {
            let category = Category(context: context)
            category.id = defaultCategory.stableID
            category.name = defaultCategory.name
            category.iconName = defaultCategory.iconName
            category.colorName = defaultCategory.colorName
            category.isDefault = true
            category.sortOrder = defaultCategory.sortOrder
            category.isSoftDeleted = false
            category.modifiedAt = Date()
        }

        do {
            try context.save()
        } catch {
            logger.error("seedDefaultCategoriesIfNeeded: context.save() FAILED — \(error.localizedDescription)")
            context.rollback()
            throw error
        }
        UserDefaults.standard.set(true, forKey: "categoriesHaveBeenSeeded")
        logger.info("seedDefaultCategoriesIfNeeded: seeding complete")
    }
}
