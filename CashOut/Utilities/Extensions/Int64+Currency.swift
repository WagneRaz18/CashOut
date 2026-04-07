import Foundation

extension Int64 {
    /// Formats satang as whole-Baht THB string (e.g., 5000 → "฿50").
    /// Hardcoded to th_TH / THB — intentional for this personal-use, THB-only app.
    /// Decimal places omitted: cash expenses are always whole Baht.
    var displayAmount: String {
        let baht = Decimal(self) / 100
        return baht.formatted(
            .currency(code: "THB")
            .locale(Locale(identifier: "th_TH"))
            .precision(.fractionLength(0))
        )
    }
}
