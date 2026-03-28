import SwiftUI

enum CategoryColor: String, CaseIterable {
    case sage = "Sage"
    case slate = "Slate"
    case lavender = "Lavender"
    case amber = "Amber"
    case dustyRose = "DustyRose"
    case coolGray = "CoolGray"

    var color: Color {
        Color(self.rawValue)
    }

    init?(from colorName: String) {
        self.init(rawValue: colorName)
    }
}
