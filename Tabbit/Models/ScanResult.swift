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

/// JSON form used by scan exports and test fixtures:
/// `{"text": "...", "confidence": 0.98, "x": 0.1, "y": 0.8, "width": 0.3, "height": 0.02, "page": 0}`.
/// Coordinates are rounded to 4 decimals and confidence to 3 to keep files readable.
extension RecognizedTextBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case text
        case confidence
        case x
        case y
        case width
        case height
        case page
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .text)
        let confidence = try container.decodeIfPresent(Float.self, forKey: .confidence) ?? 1
        let x = try container.decode(Double.self, forKey: .x)
        let y = try container.decode(Double.self, forKey: .y)
        let width = try container.decode(Double.self, forKey: .width)
        let height = try container.decode(Double.self, forKey: .height)
        let page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 0
        self.init(
            text: text,
            confidence: confidence,
            boundingBox: CGRect(x: x, y: y, width: width, height: height),
            pageIndex: page
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(RecognizedTextBlock.rounded(Double(confidence), places: 3), forKey: .confidence)
        try container.encode(RecognizedTextBlock.rounded(Double(boundingBox.minX), places: 4), forKey: .x)
        try container.encode(RecognizedTextBlock.rounded(Double(boundingBox.minY), places: 4), forKey: .y)
        try container.encode(RecognizedTextBlock.rounded(Double(boundingBox.width), places: 4), forKey: .width)
        try container.encode(RecognizedTextBlock.rounded(Double(boundingBox.height), places: 4), forKey: .height)
        try container.encode(pageIndex, forKey: .page)
    }

    private static func rounded(_ value: Double, places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (value * factor).rounded() / factor
    }
}

/// Everything recognized from one scanning session (one or more pages).
struct ScanResult: Equatable, Codable {
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
