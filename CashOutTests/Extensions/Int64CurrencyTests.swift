import XCTest
@testable import CashOut

final class Int64CurrencyTests: XCTestCase {
    func testDisplayAmountFormatsTypicalValue() {
        let amount: Int64 = 1250
        XCTAssertEqual(amount.displayAmount, "$12.50")
    }

    func testDisplayAmountFormatsZero() {
        let amount: Int64 = 0
        XCTAssertEqual(amount.displayAmount, "$0.00")
    }

    func testDisplayAmountFormatsCentsOnly() {
        let amount: Int64 = 99
        XCTAssertEqual(amount.displayAmount, "$0.99")
    }

    func testDisplayAmountFormatsLargeValue() {
        let amount: Int64 = 100000
        XCTAssertEqual(amount.displayAmount, "$1,000.00")
    }

    func testDisplayAmountFormatsSingleCent() {
        let amount: Int64 = 1
        XCTAssertEqual(amount.displayAmount, "$0.01")
    }
}
