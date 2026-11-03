import CoreGraphics
import Foundation

/// One piece of text that Vision recognized on a scanned page, usually a single line.
struct RecognizedTextBlock: Equatable {
    /// The best candidate string Vision produced for this block.
    let text: String

    /// Vision's confidence for `text`, from 0.0 to 1.0.
    let confidence: Float

    /// Where the text sits on the page, normalized to 0...1 in Vision's
    /// coordinate space: the origin is the bottom-left corner of the page
    /// and y increases upwards.
    let boundingBox: CGRect

    /// Zero-based index of the scanned page this block came from.
    let pageIndex: Int
}

/// Everything recognized from one scanning session (one or more pages).
struct ScanResult: Equatable {
    /// Number of pages that were scanned, including pages with no text.
    let pageCount: Int

    /// All recognized blocks, page by page, in the order Vision returned them.
    let blocks: [RecognizedTextBlock]

    /// The blocks that belong to a single page.
    func blocks(onPage pageIndex: Int) -> [RecognizedTextBlock] {
        return blocks.filter { block in block.pageIndex == pageIndex }
    }

    /// All recognized text as one string: one block per line,
    /// with a blank line between pages.
    var plainText: String {
        var pageTexts: [String] = []
        for pageIndex in 0..<max(pageCount, 0) {
            let lines: [String] = blocks(onPage: pageIndex).map { block in block.text }
            pageTexts.append(lines.joined(separator: "\n"))
        }
        return pageTexts.joined(separator: "\n\n")
    }
}
