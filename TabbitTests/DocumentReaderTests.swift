import CoreGraphics
import XCTest
@testable import Tabbit

/// Vision's document reader (tier 2) and the photo for Apple Intelligence (iOS 27).
/// The readers themselves only run on the phone; these cover the logic around them.
final class DocumentReaderTests: XCTestCase {

    private func block(_ text: String, x: CGFloat, width: CGFloat, centerY: CGFloat, row: Int? = nil) -> RecognizedTextBlock {
        return RecognizedTextBlock(text: text, confidence: 1,
                                   boundingBox: CGRect(x: x, y: centerY - 0.01, width: width, height: 0.02),
                                   pageIndex: 0, row: row)
    }

    // MARK: - Table rows

    func testLineIsMatchedToTheRowAroundIt() {
        let rows: [[CGRect]] = [
            [CGRect(x: 0.05, y: 0.78, width: 0.5, height: 0.04), CGRect(x: 0.7, y: 0.78, width: 0.25, height: 0.04)],
            [CGRect(x: 0.05, y: 0.74, width: 0.5, height: 0.04), CGRect(x: 0.7, y: 0.74, width: 0.25, height: 0.04)],
        ]
        XCTAssertEqual(DocumentRows.row(for: CGRect(x: 0.75, y: 0.79, width: 0.1, height: 0.02), in: rows), 0)
        XCTAssertEqual(DocumentRows.row(for: CGRect(x: 0.1, y: 0.745, width: 0.3, height: 0.02), in: rows), 1)
        XCTAssertNil(DocumentRows.row(for: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.02), in: rows))
        XCTAssertNil(DocumentRows.row(for: CGRect(x: 0.1, y: 0.79, width: 0.3, height: 0.02), in: []))
    }

    func testPriceFollowsItsDocumentRowOverTheCloserName() {
        // The price was printed beside MILK but curled down toward BREAD.
        let plain = [
            block("MILK", x: 0.1, width: 0.2, centerY: 0.80),
            block("3.49", x: 0.8, width: 0.1, centerY: 0.776),
            block("BREAD", x: 0.1, width: 0.2, centerY: 0.76),
        ]
        XCTAssertEqual(LineGrouper.lines(from: plain, pageIndex: 0).map { line in line.text }, ["MILK", "BREAD 3.49"])

        let withRows = [
            block("MILK", x: 0.1, width: 0.2, centerY: 0.80, row: 0),
            block("3.49", x: 0.8, width: 0.1, centerY: 0.776, row: 0),
            block("BREAD", x: 0.1, width: 0.2, centerY: 0.76, row: 1),
        ]
        XCTAssertEqual(LineGrouper.lines(from: withRows, pageIndex: 0).map { line in line.text }, ["MILK 3.49", "BREAD"])
    }

    func testLonePriceJoinsItsDocumentRowFurtherAway() {
        let blocks = [
            block("MILK", x: 0.1, width: 0.2, centerY: 0.80, row: 0),
            block("3.49", x: 0.8, width: 0.1, centerY: 0.765, row: 0),
            block("BREAD", x: 0.1, width: 0.2, centerY: 0.75, row: 1),
        ]
        XCTAssertEqual(LineGrouper.lines(from: blocks, pageIndex: 0).map { line in line.text }, ["MILK 3.49", "BREAD"])
    }

    func testRowsDoNotMergeTextPrintedInTheSamePlace() {
        // A table cell with two printed lines: the item and its detail line stay apart.
        let blocks = [
            block("BANANAS", x: 0.1, width: 0.3, centerY: 0.80, row: 0),
            block("2 @ 0.99", x: 0.12, width: 0.25, centerY: 0.775, row: 0),
            block("1.98", x: 0.8, width: 0.1, centerY: 0.80, row: 0),
        ]
        XCTAssertEqual(LineGrouper.lines(from: blocks, pageIndex: 0).map { line in line.text }, ["BANANAS 1.98", "2 @ 0.99"])
    }

    func testRowsAndReaderSurviveExport() throws {
        let scan = ScanResult(pageCount: 1, blocks: [
            RecognizedTextBlock(text: "MILK", confidence: 0.9,
                                boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.25, height: 0.02), pageIndex: 0, row: 4),
        ], reader: "documents", seconds: 1.5)
        let export = ScanExport(scan: scan, parsed: nil, exportedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                appVersion: nil)
        let data = try ScanExport.makeEncoder().encode(export)
        let decoded = try ScanExport.makeDecoder().decode(ScanExport.self, from: data)
        XCTAssertEqual(decoded.scan, scan)
        XCTAssertEqual(decoded.scan.blocks.first?.row, 4)
        XCTAssertEqual(ExportRedactor.redact(scan).blocks.first?.row, 4)
        XCTAssertEqual(ExportRedactor.redact(scan).reader, "documents")
    }

    // MARK: - Photo for Apple Intelligence

    func testPhotoSectionsMakeThePictureAboutSquare() {
        XCTAssertEqual(ReceiptPhoto.columnCount(heightOverWidth: 1), 1)
        XCTAssertEqual(ReceiptPhoto.columnCount(heightOverWidth: 1.5), 1)
        XCTAssertEqual(ReceiptPhoto.columnCount(heightOverWidth: 4), 2)
        XCTAssertEqual(ReceiptPhoto.columnCount(heightOverWidth: 9), 3)
        XCTAssertEqual(ReceiptPhoto.columnCount(heightOverWidth: 40), ReceiptPhoto.maxColumns)
        XCTAssertEqual(ReceiptPhoto.columnCount(heightOverWidth: 0), 1)
    }

    func testSectionsCoverTheWholeStripWithOverlap() {
        let one = ReceiptPhoto.sections(columns: 1)
        XCTAssertEqual(one.starts, [0])
        XCTAssertEqual(one.height, 1)

        let three = ReceiptPhoto.sections(columns: 3)
        XCTAssertEqual(three.starts.count, 3)
        XCTAssertEqual(three.starts[0], 0)
        XCTAssertEqual(Double(three.starts[2] + three.height), 1, accuracy: 0.0001)
        // Each section starts before the previous one ends.
        XCTAssertLessThan(three.starts[1], three.starts[0] + three.height)
        XCTAssertLessThan(three.starts[2], three.starts[1] + three.height)
    }

    func testTextAreaIsFlippedToTopLeftWithAMargin() throws {
        let blocks = [
            block("SHOP", x: 0.2, width: 0.3, centerY: 0.9),
            block("TOTAL", x: 0.3, width: 0.4, centerY: 0.3),
        ]
        let area = try XCTUnwrap(ReceiptPhoto.textArea(of: blocks))
        XCTAssertEqual(Double(area.minX), 0.18, accuracy: 0.0001)
        XCTAssertEqual(Double(area.maxX), 0.72, accuracy: 0.0001)
        // Vision's top (y 0.91) is UIKit's 0.09, less the margin.
        XCTAssertEqual(Double(area.minY), 0.07, accuracy: 0.0001)
        XCTAssertEqual(Double(area.maxY), 0.73, accuracy: 0.0001)
        XCTAssertNil(ReceiptPhoto.textArea(of: []))
    }

    func testPromptMentionsThePhotoOnlyWhenThereIsOne() {
        let scan = ReceiptLayoutBuilder().row("SHOP").row("BREAD", "3.49").row("TOTAL", "3.49").build()
        let numbered = NumberedReceipt(scan: scan)
        let plain = ReceiptPrompt.make(for: numbered)
        XCTAssertFalse(plain.contains("photo"))
        let withPhoto = ReceiptPrompt.make(for: numbered, photoSections: 2)
        XCTAssertTrue(withPhoto.contains("2 sections side by side"))
        XCTAssertTrue(withPhoto.hasSuffix(numbered.text))
        XCTAssertTrue(ReceiptPrompt.make(for: numbered, photoSections: 1).contains("The photo shows the same receipt."))
    }
}
