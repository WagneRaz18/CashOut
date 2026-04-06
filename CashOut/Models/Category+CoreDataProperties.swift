@preconcurrency import CoreData

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
    private static let nilSentinelID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    public var wrappedID: UUID {
        id ?? Self.nilSentinelID
    }

    public var wrappedName: String {
        name ?? ""
    }

    public var wrappedIconName: String {
        iconName ?? "questionmark"
    }

    public var wrappedColorName: String {
        colorName ?? "CoolGray"
    }
}
