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
            ("COUPON -0.50", .discount),
            ("MEMBER DISCOUNT 1.00", .discount),
            ("20% OFF 3.00", .discount),
            ("ROUNDING -0.02", .rounding),
            ("BANANAS 1.29", .other),
            ("CHOCOLATE BAR 1.99", .other),
            ("SUMMER SALAD 9.99", .other),
            ("IMPORTED BEER 5.99", .other),
            // Other languages
            ("SUMME 5,50", .total),
            ("SUMA 12,40", .total),
            ("ZWISCHENSUMME 5,50", .subtotal),
            ("SOUS-TOTAL 9,80", .subtotal),
            ("ZU ZAHLEN 5,50", .strongTotal),
            ("TOTAL A PAGAR 12,40", .strongTotal),
            ("MWST 19% 0,88", .tax),
            ("IVA 21% 2,15", .tax),
            ("INKL. MWST 0,88", .includedTax),
            ("IVA INCLUIDO 2,15", .includedTax),
            ("VAT INCLUDED 1.50", .includedTax),
            ("RÜCKGELD 14,50", .payment),
            ("TARJETA 12,40", .payment),
            // Wordings from real receipts
            ("SUB 45.67", .subtotal),
            ("SUB TTL 45.67", .subtotal),
            ("TURKEY SUB 8.99", .other),
            ("Total before tax 49.99", .subtotal),
            ("Total after tax 56.49", .strongTotal),
            ("Sub with tax 56.49", .strongTotal),
            ("SUB W/ TAX 56.49", .strongTotal),
            ("After tax 56.49", .strongTotal),
            ("FINAL 56.49", .strongTotal),
            ("FINAL TOTAL 56.49", .strongTotal),
            ("FINAL SALE JACKET 40.00", .other),
            ("HST 13% 6.50", .tax),
            ("H.S.T. 6.50", .tax),
            ("GST/HST 6.50", .tax),
            ("TPS 2.50", .tax),
            ("TVQ 4.99", .tax),
            ("GST/HST INCLUDED 6.32", .includedTax),
            ("TOTAL TAX 2.40", .taxTotal),
            ("PRICE/L 1.67", .unitPrice),
            ("PRICE PER LITRE 1.67", .unitPrice),
            ("UNIT PRICE 0.99", .unitPrice),
            ("LITRES 32.89", .unitPrice),
            ("1.25 LB @ 0.59/LB 0.74", .other),
            ("FUEL TOTAL 54.92", .other),
            ("YOU SAVED 2.98", .info),
            ("YOUSAVED 2.98", .info),
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
        XCTAssertTrue(ReceiptKeywords.isDetailOnly("0,456 KG X 3,99 EUR/KG"))
        XCTAssertTrue(ReceiptKeywords.isDetailOnly("2 STK X 1,29"))
        XCTAssertFalse(ReceiptKeywords.isDetailOnly("SODA"))
    }

    func testHeadingsSavingsAndInitials() {
        XCTAssertTrue(ReceiptKeywords.isHeading("PRODUCE"))
        XCTAssertTrue(ReceiptKeywords.isHeading("21-GROCERY"))
        XCTAssertTrue(ReceiptKeywords.isHeading("HEALTH & BEAUTY"))
        XCTAssertFalse(ReceiptKeywords.isHeading("PRODUCE BOX"))
        XCTAssertFalse(ReceiptKeywords.isHeading("BANANAS"))
        XCTAssertFalse(ReceiptKeywords.isHeading("4.99"))

        XCTAssertTrue(ReceiptKeywords.isSavings("YOU SAVED 2.98"))
        XCTAssertTrue(ReceiptKeywords.isSavings("TOTAL SAVINGS 4.00"))
        XCTAssertFalse(ReceiptKeywords.isSavings("REG PRICE 4.99"))

        XCTAssertEqual(ReceiptKeywords.joiningInitials(["H", "S", "T", "6", "50"]), ["HST", "6", "50"])
        XCTAssertEqual(ReceiptKeywords.joiningInitials(["MILK", "4", "99", "T"]), ["MILK", "4", "99", "T"])
        XCTAssertEqual(ReceiptKeywords.joiningInitials(["2", "X", "BURGER"]), ["2", "X", "BURGER"])
    }
}
