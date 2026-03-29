import XCTest
@testable import CashOut

final class Int64CurrencyTests: XCTestCase {
    @MainActor
    func testDisplayAmountFormatsTypicalValue() {
        let amount: Int64 = 1250
        XCTAssertTrue(
            amount.displayAmount.contains("12.50"),
            "Expected '12.50' in '\(amount.displayAmount)'"
        )
    }

    @MainActor
    func testDisplayAmountFormatsZero() {
        let amount: Int64 = 0
        XCTAssertTrue(
            amount.displayAmount.contains("0.00"),
            "Expected '0.00' in '\(amount.displayAmount)'"
        )
    }

    @MainActor
    func testDisplayAmountFormatsSatangOnly() {
        let amount: Int64 = 99
        XCTAssertTrue(
            amount.displayAmount.contains("0.99"),
            "Expected '0.99' in '\(amount.displayAmount)'"
        )
    }

    @MainActor
    func testDisplayAmountFormatsLargeValue() {
        let amount: Int64 = 100000
        XCTAssertTrue(
            amount.displayAmount.contains("1,000.00") || amount.displayAmount.contains("1 000.00"),
            "Expected thousands-formatted '1000.00' in '\(amount.displayAmount)'"
        )
    }

    @MainActor
    func testDisplayAmountFormatsSingleSatang() {
        let amount: Int64 = 1
        XCTAssertTrue(
            amount.displayAmount.contains("0.01"),
            "Expected '0.01' in '\(amount.displayAmount)'"
        )
    }

    @MainActor
    func testDisplayAmountUsesTHBCurrency() {
        let amount: Int64 = 1250
        let display = amount.displayAmount
        XCTAssertTrue(
            display.contains("฿") || display.contains("THB"),
            "Expected THB symbol or code in '\(display)'"
        )
    }
}
