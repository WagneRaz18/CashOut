import Foundation

struct ExpenseData: Sendable, Identifiable {
    let id: UUID
    let amount: Int64
    let note: String?
    let categoryID: UUID
    let createdByUserID: String
    let createdAt: Date
    let modifiedAt: Date
}
