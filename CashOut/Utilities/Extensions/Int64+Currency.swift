import Foundation

extension Int64 {
    /// Formats cents as USD string (e.g., 1250 → "$12.50").
    /// Hardcoded to en_US / USD — intentional for this personal-use, USD-only app.
    var displayAmount: String {
        let dollars = Double(self) / 100.0
        return dollars.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
    }
}
