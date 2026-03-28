import Foundation

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum DefaultCategory: CaseIterable {
    case foodAndDrink
    case transport
    case entertainment
    case household
    case shopping
    case other

    var name: String {
        switch self {
        case .foodAndDrink: "Food & Drink"
        case .transport: "Transport"
        case .entertainment: "Entertainment"
        case .household: "Household"
        case .shopping: "Shopping"
        case .other: "Other"
        }
    }

    var iconName: String {
        switch self {
        case .foodAndDrink: "fork.knife"
        case .transport: "car.fill"
        case .entertainment: "film.fill"
        case .household: "house.fill"
        case .shopping: "bag.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    var colorName: String {
        switch self {
        case .foodAndDrink: "Sage"
        case .transport: "Slate"
        case .entertainment: "Lavender"
        case .household: "Amber"
        case .shopping: "DustyRose"
        case .other: "CoolGray"
        }
    }

    var sortOrder: Int16 {
        switch self {
        case .foodAndDrink: 0
        case .transport: 1
        case .entertainment: 2
        case .household: 3
        case .shopping: 4
        case .other: 5
        }
    }
}
