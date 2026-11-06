import XCTest
@testable import Tabbit

/// Apple Intelligence can't run in CI, so these tests feed the verifier the kind of
/// line labels the model gives, right and wrong, and check what Tabbit makes of them.
final class ModelReceiptVerifierTests: XCTestCase {

    // MARK: - Helpers

    /// A label for the numbered line whose text before the amount is `printed`.
    private typealias Pick = (printed: String, kind: ModelLineKind, name: String)

    private func reading(_ numbered: NumberedReceipt, _ picks: [Pick], store: String = "",
                         pricesIncludeTax: Bool = false, category: String = "", date: String = "",
                         file: StaticString = #filePath, line: UInt = #line) -> ModelReceiptReading {
        var labels: [ModelReceiptReading.Label] = []
        for pick in picks {
            guard let entry = numbered.entries.first(where: { entry in entry.textBefore == pick.printed }) else {
                XCTFail("No numbered line \"\(pick.printed)\"", file: file, line: line)
                continue
            }
            labels.append(ModelReceiptReading.Label(line: entry.number, kind: pick.kind, name: pick.name))
        }
        return ModelReceiptReading(storeName: store, labels: labels, pricesIncludeTax: pricesIncludeTax,
                                   category: category, date: date)
    }

    private func evaluate(_ scan: ScanResult, _ picks: [Pick], store: String = "",
                          pricesIncludeTax: Bool = false, category: String = "") -> IntelligenceOutcome {
        let numbered = NumberedReceipt(scan: scan)
        let answer = reading(numbered, picks, store: store, pricesIncludeTax: pricesIncludeTax, category: category)
        return ModelReceiptVerifier.evaluate(answer, numbered: numbered, rules: RulesReceiptParser().parse(scan))
    }

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

    private let groceryPicks: [Pick] = [
        ("ORG BNNA 4011", .item, "Organic bananas"),
        ("ORGANIC MILK", .item, "Organic milk"),
        ("2 @ 0.99", .item, "Avocados"),
        ("COUPON", .discount, "Coupon"),
        ("SUBTOTAL", .subtotal, ""),
        ("TAX", .tax, ""),
        ("TOTAL", .total, ""),
        ("VISA", .payment, ""),
    ]

    // MARK: - Reading

    func testUsesTheModelsReadingWithAmountsFromTheScan() {
        let outcome = evaluate(groceryScan(), groceryPicks, store: "Trader Joe's", category: "groceries")
        let receipt = outcome.receipt
        XCTAssertTrue(outcome.usedModel)
        XCTAssertEqual(receipt.parser, .appleIntelligence)
        XCTAssertEqual(receipt.merchant, "Trader Joe's")
        XCTAssertEqual(itemList(receipt), itemList([
            ("Organic bananas", "1.29"), ("Organic milk", "4.99"), ("Avocados", "1.98"), ("Coupon", "-0.50"),
        ]))
        XCTAssertEqual(receipt.subtotal, money("7.76"))
        XCTAssertEqual(receipt.tax, money("0.62"))
        XCTAssertEqual(receipt.total, money("8.38"))
        XCTAssertEqual(receipt.date, CalendarDate(year: 2026, month: 11, day: 2))
        XCTAssertEqual(receipt.notes, [ModelReceiptVerifier.usedNote])
        XCTAssertEqual(outcome.suggestedCategory, .groceries)
    }

