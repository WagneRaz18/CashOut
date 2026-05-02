import Foundation

extension Calendar {
    // App-wide Gregorian calendar. CashOut never uses device calendar (Buddhist on Thai locale).
    static let gregorian = Calendar(identifier: .gregorian)
}
