import XCTest
@testable import Tabbit

/// Apple Intelligence can't run in CI, so these tests feed the verifier the kind of
/// answers the model gives and check what Tabbit does with them.
final class ModelReceiptVerifierTests: XCTestCase {

    private func groceryScan() -> ScanResult {
        return ReceiptLayoutBuilder()
            .row("TRADER JOE'S", height: 0.03)
            .row("11/02/2026 2:32 PM")
            .row("ORG BNNA 4011", "1.29")
            .row("ORGANIC MILK", "4.99 F")
            .row("AVOCADO")
            .row("2 @ 0.99", "1.98")
            .row("COUPON", "-0.50")
            .row("SUBTOTAL", "7.76")
            .row("TAX", "0.62")
            .row("TOTAL", "8.38")
            .row("VISA", "8.38")
            .build()
    }

    private func goodDraft() -> ModelReceiptDraft {
        return ModelReceiptDraft(
            merchant: "Trader Joe's",
            date: "2026-11-02",
            items: [
                .init(printedText: "ORG BNNA 4011", name: "Organic bananas", price: "1.29"),
                .init(printedText: "ORGANIC MILK", name: "Organic milk", price: "4.99"),
                .init(printedText: "AVOCADO", name: "Avocados", price: "1.98"),
                .init(printedText: "COUPON", name: "Coupon", price: "-0.50"),
            ],
            subtotal: "7.76",
            tax: "0.62",
            tip: nil,
            total: "8.38",
            pricesIncludeTax: false,
            category: "groceries"
        )
    }

    func testAcceptsAReadingThatChecksOut() {
        let scan = groceryScan()
        let rules = RulesReceiptParser().parse(scan)
        let outcome = ModelReceiptVerifier.evaluate(goodDraft(), scan: scan, rules: rules)
        let receipt = outcome.receipt
        XCTAssertEqual(receipt.parser, .appleIntelligence)
        XCTAssertEqual(receipt.merchant, "Trader Joe's")
        XCTAssertEqual(itemList(receipt), itemList([
            ("Organic bananas", "1.29"), ("Organic milk", "4.99"), ("Avocados", "1.98"), ("Coupon", "-0.50"),
        ]))
        XCTAssertEqual(receipt.subtotal, money("7.76"))
        XCTAssertEqual(receipt.tax, money("0.62"))
        XCTAssertEqual(receipt.total, money("8.38"))
        XCTAssertEqual(receipt.date, CalendarDate(year: 2026, month: 11, day: 2))
        XCTAssertEqual(receipt.notes.first, ModelReceiptVerifier.usedNote)
        XCTAssertEqual(outcome.suggestedCategory, .groceries)
    }

    func testRejectsAnAmountThatIsNotOnTheReceipt() {
        let scan = groceryScan()
        let rules = RulesReceiptParser().parse(scan)
        var draft = goodDraft()
        draft.items[1].price = "4.89"
        let outcome = ModelReceiptVerifier.evaluate(draft, scan: scan, rules: rules)
        XCTAssertEqual(outcome.receipt.parser, .rules)
        XCTAssertEqual(outcome.receipt.lineItems, rules.lineItems)
        XCTAssertTrue(outcome.receipt.notes.last?.contains("4.89 isn't on the receipt") == true)
        // The store name and category still come from the model when they check out.
        XCTAssertEqual(outcome.receipt.merchant, "Trader Joe's")
        XCTAssertEqual(outcome.suggestedCategory, .groceries)
    }

    func testRejectsAnInventedItem() {
        let scan = groceryScan()
        let rules = RulesReceiptParser().parse(scan)
        var draft = goodDraft()
        draft.items[2] = .init(printedText: "STRAWBERRIES", name: "Strawberries", price: "1.98")
        let outcome = ModelReceiptVerifier.evaluate(draft, scan: scan, rules: rules)
        XCTAssertEqual(outcome.receipt.parser, .rules)
        XCTAssertTrue(outcome.receipt.notes.last?.contains("STRAWBERRIES") == true)
    }

    func testRejectsAReadingThatDoesNotAddUp() {
        let scan = groceryScan()
        let rules = RulesReceiptParser().parse(scan)
        var draft = goodDraft()
        // Leaves out the coupon: every number is printed, but the items no longer match the subtotal.
        draft.items.removeLast()
        let outcome = ModelReceiptVerifier.evaluate(draft, scan: scan, rules: rules)
        XCTAssertEqual(outcome.receipt.parser, .rules)
        XCTAssertTrue(outcome.receipt.notes.last?.contains("subtotal is 7.76") == true)
    }

    func testRejectsAReadingWithoutATotal() {
        let scan = groceryScan()
        var draft = goodDraft()
        draft.total = nil
        let outcome = ModelReceiptVerifier.evaluate(draft, scan: scan, rules: RulesReceiptParser().parse(scan))
        XCTAssertEqual(outcome.receipt.parser, .rules)
    }

