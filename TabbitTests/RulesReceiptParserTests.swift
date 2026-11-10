import XCTest
@testable import Tabbit

final class RulesReceiptParserTests: XCTestCase {

    private let parser = RulesReceiptParser()

    // MARK: - Basics

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

    private let groceryItems = itemList([
        ("BANANAS", "1.29"), ("ORGANIC MILK", "4.99"), ("2× AVOCADO", "1.98"), ("COUPON", "-0.50"),
    ])

    func testGroceryReceipt() {
        for reversed in [false, true] {
            let receipt = parser.parse(groceryReceipt().build(reversed: reversed))
            XCTAssertEqual(receipt.merchant, "TRADER JOE'S")
            XCTAssertEqual(receipt.date, CalendarDate(year: 2026, month: 11, day: 2))
            XCTAssertEqual(receipt.time, ClockTime(hour: 14, minute: 32))
            XCTAssertEqual(receipt.location, "123 MAIN STREET, SPRINGFIELD, IL 62701")
            XCTAssertEqual(receipt.paymentMethod, "Visa")
            XCTAssertEqual(itemList(receipt), groceryItems)
            XCTAssertEqual(receipt.subtotal, money("7.76"))
            XCTAssertEqual(receipt.tax, money("0.62"))
            XCTAssertEqual(receipt.total, money("8.38"))
            XCTAssertEqual(receipt.parser, .rules)
            XCTAssertEqual(receipt.notes, [])

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
        XCTAssertEqual(itemList(receipt), itemList([
            ("Latte", "4.50"), ("Blueberry Muffin", "3.25"), ("Avocado Toast", "9.75"),
        ]))
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
        XCTAssertEqual(itemList(receipt), itemList([("APPLES", "3.00")]))
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
            .build(reversed: true)
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("ITEM A", "1.00"), ("ITEM B", "2.00")]))
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
        XCTAssertEqual(itemList(receipt), itemList([("BREAD", "3.49"), ("MILK", "2.99")]))
        XCTAssertEqual(receipt.total, money("6.48"))
    }

    // MARK: - Prices that don't sit level with their names

    func testTiltedReceipt() {
        for tilt: CGFloat in [0.03, -0.03, 0.06] {
            for reversed in [false, true] {
                let receipt = parser.parse(groceryReceipt().build(reversed: reversed, tilt: tilt))
                XCTAssertEqual(itemList(receipt), groceryItems, "tilt \(tilt), reversed \(reversed)")
                XCTAssertEqual(receipt.subtotal, money("7.76"), "tilt \(tilt)")
                XCTAssertEqual(receipt.total, money("8.38"), "tilt \(tilt)")
            }
        }
    }

    /// The bug from the first real-world test: every price a bit higher than its
    /// name shifted all prices up one line.
    func testPricesSittingHigherOrLowerThanTheirNames() {
        for offset: CGFloat in [0.012, -0.012, 0.016] {
            var builder = ReceiptLayoutBuilder().row("FRESH MART")
            for (name, price) in [("MILK", "3.49"), ("BREAD", "2.99"), ("EGGS", "4.29"), ("APPLES", "5.10")] {
                builder = builder.row(name, price, rightYOffset: offset)
            }
            builder = builder
                .row("SUBTOTAL", "15.87", rightYOffset: offset)
                .row("TAX", "1.27", rightYOffset: offset)
                .row("TOTAL", "17.14", rightYOffset: offset)
            let receipt = parser.parse(builder.build())
            XCTAssertEqual(itemList(receipt), itemList([
                ("MILK", "3.49"), ("BREAD", "2.99"), ("EGGS", "4.29"), ("APPLES", "5.10"),
            ]), "offset \(offset)")
            XCTAssertEqual(receipt.subtotal, money("15.87"), "offset \(offset)")
            XCTAssertEqual(receipt.total, money("17.14"), "offset \(offset)")
        }
    }

    func testOneCurledPriceFindsItsName() {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("MILK", "3.49")
            .row("BREAD", "2.99", rightYOffset: 0.014)
            .row("EGGS", "4.29")
            .row("SUBTOTAL", "10.77")
            .row("TOTAL", "10.77")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("MILK", "3.49"), ("BREAD", "2.99"), ("EGGS", "4.29")]))
    }

    func testPriceOnTheLineBelowItsName() {
        let scan = ReceiptLayoutBuilder()
            .row("HARDWARE PLUS")
            .row("LONG EXTENSION CORD 25 FT")
            .priceRow("12.99")
            .row("TOTAL", "12.99")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("LONG EXTENSION CORD 25 FT", "12.99")]))
        XCTAssertEqual(receipt.total, money("12.99"))
    }

    // MARK: - Misread subtotal

    func testMisreadSubtotalLabel() {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("MILK", "3.49")
            .row("BREAD", "2.99")
            .row("SJETOTAL", "6.48")
            .row("TAX", "0.52")
            .row("TOTAL", "7.00")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("MILK", "3.49"), ("BREAD", "2.99")]))
        XCTAssertEqual(receipt.subtotal, money("6.48"))
        XCTAssertEqual(receipt.total, money("7.00"))
    }

    func testUnreadableSubtotalFoundByItsAmount() {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("MILK", "3.49")
            .row("BREAD", "2.99")
            .row("XJBTCTAI", "6.48")
            .row("TAX", "0.52")
            .row("TOTAL", "7.00")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("MILK", "3.49"), ("BREAD", "2.99")]))
        XCTAssertEqual(receipt.subtotal, money("6.48"))
        XCTAssertEqual(receipt.notes, ["Read \"XJBTCTAI 6.48\" as the subtotal, because it equals the items above it."])
    }

    func testLastItemEqualToTheOthersStaysAnItem() {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("MILK", "2.00")
            .row("BREAD", "1.00")
            .row("EGGS", "3.00")
            .row("TAX", "0.48")
            .row("TOTAL", "6.48")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(receipt.lineItems.count, 3)
        XCTAssertNil(receipt.subtotal)
        XCTAssertEqual(receipt.total, money("6.48"))
    }

    func testVisionAlternativeReadingRescuesSubtotal() {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("MILK", "3.49")
            .row("BREAD", "2.99")
            .row("XQZZQ", "6.48", alternatives: ["SUBTOTAL"])
            .row("TOTAL", "6.48")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("MILK", "3.49"), ("BREAD", "2.99")]))
        XCTAssertEqual(receipt.subtotal, money("6.48"))
    }

    // MARK: - Sale, deal and discount lines

    func testRegularPriceAndSavingsLines() {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("CHIPS", "3.99")
            .row("REG PRICE", "4.99")
            .row("YOU SAVE", "1.00")
            .row("SODA 2 FOR 5.00", "5.00")
            .row("CLUB CARD SAVINGS", "1.00-")
            .row("SUBTOTAL", "7.99")
            .row("TOTAL", "7.99")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([
            ("CHIPS", "3.99"), ("SODA", "5.00"), ("CLUB CARD SAVINGS", "-1.00"),
        ]))
        XCTAssertEqual(receipt.notes, [])
    }

    func testDealLineUnderAPricedItemIsLeftOut() {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("SODA", "2.50")
            .row("2 FOR 5.00")
            .row("SUBTOTAL", "2.50")
            .row("TOTAL", "2.50")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("SODA", "2.50")]))
    }

    func testCountsAnUncertainLineWhenTheSubtotalNeedsIt() {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("CHIPS", "3.99")
            .row("SALE PRICE", "2.99")
            .row("SUBTOTAL", "6.98")
            .row("TOTAL", "6.98")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("CHIPS", "3.99"), ("SALE PRICE", "2.99")]))
        XCTAssertEqual(receipt.notes, ["To match the subtotal, counted \"SALE PRICE 2.99\"."])
    }

    func testDoesNotGuessWhenTwoFixesWouldWork() {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("CHIPS", "3.99")
            .row("REG PRICE", "1.00")
            .row("SALE PRICE", "1.00")
            .row("SUBTOTAL", "4.99")
            .row("TOTAL", "4.99")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("CHIPS", "3.99")]))
        XCTAssertEqual(receipt.notes, [])
    }

    // MARK: - Confidence

    func testHardToReadNamesAreMarked() {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("BNLS CHKN", "7.99", confidence: 0.3)
            .row("MILK", "3.49")
            .row("TOTAL", "11.48")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(receipt.lineItems.map { item in item.isUncertain }, [true, false])
    }
    // MARK: - Rules from receipt-parsing research (v1.0)

    func testQuantityWeightAndUnitLines() {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("2 X BURGER", "24.00")
            .row("BANANAS")
            .row("1.25 LB @ 0.59/LB", "0.74")
            .row("ÄPFEL")
            .row("0,456 kg x 3,99 EUR/kg", "1,82")
            .row("SUBTOTAL", "26.56")
            .row("TOTAL", "26.56")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([
            ("2× BURGER", "24.00"), ("BANANAS", "0.74"), ("ÄPFEL", "1.82"),
        ]))
        XCTAssertEqual(receipt.notes, [])
    }

    func testBarcodesPLUsAndTaxFlagsLeaveTheName() {
        let scan = ReceiptLayoutBuilder()
            .row("WALMART")
            .row("GV MILK 007874235186 F", "3.48 N")
            .row("4011 BANANAS", "1.12")
            .row("*BREAD", "2.50")
            .row("TOTAL", "7.10")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("GV MILK", "3.48"), ("BANANAS", "1.12"), ("BREAD", "2.50")]))
        XCTAssertEqual(receipt.total, money("7.10"))
    }

    func testNamesKeepTheirOwnNumbers() {
        XCTAssertEqual(RulesReceiptParser.itemName(from: "1000 ISLAND DRESSING"), "1000 ISLAND DRESSING")
        XCTAssertEqual(RulesReceiptParser.itemName(from: "2XL SHIRT"), "2XL SHIRT")
        XCTAssertEqual(RulesReceiptParser.itemName(from: "VITAMIN C"), "VITAMIN C")
        XCTAssertEqual(RulesReceiptParser.itemName(from: "2x Burger"), "2× Burger")
    }

    func testDiscountPrintedWithoutAMinus() {
        func scan(subtotal: String) -> ScanResult {
            return ReceiptLayoutBuilder()
                .row("FRESH MART")
                .row("MILK", "4.00")
                .row("MEMBER DISCOUNT", "1.00")
                .row("SUBTOTAL", subtotal)
                .row("TOTAL", subtotal)
                .build()
        }
        let deducted = parser.parse(scan(subtotal: "3.00"))
        XCTAssertEqual(itemList(deducted), itemList([("MILK", "4.00"), ("MEMBER DISCOUNT", "-1.00")]))
        XCTAssertEqual(deducted.notes, [])

        // If the subtotal says the discount wasn't taken off here, it's left out.
        let notDeducted = parser.parse(scan(subtotal: "4.00"))
        XCTAssertEqual(itemList(notDeducted), itemList([("MILK", "4.00")]))
        XCTAssertEqual(notDeducted.notes, ["To match the subtotal, left out \"MEMBER DISCOUNT 1.00\"."])
    }

    func testTaxStatedAsIncludedIsNotAdded() {
        let scan = ReceiptLayoutBuilder()
            .row("CAFÉ CENTRAL")
            .row("ESPRESSO", "2,50")
            .row("CROISSANT", "3,00")
            .row("SUMME", "5,50")
            .row("INKL. MWST 19%", "0,88")
            .row("KARTENZAHLUNG", "5,50")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(receipt.merchant, "CAFÉ CENTRAL")
        XCTAssertEqual(itemList(receipt), itemList([("ESPRESSO", "2.50"), ("CROISSANT", "3.00")]))
        XCTAssertEqual(receipt.total, money("5.50"))
        XCTAssertNil(receipt.tax)
        XCTAssertEqual(receipt.notes, ["The prices already include 0.88 tax."])
        XCTAssertTrue(ReceiptValidator.checks(for: receipt).allSatisfy { check in check.passed })
    }

    func testTaxThatTheItemsAlreadyIncludeIsNotCountedTwice() {
        let scan = ReceiptLayoutBuilder()
            .row("MERCADO")
            .row("PAN", "1,20")
            .row("LECHE", "0,95")
            .row("IVA 10%", "0,20")
            .row("TOTAL", "2,15")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("PAN", "1.20"), ("LECHE", "0.95")]))
        XCTAssertNil(receipt.tax)
        XCTAssertEqual(receipt.total, money("2.15"))
        XCTAssertEqual(receipt.notes, ["The prices already include 0.20 tax, so it isn't added again."])
    }

    func testTaxIsAddedWhenThePricesDontIncludeIt() {
        let scan = ReceiptLayoutBuilder()
            .row("HARDWARE PLUS")
            .row("SCREWS", "10.00")
            .row("TAX", "0.80")
            .row("TOTAL", "10.80")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(receipt.tax, money("0.80"))
        XCTAssertEqual(receipt.total, money("10.80"))
        XCTAssertEqual(receipt.notes, [])
    }

    func testGermanBakeryReceipt() {
        let scan = ReceiptLayoutBuilder()
            .row("BÄCKEREI MÜLLER")
            .row("BRÖTCHEN")
            .row("4 STK X 0,45", "1,80")
            .row("KAFFEE", "2,90")
            .row("ZWISCHENSUMME", "4,70")
            .row("ZU ZAHLEN", "4,70")
            .row("GEGEBEN", "10,00")
            .row("RÜCKGELD", "5,30")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(receipt.merchant, "BÄCKEREI MÜLLER")
        XCTAssertEqual(itemList(receipt), itemList([("4× BRÖTCHEN", "1.80"), ("KAFFEE", "2.90")]))
        XCTAssertEqual(receipt.paymentMethod, "Cash")
        XCTAssertEqual(receipt.subtotal, money("4.70"))
        XCTAssertEqual(receipt.total, money("4.70"))
    }

    func testTipGuideUnderTheTotalIsNotATip() {
        let scan = ReceiptLayoutBuilder()
            .row("SUNNY SIDE DINER")
            .row("PANCAKES", "12.00")
            .row("COFFEE", "3.00")
            .row("SUBTOTAL", "15.00")
            .row("TAX", "1.20")
            .row("TOTAL", "16.20")
            .row("18% TIP", "2.70")
            .row("20% TIP", "3.00")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertNil(receipt.tip)
        XCTAssertEqual(receipt.total, money("16.20"))
    }

    func testCashRoundingIsNotAnItem() {
        let scan = ReceiptLayoutBuilder()
            .row("CORNER CAFE")
            .row("MUFFIN", "4.99")
            .row("TEA", "4.99")
            .row("ROUNDING", "0.02")
            .row("TOTAL", "10.00")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("MUFFIN", "4.99"), ("TEA", "4.99")]))
        XCTAssertEqual(receipt.total, money("10.00"))
        XCTAssertEqual(receipt.notes, [])
    }

    func testTheBiggestLineAtTheTopIsTheStore() {
        let scan = ReceiptLayoutBuilder()
            .row("Downtown")
            .row("SUNNY SIDE DINER", height: 0.035)
            .row("PANCAKES", "12.00")
            .row("TOTAL", "12.00")
            .build()
        XCTAssertEqual(parser.parse(scan).merchant, "SUNNY SIDE DINER")
    }

    // MARK: - Wordings from real receipts

    func testYouSavedIsNeverCounted() {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("CHIPS", "3.99")
            .row("YOU SAVED", "1.00")
            .row("SUBTOTAL", "4.99")
            .row("TOTAL", "4.99")
            .build()
        XCTAssertEqual(itemList(parser.parse(scan)), itemList([("CHIPS", "3.99")]))
    }

    func testGasReceiptWithPricePerLitre() {
        let scan = ReceiptLayoutBuilder()
            .row("SHELL #1234", height: 0.03)
            .row("PUMP 05 REGULAR")
            .row("PRICE/L", "1.67")
            .row("LITRES", "32.89")
            .row("FUEL TOTAL", "54.92")
            .row("TOTAL", "54.92")
            .row("GST/HST INCLUDED", "6.32")
            .row("VISA", "54.92")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(receipt.merchant, "SHELL")
        XCTAssertEqual(itemList(receipt), itemList([("FUEL TOTAL", "54.92")]))
        XCTAssertEqual(receipt.total, money("54.92"))
        XCTAssertNil(receipt.tax)
        XCTAssertTrue(ReceiptValidator.checks(for: receipt).allSatisfy { check in check.passed })
    }

    func testHeadingsDoNotBecomeItems() {
        let scan = ReceiptLayoutBuilder()
            .row("NO FRILLS")
            .row("21-GROCERY")
            .row("PASTA", "2.49")
            .row("27-PRODUCE")
            .priceRow("1.29")
            .row("BANANAS")
            .row("SUBTOTAL", "3.78")
            .row("TOTAL", "3.78")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("PASTA", "2.49"), ("BANANAS", "1.29")]))
    }

    func testTotalBeforeAndAfterTax() {
        let scan = ReceiptLayoutBuilder()
            .row("CORNER STORE")
            .row("CHIPS", "3.00")
            .row("SODA", "2.00")
            .row("Total before tax", "5.00")
            .row("H.S.T.", "0.65")
            .row("Total after tax", "5.65")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(itemList(receipt), itemList([("CHIPS", "3.00"), ("SODA", "2.00")]))
        XCTAssertEqual(receipt.subtotal, money("5.00"))
        XCTAssertEqual(receipt.tax, money("0.65"))
        XCTAssertEqual(receipt.total, money("5.65"))
    }

    func testSubAndFinal() {
        let scan = ReceiptLayoutBuilder()
            .row("CORNER STORE")
            .row("CHIPS", "3.00")
            .row("SODA", "2.00")
            .row("SUB", "5.00")
            .row("GST", "0.25")
            .row("FINAL", "5.25")
            .build()
        let receipt = parser.parse(scan)
        XCTAssertEqual(receipt.subtotal, money("5.00"))
        XCTAssertEqual(receipt.tax, money("0.25"))
        XCTAssertEqual(receipt.total, money("5.25"))
    }

    func testStoreNameWithoutStoreNumberOrBranch() {
        XCTAssertEqual(RulesReceiptParser.storeName(from: "SHELL #1234"), "SHELL")
        XCTAssertEqual(RulesReceiptParser.storeName(from: "WALMART STORE 3045"), "WALMART")
        XCTAssertEqual(RulesReceiptParser.storeName(from: "Walmart Supercentre, Toronto ON"), "Walmart Supercentre")
        XCTAssertEqual(RulesReceiptParser.storeName(from: "BEST BUY - EATON CENTRE"), "BEST BUY")
        XCTAssertEqual(RulesReceiptParser.storeName(from: "PIER 39 CAFE"), "PIER 39 CAFE")
        XCTAssertEqual(RulesReceiptParser.storeName(from: "7-ELEVEN"), "7-ELEVEN")
    }
}
