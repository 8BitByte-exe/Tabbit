import XCTest
@testable import Tabbit

final class RulesReceiptParserTests: XCTestCase {

    private let parser = RulesReceiptParser()

    private func groceryReceipt() -> ReceiptLayoutBuilder {
        return ReceiptLayoutBuilder()
            .row("TRADER JOE'S")
            .row("123 MAIN STREET")
            .row("SPRINGFIELD, IL 62701")
            .row("(555) 123-4567")
            .row("11/02/2026 2:32 PM")
            .row("BANANAS", "1.29")
            .row("ORGANIC MILK", "4.99 F", rightYOffset: 0.006)
            .row("AVOCADO")
            .row("2 @ 0.99", "1.98")
            .row("COUPON", "-0.50")
            .row("SUBTOTAL", "7.76")
            .row("TAX", "0.62")
            .row("TOTAL", "8.38")
            .row("VISA", "8.38")
            .row("CHANGE", "0.00")
    }

    func testGroceryReceipt() {
        for reversed in [false, true] {
            let receipt = parser.parse(groceryReceipt().build(reversed: reversed))
            XCTAssertEqual(receipt.merchant, "TRADER JOE'S")
            XCTAssertEqual(receipt.date, CalendarDate(year: 2026, month: 11, day: 2))
            XCTAssertEqual(receipt.lineItems, [
                ReceiptLineItem(name: "BANANAS", amount: money("1.29")),
                ReceiptLineItem(name: "ORGANIC MILK", amount: money("4.99")),
                ReceiptLineItem(name: "AVOCADO", amount: money("1.98")),
                ReceiptLineItem(name: "COUPON", amount: money("-0.50")),
            ])
            XCTAssertEqual(receipt.subtotal, money("7.76"))
            XCTAssertEqual(receipt.tax, money("0.62"))
            XCTAssertEqual(receipt.total, money("8.38"))
            XCTAssertEqual(receipt.parser, .rules)

            let checks = ReceiptValidator.checks(for: receipt)
            XCTAssertEqual(checks.count, 2)
            XCTAssertTrue(checks.allSatisfy { check in check.passed })
        }
    }

    func testCafeReceiptWithSingleBlockLines() {
        let scan = ReceiptLayoutBuilder()
            .row("The Daily Grind Cafe")
            .row("Nov 3, 2026  8:14 AM")
            .row("Table 4   Server: Sam")
            .row("Latte 4.50")
            .row("Blueberry Muffin 3.25")
            .row("Avocado Toast 9.75")
            .row("Subtotal 17.50")
            .row("Sales Tax 8.875% 1.55")
            .row("Total $19.05")
            .row("Thank you!")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(receipt.merchant, "The Daily Grind Cafe")
        XCTAssertEqual(receipt.date, CalendarDate(year: 2026, month: 11, day: 3))
        XCTAssertEqual(receipt.lineItems, [
            ReceiptLineItem(name: "Latte", amount: money("4.50")),
            ReceiptLineItem(name: "Blueberry Muffin", amount: money("3.25")),
            ReceiptLineItem(name: "Avocado Toast", amount: money("9.75")),
        ])
        XCTAssertEqual(receipt.subtotal, money("17.50"))
        XCTAssertEqual(receipt.tax, money("1.55"))
        XCTAssertEqual(receipt.total, money("19.05"))
    }

    func testPicksTheTotalThatAddsUpAndIgnoresSavings() {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH FOODS")
            .row("APPLES", "3.00")
            .row("SUBTOTAL", "3.00")
            .row("TAX", "0.30")
            .row("TOTAL", "3.30")
            .row("GIFT CARD", "2.00")
            .row("BALANCE DUE", "1.30")
            .row("TOTAL SAVINGS", "15.00")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(receipt.total, money("3.30"))
        XCTAssertEqual(receipt.lineItems, [ReceiptLineItem(name: "APPLES", amount: money("3.00"))])
    }

    func testAddsUpSeveralTaxLines() {
        let scan = ReceiptLayoutBuilder()
            .row("CITY DELI")
            .row("SANDWICH", "8.00")
            .row("SUBTOTAL", "8.00")
            .row("STATE TAX", "0.50")
            .row("CITY TAX", "0.25")
            .row("TOTAL", "8.75")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(receipt.tax, money("0.75"))
        XCTAssertEqual(receipt.total, money("8.75"))
        XCTAssertEqual(receipt.notes, ["Added up 2 tax lines."])
    }

    func testMissingTotalStaysEmpty() {
        let scan = ReceiptLayoutBuilder()
            .row("MYSTERY SHOP")
            .row("WIDGET", "2.00")
            .row("GADGET", "3.00")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertNil(receipt.total)
        XCTAssertNil(receipt.subtotal)
        XCTAssertNil(receipt.tax)
        XCTAssertEqual(receipt.lineItems.count, 2)
        XCTAssertTrue(ReceiptValidator.checks(for: receipt).isEmpty)
    }

    func testItemsAcrossTwoPages() {
        let scan = ReceiptLayoutBuilder()
            .row("PAGE ONE SHOP")
            .row("ITEM A", "1.00")
            .newPage()
            .row("ITEM B", "2.00")
            .row("TOTAL", "3.00")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(receipt.lineItems.map { item in item.name }, ["ITEM A", "ITEM B"])
        XCTAssertEqual(receipt.total, money("3.00"))
    }

    func testEmptyScan() {
        let receipt = parser.parse(ScanResult(pageCount: 1, blocks: []))
        XCTAssertNil(receipt.merchant)
        XCTAssertNil(receipt.date)
        XCTAssertTrue(receipt.lineItems.isEmpty)
        XCTAssertNil(receipt.total)
    }

    func testExportedFixture() throws {
        let scan = try Fixtures.scan(named: "corner-market")
        let receipt = parser.parse(scan)
        XCTAssertEqual(receipt.merchant, "CORNER MARKET")
        XCTAssertEqual(receipt.date, CalendarDate(year: 2026, month: 11, day: 3))
        XCTAssertEqual(receipt.lineItems, [
            ReceiptLineItem(name: "BREAD", amount: money("3.49")),
            ReceiptLineItem(name: "MILK", amount: money("2.99")),
        ])
        XCTAssertEqual(receipt.total, money("6.48"))
    }
}
