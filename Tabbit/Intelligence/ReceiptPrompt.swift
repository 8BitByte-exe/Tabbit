import Foundation

/// A receipt's lines the way Apple Intelligence sees them.
///
/// Every line that ends in an amount gets a number: "[4] HST 13% 6.50". The model
/// only says what each numbered line is (an item, the tax, the total…) and gives items
/// a readable name. Tabbit takes every amount from the scan itself, so the model never
/// has to copy a number, and can't invent one.
struct NumberedReceipt {

    struct Entry: Equatable {
        /// The number shown to the model, from 1.
        let number: Int
        /// Where the line is in `lines`.
        let lineIndex: Int
        let text: String
        /// The amount at the end of the line, as printed (negative for "-0.50" or "0.50-").
        let amount: Decimal
        /// The text in front of the amount.
        let textBefore: String
        /// What the keywords say the line is.
        let role: ReceiptLineRole
        /// The lowest Vision confidence among the line's blocks.
        let confidence: Float
    }

    /// Lines kept above the first amount (the store's name, address, date…).
    static let headerLineLimit = 10
    /// Lines kept below the last amount (payment details, the date, a footer).
    static let footerLineLimit = 4

    let lines: [TextLine]
    /// The numbered lines, in order.
    let entries: [Entry]
    /// The receipt as the prompt shows it.
    let text: String

    init(scan: ScanResult, slopeChoice: Int = 0, maxCharacters: Int = ReceiptPrompt.maxCharacters) {
        self.init(lines: LineGrouper.lines(from: scan, slopeChoice: slopeChoice), maxCharacters: maxCharacters)
    }

    init(lines: [TextLine], maxCharacters: Int = ReceiptPrompt.maxCharacters) {
        self.lines = lines
        let amounts = lines.map { line in AmountParser.trailingAmount(in: line.text) }
        let firstAmount = amounts.firstIndex(where: { amount in amount != nil })
        let lastAmount = amounts.lastIndex(where: { amount in amount != nil })

        var entries: [Entry] = []
        var text = ""
        var headerCount = 0
        var footerCount = 0
        var lastPage = lines.first?.pageIndex ?? 0
        for (index, line) in lines.enumerated() {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            // Long receipts: keep the top, everything with amounts, and a little of the bottom.
            if let first = firstAmount, index < first {
                headerCount += 1
                if headerCount > NumberedReceipt.headerLineLimit {
                    continue
                }
            }
            if let last = lastAmount, index > last {
                footerCount += 1
                if footerCount > NumberedReceipt.footerLineLimit {
                    break
                }
            }

            var row = ""
            if line.pageIndex != lastPage {
                row += "--- next page ---\n"
                lastPage = line.pageIndex
            }
            var entry: Entry?
            if let amount = amounts[index] {
                let number = entries.count + 1
                row += "[\(number)] "
                let confidences = line.blocks.map { block in block.confidence }
                entry = Entry(
                    number: number,
                    lineIndex: index,
                    text: trimmed,
                    amount: amount.value,
                    textBefore: amount.textBefore,
                    role: NumberedReceipt.role(of: line),
                    confidence: confidences.min() ?? 1
                )
            }
            row += trimmed + "\n"
            if text.count + row.count > maxCharacters {
                break
            }
            text += row
            if let entry = entry {
                entries.append(entry)
            }
        }
        self.entries = entries
        self.text = text
    }

    func entry(number: Int) -> Entry? {
        guard number >= 1, number <= entries.count else {
            return nil
        }
        return entries[number - 1]
    }

    /// The line right above an entry, if it has a name and no amount ("AVOCADO" above "2 @ 0.99 1.98").
    func nameAbove(_ entry: Entry) -> String? {
        let index = entry.lineIndex - 1
        guard index >= 0, index < lines.count else {
            return nil
        }
        let text = lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.rangeOfCharacter(from: .letters) != nil,
              AmountParser.trailingAmount(in: text) == nil,
              !ReceiptKeywords.isHeading(text) else {
            return nil
        }
        return text
    }

    /// The text of up to `count` lines right above an entry, nearest first.
    func textsAbove(_ entry: Entry, count: Int) -> [String] {
        var texts: [String] = []
        var index = entry.lineIndex - 1
        while index >= 0 && texts.count < count {
            texts.append(lines[index].text)
            index -= 1
        }
        return texts
    }

    /// The keyword role, trusting one of Vision's other readings if only it names a summary line
    /// (the same as the rules parser does).
    private static func role(of line: TextLine) -> ReceiptLineRole {
        let role = ReceiptKeywords.role(for: line.text)
        guard role == .other else {
            return role
        }
        for alternative in line.alternativeTexts {
            let alternativeRole = ReceiptKeywords.role(for: alternative)
            if ReceiptLineRole.summaryRoles.contains(alternativeRole) {
                return alternativeRole
            }
        }
        return role
    }
}

/// What Tabbit tells Apple Intelligence about a receipt.
enum ReceiptPrompt {

    /// The on-device model has a small context window (about 4,000 tokens for the
    /// instructions, the receipt and the answer), so very long receipts are cut short.
    static let maxCharacters = 2_800

    static let categories = SpendCategory.allCases
        .filter { category in category != .other }
        .map { category in category.rawValue }
        .joined(separator: ", ")

    static let instructions = """
    You label the lines of a shopping, restaurant or gas station receipt that was scanned with a phone camera. \
    The text comes from OCR, so words can be misspelled, cut short or run together.

    Every line that ends in an amount starts with a number in brackets, like [4]. \
    Give each numbered line exactly one kind:
    - item: something bought, including fuel, deposits and bag fees. \
    When an item's name is on the line above its price, the price line is the item.
    - discount: money taken off, like a coupon, member discount, markdown or instant savings.
    - subtotal: the amount before tax, like SUBTOTAL, SUB TOTAL, SUB or Total before tax.
    - tax: one tax, like TAX, SALES TAX, HST, GST, PST, QST or VAT.
    - taxTotal: several taxes added up, like TOTAL TAX.
    - tip: a tip, gratuity or service charge that was added to the bill.
    - total: the final amount to pay, like TOTAL, FINAL, Total after tax, Sub with tax, AMOUNT DUE or BALANCE DUE.
    - payment: how it was paid or money given back, like VISA, DEBIT, CASH, TENDERED or CHANGE.
    - savings: "you saved", regular or original prices, points and rewards.
    - unitPrice: a price per litre, gallon, kg, lb or each, or an amount of fuel or weight.
    - other: anything else, like a heading, an account number, or a tip suggestion such as "18% = 7.20".

    For every item and discount, write its name the way a person would say it: expand abbreviations, \
    use normal capitalization, and drop codes, PLU numbers and tax letters. Keep it short. \
    Leave the name empty for every other kind.

    The store name is the business's brand only, like "Best Buy", "Shell" or "Trader Joe's", \
    with OCR misspellings fixed. Never include the address, city, branch, store number or slogan.

    The category is one of: \(categories).
    """

    /// The prompt for one receipt, or "" if it has no amounts to label.
    static func make(for receipt: NumberedReceipt) -> String {
        guard !receipt.entries.isEmpty else {
            return ""
        }
        return "Label the \(receipt.entries.count) numbered lines of this receipt.\n\n" + receipt.text
    }
}
