import UIKit
import XCTest
@testable import Tabbit

/// A cinema's card slip read by Vision's document reader (1.2): one amount and no list of
/// items, "Cinema" misread as "Cinerna", and a date printed "26-11-08". Scanned 2026-11-09.
final class CardSlipTests: XCTestCase {

    private let scannedOn: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 9
        components.hour = 19
        return Calendar.current.date(from: components) ?? Date()
    }()

    private func slipScan() throws -> ScanResult {
        return try Fixtures.scan(named: "revue-cinema-slip")
    }

    private func rules(_ scan: ScanResult) -> Receipt {
        return RulesReceiptParser(referenceDate: scannedOn).parse(scan)
    }

    // MARK: - Rules

    func testPaymentSlipHasNoItemsJustTheTotal() throws {
        let receipt = rules(try slipScan())
        XCTAssertEqual(receipt.lineItems, [])
        XCTAssertEqual(receipt.total, money("13.50"))
        XCTAssertEqual(receipt.paymentMethod, "Visa")
        XCTAssertTrue(receipt.notes.contains(RulesReceiptParser.paymentSlipNote))
    }

    func testDateIsReadAsTheRecentOne() throws {
        XCTAssertEqual(rules(try slipScan()).date, CalendarDate(year: 2026, month: 11, day: 8))
    }

    func testASingleProductIsStillAnItem() {
        let scan = ReceiptLayoutBuilder().row("CAFE").row("LATTE", "4.50").build()
        let receipt = RulesReceiptParser().parse(scan)
        XCTAssertEqual(receipt.lineItems.map { item in item.amount }, [money("4.50")])
        XCTAssertEqual(receipt.total, money("4.50"))
    }

    // MARK: - Apple Intelligence

    private func outcome(storeName: String, isItemized: Bool) throws -> IntelligenceOutcome {
        let scan = try slipScan()
        let numbered = NumberedReceipt(scan: scan)
        XCTAssertEqual(numbered.entries.count, 1)
        let reading = ModelReceiptReading(storeName: storeName,
                                          labels: [ModelReceiptReading.Label(line: 1, kind: .item, name: "Movie Ticket")],
                                          pricesIncludeTax: false, category: "entertainment", date: "2026-11-08",
                                          isItemized: isItemized)
        return ModelReceiptVerifier.evaluate(reading, numbered: numbered, rules: rules(scan))
    }

    func testModelSaysNotItemized() throws {
        let result = try outcome(storeName: "Revue Cinema", isItemized: false)
        XCTAssertEqual(result.receipt.lineItems, [])
        XCTAssertEqual(result.receipt.total, money("13.50"))
        XCTAssertTrue(result.receipt.notes.contains(ModelReceiptVerifier.usedNote))
        XCTAssertFalse(result.receipt.notes.contains(ModelReceiptVerifier.usedUncheckedNote))
        XCTAssertEqual(result.suggestedCategory, .entertainment)
    }

    func testModelsSpellingFixOfTheStoreIsAccepted() throws {
        // The scan says "Revue Cinerna"; the model's "Revue Cinema" differs only by a look-alike.
        XCTAssertEqual(try outcome(storeName: "Revue Cinema", isItemized: true).receipt.merchant, "Revue Cinema")
        XCTAssertEqual(try outcome(storeName: "Cinema", isItemized: true).receipt.merchant, "Cinema")
        // A name that isn't on the receipt at all is not.
        XCTAssertNotEqual(try outcome(storeName: "Cineplex Odeon", isItemized: true).receipt.merchant, "Cineplex Odeon")
    }

    // MARK: - Spelling

    func testLookAlikeDistance() {
        XCTAssertEqual(OCRSpelling.distance("Cinerna", "Cinema"), OCRSpelling.lookAlikeCost, accuracy: 0.001)
        XCTAssertEqual(OCRSpelling.distance("T0TAL", "total"), OCRSpelling.lookAlikeCost, accuracy: 0.001)
        XCTAssertEqual(OCRSpelling.distance("Sobeys", "Sobers"), 1, accuracy: 0.001)
        XCTAssertEqual(OCRSpelling.distance("same", "SAME"), 0, accuracy: 0.001)
    }

    func testRepairOnlyTakesLookAlikeSuggestions() {
        XCTAssertEqual(OCRSpelling.bestRepair(of: "Cinerna", suggestions: ["Cinerama", "Cinema"]), "Cinema")
        XCTAssertNil(OCRSpelling.bestRepair(of: "Sobeys", suggestions: ["Sobers", "Soybeans"]))
        XCTAssertEqual(OCRSpelling.matchingCase("cinema", like: "CINERNA"), "CINEMA")
        XCTAssertEqual(OCRSpelling.matchingCase("cinema", like: "Cinerna"), "Cinema")
    }

    func testDictionaryRepairsTheStoreName() {
        XCTAssertTrue(OCRSpelling.lookAlikeVariants(of: "Cinerna").contains("cinema"))
        let checker = UITextChecker()
        let language = OCRSpelling.dictionaryLanguage
        let known = checker.rangeOfMisspelledWord(in: "cinema", range: NSRange(location: 0, length: 6),
                                                  startingAt: 0, wrap: false, language: language)
        let unknown = checker.rangeOfMisspelledWord(in: "cinerna", range: NSRange(location: 0, length: 7),
                                                    startingAt: 0, wrap: false, language: language)
        XCTAssertEqual(OCRSpelling.repairedName("Revue Cinerna"), "Revue Cinema",
                       "dictionary \(language) of \(UITextChecker.availableLanguages); cinema known: \(known.location == NSNotFound), cinerna unknown: \(unknown.location != NSNotFound)")
        XCTAssertEqual(OCRSpelling.repairedName("Sobeys #1234"), "Sobeys #1234")
        XCTAssertEqual(OCRSpelling.repairedName("Trader Joe's"), "Trader Joe's")
    }

    // MARK: - Autofill and checks

    func testAutofillRepairsAndMarksWhatToCheck() throws {
        let scan = try slipScan()
        let processed = ProcessedScan(scan: scan, receipt: rules(scan), pageJPEGs: [Data([1])],
                                      thumbnailJPEG: nil, languageCorrection: false, suggestedCategory: .transport)
        let record = ScanAutofill.record(from: processed, source: .photo, groupID: nil, now: scannedOn)
        XCTAssertEqual(record.merchant, "Revue Cinema")
        XCTAssertEqual(record.category, .entertainment)
        XCTAssertEqual(record.total, money("13.50"))
        XCTAssertEqual(record.items, [])
        XCTAssertFalse(record.unreadable.contains(.items))
        XCTAssertEqual(record.checks.map { check in check.field }, [.merchant])
    }

    func testDateCheckWhenAnotherReadingIsAlsoRecent() {
        // "03/11/26" is March 11 (month first) but could be November 3, last week.
        let check = ScanAutofill.dateCheck(for: CalendarDate(year: 2026, month: 3, day: 11),
                                           lines: ["DATE 03/11/26"], now: scannedOn)
        XCTAssertEqual(check?.field, .date)
        XCTAssertNil(ScanAutofill.dateCheck(for: CalendarDate(year: 2026, month: 11, day: 8),
                                            lines: ["26-11-08 15:30"], now: scannedOn))
        // An old receipt is fine to scan, but worth a look.
        XCTAssertNotNil(ScanAutofill.dateCheck(for: CalendarDate(year: 2019, month: 1, day: 12),
                                               lines: ["01/12/2019"], now: scannedOn))
    }

    func testChangingAFieldClearsItsCheck() throws {
        var record = ReceiptRecord(merchant: "Revue Cinema",
                                   checks: [FieldCheck(field: .merchant, reason: "Corrected"),
                                            FieldCheck(field: .date, reason: "Ambiguous")])
        record.date = Calendar.current.startOfDay(for: scannedOn)
        var form = ReceiptForm(record)
        form.merchant = "Revue Cinema Toronto"
        let updated = form.record(updating: record)
        XCTAssertEqual(updated.checks.map { check in check.field }, [.date])
    }
}
