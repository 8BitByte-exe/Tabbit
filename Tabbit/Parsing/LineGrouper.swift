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
    /// The line's text with one block swapped for one of Vision's other readings.
    let alternativeTexts: [String]
}

/// Rebuilds receipt lines from Vision's blocks.
///
/// Vision often returns an item name and its price as two separate blocks, in
/// no particular order. Receipts also curl and tilt, so a price at the right
/// edge can sit noticeably higher or lower than its name. This works in three steps:
/// 1. Estimate how much the page is tilted and correct the heights for it.
/// 2. Put blocks whose corrected heights are within half a text height on one line.
/// 3. A line that is only a price joins the nearest line above or below that
///    has a name but no price.
///
/// When a page is tilted by more than about half a line spacing, the geometry is
/// ambiguous: prices line up equally well with their own names or with the names
/// one line up. So up to 3 tilt guesses are offered (`slopeChoice`), best first,
/// and the parser keeps the one whose numbers add up.
enum LineGrouper {

    /// All lines of the scan: page by page, top to bottom.
    /// `slopeChoice` picks which tilt guess to use on each page (0 = best).
    static func lines(from scan: ScanResult, slopeChoice: Int = 0) -> [TextLine] {
        var result: [TextLine] = []
        for pageIndex in 0..<max(scan.pageCount, 0) {
            let pageLines = lines(from: scan.blocks(onPage: pageIndex), pageIndex: pageIndex, slopeChoice: slopeChoice)
            result.append(contentsOf: pageLines)
        }
        return result
    }

    /// How many tilt guesses are worth trying for this scan (1 to 3).
    static func slopeChoiceCount(for scan: ScanResult) -> Int {
        var count = 1
        for pageIndex in 0..<max(scan.pageCount, 0) {
            count = max(count, candidateSlopes(of: scan.blocks(onPage: pageIndex)).count)
        }
        return count
    }

    /// The lines of one page, top to bottom.
    static func lines(from blocks: [RecognizedTextBlock], pageIndex: Int, slopeChoice: Int = 0) -> [TextLine] {
        let candidates = candidateSlopes(of: blocks)
        let slope = candidates[min(max(slopeChoice, 0), candidates.count - 1)]
        // Vision's y axis points up, so the top of the page has the largest y.
        let placed = blocks
            .map { block in PlacedBlock(block: block, y: levelY(of: block, slope: slope)) }
            .sorted { first, second in first.y > second.y }

        var rows: [[PlacedBlock]] = []
        for item in placed {
            if let rowIndex = closestRow(for: item, in: rows) {
                rows[rowIndex].append(item)
            } else {
                rows.append([item])
            }
        }
        rows.sort { first, second in averageY(first) > averageY(second) }
        rows = attachLonePrices(in: rows)

        return rows.map { row in makeLine(from: row, pageIndex: pageIndex) }
    }

    // MARK: - Tilt

    private struct PlacedBlock {
        let block: RecognizedTextBlock
        /// The block's vertical center, corrected for the page's tilt.
        let y: CGFloat
    }

    /// The block's vertical center as if the page weren't tilted.
    private static func levelY(of block: RecognizedTextBlock, slope: CGFloat) -> CGFloat {
        return block.boundingBox.midY - slope * (block.boundingBox.midX - 0.5)
    }

    /// Tilt guesses for a page, best first (never empty). A tilt is a slope: height
    /// change per page width, between -0.1 and 0.1. Each slope is scored by how many
    /// blocks it puts level with a block beside them; ties go to the flatter slope,
    /// so a page with nothing to compare stays at 0. Returns up to 3 clearly
    /// different slopes that score at least half as well as the best.
    static func candidateSlopes(of blocks: [RecognizedTextBlock]) -> [CGFloat] {
        guard blocks.count >= 4 else {
            return [0]
        }
        var scored: [(score: Int, slope: CGFloat)] = [(score: alignedCount(blocks, slope: 0), slope: 0)]
        for step in 1...40 {
            for sign in [CGFloat(1), CGFloat(-1)] {
                let slope = sign * CGFloat(step) * 0.0025
                scored.append((score: alignedCount(blocks, slope: slope), slope: slope))
            }
        }
        scored.sort { first, second in
            if first.score != second.score {
                return first.score > second.score
            }
            if abs(first.slope) != abs(second.slope) {
                return abs(first.slope) < abs(second.slope)
            }
            return first.slope > second.slope
        }
        guard let bestScore = scored.first?.score, bestScore > 0 else {
            return [0]
        }

        var picked: [CGFloat] = []
        for entry in scored {
            // Stop below half the best score, or after 3 guesses.
            if entry.score * 2 < bestScore || picked.count == 3 {
                break
            }
            let isNew = picked.allSatisfy { slope in abs(slope - entry.slope) >= 0.012 }
            if isNew {
                picked.append(entry.slope)
            }
        }
        return picked.isEmpty ? [0] : picked
    }

