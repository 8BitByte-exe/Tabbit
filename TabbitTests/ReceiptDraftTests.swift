import XCTest
@testable import Tabbit

final class ReceiptDraftTests: XCTestCase {

    func testMoneyInputFormats() {
        let cases: [(String, String?)] = [
            ("7.76", "7.76"),
            ("  7.76 ", "7.76"),
            ("$4", "4"),
            ("1,234.56", "1234.56"),
            ("1.234,56", "1234.56"),
            ("12,34", "12.34"),
            ("1,234", "1234"),
            ("-0.50", "-0.5"),
            ("0.50-", "-0.5"),
            ("$-1.00", "-1"),
            ("7.5", "7.5"),
            ("", nil),
            ("abc", nil),
            ("1.2.3x", nil),
            ("-", nil),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(MoneyInput.parse(input), expected.map { text in money(text) }, "\"\(input)\"")
        }
    }

    func testEditTextUsesTwoDecimals() {
        XCTAssertEqual(MoneyInput.editText(money("7.5")), "7.50")
        XCTAssertEqual(MoneyInput.editText(money("-0.5")), "-0.50")
        XCTAssertEqual(MoneyInput.editText(money("1234.5")), "1234.50")
        XCTAssertEqual(MoneyInput.editText(nil), "")
    }

    private let original = Receipt(
        merchant: "FRESH MART",
        date: CalendarDate(year: 2026, month: 11, day: 2),
        lineItems: [
            ReceiptLineItem(name: "BANANAS", amount: Decimal(string: "1.29")!, confidence: 1),
            ReceiptLineItem(name: "MILK", amount: Decimal(string: "6.47")!, confidence: 0.4),
        ],
        subtotal: Decimal(string: "7.76")!,
        tax: Decimal(string: "0.62")!,
        total: Decimal(string: "8.38")!,
        parser: .rules,
        notes: ["A note"]
    )

    func testUnchangedDraftGivesBackTheSameReceipt() {
        XCTAssertEqual(ReceiptDraft(original).receipt, original)
    }

    func testEditingUpdatesTheReceiptAndChecks() {
        var draft = ReceiptDraft(original)
        draft.merchant = "  Fresh Mart  "
        draft.items[1].amountText = "6.00"
        draft.addItem()
        draft.items[2].name = "Eggs"
        draft.items[2].amountText = "0.47"
        draft.totalText = "8.38"

        let receipt = draft.receipt
        XCTAssertEqual(receipt.merchant, "Fresh Mart")
        XCTAssertEqual(itemList(receipt), itemList([("BANANAS", "1.29"), ("MILK", "6.00"), ("Eggs", "0.47")]))
        XCTAssertTrue(ReceiptValidator.checks(for: receipt).allSatisfy { check in check.passed })
        XCTAssertEqual(receipt.notes, ["A note"])
    }

    func testRemovingItemsAndClearingFields() {
        var draft = ReceiptDraft(original)
        draft.removeItem(id: draft.items[0].id)
        draft.merchant = "   "
        draft.taxText = ""
        let receipt = draft.receipt
        XCTAssertEqual(receipt.lineItems.map { item in item.name }, ["MILK"])
        XCTAssertNil(receipt.merchant)
        XCTAssertNil(receipt.tax)
    }

    func testInvalidAmountsAreFlagged() {
        var draft = ReceiptDraft(original)
        XCTAssertFalse(draft.hasInvalidAmounts)
        draft.items[0].amountText = "1.2x"
        XCTAssertTrue(draft.hasInvalidAmounts)
        XCTAssertEqual(draft.receipt.lineItems.count, 1)
        draft.items[0].amountText = ""
        XCTAssertFalse(draft.hasInvalidAmounts)
    }

    func testEditedFlag() throws {
        let saved = SavedReceipt(
            id: UUID(), createdAt: Date(), updatedAt: Date(), receipt: original, parsed: original,
            scan: ScanResult(pageCount: 1, blocks: []), pageImageCount: 0, languageCorrection: false)
        XCTAssertFalse(saved.isEdited)
        var edited = saved
        edited.receipt.merchant = "Fresh Mart"
        XCTAssertTrue(edited.isEdited)
        XCTAssertEqual(edited.displayTitle, "Fresh Mart")
    }
}
