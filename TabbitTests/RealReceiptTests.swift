import XCTest
@testable import Tabbit

/// Real receipts exported from the app (redacted), read the way the phone reads them.
final class RealReceiptTests: XCTestCase {

    private let sobeysAmounts = ["4.50", "4.75", "6.99", "7.99", "0.99", "0.99"].map { text in money(text) }

    /// A Sobeys grocery receipt: GROCERY and PRODUCE headings, "1 @ 2/ $9.00" and "YOU SAVED"
    /// detail lines under items, and savings summaries and a card slip below the total.
    private func sobeysScan() throws -> ScanResult {
        return try Fixtures.scan(named: "sobeys-grocery")
    }

    func testSobeysWithTheRules() throws {
        let receipt = RulesReceiptParser().parse(try sobeysScan())
        XCTAssertEqual(receipt.lineItems.map { item in item.amount }, sobeysAmounts)
        XCTAssertTrue(receipt.lineItems.first?.name.hasPrefix("Chips Lime") ?? false)
        XCTAssertEqual(receipt.lineItems.count > 3 ? receipt.lineItems[3].name : "", "Carving Kit")
        XCTAssertEqual(receipt.subtotal, money("26.21"))
        XCTAssertEqual(receipt.tax, money("3.15"))
        XCTAssertEqual(receipt.total, money("29.36"))
        XCTAssertEqual(receipt.paymentMethod, "Visa")
        XCTAssertEqual(receipt.time, ClockTime(hour: 17, minute: 25))
        XCTAssertEqual(receipt.date, CalendarDate(year: 2026, month: 10, day: 30))
        XCTAssertTrue(receipt.location?.contains("Burlington") ?? false)
        XCTAssertTrue(ReceiptValidator.checks(for: receipt).allSatisfy { check in check.passed })
    }

    func testSobeysPromptOnlyNumbersLinesThatMatter() throws {
        let scan = try sobeysScan()
        let numbered = NumberedReceipt(scan: scan, slopeChoice: RulesReceiptParser.bestSlopeChoice(for: scan))
        // Six items, SUBTOTAL, TOTAL TAX and TOTAL. Detail lines, savings summaries and the
        // card slip have no number, so the model can't make an item of them.
        XCTAssertEqual(numbered.entries.count, 9)
        for entry in numbered.entries {
            for word in ["@", "SAVED", "Purchase", "Savings", "Discounts", "TENDER"] {
                XCTAssertFalse(entry.text.contains(word), entry.text)
            }
        }
        XCTAssertTrue(numbered.text.contains("\n    1 @ 2/ $9.00\n"))
        XCTAssertTrue(numbered.text.contains("\n    YOU SAVED $1.29\n"))
        XCTAssertTrue(numbered.text.contains("--- items ---\nGROCERY\n[1] Chips Lime Blk Pep $4.50 HC\n"))
    }

    /// The labels Apple Intelligence gave this receipt on the phone (from the export's trace),
    /// for the lines that are still numbered.
    private func sobeysReading(_ numbered: NumberedReceipt) -> ModelReceiptReading {
        let names: [(prefix: String, name: String)] = [
            ("Chips Lime", "chips lime block pepper"), ("Chips Rolld", "chips roll-up fiery"),
            ("Reese", "reese peanut butter cup mini"), ("Carving", "carving kit"), ("Pumpkin", "pumpkin regular"),
        ]
        var labels: [ModelReceiptReading.Label] = []
        for entry in numbered.entries {
            switch entry.role {
            case .subtotal:
                labels.append(ModelReceiptReading.Label(line: entry.number, kind: .subtotal, name: ""))
            case .taxTotal:
                labels.append(ModelReceiptReading.Label(line: entry.number, kind: .tax, name: ""))
            case .total:
                labels.append(ModelReceiptReading.Label(line: entry.number, kind: .total, name: ""))
            default:
                let name = names.first(where: { pair in entry.text.hasPrefix(pair.prefix) })?.name ?? ""
                labels.append(ModelReceiptReading.Label(line: entry.number, kind: .item, name: name))
            }
        }
        return ModelReceiptReading(storeName: "Sobeys", labels: labels, pricesIncludeTax: false,
                                   category: "food", date: "2026-10-30")
    }

    func testSobeysWithAppleIntelligence() throws {
        let scan = try sobeysScan()
        let numbered = NumberedReceipt(scan: scan, slopeChoice: RulesReceiptParser.bestSlopeChoice(for: scan))
        let outcome = ModelReceiptVerifier.evaluate(sobeysReading(numbered), numbered: numbered,
                                                    rules: RulesReceiptParser().parse(scan))
        let receipt = outcome.receipt
        XCTAssertTrue(outcome.usedModel)
        XCTAssertEqual(itemList(receipt), itemList([
            ("Chips Lime Block Pepper", "4.50"), ("Chips Roll-up Fiery", "4.75"),
            ("Reese Peanut Butter Cup Mini", "6.99"), ("Carving Kit", "7.99"),
            ("Pumpkin Regular", "0.99"), ("Pumpkin Regular", "0.99"),
        ]))
        XCTAssertEqual(receipt.merchant, "Sobeys")
        XCTAssertEqual(receipt.subtotal, money("26.21"))
        XCTAssertEqual(receipt.tax, money("3.15"))
        XCTAssertEqual(receipt.total, money("29.36"))
        XCTAssertEqual(receipt.notes, [ModelReceiptVerifier.usedNote])

        // The model said "food" (Dining); the store name and the GROCERY/PRODUCE headings say Groceries.
        XCTAssertEqual(outcome.suggestedCategory, .food)
        let lines = LineGrouper.lines(from: scan).map { line in line.text }
        XCTAssertEqual(CategoryGuesser.guess(merchant: receipt.merchant ?? "", items: [],
                                             suggestion: outcome.suggestedCategory, receiptLines: lines), .groceries)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Jobeys", items: [],
                                             suggestion: outcome.suggestedCategory, receiptLines: lines), .groceries)
    }

    func testSobeysEvenIfTheModelCallsEverythingAnItem() throws {
        // The worst answer: every numbered line an item, with invented names. The layout and
        // the arithmetic still give the right receipt, with the printed names.
        let scan = try sobeysScan()
        let numbered = NumberedReceipt(scan: scan, slopeChoice: RulesReceiptParser.bestSlopeChoice(for: scan))
        let labels = numbered.entries.map { entry in
            ModelReceiptReading.Label(line: entry.number, kind: .item, name: "Strawberries")
        }
        let reading = ModelReceiptReading(storeName: "", labels: labels, pricesIncludeTax: false, category: "", date: "")
        let outcome = ModelReceiptVerifier.evaluate(reading, numbered: numbered, rules: RulesReceiptParser().parse(scan))
        XCTAssertEqual(outcome.receipt.lineItems.map { item in item.amount }, sobeysAmounts)
        XCTAssertFalse(outcome.receipt.lineItems.contains { item in item.name == "Strawberries" })
        XCTAssertEqual(outcome.receipt.subtotal, money("26.21"))
        XCTAssertEqual(outcome.receipt.tax, money("3.15"))
        XCTAssertEqual(outcome.receipt.total, money("29.36"))
    }
}
