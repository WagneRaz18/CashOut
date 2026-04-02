import Foundation
import SwiftUI

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

// MARK: - Partner Colors (Story 2-1)

enum PartnerColor {
    /// Current user: cool blue
    static let currentUser = Color(red: 0x6B / 255.0, green: 0x8A / 255.0, blue: 0xAE / 255.0)
    /// Current user dark mode
    static let currentUserDark = Color(red: 0x8A / 255.0, green: 0xA8 / 255.0, blue: 0xC8 / 255.0)
    /// Partner: warm stone
    static let partner = Color(red: 0xA8 / 255.0, green: 0x9B / 255.0, blue: 0x8A / 255.0)
    /// Partner dark mode
    static let partnerDark = Color(red: 0xC0 / 255.0, green: 0xB0 / 255.0, blue: 0xA0 / 255.0)

    static func color(isCurrentUser: Bool, colorScheme: ColorScheme) -> Color {
        switch (isCurrentUser, colorScheme) {
        case (true, .light): currentUser
        case (true, .dark): currentUserDark
        case (false, .light): partner
        case (false, .dark): partnerDark
        @unknown default: currentUser
        }
    }
}