    func testTaxIncludedInPricesIsNotAddedAgain() {
        let scan = ReceiptLayoutBuilder()
            .row("BÄCKEREI SCHMIDT")
            .row("BREZEL", "1,20")
            .row("KAFFEE", "2,80")
            .row("SUMME EUR", "4,00")
            .row("MwSt 7%", "0,26")
            .build()
        let draft = ModelReceiptDraft(
            merchant: "Bäckerei Schmidt", date: nil,
            items: [
                .init(printedText: "BREZEL", name: "Pretzel", price: "1,20"),
                .init(printedText: "KAFFEE", name: "Coffee", price: "2,80"),
            ],
            subtotal: nil, tax: "0,26", tip: nil, total: "4,00", pricesIncludeTax: true, category: "food")
        let outcome = ModelReceiptVerifier.evaluate(draft, scan: scan, rules: RulesReceiptParser().parse(scan))
        XCTAssertEqual(outcome.receipt.parser, .appleIntelligence)
        XCTAssertNil(outcome.receipt.tax)
        XCTAssertEqual(outcome.receipt.total, money("4.00"))
        XCTAssertTrue(outcome.receipt.notes.contains { note in note.contains("already include 0.26 tax") })
    }

    func testTipMustBePrinted() {
        let scan = ReceiptLayoutBuilder()
            .row("The Daily Grind Cafe")
            .row("Latte 4.50")
            .row("Muffin 3.25")
            .row("Subtotal 7.75")
            .row("Tax 0.69")
            .row("Tip 1.50")
            .row("Total 9.94")
            .build()
        var draft = ModelReceiptDraft(
            merchant: "The Daily Grind Cafe", date: nil,
            items: [
                .init(printedText: "Latte", name: "Latte", price: "4.50"),
                .init(printedText: "Muffin", name: "Muffin", price: "3.25"),
            ],
            subtotal: "7.75", tax: "0.69", tip: "1.50", total: "9.94", pricesIncludeTax: false, category: "coffee")
        let rules = RulesReceiptParser().parse(scan)
        XCTAssertEqual(ModelReceiptVerifier.evaluate(draft, scan: scan, rules: rules).receipt.tip, money("1.50"))

        draft.tip = "2.00"
        XCTAssertEqual(ModelReceiptVerifier.evaluate(draft, scan: scan, rules: rules).receipt.parser, .rules)
    }

    func testMerchantMustBeOnTheReceipt() {
        let evidence = ScanEvidence(groceryScan())
        XCTAssertEqual(ModelReceiptVerifier.groundedMerchant("Trader Joe's", evidence: evidence), "Trader Joe's")
        XCTAssertNil(ModelReceiptVerifier.groundedMerchant("Whole Foods Market", evidence: evidence))
        XCTAssertNil(ModelReceiptVerifier.groundedMerchant("  ", evidence: evidence))
    }

    func testEvidenceFindsAmountsAndWords() {
        let evidence = ScanEvidence(groceryScan())
        XCTAssertTrue(evidence.contains(amount: money("4.99")))
        XCTAssertTrue(evidence.contains(amount: money("-0.50")))
        XCTAssertFalse(evidence.contains(amount: money("5.00")))
        XCTAssertTrue(evidence.mentions("Organic Milk"))
        XCTAssertTrue(evidence.mentions("ORG BNNA"))
        XCTAssertFalse(evidence.mentions("Chocolate bar"))
    }

    func testCategoryAndDateSuggestions() {
        XCTAssertEqual(ModelReceiptVerifier.suggestedCategory("Groceries"), .groceries)
        XCTAssertEqual(ModelReceiptVerifier.suggestedCategory("coffee"), .coffee)
        XCTAssertNil(ModelReceiptVerifier.suggestedCategory("other"))
        XCTAssertNil(ModelReceiptVerifier.suggestedCategory("spaceships"))
        XCTAssertEqual(ModelReceiptVerifier.calendarDate("2026-03-05"), CalendarDate(year: 2026, month: 3, day: 5))
        XCTAssertNil(ModelReceiptVerifier.calendarDate("2026-13-05"))
        XCTAssertNil(ModelReceiptVerifier.calendarDate("yesterday"))
        XCTAssertNil(ModelReceiptVerifier.calendarDate("2099-01-01"))
    }

    func testCategoryGuessPrefersTheStoreNameThenTheModel() {
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Joe's Pizza", items: [], suggestion: .groceries), .food)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Blue Door", items: ["latte"], suggestion: .food), .food)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Blue Door", items: ["latte"], suggestion: nil), .coffee)
    }

    func testPromptListsTheLinesTopToBottom() {
        let prompt = ReceiptPrompt.make(for: groceryScan())
        XCTAssertTrue(prompt.contains("TRADER JOE'S\n"))
        XCTAssertTrue(prompt.contains("ORGANIC MILK 4.99 F\n"))
        let milk = prompt.range(of: "ORGANIC MILK")
        let total = prompt.range(of: "TOTAL 8.38")
        XCTAssertNotNil(milk)
        XCTAssertNotNil(total)
        if let milk = milk, let total = total {
            XCTAssertLessThan(milk.lowerBound, total.lowerBound)
        }
        XCTAssertTrue(ReceiptPrompt.instructions.contains("groceries"))
        XCTAssertEqual(ReceiptPrompt.make(for: ScanResult(pageCount: 1, blocks: [])), "")
    }

    func testAllAmountsInALine() {
        XCTAssertEqual(AmountParser.allAmounts(in: "2 @ 0.99   1.98"), [money("0.99"), money("1.98")])
        XCTAssertEqual(AmountParser.allAmounts(in: "COUPON -0.50"), [money("0.50")])
        XCTAssertEqual(AmountParser.allAmounts(in: "SUMME EUR 1.234,56"), [money("1234.56")])
        XCTAssertEqual(AmountParser.allAmounts(in: "18% tip guide"), [])
    }
}
