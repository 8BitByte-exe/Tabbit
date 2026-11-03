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
struct ReceiptLayoutBuilder {
    static let rowHeight: CGFloat = 0.02
    static let rowSpacing: CGFloat = 0.01

    private var blocks: [RecognizedTextBlock] = []
    private var nextRowTop: CGFloat = 0.95
    private var pageIndex: Int = 0
    private var pageCount: Int = 1

    func row(_ left: String, _ right: String? = nil, rightYOffset: CGFloat = 0) -> ReceiptLayoutBuilder {
        var copy = self
        let minY = copy.nextRowTop - ReceiptLayoutBuilder.rowHeight
        copy.blocks.append(copy.makeBlock(left, x: 0.05, y: minY, width: 0.45))
        if let right = right {
            copy.blocks.append(copy.makeBlock(right, x: 0.75, y: minY + rightYOffset, width: 0.15))
        }
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
    /// doesn't depend on Vision's ordering.
    func build(reversed: Bool = false) -> ScanResult {
        let ordered: [RecognizedTextBlock] = reversed ? Array(blocks.reversed()) : blocks
        return ScanResult(pageCount: pageCount, blocks: ordered)
    }

    private func makeBlock(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) -> RecognizedTextBlock {
        return RecognizedTextBlock(
            text: text,
            confidence: 1,
            boundingBox: CGRect(x: x, y: y, width: width, height: ReceiptLayoutBuilder.rowHeight),
            pageIndex: pageIndex
        )
    }
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
