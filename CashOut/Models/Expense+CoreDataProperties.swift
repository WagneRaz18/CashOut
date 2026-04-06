@preconcurrency import CoreData

extension Expense {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Expense> {
        NSFetchRequest<Expense>(entityName: "Expense")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var amount: Int64
    @NSManaged public var note: String?
    @NSManaged public var categoryID: UUID?
    @NSManaged public var createdByUserID: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
}

extension Expense: Identifiable {
    private static let nilSentinelID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    public var wrappedID: UUID {
        id ?? Self.nilSentinelID
    }

    public var wrappedCreatedAt: Date {
        createdAt ?? .distantPast
    }

    public var wrappedModifiedAt: Date {
        modifiedAt ?? .distantPast
    }

    public var wrappedCreatedByUserID: String {
        createdByUserID ?? ""
    }
}