    func testTotalTaxLabelledAsTheTotalLosesToTheTotalThatAddsUp() {
        let scan = ReceiptLayoutBuilder()
            .row("PIZZA PALACE")
            .row("PIZZA", "12.00")
            .row("WINGS", "8.00")
            .row("SUBTOTAL", "20.00")
            .row("GST", "1.00")
            .row("PST", "1.40")
            .row("TOTAL TAX", "2.40")
            .row("TOTAL", "22.40")
            .build()
        let outcome = evaluate(scan, [
            ("PIZZA", .item, "Pizza"), ("WINGS", .item, "Wings"), ("SUBTOTAL", .subtotal, ""),
            ("GST", .tax, ""), ("PST", .tax, ""), ("TOTAL TAX", .total, ""), ("TOTAL", .total, ""),
        ])
        XCTAssertEqual(outcome.receipt.parser, .appleIntelligence)
        XCTAssertEqual(outcome.receipt.subtotal, money("20.00"))
        XCTAssertEqual(outcome.receipt.tax, money("2.40"))
        XCTAssertEqual(outcome.receipt.total, money("22.40"))
        XCTAssertEqual(outcome.receipt.notes.first, ModelReceiptVerifier.usedNote)
    }

    func testHSTTheModelMissedIsFoundByTheArithmetic() {
        let scan = ReceiptLayoutBuilder()
            .row("BEST BUY", height: 0.03)
            .row("220 YONGE ST TORONTO ON")
            .row("USB-C CABLE", "29.99")
            .row("SCREEN PROTECTOR", "20.00")
            .row("SUBTOTAL", "49.99")
            .row("HST 13%", "6.50")
            .row("TOTAL", "56.49")
            .row("VISA", "56.49")
            .build()
        let outcome = evaluate(scan, [
            ("USB-C CABLE", .item, "USB-C cable"), ("SCREEN PROTECTOR", .item, "Screen protector"),
            ("SUBTOTAL", .subtotal, ""), ("HST 13%", .other, ""), ("TOTAL", .total, ""), ("VISA", .payment, ""),
        ], store: "Best Buy, 220 Yonge St")
        XCTAssertEqual(outcome.receipt.parser, .appleIntelligence)
        XCTAssertEqual(outcome.receipt.merchant, "Best Buy")
        XCTAssertEqual(outcome.receipt.tax, money("6.50"))
        XCTAssertEqual(outcome.receipt.total, money("56.49"))
        XCTAssertEqual(itemList(outcome.receipt), itemList([("USB-C cable", "29.99"), ("Screen protector", "20.00")]))
    }

    func testGasReceiptPricePerLitreIsNeverAnItem() {
        let scan = ReceiptLayoutBuilder()
            .row("SHELL", height: 0.03)
            .row("PUMP 05 REGULAR")
            .row("PRICE/L", "1.67")
            .row("FUEL TOTAL", "54.92")
            .row("HST INCLUDED", "6.32")
            .row("TOTAL", "54.92")
            .row("VISA", "54.92")
            .build()
        // The model gets the price per litre wrong; the keywords overrule it.
        let outcome = evaluate(scan, [
            ("PRICE/L", .item, "Price per litre"), ("FUEL TOTAL", .item, "Regular gas"),
            ("HST INCLUDED", .tax, ""), ("TOTAL", .total, ""), ("VISA", .payment, ""),
        ], store: "Shell", pricesIncludeTax: true, category: "fuel")
        let receipt = outcome.receipt
        XCTAssertEqual(receipt.parser, .appleIntelligence)
        XCTAssertEqual(itemList(receipt), itemList([("Regular gas", "54.92")]))
        XCTAssertNil(receipt.tax)
        XCTAssertEqual(receipt.total, money("54.92"))
        XCTAssertTrue(receipt.notes.contains { note in note.contains("already include 6.32 tax") })
        XCTAssertEqual(outcome.suggestedCategory, .fuel)
    }

