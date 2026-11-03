import Foundation

/// Turns OCR output into a Receipt using hand-written rules.
///
/// Runs on every supported iPhone with no AI model. Rough outline:
/// 1. Rebuild visual lines from Vision's blocks (LineGrouper).
/// 2. Label each line: subtotal, tax, total, payment, or other.
/// 3. Item lines are the lines with an amount above the first subtotal/tax/total line.
/// 4. The merchant is the first name-like line at the top; the date is the first date found.
struct RulesReceiptParser {

    func parse(_ scan: ScanResult) -> Receipt {
        let lines = LineGrouper.lines(from: scan).map { line in AnalyzedLine(line) }
        var notes: [String] = []

        let items = RulesReceiptParser.findItems(in: lines)
        let subtotalLine = lines.first(where: { line in line.role == .subtotal && line.amount != nil })
        let subtotal = subtotalLine?.amount?.value

        // Only tax lines above the first total line count; some receipts repeat tax in a footer.
        let firstTotalIndex = lines.firstIndex(where: { line in
            (line.role == .total || line.role == .strongTotal) && line.amount != nil
        })
        let taxLines = Array(lines[0..<(firstTotalIndex ?? lines.count)])
        let tax = RulesReceiptParser.findTax(in: taxLines, notes: &notes)

        // What the total should be, if the receipt adds up.
        var expectedTotal: Decimal?
        if let subtotal = subtotal {
            expectedTotal = subtotal + (tax ?? Decimal(0))
        } else if !items.isEmpty {
            let itemsTotal = items.reduce(Decimal(0)) { sum, item in sum + item.amount }
            expectedTotal = itemsTotal + (tax ?? Decimal(0))
        }
        let total = RulesReceiptParser.findTotal(in: lines, expected: expectedTotal)

        let merchant = RulesReceiptParser.findMerchant(in: lines)
        let date = ReceiptDateParser.firstDate(in: lines.map { line in line.text })

        return Receipt(
            merchant: merchant,
            date: date,
            lineItems: items,
            subtotal: subtotal,
            tax: tax,
            total: total,
            parser: .rules,
            notes: notes
        )
    }

    // MARK: - Line labels

    enum LineRole: Equatable {
        case subtotal
        /// A line that states the overall tax, like "TOTAL TAX".
        case taxTotal
        case tax
        /// "GRAND TOTAL", "AMOUNT DUE", "BALANCE DUE": preferred over a plain "TOTAL".
        case strongTotal
        case total
        /// "TOTAL SAVINGS", "TOTAL ITEMS" and similar: not the amount paid.
        case notATotal
        /// Card, cash, change, tip and similar lines.
        case payment
        case other
    }

    struct AnalyzedLine {
        let text: String
        let pageIndex: Int
        let amount: AmountParser.ParsedAmount?
        let role: LineRole

        init(_ line: TextLine) {
            self.text = line.text
            self.pageIndex = line.pageIndex
            self.amount = AmountParser.trailingAmount(in: line.text)
            self.role = RulesReceiptParser.role(for: line.text.uppercased())
        }
    }

