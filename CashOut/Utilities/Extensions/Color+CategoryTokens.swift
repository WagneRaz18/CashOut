import SwiftUI

enum CategoryColor: String, CaseIterable {
    // Predefined category defaults — NOT selectable for custom categories
    case sage = "Sage"
    case slate = "Slate"
    case lavender = "Lavender"
    case amber = "Amber"
    case dustyRose = "DustyRose"
    case coolGray = "CoolGray"

    // Secondary palette — selectable for custom categories
    case teal = "Teal"
    case coral = "Coral"
    case plum = "Plum"
    case olive = "Olive"
    case indigo = "Indigo"
    case clay = "Clay"

    var color: Color {
        Color(self.rawValue)
    }

    static var customPalette: [CategoryColor] {
        [.teal, .coral, .plum, .olive, .indigo, .clay]
    }

    init?(from colorName: String) {
        self.init(rawValue: colorName)
    }
}