    func testHeadingsAreNotNumberedAndSavingsAreNotItems() {
        let scan = ReceiptLayoutBuilder()
            .row("NO FRILLS")
            .row("21-GROCERY")
            .row("PASTA", "2.49")
            .row("SAUCE", "3.99")
            .row("27-PRODUCE")
            .row("APPLES", "4.50")
            .row("YOU SAVED", "2.98")
            .row("SUBTOTAL", "10.98")
            .row("TOTAL", "10.98")
            .build()
        let numbered = NumberedReceipt(scan: scan)
        XCTAssertFalse(numbered.entries.contains { entry in entry.text.contains("GROCERY") })
        XCTAssertFalse(numbered.entries.contains { entry in entry.text.contains("PRODUCE") })

        let outcome = evaluate(scan, [
            ("PASTA", .item, "Pasta"), ("SAUCE", .item, "Sauce"), ("APPLES", .item, "Apples"),
            ("YOU SAVED", .item, "You saved"), ("SUBTOTAL", .subtotal, ""), ("TOTAL", .total, ""),
        ])
        XCTAssertEqual(itemList(outcome.receipt), itemList([("Pasta", "2.49"), ("Sauce", "3.99"), ("Apples", "4.50")]))
        XCTAssertEqual(outcome.receipt.notes, [ModelReceiptVerifier.usedNote])
    }

    func testAnItemTheModelSkippedIsCountedWhenTheSubtotalNeedsIt() {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("CASHEWS", "5.99")
            .row("BREAD", "3.00")
            .row("SUBTOTAL", "8.99")
            .row("TOTAL", "8.99")
            .build()
        let outcome = evaluate(scan, [
            ("CASHEWS", .other, ""), ("BREAD", .item, "Bread"), ("SUBTOTAL", .subtotal, ""), ("TOTAL", .total, ""),
        ])
        XCTAssertEqual(outcome.receipt.parser, .appleIntelligence)
        XCTAssertEqual(itemList(outcome.receipt), itemList([("CASHEWS", "5.99"), ("Bread", "3.00")]))
        XCTAssertTrue(outcome.receipt.notes.contains("To match the subtotal, counted \"CASHEWS 5.99\"."))
    }

    func testLinesTheModelLeftOutAreFilledInFromTheKeywords() {
        let outcome = evaluate(groceryScan(), [
            ("ORG BNNA 4011", .item, "Organic bananas"),
            ("ORGANIC MILK", .item, "Organic milk"),
            ("2 @ 0.99", .item, "Avocados"),
            ("COUPON", .discount, "Coupon"),
        ])
        XCTAssertEqual(outcome.receipt.parser, .appleIntelligence)
        XCTAssertEqual(outcome.receipt.subtotal, money("7.76"))
        XCTAssertEqual(outcome.receipt.tax, money("0.62"))
        XCTAssertEqual(outcome.receipt.total, money("8.38"))
    }

    func testTipThatWasCharged() {
        let scan = ReceiptLayoutBuilder()
            .row("The Daily Grind Cafe")
            .row("Latte 4.50")
            .row("Muffin 3.25")
            .row("Subtotal 7.75")
            .row("Tax 0.69")
            .row("Tip 1.50")
            .row("Total 9.94")
            .build()
        let outcome = evaluate(scan, [
            ("Latte", .item, "Latte"), ("Muffin", .item, "Muffin"), ("Subtotal", .subtotal, ""),
            ("Tax", .tax, ""), ("Tip", .tip, ""), ("Total", .total, ""),
        ])
        XCTAssertEqual(outcome.receipt.tip, money("1.50"))
        XCTAssertEqual(outcome.receipt.total, money("9.94"))
        XCTAssertEqual(outcome.receipt.notes, [ModelReceiptVerifier.usedNote])
    }

    func testTaxIncludedInPricesIsNotAddedAgain() {
        let scan = ReceiptLayoutBuilder()
            .row("BÄCKEREI SCHMIDT")
            .row("BREZEL", "1,20")
            .row("KAFFEE", "2,80")
            .row("SUMME EUR", "4,00")
            .row("MwSt 7%", "0,26")
            .build()
        let outcome = evaluate(scan, [
            ("BREZEL", .item, "Brezel"), ("KAFFEE", .item, "Kaffee"), ("SUMME EUR", .total, ""),
            ("MwSt 7%", .tax, ""),
        ], store: "Bäckerei Schmidt", pricesIncludeTax: true)
        XCTAssertEqual(outcome.receipt.parser, .appleIntelligence)
        XCTAssertNil(outcome.receipt.tax)
        XCTAssertEqual(outcome.receipt.total, money("4.00"))
        XCTAssertTrue(outcome.receipt.notes.contains { note in note.contains("already include 0.26 tax") })
    }

