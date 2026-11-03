import XCTest
@testable import Tabbit

final class LineGrouperTests: XCTestCase {

    func testBlocksAtTheSameHeightBecomeOneLine() {
        let scan = ReceiptLayoutBuilder()
            .row("TRADER JOE'S")
            .row("BANANAS", "1.29")
            .row("TOTAL", "1.29")
            .build()
        let texts = LineGrouper.lines(from: scan).map { line in line.text }
        XCTAssertEqual(texts, ["TRADER JOE'S", "BANANAS 1.29", "TOTAL 1.29"])
    }

    func testOrderOfBlocksDoesNotMatter() {
        let builder = ReceiptLayoutBuilder()
            .row("TRADER JOE'S")
            .row("BANANAS", "1.29")
            .row("TOTAL", "1.29")
        let normal = LineGrouper.lines(from: builder.build()).map { line in line.text }
        let reversed = LineGrouper.lines(from: builder.build(reversed: true)).map { line in line.text }
        XCTAssertEqual(normal, reversed)
    }

    func testSlightlyHigherPriceStaysOnItsLine() {
        let scan = ReceiptLayoutBuilder()
            .row("ORGANIC MILK", "4.99", rightYOffset: 0.006)
            .row("EGGS", "3.49", rightYOffset: -0.006)
            .build()
        let texts = LineGrouper.lines(from: scan).map { line in line.text }
        XCTAssertEqual(texts, ["ORGANIC MILK 4.99", "EGGS 3.49"])
    }

    func testPagesComeInOrder() {
        let scan = ReceiptLayoutBuilder()
            .row("PAGE ONE SHOP")
            .row("ITEM A", "1.00")
            .newPage()
            .row("ITEM B", "2.00")
            .build(reversed: true)
        let lines = LineGrouper.lines(from: scan)
        XCTAssertEqual(lines.map { line in line.text }, ["PAGE ONE SHOP", "ITEM A 1.00", "ITEM B 2.00"])
        XCTAssertEqual(lines.map { line in line.pageIndex }, [0, 0, 1])
    }
}
