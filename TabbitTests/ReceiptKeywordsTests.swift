import XCTest
@testable import Tabbit

final class ReceiptKeywordsTests: XCTestCase {

    func testEditDistance() {
        XCTAssertEqual(ReceiptKeywords.editDistance("SJETOTAL", "SUBTOTAL"), 2)
        XCTAssertEqual(ReceiptKeywords.editDistance("", "ABC"), 3)
        XCTAssertEqual(ReceiptKeywords.editDistance("TOTAL", "TOTAL"), 0)
    }

    func testWordsUndoDigitLetterMixups() {
        XCTAssertEqual(ReceiptKeywords.words(in: "T0TAL 8.38"), ["TOTAL", "8", "38"])
        XCTAssertEqual(ReceiptKeywords.words(in: "5UBTOTAL"), ["SUBTOTAL"])
        XCTAssertEqual(ReceiptKeywords.words(in: "TAX1 0.50"), ["TAX", "0", "50"])
    }

    func testRoles() {
        let expectations: [(String, ReceiptLineRole)] = [
            ("SUBTOTAL", .subtotal),
            ("SUB TOTAL", .subtotal),
            ("SUB-TOTAL", .subtotal),
            ("SJETOTAL 6.48", .subtotal),
            ("5UBTOTAL", .subtotal),
            ("SUBTTL", .subtotal),
            ("T0TAL 8.38", .total),
            ("TOTA1 8.38", .total),
            ("TOTAL INCL. VAT", .total),
            ("TOTAL TAX", .taxTotal),
            ("TAX1 0.50", .tax),
            ("SALES TAX 8.875% 1.55", .tax),
            ("TOTAL SAVINGS 15.00", .notATotal),
            ("TOTAL YOU SAVED", .notATotal),
            ("BALANCE DUE", .strongTotal),
            ("BALANSE DUE", .strongTotal),
            ("AMOUNT DUE", .strongTotal),
            ("GRAND TOTAL", .strongTotal),
            ("VISA 8.38", .payment),
            ("CHANGE 0.00", .payment),
            ("REG PRICE 4.99", .info),
            ("YOU SAVE 1.00", .info),
            ("CLUB CARD SAVINGS 1.00-", .info),
            ("REG COLA 1.99", .other),
            ("ORIGINAL CHIPS 3.99", .other),
            ("TAXI FARE 12.00", .other),
            ("CASHEWS 5.99", .other),
            ("COUPON -0.50", .other),
            ("BANANAS 1.29", .other),
        ]
        for (text, role) in expectations {
            XCTAssertEqual(ReceiptKeywords.role(for: text), role, "\"\(text)\"")
        }
    }

    func testDetailOnlyText() {
        XCTAssertTrue(ReceiptKeywords.isDetailOnly("2 @ 0.99"))
        XCTAssertTrue(ReceiptKeywords.isDetailOnly("2 FOR"))
        XCTAssertTrue(ReceiptKeywords.isDetailOnly(""))
        XCTAssertTrue(ReceiptKeywords.isDetailOnly("1.25 LB @ 0.99/LB"))
        XCTAssertTrue(ReceiptKeywords.isDetailOnly("2 X 0.99"))
        XCTAssertFalse(ReceiptKeywords.isDetailOnly("SODA"))
    }
}
