import Foundation

extension Date {
    /// Relative time string (e.g., "2 min. ago", "1 hr. ago").
    /// Uses device locale intentionally — relative time strings follow display language, not financial locale.
    /// - Parameter reference: the "now" used for comparison. Pass a `TimelineView` context date
    ///   for live-ticking displays; defaults to `Date()` for one-shot reads (e.g., accessibility labels).
    func relativeFormatted(relativeTo reference: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: reference)
    }

    var relativeFormatted: String { relativeFormatted(relativeTo: Date()) }
}
