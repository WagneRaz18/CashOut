import XCTest
@testable import CashOut

@MainActor
final class Int64CurrencyTests: XCTestCase {
    func testDisplayAmountFormatsTypicalValue() {
        let amount: Int64 = 5000
        XCTAssertTrue(
            amount.displayAmount.contains("50"),
            "Expected '50' in '\(amount.displayAmount)' (5000 satang = 50 Baht)"
        )
    }

    func testDisplayAmountFormatsZero() {
        let amount: Int64 = 0
        XCTAssertTrue(
            amount.displayAmount.contains("0"),
            "Expected '0' in '\(amount.displayAmount)'"
        )
    }

    func testDisplayAmountOmitsDecimalPlaces() {
        let amount: Int64 = 1250
        XCTAssertFalse(
            amount.displayAmount.contains("."),
            "displayAmount should not contain decimal point, got '\(amount.displayAmount)'"
        )
    }

    func testDisplayAmountFormatsLargeValue() {
        let amount: Int64 = 100_000
        XCTAssertTrue(
            amount.displayAmount.contains("1,000") || amount.displayAmount.contains("1 000"),
            "Expected thousands-formatted '1,000' in '\(amount.displayAmount)' (100000 satang = 1000 Baht)"
        )
    }

    func testDisplayAmountRoundsSubBahtToZero() {
        let amount: Int64 = 49
        XCTAssertTrue(
            amount.displayAmount.contains("0"),
            "Expected '0' in '\(amount.displayAmount)' (49 satang < 1 Baht)"
        )
    }

    func testDisplayAmountUsesTHBCurrency() {
        let amount: Int64 = 1250
        let display = amount.displayAmount
        XCTAssertTrue(
            display.contains("฿") || display.contains("THB"),
            "Expected THB symbol or code in '\(display)'"
        )
    }
}
