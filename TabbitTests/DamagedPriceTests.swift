import XCTest
@testable import Tabbit

/// Prices whose last digits OCR couldn't read. A Best Buy receipt (redacted) printed the
/// second item's price "$24.99", but the scan read it as "$24.9îŚ", so for several versions
/// the item was missing and the items never added up to the 59.98 subtotal.
final class DamagedPriceTests: XCTestCase {

    private let scannedOn: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 10
        components.hour = 9
        return Calendar.current.date(from: components) ?? Date()
    }()

    private func bestBuyScan() throws -> ScanResult {
        return try Fixtures.scan(named: "bestbuy-two-items")
    }

    // MARK: - Reading the price

    func testGarbledCentsAreAPartlyReadPrice() throws {
        let damaged = try XCTUnwrap(AmountParser.damagedAmount(in: "S26FE/25 IS GL ELITE $24.9îŚ"))
        XCTAssertEqual(damaged.low, money("24.90"))
        XCTAssertEqual(damaged.high, money("24.99"))
        XCTAssertNil(damaged.lookAlike)
        XCTAssertEqual(damaged.textBefore, "S26FE/25 IS GL ELITE")
        XCTAssertEqual(damaged.printed, "$24.9îŚ")
        XCTAssertEqual(AmountParser.damagedAmount(in: "ITEM $24.9îŚ H")?.high, money("24.99"))
    }

    func testLookAlikeDigitsAreReadByShape() {
        XCTAssertEqual(AmountParser.damagedAmount(in: "COFFEE $4.9S")?.lookAlike, money("4.95"))
        XCTAssertEqual(AmountParser.damagedAmount(in: "COFFEE 4.O|")?.lookAlike, money("4.01"))
        XCTAssertEqual(AmountParser.damagedAmount(in: "COFFEE 4.9Ś")?.lookAlike, money("4.95"))
    }

    func testOrdinaryTextIsNotADamagedPrice() {
        XCTAssertNil(AmountParser.damagedAmount(in: "MILK 3.49"))
        XCTAssertNil(AmountParser.damagedAmount(in: "REGULAR 45.3L"))
        XCTAssertNil(AmountParser.damagedAmount(in: "APPLES 1.5KG"))
        XCTAssertNil(AmountParser.damagedAmount(in: "HST 8.8%"))
        XCTAssertNil(AmountParser.damagedAmount(in: "Override $15.00 Off (39.99-15.00)"))
        XCTAssertNil(AmountParser.damagedAmount(in: "Visit Bestbuy.ca"))
    }

    func testArithmeticFillsInTheMissingDigit() {
        let scan = ReceiptLayoutBuilder()
            .row("SHOP")
            .row("CASE", "$34.99")
            .row("SCREEN GUARD", "$24.9îŚ")
            .row("SUBTOTAL", "$59.98")
            .row("TAX", "$7.80")
            .row("TOTAL", "$67.78")
            .build()
        let receipt = RulesReceiptParser().parse(scan)
        XCTAssertEqual(receipt.lineItems.map { item in item.amount }, [money("34.99"), money("24.99")])
        XCTAssertTrue(receipt.notes.contains { note in note.hasPrefix(RulesReceiptParser.repairedPricePrefix) })
        XCTAssertTrue(ReceiptValidator.checks(for: receipt).allSatisfy { check in check.passed })
    }

    func testAPriceTheArithmeticRulesOutIsLeftUnread() {
        // 59.98 − 34.99 is 24.99, which "$23.9îŚ" (23.90–23.99) can't be.
        let scan = ReceiptLayoutBuilder()
            .row("SHOP")
            .row("CASE", "$34.99")
            .row("SCREEN GUARD", "$23.9îŚ")
            .row("SUBTOTAL", "$59.98")
            .row("TOTAL", "$59.98")
            .build()
        let receipt = RulesReceiptParser().parse(scan)
        XCTAssertEqual(receipt.lineItems.map { item in item.amount }, [money("34.99")])
        XCTAssertFalse(receipt.notes.contains { note in note.hasPrefix(RulesReceiptParser.repairedPricePrefix) })
    }

    // MARK: - The Best Buy receipt

    func testBestBuyWithTheRules() throws {
        let receipt = RulesReceiptParser(referenceDate: scannedOn).parse(try bestBuyScan())
        XCTAssertEqual(receipt.lineItems.map { item in item.amount }, [money("34.99"), money("24.99")])
        XCTAssertEqual(receipt.subtotal, money("59.98"))
        XCTAssertEqual(receipt.tax, money("7.80"))
        XCTAssertEqual(receipt.total, money("67.78"))
        XCTAssertTrue(receipt.notes.contains { note in note.hasPrefix(RulesReceiptParser.repairedPricePrefix) })
        XCTAssertTrue(ReceiptValidator.checks(for: receipt).allSatisfy { check in check.passed })
    }

    func testBestBuyWithAppleIntelligence() throws {
        let scan = try bestBuyScan()
        let numbered = NumberedReceipt(scan: scan, slopeChoice: RulesReceiptParser.bestSlopeChoice(for: scan))
        let second = numbered.entries.first { entry in entry.text.contains("ELITE") }
        XCTAssertEqual(second?.amount, money("24.99"))
        var labels: [ModelReceiptReading.Label] = []
        for entry in numbered.entries {
            let kind: ModelLineKind
            switch entry.role {
            case .subtotal:
                kind = .subtotal
            case .tax, .taxTotal:
                kind = .tax
            case .total, .strongTotal:
                kind = .total
            default:
                kind = .item
            }
            labels.append(ModelReceiptReading.Label(line: entry.number, kind: kind, name: kind == .item ? entry.textBefore : ""))
        }
        let reading = ModelReceiptReading(storeName: "Best Buy", labels: labels, pricesIncludeTax: false,
                                          category: "electronics", date: "2026-11-04", isItemized: true)
        let rules = RulesReceiptParser(referenceDate: scannedOn).parse(scan)
        let outcome = ModelReceiptVerifier.evaluate(reading, numbered: numbered, rules: rules)
        let amounts = outcome.receipt.lineItems.map { item in item.amount }.filter { amount in amount != 0 }
        XCTAssertEqual(amounts, [money("34.99"), money("24.99")])
        XCTAssertEqual(outcome.receipt.total, money("67.78"))
        XCTAssertTrue(ReceiptValidator.checks(for: outcome.receipt).allSatisfy { check in check.passed })
        XCTAssertTrue(outcome.receipt.notes.contains { note in note.hasPrefix(RulesReceiptParser.repairedPricePrefix) })
    }

    func testBestBuyAsksToCheckTheItemsNotTheTotal() throws {
        let scan = try bestBuyScan()
        let processed = ProcessedScan(scan: scan, receipt: RulesReceiptParser(referenceDate: scannedOn).parse(scan),
                                      pageJPEGs: [Data([1])], thumbnailJPEG: nil, languageCorrection: false,
                                      suggestedCategory: nil)
        let record = ScanAutofill.record(from: processed, source: .photo, groupID: nil, now: scannedOn)
        XCTAssertEqual(record.items.map { item in item.price }, [money("34.99"), money("24.99")])
        let fields = record.checks.map { check in check.field }
        XCTAssertTrue(fields.contains(.items))
        XCTAssertFalse(fields.contains(.total))
    }
}
