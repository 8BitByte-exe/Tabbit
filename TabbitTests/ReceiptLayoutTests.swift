import CoreGraphics
import XCTest
@testable import Tabbit

/// Reading a receipt by its layout: the price column, detail lines under an item, the
/// receipt's parts, and the evidence-weighted choice of what adds up.
final class ReceiptLayoutTests: XCTestCase {

    private let parser = RulesReceiptParser()

    /// Two items, each with detail lines whose amounts sit mid-line, not in the price column.
    private func detailScan(subtotal: String) -> ScanResult {
        return ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("CHIPS", "4.50")
            .inlineRow("1 @ 2/ $9.00")
            .inlineRow("YOU SAVED $1.29")
            .row("COOKIES", "3.00")
            .inlineRow("MEMBER DEAL 1.50")
            .row("SUBTOTAL", subtotal)
            .row("TOTAL", subtotal)
            .build()
    }

    // MARK: - Price column

    func testAmountsOutsideThePriceColumnAreDetails() {
        let receipt = parser.parse(detailScan(subtotal: "7.50"))
        XCTAssertEqual(itemList(receipt), itemList([("CHIPS", "4.50"), ("COOKIES", "3.00")]))
        XCTAssertEqual(receipt.notes, [])
    }

    func testADetailLineCountsWhenTheSubtotalNeedsIt() {
        // The arithmetic outranks the layout: if the subtotal includes it, it's counted.
        let receipt = parser.parse(detailScan(subtotal: "9.00"))
        XCTAssertEqual(itemList(receipt), itemList([("CHIPS", "4.50"), ("COOKIES", "3.00"), ("MEMBER DEAL", "1.50")]))
        XCTAssertEqual(receipt.notes, ["To match the subtotal, counted \"MEMBER DEAL 1.50\"."])
    }

    func testFindsThePriceColumn() {
        let lines = LineGrouper.lines(from: detailScan(subtotal: "7.50"))
        let flags = ReceiptLayout.inPriceColumn(lines, hasAmount: lines.map { line in
            AmountParser.trailingAmount(in: line.text) != nil
        })
        let outside = lines.indices.filter { index in !flags[index] }.map { index in lines[index].text }
        XCTAssertEqual(outside, ["1 @ 2/ $9.00", "YOU SAVED $1.29", "MEMBER DEAL 1.50"])
    }

    func testNoColumnWhenAmountsFollowTheNames() {
        // Every amount ends somewhere else, so position says nothing.
        let scan = ReceiptLayoutBuilder()
            .row("CORNER CAFE")
            .inlineRow("Tea 2.00", x: 0.05, width: 0.15)
            .inlineRow("Large Latte 4.50", x: 0.05, width: 0.35)
            .inlineRow("Avocado Toast Special 9.75", x: 0.05, width: 0.6)
            .inlineRow("Subtotal 16.25", x: 0.05, width: 0.3)
            .inlineRow("Total 16.25", x: 0.05, width: 0.25)
            .build()
        let lines = LineGrouper.lines(from: scan)
        let flags = ReceiptLayout.inPriceColumn(lines, hasAmount: lines.map { line in
            AmountParser.trailingAmount(in: line.text) != nil
        })
        XCTAssertTrue(flags.allSatisfy { flag in flag })
        XCTAssertEqual(parser.parse(scan).lineItems.count, 3)
    }

    func testAmountEdgeInsideABlock() {
        let block = RecognizedTextBlock(text: "$4.50 HC", confidence: 1,
                                        boundingBox: CGRect(x: 0.5, y: 0.5, width: 0.4, height: 0.02),
                                        pageIndex: 0, alternatives: [])
        let line = TextLine(text: block.text, pageIndex: 0, boundingBox: block.boundingBox, blocks: [block],
                            alternativeTexts: [])
        // "$4.50" is the first 5 of 8 characters.
        XCTAssertEqual(ReceiptLayout.amountRightEdge(of: line) ?? 0, 0.75, accuracy: 0.001)
    }

    // MARK: - Parts of the receipt

    func testThePromptShowsTheReceiptsParts() {
        let numbered = NumberedReceipt(scan: detailScan(subtotal: "7.50"))
        XCTAssertEqual(numbered.entries.map { entry in entry.textBefore }, ["CHIPS", "COOKIES", "SUBTOTAL", "TOTAL"])
        XCTAssertTrue(numbered.text.contains("--- items ---\n[1] CHIPS 4.50\n    1 @ 2/ $9.00\n    YOU SAVED $1.29\n"))
        XCTAssertTrue(numbered.text.contains("[2] COOKIES 3.00\n    MEMBER DEAL 1.50\n--- totals ---\n"))
    }