    private static let subtotalPattern = Patterns.make(#"\bSUB[\s-]?TOTAL\b|\bSUB[\s-]?TTL\b"#)
    private static let taxTotalPattern = Patterns.make(#"\bTOTAL\s+TAX(ES)?\b|\bTAX(ES)?\s+TOTAL\b"#)
    private static let notATotalPattern = Patterns.make(
        #"\bTOTAL\s+(YOU\s+)?(SAVINGS|SAVED|SAVE|DISCOUNTS?|ITEMS?|QTY|QUANTITY|NUMBER|POINTS)\b"#
    )
    private static let strongTotalPattern = Patterns.make(
        #"\bGRAND\s+TOTAL\b|\bAMOUNT\s+DUE\b|\bBALANCE\s+DUE\b|\bTOTAL\s+DUE\b|\bTOTAL\s+AMOUNT\b|\bAMOUNT\s+TOTAL\b"#
    )
    private static let taxPattern = Patterns.make(#"\bTAX(ES)?\b|\bHST\b|\bGST\b|\bPST\b|\bQST\b|\bVAT\b"#)
    private static let includedPattern = Patterns.make(#"\bINCL"#)
    private static let totalPattern = Patterns.make(#"\bTOTAL\b"#)
    private static let paymentPattern = Patterns.make(
        #"\b(CHANGE|CASH|TEND|TENDER|TENDERED|VISA|MASTERCARD|MASTER\s+CARD|AMEX|AMERICAN\s+EXPRESS|DISCOVER|DEBIT|CREDIT|PAYMENT|PAID|AUTH|APPROVAL|APPROVED|ACCOUNT|ACCT|REFUND|TIP|GRATUITY|SAVINGS|SAVED|POINTS|REWARDS?)\b"#
    )

    /// Labels one line. `upper` is the line's text in upper case.
    static func role(for upper: String) -> LineRole {
        if subtotalPattern.hasMatch(in: upper) {
            return .subtotal
        }
        if taxTotalPattern.hasMatch(in: upper) {
            return .taxTotal
        }
        if notATotalPattern.hasMatch(in: upper) {
            return .notATotal
        }
        if strongTotalPattern.hasMatch(in: upper) {
            return .strongTotal
        }
        // "TOTAL INCL. TAX" is a total, not a tax line.
        if taxPattern.hasMatch(in: upper) && !includedPattern.hasMatch(in: upper) {
            return .tax
        }
        if totalPattern.hasMatch(in: upper) {
            return .total
        }
        if paymentPattern.hasMatch(in: upper) {
            return .payment
        }
        return .other
    }

    // MARK: - Totals

    /// Picks the total from the "TOTAL"-like lines:
    /// 1. the first one that equals subtotal + tax (or items + tax), if known;
    /// 2. otherwise prefer "AMOUNT DUE"-style lines over a plain "TOTAL";
    /// 3. then the largest amount.
    /// Rule 1 handles receipts like "TOTAL 3.30 / GIFT CARD 2.00 / BALANCE DUE 1.30".
    private static func findTotal(in lines: [AnalyzedLine], expected: Decimal?) -> Decimal? {
        var strong: [Decimal] = []
        var plain: [Decimal] = []
        for line in lines {
            guard let amount = line.amount else {
                continue
            }
            if line.role == .strongTotal {
                strong.append(amount.value)
            } else if line.role == .total {
                plain.append(amount.value)
            }
        }

        if let expected = expected {
            for line in lines where line.role == .total || line.role == .strongTotal {
                if let value = line.amount?.value, ReceiptValidator.matches(value, expected) {
                    return value
                }
            }
        }

        let candidates = strong.isEmpty ? plain : strong
        return candidates.max()
    }

    /// Uses a "TOTAL TAX" line if there is one, otherwise adds up the tax lines
    /// (for example separate state and city tax).
    private static func findTax(in lines: [AnalyzedLine], notes: inout [String]) -> Decimal? {
        if let taxTotal = lines.first(where: { line in line.role == .taxTotal && line.amount != nil }) {
            return taxTotal.amount?.value
        }
        let taxAmounts: [Decimal] = lines.compactMap { line in
            line.role == .tax ? line.amount?.value : nil
        }
        if taxAmounts.isEmpty {
            return nil
        }
        if taxAmounts.count > 1 {
            notes.append("Added up \(taxAmounts.count) tax lines.")
        }
        return taxAmounts.reduce(Decimal(0), +)
    }

    // MARK: - Items

    private static let quantityOnlyPattern = Patterns.make(
        #"^\s*\d+(?:[.,]\d+)?\s*(?:LBS?|KG|OZ|EA)?\s*(?:@|X|×)\s*[$€£]?\s*\d+(?:[.,]\d+)?\s*(?:/\s*(?:LBS?|KG|OZ|EA))?\s*$"#,
        caseInsensitive: true
    )

    /// Item lines: lines with an amount above the first subtotal/tax/total line,
    /// skipping payment lines. A price line with no name of its own
    /// (like "2 @ 0.99   1.98") takes the name from the line above it.
    private static func findItems(in lines: [AnalyzedLine]) -> [ReceiptLineItem] {
        let summaryRoles: [LineRole] = [.subtotal, .taxTotal, .tax, .strongTotal, .total]
        let summaryIndex = lines.firstIndex(where: { line in
            summaryRoles.contains(line.role) && line.amount != nil
        })
        let regionEnd = summaryIndex ?? lines.count

        var items: [ReceiptLineItem] = []
        var nameFromLineAbove: String?
        for line in lines[0..<regionEnd] {
            guard let amount = line.amount else {
                nameFromLineAbove = hasLetters(line.text) ? cleanName(line.text) : nil
                continue
            }
            guard line.role == .other else {
                nameFromLineAbove = nil
                continue
            }

            var name = cleanName(amount.textBefore)
            if !hasLetters(name) || quantityOnlyPattern.hasMatch(in: name) {
                if let aboveName = nameFromLineAbove {
                    name = aboveName
                } else if name.isEmpty {
                    name = "Item"
                }
            }
            items.append(ReceiptLineItem(name: name, amount: amount.value))
            nameFromLineAbove = nil
        }
        return items
    }

    // MARK: - Merchant

    private static let merchantNoisePattern = Patterns.make(
        #"\b(WELCOME|THANK|THANKS|RECEIPT|INVOICE|TEL|PHONE|FAX|CASHIER|REGISTER|TERMINAL|ORDER|TABLE|SERVER|GUEST|DATE|TIME|TRANS|TRANSACTION|COPY|MERCHANT)\b|\bSTORE\s*(#|NO\b)|WWW\.|HTTPS?:|\.COM\b"#
    )

    private static let contactDetector: NSDataDetector? = {
        let types = NSTextCheckingResult.CheckingType.phoneNumber.rawValue
            | NSTextCheckingResult.CheckingType.address.rawValue
            | NSTextCheckingResult.CheckingType.link.rawValue
            | NSTextCheckingResult.CheckingType.date.rawValue
        return try? NSDataDetector(types: types)
    }()

    /// The first name-like line at the top of the first page, before any amounts.
    private static func findMerchant(in lines: [AnalyzedLine]) -> String? {
        let header = lines.prefix(while: { line in line.amount == nil }).prefix(8)
        for line in header where line.pageIndex == 0 {
            if isMerchantCandidate(line.text) {
                return cleanName(line.text)
            }
        }
        return nil
    }

    private static func isMerchantCandidate(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.unicodeScalars.first, !CharacterSet.decimalDigits.contains(first) else {
            // Empty, or starts with a number (usually a street address).
            return false
        }
        let visible = trimmed.unicodeScalars.filter { scalar in !CharacterSet.whitespaces.contains(scalar) }
        let letters = visible.filter { scalar in CharacterSet.letters.contains(scalar) }
        guard letters.count >= 3, Double(letters.count) >= 0.5 * Double(visible.count) else {
            return false
        }
        if merchantNoisePattern.hasMatch(in: trimmed.uppercased()) {
            return false
        }
        return !isMostlyContactDetails(trimmed)
    }

    /// True if at least half the line is a phone number, address, link or date.
    private static func isMostlyContactDetails(_ text: String) -> Bool {
        guard let detector = contactDetector else {
            return false
        }
        let length = (text as NSString).length
        guard length > 0 else {
            return false
        }
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: length))
        let covered = matches.reduce(0) { sum, match in sum + match.range.length }
        return Double(covered) >= 0.5 * Double(length)
    }

    // MARK: - Text helpers

    private static func hasLetters(_ text: String) -> Bool {
        return text.rangeOfCharacter(from: .letters) != nil
    }

    /// Trims spaces and stray separators, and collapses runs of spaces.
    private static func cleanName(_ text: String) -> String {
        let pieces = text.split(separator: " ", omittingEmptySubsequences: true)
        let joined = pieces.joined(separator: " ")
        let separators = CharacterSet(charactersIn: " :$€£.-")
        return joined.trimmingCharacters(in: separators)
    }
}
