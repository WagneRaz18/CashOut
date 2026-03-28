import CoreData

extension Category {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Category> {
        NSFetchRequest<Category>(entityName: "Category")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var iconName: String?
    @NSManaged public var colorName: String?
    @NSManaged public var isDefault: Bool
    @NSManaged public var sortOrder: Int16
}

extension Category: Identifiable {
    public var wrappedID: UUID {
        id ?? UUID()
    }

    public var wrappedName: String {
        name ?? ""
    }

    public var wrappedIconName: String {
        iconName ?? "questionmark"
    }

    public var wrappedColorName: String {
        colorName ?? "gray"
    }
}
