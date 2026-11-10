import Foundation

/// A receipt the way Apple Intelligence sees it: already split into its parts.
///
/// Tabbit reads the receipt's structure itself before the model sees it, from the layout
/// and the keywords (`ReceiptLayout`, `RulesReceiptParser.itemCandidates`):
/// - the store part at the top, the items, the totals, then payment and other details;
/// - detail lines under an item ("1 @ 2/ $9.00", "YOU SAVED $1.29"), which describe it.
///
/// The prompt shows each part under a heading. Item lines and totals get a number, like
/// "[4] HST 13% 6.50". Detail lines are indented under their item without a number, and
/// nothing below the totals is numbered, so the model only labels lines that could
/// matter: it can't call a deal, a savings line or the card slip an item. Tabbit takes
/// every amount from the scan itself, so the model never copies a number and can't
/// invent one.
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
        /// How many, and the price of one, if the line shows them ("2 @ 1.99", "2 BANANAS 1.99/EA").
        var quantity: Decimal? = nil
        var unitPrice: Decimal? = nil
        /// The amount is quantity × unit price, because no line total is printed.
        var isComputed: Bool = false
        /// Another reading of the amount ("2 BANANAS 1.99" as 3.98), tried if the items don't add up.
        var alternative: Decimal? = nil
    }

    /// The parts of a receipt, top to bottom.
    enum Section: Equatable {
        /// The store's name, address and other details above the items.
        case store
        case items
        /// From the first subtotal, tax or total line to the last one.
        case totals
        /// Payment, savings summaries, surveys: nothing here is an item.
        case details

        var heading: String {
            switch self {
            case .store: return "--- store ---"
            case .items: return "--- items ---"
            case .totals: return "--- totals ---"
            case .details: return "--- payment and other details (no items here) ---"
            }
        }
    }

    /// Lines kept above the items (the store's name, address, date…).
    static let headerLineLimit = 10
    /// Lines kept below the totals (payment details, the date, a footer).
    static let footerLineLimit = 6

    /// Lines that end the totals: the last of these (with an amount) is the end of the totals part.
    static let totalsRoles: [ReceiptLineRole] = [
        .subtotal, .taxTotal, .tax, .strongTotal, .total, .tip, .rounding, .includedTax,
    ]

    let lines: [TextLine]
    /// What the layout and keywords make of every line that might be a purchase.
    let candidates: [RulesReceiptParser.ItemCandidate]
    /// What the payment lines say was paid; a total that equals one is confirmed by it.
    let paidAmounts: Set<Decimal>
    /// The numbered lines, in order.
    let entries: [Entry]
    /// The receipt as the prompt shows it.
    let text: String
    /// How prices that were partly unreadable were filled in (`RulesReceiptParser.repairNotes`).
    let repairNotes: [String]
    /// The receipt's main language ("en", "fr"), or nil when it's unclear (`ReceiptAlphabet`).
    let language: String?

    init(scan: ScanResult, slopeChoice: Int = 0, maxCharacters: Int = ReceiptPrompt.maxCharacters) {
        self.init(lines: LineGrouper.lines(from: scan, slopeChoice: slopeChoice), maxCharacters: maxCharacters)
    }

    init(lines: [TextLine], maxCharacters: Int = ReceiptPrompt.maxCharacters) {
        self.lines = lines
        let analyzed = RulesReceiptParser.analyze(lines)
        let candidates = RulesReceiptParser.itemCandidates(in: analyzed)
        self.candidates = candidates
        self.repairNotes = RulesReceiptParser.repairNotes(in: analyzed)
        self.language = ReceiptAlphabet.mainLanguage(of: lines.map { line in line.text })
        var detailLines: Set<Int> = []
        for candidate in candidates where candidate.isDetail {
            detailLines.insert(candidate.lineIndex)
        }
        let sections = NumberedReceipt.sections(of: analyzed)
        let firstTotal = analyzed.firstIndex(where: { line in
            (line.role == .total || line.role == .strongTotal) && line.amount != nil
        })
        var paid: Set<Decimal> = []
        if let amount = RulesReceiptParser.paidAmount(in: analyzed, after: firstTotal) {
            paid.insert(amount)
        }
        self.paidAmounts = paid

        var entries: [Entry] = []
        var text = ""
        var headerCount = 0
        var footerCount = 0
        var lastPage = lines.first?.pageIndex ?? 0
        var lastSection: Section?
        for (index, line) in lines.enumerated() {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let section = sections[index]
            // Long receipts: keep the top, everything with amounts, and a little of the bottom.
            if section == .store {
                headerCount += 1
                if headerCount > NumberedReceipt.headerLineLimit {
                    continue
                }
            }
            if section == .details {
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
            if lastSection != section {
                row += section.heading + "\n"
                lastSection = section
            }
            var entry: Entry?
            let isDetail = detailLines.contains(index)
            if let amount = NumberedReceipt.amount(of: analyzed[index]),
               section == .items || section == .totals, !isDetail {
                let number = entries.count + 1
                row += "[\(number)] "
                let confidences = line.blocks.map { block in block.confidence }
                entry = Entry(
                    number: number,
                    lineIndex: index,
                    text: trimmed,
                    amount: amount.value,
                    textBefore: amount.textBefore,
                    role: analyzed[index].role,
                    confidence: confidences.min() ?? 1,
                    quantity: amount.quantity,
                    unitPrice: amount.unitPrice,
                    isComputed: amount.isComputed,
                    alternative: amount.alternative
                )
            } else if isDetail {
                row += "    "
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

    /// Which part of the receipt each line is in.
    static func sections(of lines: [RulesReceiptParser.AnalyzedLine]) -> [Section] {
        guard let firstAmount = lines.firstIndex(where: { line in line.amount != nil }) else {
            return lines.map { _ in Section.store }
        }
        // The items start at the first amount, or just above it: the first item's name when its
        // price is on the line below, and the department headings over it ("GROCERY").
        var itemsStart = firstAmount
        if itemsStart > 0, let amount = lines[itemsStart].amount, ReceiptKeywords.isDetailOnly(amount.textBefore),
           lines[itemsStart - 1].text.rangeOfCharacter(from: .letters) != nil {
            itemsStart -= 1
        }
        while itemsStart > 0 && ReceiptKeywords.isHeading(lines[itemsStart - 1].text) {
            itemsStart -= 1
        }
        let firstSummary = lines.firstIndex(where: { line in
            ReceiptLineRole.summaryRoles.contains(line.role) && line.amount != nil
        })
        let lastSummary = lines.lastIndex(where: { line in
            NumberedReceipt.totalsRoles.contains(line.role) && line.amount != nil
        })
        return lines.indices.map { index -> Section in
            if index < itemsStart {
                return .store
            }
            guard let summary = firstSummary else {
                return .items
            }
            if index < summary {
                return .items
            }
            if let last = lastSummary, index <= last {
                return .totals
            }
            return .details
        }
    }

    /// The line's amount, with its quantity and unit price for lines that may be items.
    private static func amount(of line: RulesReceiptParser.AnalyzedLine) -> LineAmount? {
        if let detail = line.detail {
            return detail
        }
        guard let amount = line.amount else {
            return nil
        }
        return LineAmount(value: amount.value, textBefore: amount.textBefore)
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
              LineAmountParser.read(text) == nil,
              !ReceiptKeywords.isHeading(text), !ReceiptKeywords.isDeal(text) else {
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
}

/// What Tabbit tells Apple Intelligence about a receipt.
enum ReceiptPrompt {

    /// The on-device model has a small context window (about 4,000 tokens for the
    /// instructions, the receipt and the answer), so very long receipts are cut short.
    static let maxCharacters = 2_800

    /// What the less obvious categories mean, so a supermarket isn't read as a restaurant.
    private static let categoryHints: [SpendCategory: String] = [
        .groceries: "supermarkets and grocery stores, and receipts with departments like PRODUCE or GROCERY",
        .food: "restaurants, takeout and fast food",
        .coffee: "coffee shops",
        .drinks: "bars, pubs and liquor stores",
        .fuel: "gas stations",
        .household: "hardware, furniture and home stores",
        .shopping: "department stores and general shopping",
        .utilities: "bills like electricity, water, internet and phone",
    ]

    static let categories = SpendCategory.allCases
        .filter { category in category != .other }
        .map { category -> String in
            if let hint = categoryHints[category] {
                return "\(category.rawValue) (\(hint))"
            }
            return category.rawValue
        }
        .joined(separator: ", ")

    static let instructions = """
    You read a shopping, restaurant or gas station receipt that was scanned with a phone camera. \
    The text comes from OCR, so words can be misspelled, cut short or run together.

    The receipt is already split into parts, each under a heading like --- items ---:
    - store: the business's name, address and other details.
    - items: what was bought. An indented line under an item describes that item, like a quantity \
    ("1 @ 2/ $9.00"), a deal, a regular price or "you saved". It isn't a purchase and has no number.
    - totals: the subtotal, taxes, tip and total.
    - payment and other details: how it was paid, savings summaries, surveys. Nothing there is an item.

    Lines that matter start with a number in brackets, like [4]. Answer once for each numbered line, in order, \
    with exactly one kind:
    - item: something bought, including fuel, deposits and bag fees. \
    When an item's name is on the line above its price, the price line is the item.
    - discount: money taken off what was bought, like a coupon or member discount, usually with a minus sign.
    - subtotal: the amount before tax, like SUBTOTAL, SUB TOTAL, SUB or Total before tax.
    - tax: one tax, like TAX, SALES TAX, HST 13%, GST, PST, QST or VAT. Tax is always less than the total.
    - taxTotal: several taxes added up, like TOTAL TAX.
    - tip: a tip, gratuity or service charge that was added to the bill.
    - total: the final amount to pay, like TOTAL, FINAL, Total after tax, Sub with tax, AMOUNT DUE or BALANCE DUE, \
    or the amount on a card slip or payment stub that lists no products ("Amount: $13.50").
    - payment: how it was paid or money given back, like VISA, DEBIT, CASH, TENDERED or CHANGE.
    - savings: "you saved", regular or original prices, points and rewards. These are information, not purchases.
    - unitPrice: a price per litre, gallon, kg or lb on a line of its own, or an amount of fuel or weight.
    - other: anything else, like an account number, a deal such as "2 FOR 1" or "BUY 1 GET 1", \
    or a tip suggestion such as "18% = 7.20".

    For every item and discount, write the product's name in Title Case the way a shelf label reads, \
    like "Organic Bananas": expand abbreviations (BLK is Black, ORG is Organic, CHKN is Chicken), keep brand names, \
    and leave out codes, prices, quantities and tax letters. Never write numbers as words. Keep it short. \
    Leave the name empty for every other kind.

    The store name is the business's brand only, like "Best Buy", "Shell" or "Trader Joe's", \
    spelled the way the business spells it: OCR often misreads letters (rn for m, 0 for O, 1 for l), so fix them. \
    Never include the address, city, branch, store number or slogan.

    Read every word in context, the way a person would. A receipt is written in one language, \
    sometimes with whole lines in a second one, and never switches language or alphabet in the middle of a word. \
    OCR sometimes puts a stray letter from another alphabet or an odd accent into a word: \
    on an English receipt a word with one strange character is still an English word, so name it as the English word \
    that fits the receipt. A line that is entirely in the second language stays in that language.

    The category is the kind of business, one of: \(categories). Decide it from the store's name; \
    when the name doesn't say, decide from what was bought (bananas, milk and bread mean groceries).
    """

    /// The prompt for one receipt, or "" if it has no amounts to label. `photoSections` is
    /// how many sections the attached photo has (0 when there is no photo, see `ReceiptPhoto`).
    static func make(for receipt: NumberedReceipt, photoSections: Int = 0) -> String {
        guard !receipt.entries.isEmpty else {
            return ""
        }
        var prompt = "Label the \(receipt.entries.count) numbered lines of this receipt.\n\n"
        if let note = languageNote(receipt.language) {
            prompt += note + "\n\n"
        }
        if photoSections > 0 {
            prompt += photoNote(sections: photoSections) + "\n\n"
        }
        return prompt + receipt.text
    }

    /// "This receipt is in French." for a receipt whose language is clear, else nil.
    static func languageNote(_ language: String?) -> String? {
        guard let language = language,
              let name = Locale(identifier: "en_US").localizedString(forLanguageCode: language) else {
            return nil
        }
        return "This receipt is in \(name)."
    }

    /// What the model is told about the photo. The amounts always come from the text.
    static func photoNote(sections: Int) -> String {
        var layout = "The photo shows the same receipt."
        if sections > 1 {
            layout = "The photo shows the same receipt cut into \(sections) sections side by side: " +
                "read the left section from top to bottom, then the next one."
        }
        return layout + " Use it to see which name and price are printed on the same line, " +
            "which lines are indented details, and how misspelled words are really spelled. " +
            "The line numbers and amounts are in the text below."
    }
}
