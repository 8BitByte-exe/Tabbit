import XCTest
@testable import Tabbit

/// Quantities and unit prices, deals, the time, address and payment method, and the
/// arithmetic sanity checks that keep a misread line from being taken at face value.
final class ReceiptDetailsTests: XCTestCase {

    private let parser = RulesReceiptParser()

    // MARK: - Quantity and unit price

    func testOnlyAUnitPriceIsPrinted() {
        let atSign = LineAmountParser.read("2 @ 1.99")
        XCTAssertEqual(atSign?.value, money("3.98"))
        XCTAssertEqual(atSign?.quantity, money("2"))
        XCTAssertEqual(atSign?.unitPrice, money("1.99"))
        XCTAssertEqual(atSign?.isComputed, true)
        XCTAssertEqual(atSign?.alternative, money("1.99"))
        XCTAssertEqual(atSign?.textBefore, "")

        let each = LineAmountParser.read("2 BANANAS 1.99/EA")
        XCTAssertEqual(each?.value, money("3.98"))
        XCTAssertEqual(each?.textBefore, "2 BANANAS")
        XCTAssertEqual(each?.quantity, money("2"))

        XCTAssertEqual(LineAmountParser.read("2 Bananas - $1.99/ea")?.value, money("3.98"))
        XCTAssertEqual(LineAmountParser.read("2 @ 1.99 EA")?.value, money("3.98"))
        XCTAssertEqual(LineAmountParser.read("BANANAS 1.99 EACH")?.value, money("1.99"))
    }

    func testQuantityWithTheLineTotal() {
        let total = LineAmountParser.read("2 BANANAS 3.98")
        XCTAssertEqual(total?.value, money("3.98"))
        XCTAssertEqual(total?.quantity, money("2"))
        XCTAssertEqual(total?.unitPrice, money("1.99"))
        XCTAssertEqual(total?.isComputed, false)
        // It could also mean 3.98 each; that reading is only tried if the receipt needs it.
        XCTAssertEqual(total?.alternative, money("7.96"))

        let both = LineAmountParser.read("2 @ 0.99 1.98")
        XCTAssertEqual(both?.value, money("1.98"))
        XCTAssertEqual(both?.quantity, money("2"))
        XCTAssertEqual(both?.unitPrice, money("0.99"))
        XCTAssertNil(both?.alternative)

        let weight = LineAmountParser.read("1.25 LB @ 0.99/LB 1.24")
        XCTAssertEqual(weight?.value, money("1.24"))
        XCTAssertEqual(weight?.quantity, money("1.25"))
        XCTAssertEqual(weight?.unitPrice, money("0.99"))

        let unitAndTotal = LineAmountParser.read("2 BANANAS 1.99/EA 3.98")
        XCTAssertEqual(unitAndTotal?.value, money("3.98"))
        XCTAssertEqual(unitAndTotal?.unitPrice, money("1.99"))
        XCTAssertNil(unitAndTotal?.alternative)
    }

    func testSizesAndNumbersInNamesAreNotQuantities() {
        XCTAssertNil(LineAmountParser.read("12 PACK WATER 4.99")?.quantity)
        XCTAssertNil(LineAmountParser.read("7UP 1.99")?.quantity)
        XCTAssertNil(LineAmountParser.read("1000 ISLAND 2.49")?.quantity)
        XCTAssertNil(LineAmountParser.read("6 INCH SUB 5.99")?.quantity)
        // A 6-pack, not six of them.
        let pack = LineAmountParser.read("BOUNTY 6X 12.99")
        XCTAssertEqual(pack?.value, money("12.99"))
        XCTAssertNil(pack?.quantity)
        XCTAssertNil(LineAmountParser.read("NO AMOUNT HERE"))
    }

