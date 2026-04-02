import Foundation

extension Date {
    /// Relative time string (e.g., "2 min. ago", "1 hr. ago").
    /// Uses device locale intentionally — relative time strings follow display language, not financial locale.
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
