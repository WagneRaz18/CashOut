@preconcurrency import CoreData

@MainActor
final class CategoryRepository: CategoryRepositoryProtocol {
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
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]

        let results = try persistence.container.viewContext.fetch(request)
        return results.map { category in
            CategoryData(
                id: category.wrappedID,
                name: category.wrappedName,
                iconName: category.wrappedIconName,
                colorName: category.wrappedColorName,
                isDefault: category.isDefault,
                sortOrder: category.sortOrder
            )
        }
    }

    func saveCategory(_ data: CategoryData) async throws {
        let context = persistence.container.viewContext

        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", data.id as CVarArg)
        request.fetchLimit = 1

        let existing = try context.fetch(request).first
        let isNewCustomCategory = existing == nil && !data.isDefault
        let category = existing ?? Category(context: context)

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

        try context.save()

        if isNewCustomCategory {
            guard !Task.isCancelled else { return }
            try await cloudSharingService?.shareObjectsToHouseholdIfNeeded([category])
        }
    }

    func seedDefaultCategoriesIfNeeded() async throws {
        let context = persistence.container.viewContext

        let request: NSFetchRequest<Category> = Category.fetchRequest()
        let count = try context.count(for: request)

        guard count == 0 else { return }

        for defaultCategory in DefaultCategory.allCases {
            let category = Category(context: context)
            category.id = UUID()
            category.name = defaultCategory.name
            category.iconName = defaultCategory.iconName
            category.colorName = defaultCategory.colorName
            category.isDefault = true
            category.sortOrder = defaultCategory.sortOrder
        }

        try context.save()
    }
}
