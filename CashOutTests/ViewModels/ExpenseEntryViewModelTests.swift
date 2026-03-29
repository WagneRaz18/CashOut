import XCTest
@testable import CashOut

final class ExpenseEntryViewModelTests: XCTestCase {

    // MARK: - appendDigit Tests (AC #3, #4)

    @MainActor
    func testAppendDigitBuildsCorrectCentsValue() {
        let viewModel = ExpenseEntryViewModel()

        viewModel.appendDigit("1")
        viewModel.appendDigit("2")
        viewModel.appendDigit("5")
        viewModel.appendDigit("0")

        XCTAssertEqual(
            viewModel.amountInCents, 1250,
            "Typing '1250' should produce 1250 satang (฿12.50)"
        )
    }

    // MARK: - deleteLastDigit Tests (AC #5)

    @MainActor
    func testDeleteLastDigitRemovesRightmostDigit() {
        let viewModel = ExpenseEntryViewModel()
        viewModel.amountInCents = 1250

        viewModel.deleteLastDigit()

        XCTAssertEqual(
            viewModel.amountInCents, 125,
            "Deleting from 1250 should produce 125 satang (฿1.25)"
        )
    }

    @MainActor
    func testDeleteLastDigitFromZeroStaysZero() {
        let viewModel = ExpenseEntryViewModel()

        viewModel.deleteLastDigit()

        XCTAssertEqual(
            viewModel.amountInCents, 0,
            "Deleting from 0 should remain 0 (no crash)"
        )
    }

    // MARK: - Cap Tests

    @MainActor
    func testAppendDigitEnforcesCap() {
        let viewModel = ExpenseEntryViewModel()
        viewModel.amountInCents = 1_000_000

        viewModel.appendDigit("5")

        XCTAssertEqual(
            viewModel.amountInCents, 1_000_000,
            "Should not append when amountInCents >= 1_000_000 (cap at ฿99,999.99)"
        )
    }

    // MARK: - resetAmount Tests

    @MainActor
    func testResetAmountSetsToZero() {
        let viewModel = ExpenseEntryViewModel()
        viewModel.amountInCents = 5000

        viewModel.resetAmount()

        XCTAssertEqual(
            viewModel.amountInCents, 0,
            "Reset should set amountInCents to 0"
        )
    }

    // MARK: - isAmountZero Tests

    @MainActor
    func testIsAmountZeroWhenZero() {
        let viewModel = ExpenseEntryViewModel()

        XCTAssertTrue(
            viewModel.isAmountZero,
            "isAmountZero should be true when amountInCents is 0"
        )
    }

    @MainActor
    func testIsAmountZeroWhenNonZero() {
        let viewModel = ExpenseEntryViewModel()
        viewModel.amountInCents = 100

        XCTAssertFalse(
            viewModel.isAmountZero,
            "isAmountZero should be false when amountInCents > 0"
        )
    }

    // MARK: - appendDecimalPoint Tests

    @MainActor
    func testAppendDecimalPointIsNoOp() {
        let viewModel = ExpenseEntryViewModel()
        viewModel.amountInCents = 500

        viewModel.appendDecimalPoint()

        XCTAssertEqual(
            viewModel.amountInCents, 500,
            "appendDecimalPoint should be a no-op (amount unchanged)"
        )
    }
}
