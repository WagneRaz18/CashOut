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
    public var wrappedID: UUID {
        id ?? UUID()
    }

    public var wrappedCreatedAt: Date {
        createdAt ?? Date()
    }

    public var wrappedModifiedAt: Date {
        modifiedAt ?? Date()
    }

    public var wrappedCreatedByUserID: String {
        createdByUserID ?? ""
    }
}
