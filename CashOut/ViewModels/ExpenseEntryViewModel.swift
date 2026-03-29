import Foundation

@MainActor
@Observable
final class ExpenseEntryViewModel {

    // MARK: - Properties

    var amountInCents: Int64 = 0

    var isAmountZero: Bool {
        amountInCents == 0
    }

    // MARK: - Actions

    // Guard threshold: values below this can safely append one digit
    // without exceeding the cap of 9_999_999 cents ($99,999.99).
    private let maxBeforeAppend: Int64 = 1_000_000

    func appendDigit(_ digit: String) {
        guard amountInCents < maxBeforeAppend else { return }
        guard let value = Int64(digit) else { return }
        amountInCents = amountInCents * 10 + value
    }

    func deleteLastDigit() {
        amountInCents = amountInCents / 10
    }

    func appendDecimalPoint() {
        // No-op: decimal is implicit in fixed-point cents model.
        // Included for numpad grid visual completeness.
    }

    func resetAmount() {
        amountInCents = 0
    }
}
