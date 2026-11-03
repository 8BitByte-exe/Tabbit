import CoreGraphics
import Foundation
@testable import Tabbit

/// Exact decimal from a string, e.g. money("1.29").
func money(_ text: String) -> Decimal {
    return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
}

/// Builds fake OCR output that looks like Vision's, one receipt row at a time from the top.
///
/// `row("BANANAS", "1.29")` puts the name on the left and the price on the right as
/// two separate blocks, the way Vision usually returns receipt lines with a wide gap.
/// `row("Latte 4.50")` is a line Vision returned as a single block.
/// `rightYOffset` moves the price up (+) or down (-); a text line is 0.02 high
/// and rows are 0.03 apart.
struct ReceiptLayoutBuilder {
    static let rowHeight: CGFloat = 0.02
    static let rowSpacing: CGFloat = 0.01

    private var blocks: [RecognizedTextBlock] = []
    private var nextRowTop: CGFloat = 0.95
    private var pageIndex: Int = 0
    private var pageCount: Int = 1

    func row(_ left: String, _ right: String? = nil, rightYOffset: CGFloat = 0,
             confidence: Float = 1, alternatives: [String] = []) -> ReceiptLayoutBuilder {
        var copy = self
        let minY = copy.nextRowTop - ReceiptLayoutBuilder.rowHeight
        copy.blocks.append(copy.makeBlock(left, x: 0.05, y: minY, width: 0.45,
                                          confidence: confidence, alternatives: alternatives))
        if let right = right {
            copy.blocks.append(copy.makeBlock(right, x: 0.75, y: minY + rightYOffset, width: 0.15,
                                              confidence: 1, alternatives: []))
        }
        copy.nextRowTop = minY - ReceiptLayoutBuilder.rowSpacing
        return copy
    }

    /// A price on its own row at the right, under the previous row.
    func priceRow(_ price: String) -> ReceiptLayoutBuilder {
        var copy = self
        let minY = copy.nextRowTop - ReceiptLayoutBuilder.rowHeight
        copy.blocks.append(copy.makeBlock(price, x: 0.75, y: minY, width: 0.15, confidence: 1, alternatives: []))
        copy.nextRowTop = minY - ReceiptLayoutBuilder.rowSpacing
        return copy
    }

    func newPage() -> ReceiptLayoutBuilder {
        var copy = self
        copy.pageIndex += 1
        copy.pageCount += 1
        copy.nextRowTop = 0.95
        return copy
    }

    /// `reversed: true` returns the blocks in reverse order, to prove the parser
    /// doesn't depend on Vision's ordering. `tilt` rotates the page: each block
    /// moves up by `tilt × (its center x − 0.5)`.
    func build(reversed: Bool = false, tilt: CGFloat = 0) -> ScanResult {
        let tilted = blocks.map { block -> RecognizedTextBlock in
            let box = block.boundingBox
            let moved = CGRect(x: box.minX, y: box.minY + tilt * (box.midX - 0.5), width: box.width, height: box.height)
            return RecognizedTextBlock(text: block.text, confidence: block.confidence, boundingBox: moved,
                                       pageIndex: block.pageIndex, alternatives: block.alternatives)
        }
        let ordered: [RecognizedTextBlock] = reversed ? Array(tilted.reversed()) : tilted
        return ScanResult(pageCount: pageCount, blocks: ordered)
    }

    private func makeBlock(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat,
                           confidence: Float, alternatives: [String]) -> RecognizedTextBlock {
        return RecognizedTextBlock(
            text: text,
            confidence: confidence,
            boundingBox: CGRect(x: x, y: y, width: width, height: ReceiptLayoutBuilder.rowHeight),
            pageIndex: pageIndex,
            alternatives: alternatives
        )
    }
}

/// Line items as "NAME = amount" strings, for readable assertions:
/// `XCTAssertEqual(itemList(receipt), itemList([("BANANAS", "1.29")]))`.
func itemList(_ receipt: Receipt) -> [String] {
    return receipt.lineItems.map { item in "\(item.name) = \(item.amount)" }
}

func itemList(_ pairs: [(String, String)]) -> [String] {
    return pairs.map { pair in "\(pair.0) = \(money(pair.1))" }
}

/// Loads JSON fixtures from TabbitTests/Fixtures. Files from the app's Export button work as-is.
enum Fixtures {
    private final class BundleToken {}

    enum FixtureError: Error {
        case missing(String)
    }

    static func export(named name: String) throws -> ScanExport {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw FixtureError.missing(name)
        }
        let data = try Data(contentsOf: url)
        return try ScanExport.makeDecoder().decode(ScanExport.self, from: data)
    }

    static func scan(named name: String) throws -> ScanResult {
        return try export(named: name).scan
    }
}