    func testHeadingsAboveTheFirstItemBelongToTheItems() {
        let scan = ReceiptLayoutBuilder()
            .row("NO FRILLS")
            .row("21-GROCERY")
            .row("PASTA", "2.49")
            .row("TOTAL", "2.49")
            .build()
        let numbered = NumberedReceipt(scan: scan)
        XCTAssertTrue(numbered.text.hasPrefix("--- store ---\nNO FRILLS\n--- items ---\n21-GROCERY\n[1] PASTA 2.49\n"))
    }

    // MARK: - Evidence

    func testCheapestFixWins() {
        let choices = [
            ItemReconciler.Choice(amount: money("3.99"), alternative: nil, evidence: 6),
            ItemReconciler.Choice(amount: money("2.99"), alternative: nil, evidence: -2),
            ItemReconciler.Choice(amount: money("2.99"), alternative: nil, evidence: -9),
        ]
        let moves = ItemReconciler.moves(for: choices)
        // Only the line Tabbit isn't sure about may change.
        XCTAssertEqual(moves.map { move in move.index }, [1])
        let fixes = ItemReconciler.reachableSums(choices, moves: moves)
        XCTAssertEqual(ItemReconciler.lookup(money("3.99"), in: fixes)?.cost, 0)
        XCTAssertEqual(ItemReconciler.lookup(money("6.98"), in: fixes)?.cost, 2)
        XCTAssertNil(ItemReconciler.lookup(money("9.97"), in: fixes))
    }

    func testEquallyCheapFixesAreNotGuessed() {
        let tied = [
            ItemReconciler.Choice(amount: money("3.99"), alternative: nil, evidence: 6),
            ItemReconciler.Choice(amount: money("1.00"), alternative: nil, evidence: -2),
            ItemReconciler.Choice(amount: money("1.00"), alternative: nil, evidence: -2),
        ]
        XCTAssertNil(ItemReconciler.lookup(money("4.99"), in: ItemReconciler.reachableSums(
            tied, moves: ItemReconciler.moves(for: tied))))

        // With one line less sure than the other, the likelier fix is used.
        let ranked = [
            ItemReconciler.Choice(amount: money("3.99"), alternative: nil, evidence: 6),
            ItemReconciler.Choice(amount: money("1.00"), alternative: nil, evidence: -2),
            ItemReconciler.Choice(amount: money("1.00"), alternative: nil, evidence: -4),
        ]
        let moves = ItemReconciler.moves(for: ranked)
        let fix = ItemReconciler.lookup(money("4.99"), in: ItemReconciler.reachableSums(ranked, moves: moves))
        XCTAssertEqual(fix?.cost, 2)
        if let fix = fix {
            XCTAssertEqual(ItemReconciler.applied(fix, moves: moves).map { move in move.index }, [1])
        }
    }

    // MARK: - Keywords and categories

    func testGarbledYouSavedIsStillSavings() {
        XCTAssertEqual(ReceiptKeywords.role(for: "VOU SAVED $1.04"), .info)
        XCTAssertEqual(ReceiptKeywords.role(for: "Y0U SAVED 2.98"), .info)
        XCTAssertEqual(ReceiptKeywords.role(for: "CHOCOLATE SAVED 2.98"), .other)
    }

    func testDepartmentHeadingsMeanASupermarket() {
        XCTAssertEqual(CategoryGuesser.departmentHint(in: ["21-GROCERY", "PASTA 2.49"]), .groceries)
        XCTAssertEqual(CategoryGuesser.departmentHint(in: ["DELI", "HAM 4.00", "BAKERY"]), .groceries)
        XCTAssertNil(CategoryGuesser.departmentHint(in: ["BAKERY", "CROISSANT 3.00"]))
        XCTAssertNil(CategoryGuesser.departmentHint(in: ["PHARMACY"]))
        // The headings outrank Apple Intelligence's guess, but not a store name that says what it is.
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Jobeys", items: [], suggestion: .food,
                                             receiptLines: ["PRODUCE", "APPLES 1.00"]), .groceries)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Joe's Pizza", items: [], suggestion: nil,
                                             receiptLines: ["PRODUCE"]), .food)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Sobeys", items: []), .groceries)
    }

    func testModelNamesInLowerCaseGetCapitals() {
        XCTAssertEqual(ModelReceiptVerifier.tidyName("chips lime block pepper"), "Chips Lime Block Pepper")
        XCTAssertEqual(ModelReceiptVerifier.tidyName(" \"Organic bananas\" "), "Organic bananas")
    }
}
