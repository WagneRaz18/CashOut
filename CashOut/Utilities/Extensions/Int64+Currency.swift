import Foundation

extension Int64 {
    var displayAmount: String {
        let dollars = Double(self) / 100.0
        return dollars.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
    }
}