    /// How many blocks have another block beside them (not overlapping horizontally)
    /// within a quarter text height, once the slope is corrected for.
    private static func alignedCount(_ blocks: [RecognizedTextBlock], slope: CGFloat) -> Int {
        let levels = blocks.map { block in levelY(of: block, slope: slope) }
        var count = 0
        for i in 0..<blocks.count {
            let a = blocks[i].boundingBox
            for j in 0..<blocks.count where j != i {
                let b = blocks[j].boundingBox
                let separated = b.minX >= a.maxX - 0.005 || b.maxX <= a.minX + 0.005
                guard separated else {
                    continue
                }
                if abs(levels[i] - levels[j]) < 0.25 * min(a.height, b.height) {
                    count += 1
                    break
                }
            }
        }
        return count
    }

    // MARK: - Grouping

    /// The row whose center is within half a text height of the block's center.
    private static func closestRow(for item: PlacedBlock, in rows: [[PlacedBlock]]) -> Int? {
        var bestIndex: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, row) in rows.enumerated() {
            let tolerance = max(0.5 * min(averageHeight(row), item.block.boundingBox.height), 0.002)
            let distance = abs(averageY(row) - item.y)
            if distance <= tolerance && distance < bestDistance {
                bestIndex = index
                bestDistance = distance
            }
        }
        return bestIndex
    }

    /// Moves rows that are only a price (like "4.99" or "4.99 F") onto the nearest
    /// neighboring row that has a name but no price. Within 1.6 text heights;
    /// on a near tie the row above wins.
    private static func attachLonePrices(in rows: [[PlacedBlock]]) -> [[PlacedBlock]] {
        var rows = rows
        var index = 0
        while index < rows.count {
            guard isPriceOnly(rowText(rows[index])) else {
                index += 1
                continue
            }
            let y = averageY(rows[index])
            let height = averageHeight(rows[index])
            var target: Int?
            var bestScore = CGFloat.greatestFiniteMagnitude
            for candidate in [index - 1, index + 1] where candidate >= 0 && candidate < rows.count {
                let text = rowText(rows[candidate])
                guard hasLetters(text), AmountParser.trailingAmount(in: text) == nil else {
                    continue
                }
                let distance = abs(averageY(rows[candidate]) - y)
                guard distance <= 1.6 * height else {
                    continue
                }
                let score = candidate < index ? distance - 0.2 * height : distance
                if score < bestScore {
                    bestScore = score
                    target = candidate
                }
            }
            if let target = target {
                rows[target].append(contentsOf: rows[index])
                rows.remove(at: index)
                // Either way, the row now at `index` hasn't been looked at yet
                // (or is the merged row, which now has a price).
                continue
            }
            index += 1
        }
        return rows
    }

    private static func isPriceOnly(_ text: String) -> Bool {
        guard let amount = AmountParser.trailingAmount(in: text) else {
            return false
        }
        return amount.textBefore.rangeOfCharacter(from: .alphanumerics) == nil
    }

    // MARK: - Helpers

    private static func makeLine(from row: [PlacedBlock], pageIndex: Int) -> TextLine {
        let ordered = row
            .map { item in item.block }
            .sorted { first, second in first.boundingBox.minX < second.boundingBox.minX }
        var box = CGRect.null
        for block in ordered {
            box = box.union(block.boundingBox)
        }
        let texts = ordered.map { block in block.text.trimmingCharacters(in: .whitespacesAndNewlines) }

        var alternativeTexts: [String] = []
        for (index, block) in ordered.enumerated() {
            for alternative in block.alternatives.prefix(2) {
                var swapped = texts
                swapped[index] = alternative.trimmingCharacters(in: .whitespacesAndNewlines)
                alternativeTexts.append(joined(swapped))
            }
        }

        return TextLine(
            text: joined(texts),
            pageIndex: pageIndex,
            boundingBox: box,
            blocks: ordered,
            alternativeTexts: Array(alternativeTexts.prefix(6))
        )
    }

    private static func joined(_ pieces: [String]) -> String {
        return pieces.filter { piece in !piece.isEmpty }.joined(separator: " ")
    }

    private static func rowText(_ row: [PlacedBlock]) -> String {
        let ordered = row.sorted { first, second in first.block.boundingBox.minX < second.block.boundingBox.minX }
        return joined(ordered.map { item in item.block.text.trimmingCharacters(in: .whitespacesAndNewlines) })
    }

    private static func hasLetters(_ text: String) -> Bool {
        return text.rangeOfCharacter(from: .letters) != nil
    }

    private static func averageY(_ row: [PlacedBlock]) -> CGFloat {
        guard !row.isEmpty else {
            return 0
        }
        return row.map { item in item.y }.reduce(0, +) / CGFloat(row.count)
    }

    private static func averageHeight(_ row: [PlacedBlock]) -> CGFloat {
        guard !row.isEmpty else {
            return 0
        }
        return row.map { item in item.block.boundingBox.height }.reduce(0, +) / CGFloat(row.count)
    }
}
