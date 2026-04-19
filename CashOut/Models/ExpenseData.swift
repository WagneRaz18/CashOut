import Foundation

struct ExpenseData: Sendable, Identifiable {
    let id: UUID
    let amount: Int64
    let note: String?
    let categoryID: UUID
    let createdByUserID: String
    let createdByDisplayName: String
    let createdAt: Date
    let modifiedAt: Date

    init(
        id: UUID,
        amount: Int64,
        note: String?,
        categoryID: UUID,
        createdByUserID: String,
        createdByDisplayName: String = "",
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.amount = amount
        self.note = note
        self.categoryID = categoryID
        self.createdByUserID = createdByUserID
        self.createdByDisplayName = createdByDisplayName
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
