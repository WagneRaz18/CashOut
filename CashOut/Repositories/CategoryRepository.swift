@preconcurrency import CoreData
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "CategoryRepository")

@MainActor
final class CategoryRepository: CategoryRepositoryProtocol {
    static let shared = CategoryRepository()

    private let persistence: PersistenceController
    private let cloudSharingService: CloudSharingServiceProtocol?

    init(
        persistence: PersistenceController = .shared,
        cloudSharingService: CloudSharingServiceProtocol? = CloudSharingService.shared
    ) {
        self.persistence = persistence
        self.cloudSharingService = cloudSharingService
    }

    func fetchCategories() async throws -> [CategoryData] {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "id", ascending: true),
        ]

        let results = try persistence.container.viewContext.fetch(request)
        logger.debug("fetchCategories: found \(results.count) categories (pre-dedup)")

        // Deduplicate default categories by name or id — CloudKit sync across
        // private/shared stores can create duplicates when both devices seed.
        // Custom categories are never deduplicated (user may reuse names).
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
        request.predicate = NSPredicate(format: "id == %@", data.id as CVarArg)
        request.fetchLimit = 1

        let existing = try context.fetch(request).first
        let isNewCustomCategory = existing == nil && !data.isDefault
        let category = existing ?? Category(context: context)
        logger.debug("saveCategory: \(existing != nil ? "updating" : "creating") \(isNewCustomCategory ? "(custom)" : "")")

        category.id = data.id
        category.name = data.name
        category.iconName = data.iconName
        category.colorName = data.colorName
        category.isDefault = data.isDefault
        category.sortOrder = data.sortOrder

        // Route new custom categories to shared zone for partner sync
        if isNewCustomCategory {
            cloudSharingService?.prepareObjectForSharedSave(category)
        }

        do {
            try context.save()
            logger.info("saveCategory: saved successfully")
        } catch {
            logger.error("saveCategory: context.save() FAILED — \(error.localizedDescription)")
            context.rollback()
            throw error
        }

    }

    func deleteCategory(id: UUID) async throws {
        logger.info("deleteCategory: id=\(id)")
        let context = persistence.container.viewContext

        // Block deletion if any expenses reference this category
        let expenseRequest: NSFetchRequest<Expense> = Expense.fetchRequest()
        expenseRequest.predicate = NSPredicate(format: "categoryID == %@", id as CVarArg)
        let expenseCount = try context.count(for: expenseRequest)
        if expenseCount > 0 {
            logger.warning("deleteCategory: blocked — \(expenseCount) expenses reference this category")
            throw CategoryRepositoryError.categoryInUse(expenseCount: expenseCount)
        }

        // Delete from private store — NSPersistentCloudKitContainer propagates the
        // tombstone to the partner's shared store via CloudKit history tracking.
        if let privateStore = persistence.privatePersistentStore {
            let privateRequest: NSFetchRequest<Category> = Category.fetchRequest()
            privateRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            privateRequest.affectedStores = [privateStore]
            let privateResults = try context.fetch(privateRequest)
            for category in privateResults {
                context.delete(category)
            }
            logger.debug("deleteCategory: marked \(privateResults.count) private-store record(s) for deletion")
        }

        do {
            try context.save()
            logger.info("deleteCategory: success")
        } catch {
            logger.error("deleteCategory: context.save() FAILED — \(error.localizedDescription)")
            context.rollback()
            throw error
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

        let lookup = Dictionary(grouping: results, by: { $0.wrappedID })
        for (index, id) in orderedIDs.enumerated() {
            guard let categories = lookup[id] else { continue }
            for category in categories {
                category.sortOrder = Int16(index)
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
    }

    func shareNewCategoryToHousehold(id: UUID) async {
        let context = persistence.container.viewContext
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        let category: Category
        do {
            guard let found = try context.fetch(request).first else {
                logger.warning("shareNewCategoryToHousehold: category \(id, privacy: .private) not found — skipping")
                return
            }
            category = found
        } catch {
            logger.fault("shareNewCategoryToHousehold: fetch FAILED — \(error.localizedDescription, privacy: .public)")
            return
        }
        guard !Task.isCancelled else { return }
        logger.debug("shareNewCategoryToHousehold: sharing to household")
        do {
            try await cloudSharingService?.shareObjectsToHouseholdIfNeeded([category])
        } catch {
            logger.error("shareNewCategoryToHousehold: FAILED — \(error.localizedDescription)")
        }
    }

    /// Best-effort cleanup that deletes duplicate default category records from the
    /// private store, keeping the first (by sortOrder, then id) for each name.
    /// Client-side dedup in fetchCategories() is the authoritative gate;
    /// this reduces persistent storage bloat only.
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

        // Guard: context.save() throws NSInternalInconsistencyException (ObjC exception,
        // not caught by Swift do/catch) when the coordinator has zero stores.
        // Check specifically for the private store — default categories are private data.
        guard let privateStore = persistence.privatePersistentStore else {
            logger.error("seedDefaultCategoriesIfNeeded: no persistent stores — skipping")
            return
        }

        // Use a UserDefaults flag instead of count check. If user deletes all defaults,
        // count would be 0 and re-seeding would undo their deletions.
        guard !UserDefaults.standard.bool(forKey: "categoriesHaveBeenSeeded") else {
            logger.debug("seedDefaultCategoriesIfNeeded: already seeded — skipped")
            return
        }

        // Also skip if defaults already exist (first-launch backward compat)
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
