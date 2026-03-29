import Foundation

extension Int64 {
    /// Formats satang as THB string (e.g., 1250 → "฿12.50").
    /// Hardcoded to th_TH / THB — intentional for this personal-use, THB-only app.
    var displayAmount: String {
        let baht = Decimal(self) / 100
        return baht.formatted(.currency(code: "THB").locale(Locale(identifier: "th_TH")))
    }
}
