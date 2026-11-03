import CoreGraphics
import Foundation

/// One visual line of a receipt: the blocks that sit at the same height, left to right.
struct TextLine: Equatable {
    /// The blocks' text joined with spaces, left to right.
    let text: String
    let pageIndex: Int
    /// The union of the blocks' boxes (normalized, Vision coordinates).
    let boundingBox: CGRect
    /// The blocks that make up the line, left to right.
    let blocks: [RecognizedTextBlock]
}

/// Rebuilds receipt lines from Vision's blocks.
///
/// Vision often returns an item name and its price as two separate blocks,
/// and doesn't promise any particular order. Grouping blocks by height puts
/// "BANANAS" and "1.29" back on the same line.
enum LineGrouper {

    /// All lines of the scan: page by page, top to bottom.
    static func lines(from scan: ScanResult) -> [TextLine] {
        var result: [TextLine] = []
        for pageIndex in 0..<max(scan.pageCount, 0) {
            let pageLines = lines(from: scan.blocks(onPage: pageIndex), pageIndex: pageIndex)
            result.append(contentsOf: pageLines)
        }
        return result
    }

    /// The lines of one page, top to bottom.
    static func lines(from blocks: [RecognizedTextBlock], pageIndex: Int) -> [TextLine] {
        // Vision's y axis points up, so the top of the page has the largest y.
        let sorted = blocks.sorted { first, second in
            first.boundingBox.midY > second.boundingBox.midY
        }

        var rows: [[RecognizedTextBlock]] = []
        for block in sorted {
            if let rowIndex = closestRow(for: block, in: rows) {
                rows[rowIndex].append(block)
            } else {
                rows.append([block])
            }
        }

        let lines = rows.map { row in makeLine(from: row, pageIndex: pageIndex) }
        return lines.sorted { first, second in
            first.boundingBox.midY > second.boundingBox.midY
        }
    }

    /// The row whose vertical center is within half a text height of the block's center.
    private static func closestRow(for block: RecognizedTextBlock, in rows: [[RecognizedTextBlock]]) -> Int? {
        var bestIndex: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, row) in rows.enumerated() {
            let rowMidY = average(row.map { member in member.boundingBox.midY })
            let rowHeight = average(row.map { member in member.boundingBox.height })
            let tolerance = max(0.5 * min(rowHeight, block.boundingBox.height), 0.002)
            let distance = abs(rowMidY - block.boundingBox.midY)
            if distance <= tolerance && distance < bestDistance {
                bestIndex = index
                bestDistance = distance
            }
        }
        return bestIndex
    }

    private static func makeLine(from blocks: [RecognizedTextBlock], pageIndex: Int) -> TextLine {
        let ordered = blocks.sorted { first, second in
            first.boundingBox.minX < second.boundingBox.minX
        }
        var box = CGRect.null
        for block in ordered {
            box = box.union(block.boundingBox)
        }
        let text = ordered
            .map { block in block.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { piece in !piece.isEmpty }
            .joined(separator: " ")
        return TextLine(text: text, pageIndex: pageIndex, boundingBox: box, blocks: ordered)
    }

    private static func average(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else {
            return 0
        }
        return values.reduce(0, +) / CGFloat(values.count)
    }
}