    func testRulesAreKeptWhenTheyAddUpBetter() {
        // The model calls the milk a discount, so its items can't match the subtotal.
        var picks = groceryPicks
        picks[1] = ("ORGANIC MILK", .discount, "Organic milk")
        let scan = groceryScan()
        let rules = RulesReceiptParser().parse(scan)
        let outcome = evaluate(scan, picks, store: "Trader Joe's")
        XCTAssertFalse(outcome.usedModel)
        XCTAssertEqual(outcome.receipt.parser, .rules)
        XCTAssertEqual(outcome.receipt.lineItems, rules.lineItems)
        XCTAssertEqual(outcome.receipt.notes.last, ModelReceiptVerifier.rulesAddUpBetterNote)
        // The store name still comes from the model.
        XCTAssertEqual(outcome.receipt.merchant, "Trader Joe's")
    }

    func testNoItemsKeepsTheRules() {
        let scan = ReceiptLayoutBuilder()
            .row("PARKING")
            .row("TOTAL", "8.00")
            .row("VISA", "8.00")
            .build()
        let outcome = evaluate(scan, [("TOTAL", .total, ""), ("VISA", .payment, "")])
        XCTAssertFalse(outcome.usedModel)
        XCTAssertEqual(outcome.receipt.notes.last, ModelReceiptVerifier.noItemsNote)
    }

    // MARK: - Names

    func testItemNamesMustSpellOutThePrintedText() {
        XCTAssertTrue(ModelReceiptVerifier.isPlausibleName("Organic bananas", printed: "ORG BNNA 4011"))
        XCTAssertTrue(ModelReceiptVerifier.isPlausibleName("Milk", printed: "2% MLK"))
        XCTAssertTrue(ModelReceiptVerifier.isPlausibleName("Bananas", printed: "BANNANAS"))
        XCTAssertFalse(ModelReceiptVerifier.isPlausibleName("Rotisserie chicken", printed: "HOT FOOD"))

        // An invented name falls back to the printed one.
        var picks = groceryPicks
        picks[1] = ("ORGANIC MILK", .item, "Strawberries")
        let outcome = evaluate(groceryScan(), picks)
        XCTAssertEqual(outcome.receipt.lineItems[1].name, "ORGANIC MILK")
    }

    func testStoreNameIsGroundedAndTidied() {
        let scan = ReceiptLayoutBuilder()
            .row("BUY", height: 0.03)
            .row("www.bestbuy.ca")
            .row("CABLE", "29.99")
            .build()
        let evidence = ScanEvidence(scan)
        XCTAssertEqual(ModelReceiptVerifier.groundedMerchant("Best Buy", evidence: evidence), "Best Buy")
        XCTAssertEqual(ModelReceiptVerifier.groundedMerchant("Best Buy #0931", evidence: evidence), "Best Buy")
        XCTAssertNil(ModelReceiptVerifier.groundedMerchant("Costco", evidence: evidence))
        XCTAssertNil(ModelReceiptVerifier.groundedMerchant("  ", evidence: evidence))

        let grocery = ScanEvidence(groceryScan())
        XCTAssertEqual(ModelReceiptVerifier.groundedMerchant("Trader Joe's", evidence: grocery), "Trader Joe's")
        XCTAssertEqual(ModelReceiptVerifier.groundedMerchant("Trader Joes", evidence: grocery), "Trader Joes")
        XCTAssertNil(ModelReceiptVerifier.groundedMerchant("Whole Foods Market", evidence: grocery))
    }

