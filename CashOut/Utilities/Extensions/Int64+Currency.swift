import Foundation

extension Int64 {
    /// Formats satang as THB string (e.g., 1250 → "฿12.50").
    /// Hardcoded to th_TH / THB — intentional for this personal-use, THB-only app.
    var displayAmount: String {
        let baht = Double(self) / 100.0
        return baht.formatted(.currency(code: "THB").locale(Locale(identifier: "th_TH")))
    }
}