    func testQuantityInTheName() {
        XCTAssertEqual(LineAmountParser.name("2 BANANAS", quantity: money("2")), "2× BANANAS")
        XCTAssertEqual(LineAmountParser.name("2X BURGER", quantity: money("2")), "2× BURGER")
        XCTAssertEqual(LineAmountParser.name("QTY 3 TACO", quantity: money("3")), "3× TACO")
        XCTAssertEqual(LineAmountParser.name("Bananas", quantity: money("2")), "2× Bananas")
        XCTAssertEqual(LineAmountParser.name("Bananas", quantity: money("1.25")), "Bananas")
        XCTAssertEqual(LineAmountParser.name("Bananas", quantity: money("1")), "Bananas")
        XCTAssertEqual(LineAmountParser.name("Bananas", quantity: nil), "Bananas")
    }

    func testUnitPriceOnlyLinesAreWorkedOut() {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("2 BANANAS 1.99/EA")
            .row("MILK", "3.49")
            .row("SUBTOTAL", "7.47")
            .row("TOTAL", "7.47")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("2× BANANAS", "3.98"), ("MILK", "3.49")]))
        XCTAssertEqual(receipt.lineItems.first?.quantity, money("2"))
        XCTAssertEqual(receipt.lineItems.first?.unitPrice, money("1.99"))
        XCTAssertTrue(ReceiptValidator.checks(for: receipt).allSatisfy { check in check.passed })
        XCTAssertEqual(receipt.notes, ["Worked out the price of \"2 BANANAS 1.99/EA\" from its quantity and unit price."])
    }

    func testPriceForEachIsUsedWhenTheSubtotalNeedsIt() {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("2 BANANAS", "1.99")
            .row("BREAD", "3.00")
            .row("SUBTOTAL", "6.98")
            .row("TOTAL", "6.98")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("2× BANANAS", "3.98"), ("BREAD", "3.00")]))
        XCTAssertEqual(receipt.lineItems.first?.unitPrice, money("1.99"))
        XCTAssertEqual(receipt.notes, ["To match the subtotal, read \"2 BANANAS 1.99\" as 3.98."])
    }

    func testLineTotalIsKeptWhenItAddsUp() {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("2 BANANAS", "3.98")
            .row("SUBTOTAL", "3.98")
            .row("TOTAL", "3.98")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("2× BANANAS", "3.98")]))
        XCTAssertEqual(receipt.lineItems.first?.unitPrice, money("1.99"))
        XCTAssertEqual(receipt.notes, [])
    }

    // MARK: - Deals

    func testDealDescriptions() {
        XCTAssertTrue(ReceiptKeywords.isDeal("2 FOR 1"))
        XCTAssertTrue(ReceiptKeywords.isDeal("BUY 1 GET 1 FREE"))
        XCTAssertTrue(ReceiptKeywords.isDeal("B1G1"))
        XCTAssertTrue(ReceiptKeywords.isDeal("MIX & MATCH"))
        XCTAssertTrue(ReceiptKeywords.isDeal("BOGO"))
        XCTAssertFalse(ReceiptKeywords.isDeal("2 FOR 5.00"))
        XCTAssertFalse(ReceiptKeywords.isDeal("2 FOR 1 PIZZA"))
        XCTAssertFalse(ReceiptKeywords.isDeal("FREE RANGE EGGS"))
        XCTAssertEqual(ReceiptKeywords.role(for: "2 FOR 1 3.99"), .info)
        XCTAssertEqual(ReceiptKeywords.role(for: "MIX & MATCH 2.00"), .info)
        XCTAssertEqual(ReceiptKeywords.role(for: "BUY 1 GET 1 FREE -1.99"), .discount)
    }

    func testDealLinesAreNotItems() {
        let scan = ReceiptLayoutBuilder()
            .row("CORNER STORE")
            .row("SODA", "1.50")
            .row("CHIPS", "2.50")
            .row("MIX & MATCH", "2.00")
            .row("TOTAL", "4.00")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("SODA", "1.50"), ("CHIPS", "2.50")]))
        XCTAssertEqual(receipt.total, money("4.00"))
    }

    func testBuyOneGetOneFreeTakesMoneyOff() {
        let scan = ReceiptLayoutBuilder()
            .row("CORNER STORE")
            .row("CHIPS", "3.99")
            .row("CHIPS", "3.99")
            .row("BUY 1 GET 1 FREE", "3.99")
            .row("SUBTOTAL", "3.99")
            .row("TOTAL", "3.99")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(receipt.lineItems.count, 3)
        XCTAssertEqual(receipt.lineItems.last?.amount, money("-3.99"))
        XCTAssertTrue(ReceiptValidator.checks(for: receipt).allSatisfy { check in check.passed })
    }

    // MARK: - Time, address, payment

    func testTimeOfPurchase() {
        XCTAssertEqual(ReceiptDetailsParser.time(in: ["11/03/2026 2:32 PM"]), ClockTime(hour: 14, minute: 32))
        XCTAssertEqual(ReceiptDetailsParser.time(in: ["REF 10:01", "TIME 09:05"]), ClockTime(hour: 9, minute: 5))
        XCTAssertEqual(ReceiptDetailsParser.time(in: ["REF 10:01"]), ClockTime(hour: 10, minute: 1))
        XCTAssertEqual(ReceiptDetailsParser.time(inLine: "12:05 AM"), ClockTime(hour: 0, minute: 5))
        XCTAssertEqual(ReceiptDetailsParser.time(inLine: "12:30 PM"), ClockTime(hour: 12, minute: 30))
        XCTAssertEqual(ReceiptDetailsParser.time(inLine: "03.11.2026 14:32:10"), ClockTime(hour: 14, minute: 32))
        XCTAssertEqual(ReceiptDetailsParser.time(inLine: "14h32"), ClockTime(hour: 14, minute: 32))
        XCTAssertNil(ReceiptDetailsParser.time(inLine: "TOTAL 12.34"))
        XCTAssertNil(ReceiptDetailsParser.time(inLine: "TRANS 01:23:45:67"))
    }

    func testStoreAddress() {
        XCTAssertEqual(ReceiptDetailsParser.location(in: [
            "TRADER JOE'S #552", "123 MAIN ST", "SPRINGFIELD, IL 62701", "(555) 123-4567",
        ]), "123 MAIN ST, SPRINGFIELD, IL 62701")
        XCTAssertEqual(ReceiptDetailsParser.location(in: ["REWE", "Hauptstraße 12", "10115 Berlin"]),
                       "Hauptstraße 12, 10115 Berlin")
        XCTAssertEqual(ReceiptDetailsParser.location(in: ["SHELL", "TORONTO ON M5V 2T6"]), "TORONTO ON M5V 2T6")
        XCTAssertNil(ReceiptDetailsParser.location(in: ["CATERING", "TEL 555 1234"]))
    }

    func testPaymentMethod() {
        XCTAssertEqual(ReceiptDetailsParser.paymentMethod(in: [
            "SUBTOTAL 10.00", "TOTAL 10.80", "VISA ************1234 10.80",
        ]), "Visa")
        XCTAssertEqual(ReceiptDetailsParser.paymentMethod(in: ["TOTAL 5.00", "CASH 10.00", "CHANGE 5.00"]), "Cash")
        XCTAssertEqual(ReceiptDetailsParser.paymentMethod(in: [
            "TOTAL 5.00", "DEBIT MASTERCARD 25.00", "CASH BACK 20.00",
        ]), "Mastercard")
        XCTAssertEqual(ReceiptDetailsParser.paymentMethod(in: ["TOTAL 5.00", "INTERAC 5.00"]), "Interac")
        XCTAssertEqual(ReceiptDetailsParser.paymentMethod(in: ["SUMME 5,00", "BAR 10,00"]), "Cash")
        // "Bar" in a footer isn't a cash payment.
        XCTAssertNil(ReceiptDetailsParser.paymentMethod(in: ["TOTAL 5.00", "THANK YOU FOR VISITING OUR BAR"]))
        XCTAssertNil(ReceiptDetailsParser.paymentMethod(in: ["APPLE PAY ACCEPTED", "TOTAL 3.00"]))
    }

    func testTaxRate() {
        XCTAssertEqual(ReceiptDetailsParser.percent(in: "HST 13% 6.50"), money("13"))
        XCTAssertEqual(ReceiptDetailsParser.percent(in: "MwSt 19,0 % 1,52"), money("19"))
        XCTAssertEqual(ReceiptDetailsParser.percent(in: "SALES TAX 8.875% 0.89"), money("8.875"))
        XCTAssertNil(ReceiptDetailsParser.percent(in: "TAX 0.89"))
    }

    // MARK: - Sanity checks

    func testTotalFromCashAndChange() {
        let scan = ReceiptLayoutBuilder()
            .row("CORNER STORE")
            .row("BREAD", "3.00")
            .row("MILK", "2.00")
            .row("CASH", "10.00")
            .row("CHANGE", "5.00")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(receipt.total, money("5.00"))
        XCTAssertEqual(receipt.paymentMethod, "Cash")
        XCTAssertEqual(receipt.notes, ["Took the total from the payment, 5.00."])
    }

    func testTaxIsNeverAsMuchAsTheTotal() {
        let scan = ReceiptLayoutBuilder()
            .row("DELI")
            .row("LUNCH", "10.00")
            .row("SUBTOTAL", "10.00")
            .row("TAX", "10.00")
            .row("TOTAL", "10.00")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertNil(receipt.tax)
        XCTAssertEqual(receipt.total, money("10.00"))
        XCTAssertTrue(receipt.notes.contains("Left out the tax line (10.00): tax is always less than the total."))
    }

    func testIncludedTaxIsKept() {
        let scan = ReceiptLayoutBuilder()
            .row("BÄCKEREI")
            .row("BROT", "3,50")
            .row("KAFFEE", "2,50")
            .row("SUMME", "6,00")
            .row("MWST 7% ENTHALTEN", "0,39")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertNil(receipt.tax)
        XCTAssertEqual(receipt.includedTax, money("0.39"))
        XCTAssertEqual(receipt.total, money("6.00"))
    }

    // MARK: - Saved receipts

    func testNewFieldsSurviveSavingAndEditing() throws {
        let record = ReceiptRecord(merchant: "Shell", location: "123 Main St", time: ClockTime(hour: 7, minute: 5),
                                   paymentMethod: "Visa", category: .fuel)
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ReceiptRecord.self, from: data)
        XCTAssertEqual(decoded.location, "123 Main St")
        XCTAssertEqual(decoded.time, ClockTime(hour: 7, minute: 5))
        XCTAssertEqual(decoded.paymentMethod, "Visa")

        var form = ReceiptForm(record)
        form.paymentMethod = " Cash "
        form.time = nil
        let edited = form.record(updating: record)
        XCTAssertEqual(edited.paymentMethod, "Cash")
        XCTAssertNil(edited.time)
        XCTAssertEqual(ReceiptForm.changedFields(from: record, to: edited), [.payment, .time])
    }

    func testLineItemQuantityRoundTrips() throws {
        var item = ReceiptLineItem(name: "2× Bananas", amount: money("3.98"))
        item.quantity = money("2")
        item.unitPrice = money("1.99")
        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(ReceiptLineItem.self, from: data), item)
    }

    func testClockTime() {
        XCTAssertEqual(ClockTime(hour: 7, minute: 5).text24, "07:05")
        XCTAssertEqual(ClockTime(hour: 25, minute: 61), ClockTime(hour: 23, minute: 59))
        XCTAssertTrue(ClockTime(hour: 9, minute: 30) < ClockTime(hour: 10, minute: 0))
        let day = Calendar.current.startOfDay(for: Date())
        XCTAssertEqual(ClockTime(ClockTime(hour: 14, minute: 32).date(on: day)), ClockTime(hour: 14, minute: 32))
    }
}
