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

        if isNewCustomCategory {
            guard !Task.isCancelled else { return }
            logger.debug("saveCategory: sharing custom category to household")
            try await cloudSharingService?.shareObjectsToHouseholdIfNeeded([category])
        }
    }

    func seedDefaultCategoriesIfNeeded() async throws {
        let context = persistence.container.viewContext

        // Guard: context.save() throws NSInternalInconsistencyException (ObjC exception,
        // not caught by Swift do/catch) when the coordinator has zero stores.
        // Check specifically for the private store — default categories are private data.
        guard persistence.privatePersistentStore != nil else {
            logger.error("seedDefaultCategoriesIfNeeded: no persistent stores — skipping")
            return
        }

        let request: NSFetchRequest<Category> = Category.fetchRequest()
        let count = try context.count(for: request)

        guard count == 0 else {
            logger.debug("seedDefaultCategoriesIfNeeded: \(count) categories exist — skipped")
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
            context.rollback()
            throw error
        }
        logger.info("seedDefaultCategoriesIfNeeded: seeding complete")
    }
}