    func testCategoryAndDateSuggestions() {
        XCTAssertEqual(ModelReceiptVerifier.suggestedCategory("Groceries"), .groceries)
        XCTAssertEqual(ModelReceiptVerifier.suggestedCategory("coffee"), .coffee)
        XCTAssertNil(ModelReceiptVerifier.suggestedCategory("other"))
        XCTAssertNil(ModelReceiptVerifier.suggestedCategory("spaceships"))
        XCTAssertNil(ModelReceiptVerifier.suggestedCategory(""))
        XCTAssertEqual(ModelReceiptVerifier.calendarDate("2026-03-05"), CalendarDate(year: 2026, month: 3, day: 5))
        XCTAssertNil(ModelReceiptVerifier.calendarDate("2026-13-05"))
        XCTAssertNil(ModelReceiptVerifier.calendarDate(""))
        XCTAssertNil(ModelReceiptVerifier.calendarDate("2099-01-01"))
    }

    func testCategoryGuessPrefersTheStoreNameThenTheModel() {
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Joe's Pizza", items: [], suggestion: .groceries), .food)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Blue Door", items: ["latte"], suggestion: .food), .food)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Blue Door", items: ["latte"], suggestion: nil), .coffee)
    }

    // MARK: - Prompt and trace

    func testPromptNumbersTheLinesWithAmounts() {
        let numbered = NumberedReceipt(scan: groceryScan())
        XCTAssertEqual(numbered.entries.count, 8)
        XCTAssertTrue(numbered.text.hasPrefix("TRADER JOE'S\n"))
        XCTAssertTrue(numbered.text.contains("[1] ORG BNNA 4011 1.29\n"))
        XCTAssertTrue(numbered.text.contains("\nAVOCADO\n[3] 2 @ 0.99 1.98\n"))
        XCTAssertTrue(numbered.text.contains("[7] TOTAL 8.38\n"))
        XCTAssertEqual(numbered.entry(number: 4)?.amount, money("-0.50"))
        if let avocado = numbered.entry(number: 3) {
            XCTAssertEqual(numbered.nameAbove(avocado), "AVOCADO")
        } else {
            XCTFail("No line 3")
        }

        let prompt = ReceiptPrompt.make(for: numbered)
        XCTAssertTrue(prompt.hasPrefix("Label the 8 numbered lines"))
        XCTAssertTrue(ReceiptPrompt.instructions.contains("taxTotal"))
        XCTAssertTrue(ReceiptPrompt.instructions.contains("groceries"))
        XCTAssertEqual(ReceiptPrompt.make(for: NumberedReceipt(scan: ScanResult(pageCount: 1, blocks: []))), "")
    }

    func testLongReceiptsAreCutToFit() {
        let numbered = NumberedReceipt(scan: groceryScan(), maxCharacters: 80)
        XCTAssertLessThanOrEqual(numbered.text.count, 80)
        XCTAssertLessThan(numbered.entries.count, 8)
        XCTAssertTrue(numbered.entries.allSatisfy { entry in numbered.text.contains("[\(entry.number)] ") })
    }

    func testTraceRecordsWhatTheModelSaid() {
        let scan = groceryScan()
        let numbered = NumberedReceipt(scan: scan)
        let answer = reading(numbered, groceryPicks, store: "Trader Joe's", category: "groceries")
        let outcome = ModelReceiptVerifier.evaluate(answer, numbered: numbered, rules: RulesReceiptParser().parse(scan))
        let trace = ModelReceiptVerifier.trace(of: answer, numbered: numbered, outcome: outcome, seconds: 2.5)
        XCTAssertEqual(trace.outcome, "used")
        XCTAssertEqual(trace.storeName, "Trader Joe's")
        XCTAssertEqual(trace.labels.first, "[1] item: ORG BNNA 4011 1.29 → Organic bananas")
        XCTAssertEqual(trace.labels.count, 8)

        // It's saved with the receipt and survives a round trip through JSON.
        var receipt = outcome.receipt
        receipt.intelligence = trace
        let data = try? JSONEncoder().encode(receipt)
        let decoded = data.flatMap { json in try? JSONDecoder().decode(Receipt.self, from: json) }
        XCTAssertEqual(decoded?.intelligence, trace)
    }
}
