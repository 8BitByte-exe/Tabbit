import XCTest
@testable import Tabbit

final class AmountParserTests: XCTestCase {

    func testPriceAfterName() {
        let parsed = AmountParser.trailingAmount(in: "BANANAS 1.29")
        XCTAssertEqual(parsed?.value, money("1.29"))
        XCTAssertEqual(parsed?.textBefore, "BANANAS")
    }

    func testTaxFlagAfterPrice() {
        XCTAssertEqual(AmountParser.trailingAmount(in: "ORGANIC MILK 4.99 F")?.value, money("4.99"))
    }

    func testCurrencySymbol() {
        XCTAssertEqual(AmountParser.trailingAmount(in: "Total $19.05")?.value, money("19.05"))
    }

    func testCurrencyCodeAfterPrice() {
        XCTAssertEqual(AmountParser.trailingAmount(in: "TOTAL 23.45 USD")?.value, money("23.45"))
    }

    func testLeadingMinusIsDiscount() {
        let parsed = AmountParser.trailingAmount(in: "COUPON -0.50")
        XCTAssertEqual(parsed?.value, money("-0.50"))
        XCTAssertEqual(parsed?.textBefore, "COUPON")
    }

    func testTrailingMinusIsDiscount() {
        XCTAssertEqual(AmountParser.trailingAmount(in: "COUPON 0.50-")?.value, money("-0.50"))
    }

    func testThousandsSeparators() {
        XCTAssertEqual(AmountParser.trailingAmount(in: "TV 1,234.56")?.value, money("1234.56"))
        XCTAssertEqual(AmountParser.trailingAmount(in: "TV 1.234,56")?.value, money("1234.56"))
    }

    func testCommaDecimal() {
        XCTAssertEqual(AmountParser.trailingAmount(in: "BROT 2,49")?.value, money("2.49"))
    }

    func testPercentagesAreNotAmounts() {
        XCTAssertEqual(AmountParser.trailingAmount(in: "Sales Tax 8.875% 1.55")?.value, money("1.55"))
        XCTAssertNil(AmountParser.trailingAmount(in: "TAX 8.25%"))
    }

    func testLastAmountOnTheLineWins() {
        let parsed = AmountParser.trailingAmount(in: "2 @ 0.99 1.98")
        XCTAssertEqual(parsed?.value, money("1.98"))
        XCTAssertEqual(parsed?.textBefore, "2 @ 0.99")
    }

    func testTextThatIsNotAnAmount() {
        let texts = [
            "11/02/2026 2:32 PM",
            "(555) 123-4567",
            "555.123.4567",
            "STORE #1234",
            "11.02.26",
            "GAS 3.499",
            "1.99 EACH BANANAS",
            "",
        ]
        for text in texts {
            XCTAssertNil(AmountParser.trailingAmount(in: text), "Expected no amount in \"\(text)\"")
        }
    }
}
