import Foundation

struct CategoryData: Sendable, Hashable {
    let id: UUID
    let name: String
    let iconName: String
    let colorName: String
    let isDefault: Bool
    let sortOrder: Int16
}
