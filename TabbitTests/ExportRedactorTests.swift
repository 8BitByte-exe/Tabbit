import CoreGraphics
import XCTest
@testable import Tabbit

final class ExportRedactorTests: XCTestCase {

    func testCardAndAuthNumbersAreBlanked() {
        XCTAssertEqual(ExportRedactor.redact("VISA ************1234"), "VISA ************####")
        XCTAssertEqual(ExportRedactor.redact("AUTH CODE 123456"), "AUTH CODE ######")
        XCTAssertEqual(ExportRedactor.redact("ACCT XXXX5678"), "ACCT XXXX####")
    }

    func testPricesDatesAndTimesOnSensitiveLinesAreKept() {
        XCTAssertEqual(ExportRedactor.redact("VISA 8.38"), "VISA 8.38")
        XCTAssertEqual(ExportRedactor.redact("CLUB CARD SAVINGS 1.00-"), "CLUB CARD SAVINGS 1.00-")
        XCTAssertEqual(ExportRedactor.redact("TRANS 4421 11/02/2026 14:32"), "TRANS #### 11/02/2026 14:32")
    }

    func testPhoneNumbersAndLongNumbersAreBlanked() {
        XCTAssertEqual(ExportRedactor.redact("(555) 123-4567"), "(###) ###-####")
        XCTAssertEqual(ExportRedactor.redact("TEL 555-123-4567"), "TEL ###-###-####")
        XCTAssertEqual(ExportRedactor.redact("0123456789012"), "#############")
    }

    func testOrdinaryLinesAreUntouched() {
        for text in ["BANANAS 1.29", "11/02/2026 2:32 PM", "STORE #1234", "123 MAIN STREET", "TOTAL 8.38"] {
            XCTAssertEqual(ExportRedactor.redact(text), text)
        }
    }

    func testRedactsBlocksAndAlternatives() {
        let scan = ScanResult(pageCount: 1, blocks: [
            RecognizedTextBlock(text: "VISA ****1234", confidence: 0.9,
                                boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.3, height: 0.02),
                                pageIndex: 0, alternatives: ["VISA ****1284"]),
        ])
        let redacted = ExportRedactor.redact(scan)
        XCTAssertEqual(redacted.blocks.first?.text, "VISA ****####")
        XCTAssertEqual(redacted.blocks.first?.alternatives, ["VISA ****####"])
        XCTAssertEqual(redacted.blocks.first?.boundingBox, scan.blocks.first?.boundingBox)
    }
}
