import CoreGraphics
import Foundation

/// Where things sit on a receipt, so the parsers can read it the way a person does.
///
/// Receipts print each item's price in a column at the right. Detail lines under an item
/// ("1 @ 2/ $9.00", "YOU SAVED $1.29") are usually indented, with their amount in the
/// middle of the line instead. An amount that isn't in the price column is almost never
/// a price paid, whatever its words say.
enum ReceiptLayout {

    /// A column needs at least this many amounts lined up in it.
    static let minimumAmountLines = 4

    /// How far left of the column an amount may end and still be in it, as a share of the
    /// receipt's width (covers tilt, curl and tax flags after the price).
    static let columnTolerance: CGFloat = 0.15
    /// Amounts that end this close to the column (share of the width) are lined up with it.
    static let alignedBand: CGFloat = 0.05
    /// Amounts between this far left of the column and the aligned band are neither clearly
    /// in the column nor clearly away from it. Many of those mean the amounts don't line up.
    static let grayZone: CGFloat = 0.3

    /// For each line, whether its amount ends in the price column. Lines without an amount,
    /// and every line on a page with no clear column (amounts printed right after the
    /// names, or too few of them), count as in the column.
    static func inPriceColumn(_ lines: [TextLine], hasAmount: [Bool]) -> [Bool] {
        var result = Array(repeating: true, count: lines.count)
        let pages = Set(lines.map { line in line.pageIndex })
        for page in pages {
            var edges: [(index: Int, edge: CGFloat)] = []
            var lefts: [CGFloat] = []
            for (index, line) in lines.enumerated() where line.pageIndex == page {
                lefts.append(contentsOf: line.blocks.map { block in block.boundingBox.minX })
                if index < hasAmount.count, hasAmount[index], let edge = amountRightEdge(of: line) {
                    edges.append((index: index, edge: edge))
                }
            }
            guard edges.count >= minimumAmountLines, !lefts.isEmpty else {
                continue
            }
            // The column is where most amounts end: the middle of the right half of the edges.
            let sorted = edges.map { entry in entry.edge }.sorted(by: >)
            let rightHalf = Array(sorted.prefix((sorted.count + 1) / 2))
            let column = rightHalf[rightHalf.count / 2]
            let sortedLefts = lefts.sorted()
            let left = sortedLefts[sortedLefts.count / 10]
            let width = max(column - left, 0.2)
            let threshold = column - max(columnTolerance * width, 0.03)
            let alignedEdge = column - max(alignedBand * width, 0.02)
            let grayEdge = column - grayZone * width

            // A real column: several amounts end right at it (at least 40% of them), and few
            // end somewhat short of it. Amounts printed right after their names end all over.
            let aligned = edges.filter { entry in entry.edge >= alignedEdge }.count
            let gray = edges.filter { entry in entry.edge >= grayEdge && entry.edge < alignedEdge }.count
            guard aligned >= minimumAmountLines, aligned * 10 >= edges.count * 4, gray * 5 <= edges.count else {
                continue
            }
            for entry in edges {
                result[entry.index] = entry.edge >= threshold
            }
        }
        return result
    }

    /// Where the line's amount ends, in page coordinates: the last digit of the rightmost
    /// block with a digit in it. Within a block the position is estimated from the share of
    /// characters before it ("$4.50 HC" ends about 5/8 of the way along its block).
    static func amountRightEdge(of line: TextLine) -> CGFloat? {
        let withDigits = line.blocks.filter { block in block.text.rangeOfCharacter(from: .decimalDigits) != nil }
        guard let block = withDigits.max(by: { first, second in
            first.boundingBox.maxX < second.boundingBox.maxX
        }) else {
            return nil
        }
        let characters = Array(block.text)
        guard !characters.isEmpty else {
            return nil
        }
        var end = 0
        for (offset, character) in characters.enumerated() where character.isNumber {
            end = offset + 1
        }
        let box = block.boundingBox
        return box.minX + box.width * CGFloat(end) / CGFloat(characters.count)
    }
}
