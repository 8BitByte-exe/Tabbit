import XCTest
@testable import Tabbit

final class ReceiptFormTests: XCTestCase {

    private let alex = UUID()
    private let blair = UUID()

    private func scanned() -> ReceiptRecord {
        return ReceiptRecord(
            merchant: "FRESH MART",
            date: Calendar.current.startOfDay(for: Date()),
            category: .groceries,
            items: [
                SplitItem(name: "BREAD", price: money("3.49"), confidence: 1),
                SplitItem(name: "BNLS CHKN", price: money("8.47"), confidence: 0.4),
            ],
            tax: money("0.50"),
            total: money("12.46"),
            source: .camera,
            autofilled: [.merchant, .category, .total, .tax, .items],
            unreadable: [.date, .tip]
        )
    }

    func testUnchangedFormGivesBackTheSameReceipt() {
        let record = scanned()
        XCTAssertEqual(ReceiptForm(record).record(updating: record), record)
    }

    func testEditingDropsTheScanMarksOfThatFieldOnly() {
        let record = scanned()
        var form = ReceiptForm(record)
        form.merchant = "Fresh Mart"
        form.tipText = "1.00"
        let edited = form.record(updating: record)
        XCTAssertEqual(edited.merchant, "Fresh Mart")
        XCTAssertEqual(edited.tip, .amount(money("1.00")))
        XCTAssertFalse(edited.autofilled.contains(.merchant))
        XCTAssertTrue(edited.autofilled.contains(.total))
        XCTAssertFalse(edited.unreadable.contains(.tip))
        XCTAssertTrue(edited.unreadable.contains(.date))
    }

    func testRenamingAnItemClearsItsUncertainMark() {
        let record = scanned()
        var form = ReceiptForm(record)
        XCTAssertTrue(form.items[1].isUncertain)
        form.items[1].name = "Boneless chicken"
        let edited = form.record(updating: record)
        XCTAssertNil(edited.items[1].confidence)
        XCTAssertEqual(edited.items[0].confidence, 1)
        XCTAssertFalse(edited.autofilled.contains(.items))
    }

    func testPercentTipRoundTrips() {
        var record = scanned()
        record.tip = .percent(money("12.5"))
        let form = ReceiptForm(record)
        XCTAssertTrue(form.tipIsPercent)
        XCTAssertEqual(form.tipText, "12.5")
        XCTAssertEqual(form.record(updating: record).tip, .percent(money("12.5")))
    }

    func testInvalidAmountsAreReported() {
        var form = ReceiptForm(ReceiptRecord())
        let id = form.addItem()
        XCTAssertTrue(form.isValid, "an empty new item is fine")
        form.items[0].name = "Coffee"
        XCTAssertEqual(form.invalidFields, [.itemPrice(id)], "a named item needs a price")
        form.items[0].priceText = "4.50"
        form.taxText = "abc"
        form.tipText = "-2"
        XCTAssertEqual(form.invalidFields, [.tax, .tip])
    }

    func testEmptyItemsAreDropped() {
        var form = ReceiptForm(ReceiptRecord())
        form.addItem()
        let id = form.addItem()
        form.items[1].name = "Tea"
        form.items[1].priceText = "3"
        let record = form.record(updating: ReceiptRecord())
        XCTAssertEqual(record.items.map { item in item.id }, [id])
        XCTAssertEqual(record.items.first?.price, money("3"))
    }

    func testTogglingAssignees() {
        let members = [Person.meID, alex, blair]
        // From everyone, tapping one person picks just them.
        XCTAssertEqual(ReceiptForm.toggled([], person: alex, members: members), [alex])
        XCTAssertEqual(ReceiptForm.toggled([alex], person: Person.meID, members: members), [Person.meID, alex])
        // Picking everybody, or nobody, means everyone.
        XCTAssertEqual(ReceiptForm.toggled([Person.meID, alex], person: blair, members: members), [])
        XCTAssertEqual(ReceiptForm.toggled([alex], person: alex, members: members), [])
    }
}
