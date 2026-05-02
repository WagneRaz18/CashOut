import Foundation

extension Calendar {
    // App-wide Gregorian calendar. CashOut never uses device calendar (Buddhist on Thai locale).
    // firstWeekday = 1 (Sunday-first grid). timeZone pinned to Bangkok — not device timezone —
    // so startOfDay is consistent in CI (UTC) and on Thai devices.
    static let gregorian: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return cal
    }()
}
