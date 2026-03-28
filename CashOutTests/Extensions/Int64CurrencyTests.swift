import XCTest
@testable import CashOut

final class Int64CurrencyTests: XCTestCase {
    @MainActor
    func testDisplayAmountFormatsTypicalValue() {
        let amount: Int64 = 1250
        XCTAssertEqual(amount.displayAmount, "$12.50")
    }

    @MainActor
    func testDisplayAmountFormatsZero() {
        let amount: Int64 = 0
        XCTAssertEqual(amount.displayAmount, "$0.00")
    }

    @MainActor
    func testDisplayAmountFormatsCentsOnly() {
        let amount: Int64 = 99
        XCTAssertEqual(amount.displayAmount, "$0.99")
    }

    @MainActor
    func testDisplayAmountFormatsLargeValue() {
        let amount: Int64 = 100000
        XCTAssertEqual(amount.displayAmount, "$1,000.00")
    }

    @MainActor
    func testDisplayAmountFormatsSingleCent() {
        let amount: Int64 = 1
        XCTAssertEqual(amount.displayAmount, "$0.01")
    }
}
