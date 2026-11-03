import XCTest
@testable import Tabbit

final class ReceiptDateParserTests: XCTestCase {

    private func iso(_ text: String) -> String? {
        return ReceiptDateParser.date(in: text)?.isoString
    }

    func testUSNumericDates() {
        XCTAssertEqual(iso("11/02/2026 2:32 PM"), "2026-11-02")
        XCTAssertEqual(iso("12/25/26"), "2026-12-25")
    }

    func testDayFirstWhenTheFirstNumberCannotBeAMonth() {
        XCTAssertEqual(iso("25/12/2026"), "2026-12-25")
    }

    func testYearFirst() {
        XCTAssertEqual(iso("2026-11-03"), "2026-11-03")
    }

    func testDottedDatesAreDayFirst() {
        XCTAssertEqual(iso("03.11.2026"), "2026-11-03")
    }

    func testMonthNames() {
        XCTAssertEqual(iso("Nov 3, 2026  8:14 AM"), "2026-11-03")
        XCTAssertEqual(iso("November 3rd, 2026"), "2026-11-03")
        XCTAssertEqual(iso("3 November 2026"), "2026-11-03")
        XCTAssertEqual(iso("03-NOV-26"), "2026-11-03")
    }

    func testNotDates() {
        let texts = [
            "DECAF 12 16",       // "DEC" inside a word is not a month
            "13/13/2026",
            "02/30/2026",        // no February 30th
            "14:32",             // a time alone is not a date
            "(555) 123-4567",
            "BANANAS 1.29",
        ]
        for text in texts {
            XCTAssertNil(ReceiptDateParser.date(in: text), "Expected no date in \"\(text)\"")
        }
    }

    func testFirstDateInLines() {
        let lines = ["TRADER JOE'S", "(555) 123-4567", "11/02/2026 2:32 PM", "Return by 12/02/2026"]
        XCTAssertEqual(ReceiptDateParser.firstDate(in: lines)?.isoString, "2026-11-02")
    }
}
