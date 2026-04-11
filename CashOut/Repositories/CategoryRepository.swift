@preconcurrency import CoreData
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "CategoryRepository")

@MainActor
final class CategoryRepository: CategoryRepositoryProtocol {
    static let shared = CategoryRepository()

    private let persistence: PersistenceController
    private let cloudSharingService: CloudSharingServiceProtocol?

    /// Active fire-and-forget share tasks, keyed by category ID. Owned by the singleton so
    /// they survive view dismissal — a successful save must never lose its household share
    /// just because the user popped Settings before CloudKit finished.
    private var activeShareTasks: [UUID: Task<Void, Never>] = [:]

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

        // Scope the fetch to the user's primary store. Without this, an unscoped
        // viewContext.fetch aggregates records from BOTH stores, returning 2N
        // results once NSPersistentCloudKitContainer mirrors private-store data
        // into the shared-store backing zone. Mirrors the role-based pattern in
        // ExpenseRepository.deleteExpense: participants target sharedPersistentStore
        // (their categories live there via prepareObjectForSharedSave); owner and
        // solo mode target privatePersistentStore.
        let targetStore: NSPersistentStore?
        if let svc = cloudSharingService,
           !svc.isShareOwner,
           case .connected = svc.state {
            targetStore = persistence.sharedPersistentStore
        } else {
            targetStore = persistence.privatePersistentStore
        }
        if let targetStore {
            request.affectedStores = [targetStore]
        }

        let results = try persistence.container.viewContext.fetch(request)
        logger.debug("fetchCategories: found \(results.count) categories (pre-dedup)")

        // Defense-in-depth dedup: scoping above eliminates the 2N cross-store
        // duplication, but this block still guards against transient races
        // during participant-mode shared-zone imports and double-seeding
        // across reinstalls. Custom categories are never deduplicated.
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

        // Route new custom categories to shared zone for partner sync.
        // `prepareObjectForSharedSave` no-ops outside of participant+.connected,
        // and it emits its own debug log when it actually performs the assignment.
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
        if results.count != orderedIDs.count {
            logger.warning("reorderCategories: fetched \(results.count) but expected \(orderedIDs.count) — some categories missing from store")
        }

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

    /// Delay before calling `container.share()` to let NSPersistentCloudKitContainer's
    /// async export cycle (triggered by the preceding `context.save()`) register
    /// metadata for the new record. Without this delay, `container.share()` races the
    /// export and produces "Missing metadata for recordID" errors plus a 3s result-
    /// accumulator timeout inside the container. 800ms is empirically sufficient for
    /// the export to advance past the metadata-registration point on a warm connection.
    private static let shareExportSettleDelay: UInt64 = 800_000_000 // 800ms

    func enqueueShareForNewCategory(id: UUID) {
        // Solo-mode fast path: skip Task creation + 800ms sleep + inner isShareOwner
        // guard entirely. The NSPersistentStoreRemoteChange listener in ContentView
        // handles state transitions; this guard only needs to catch the steady state.
        guard let svc = cloudSharingService, svc.state != .solo else {
            logger.debug("enqueueShareForNewCategory: solo mode — skipping")
            return
        }
        logger.debug("enqueueShareForNewCategory: id=\(id, privacy: .private)")
        activeShareTasks[id]?.cancel()
        let task = Task { [self] in
            // Yield first so the caller's @MainActor continuation (e.g. Settings
            // sheet dismiss) can resume before container.share() grabs the actor.
            await Task.yield()
            await shareNewCategoryToHousehold(id: id)
            activeShareTasks[id] = nil
        }
        activeShareTasks[id] = task
    }

    func shareNewCategoryToHousehold(id: UUID) async {
        logger.info("shareNewCategoryToHousehold: starting — id=\(id, privacy: .private)")
        // Participant path no-ops inside shareObjectsToHouseholdIfNeeded, so skip the
        // 800ms sleep entirely for participants — they use the pre-save routing path.
        guard cloudSharingService?.isShareOwner == true else {
            logger.debug("shareNewCategoryToHousehold: not owner — skipping post-save share")
            return
        }
        // Let context.save()'s async CloudKit export register metadata before we
        // invoke container.share() — see shareExportSettleDelay doc comment.
        // Must catch CancellationError explicitly: `try?` would silently proceed on
        // cancel and race the caller's teardown.
        do {
            try await Task.sleep(nanoseconds: Self.shareExportSettleDelay)
        } catch {
            return
        }

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
