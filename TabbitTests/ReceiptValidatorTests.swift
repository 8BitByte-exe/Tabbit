import XCTest
@testable import Tabbit

final class ReceiptValidatorTests: XCTestCase {

    private func receipt(items: [String], subtotal: String?, tax: String?, total: String?) -> Receipt {
        return Receipt(
            merchant: nil,
            date: nil,
            lineItems: items.map { amount in ReceiptLineItem(name: "Item", amount: money(amount)) },
            subtotal: subtotal.map { value in money(value) },
            tax: tax.map { value in money(value) },
            total: total.map { value in money(value) },
            parser: .rules,
            notes: []
        )
    }

    func testEverythingAddsUp() {
        let checks = ReceiptValidator.checks(for: receipt(items: ["1.00", "2.00"], subtotal: "3.00", tax: "0.30", total: "3.30"))
        XCTAssertEqual(checks.map { check in check.kind }, [.itemsMatchSubtotal, .subtotalPlusTaxMatchesTotal])
        XCTAssertTrue(checks.allSatisfy { check in check.passed })
    }

    func testItemsDoNotMatchSubtotal() {
        let checks = ReceiptValidator.checks(for: receipt(items: ["1.00", "2.00"], subtotal: "4.00", tax: nil, total: nil))
        XCTAssertEqual(checks, [
            ReceiptCheck(kind: .itemsMatchSubtotal, passed: false, printed: money("4.00"), computed: money("3.00")),
        ])
    }

    func testOneCentRoundingIsAllowed() {
        let close = ReceiptValidator.checks(for: receipt(items: [], subtotal: "3.00", tax: "0.30", total: "3.31"))
        XCTAssertEqual(close.map { check in check.passed }, [true])
        let off = ReceiptValidator.checks(for: receipt(items: [], subtotal: "3.00", tax: "0.30", total: "3.32"))
        XCTAssertEqual(off.map { check in check.passed }, [false])
    }

    func testUsesItemsWhenThereIsNoSubtotal() {
        let checks = ReceiptValidator.checks(for: receipt(items: ["1.00", "2.00"], subtotal: nil, tax: "0.30", total: "3.30"))
        XCTAssertEqual(checks.map { check in check.kind }, [.itemsPlusTaxMatchesTotal])
        XCTAssertEqual(checks.first?.passed, true)
    }

    func testNothingToCheck() {
        XCTAssertTrue(ReceiptValidator.checks(for: receipt(items: ["1.00"], subtotal: nil, tax: nil, total: nil)).isEmpty)
    }
}
