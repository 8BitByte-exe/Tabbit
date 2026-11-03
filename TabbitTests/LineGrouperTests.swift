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

    func testTiltedPageStillPairsNamesAndPrices() {
        let builder = ReceiptLayoutBuilder()
            .row("SHOP")
            .row("MILK", "3.49")
            .row("BREAD", "2.99")
            .row("EGGS", "4.29")
            .row("TOTAL", "10.77")
        for tilt: CGFloat in [0.02, -0.02] {
            let texts = LineGrouper.lines(from: builder.build(tilt: tilt)).map { line in line.text }
            XCTAssertEqual(texts, ["SHOP", "MILK 3.49", "BREAD 2.99", "EGGS 4.29", "TOTAL 10.77"], "tilt \(tilt)")
        }
    }

    func testFlatPageHasNoTilt() {
        let scan = ReceiptLayoutBuilder()
            .row("SHOP")
            .row("MILK", "3.49")
            .row("TOTAL", "3.49")
            .build()
        XCTAssertEqual(LineGrouper.candidateSlopes(of: scan.blocks).first, 0)
    }

    func testAlternativeReadingsAreCarriedToTheLine() {
        let scan = ReceiptLayoutBuilder()
            .row("SJBTOTAL", "6.48", alternatives: ["SUBTOTAL"])
            .build()
        let line = LineGrouper.lines(from: scan).first
        XCTAssertEqual(line?.alternativeTexts, ["SUBTOTAL 6.48"])
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
