import XCTest
@testable import Tabbit

/// A cinema's card slip read by Vision's document reader (1.2): one amount, no total line,
/// and "Cinema" misread as "Cinerna".
final class CardSlipTests: XCTestCase {

    private func slipScan() throws -> ScanResult {
        return try Fixtures.scan(named: "revue-cinema-slip")
    }

    func testTheOnlyAmountIsTheTotal() throws {
        let receipt = RulesReceiptParser().parse(try slipScan())
        XCTAssertEqual(receipt.lineItems.map { item in item.amount }, [money("13.50")])
        XCTAssertEqual(receipt.total, money("13.50"))
        XCTAssertEqual(receipt.paymentMethod, "Visa")
        XCTAssertTrue(receipt.notes.contains(RulesReceiptParser.singleAmountNote))
    }

    func testAppleIntelligenceReadingAddsUp() throws {
        let scan = try slipScan()
        let numbered = NumberedReceipt(scan: scan)
        XCTAssertEqual(numbered.entries.count, 1)
        // What the model answered on the phone: line 1 is the item, plus labels for lines
        // that don't exist, which are ignored.
        var labels = [ModelReceiptReading.Label(line: 1, kind: .item, name: "")]
        labels.append(ModelReceiptReading.Label(line: 7, kind: .total, name: ""))
        let reading = ModelReceiptReading(storeName: "Revue Cinerna", labels: labels, pricesIncludeTax: false,
                                          category: "transport", date: "2008-11-26")
        let outcome = ModelReceiptVerifier.evaluate(reading, numbered: numbered, rules: RulesReceiptParser().parse(scan))
        XCTAssertEqual(outcome.receipt.total, money("13.50"))
        XCTAssertTrue(outcome.receipt.notes.contains(ModelReceiptVerifier.usedNote))
        XCTAssertFalse(outcome.receipt.notes.contains(ModelReceiptVerifier.usedUncheckedNote))
    }

    func testMisreadCinemaIsStillEntertainment() throws {
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Revue Cinerna", items: []), .entertainment)
        // The store's name outranks Apple Intelligence's guess.
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Revue Cinerna", items: [], suggestion: .transport), .entertainment)
        XCTAssertEqual(CategoryGuesser.repairedName("Revue Cinerna"), "Revue Cinema")
        XCTAssertEqual(CategoryGuesser.repairedName("REVUE CINERNA"), "REVUE CINEMA")
        XCTAssertEqual(CategoryGuesser.repairedName("Burns Bakery"), "Burns Bakery")
        XCTAssertEqual(CategoryGuesser.repairedName("Barnes"), "Barnes")
    }

    func testAutofillUsesTheRepairedName() throws {
        let scan = try slipScan()
        let processed = ProcessedScan(scan: scan, receipt: RulesReceiptParser().parse(scan), pageJPEGs: [Data([1])],
                                      thumbnailJPEG: nil, languageCorrection: false, suggestedCategory: .transport)
        let record = ScanAutofill.record(from: processed, source: .camera, groupID: nil)
        XCTAssertEqual(record.merchant, "Revue Cinema")
        XCTAssertEqual(record.category, .entertainment)
        XCTAssertEqual(record.total, money("13.50"))
    }
}
