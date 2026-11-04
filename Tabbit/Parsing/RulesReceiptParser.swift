import Foundation

/// Turns OCR output into a Receipt using hand-written rules.
///
/// Runs on every supported iPhone with no AI model. Rough outline:
/// 1. Rebuild visual lines from Vision's blocks, correcting for tilt (LineGrouper).
/// 2. Label each line (ReceiptKeywords), tolerating OCR misreads like "SJETOTAL".
/// 3. Item lines are the lines with a price above the first subtotal/tax/total line.
///    Regular-price and "you save" lines are set aside; discounts count.
/// 4. If no line is labelled subtotal, a line right above the totals whose amount
///    equals the items above it is taken as the subtotal.
/// 5. If the items don't add up to the subtotal, try counting or leaving out the
///    lines that could go either way, and note what was changed.
/// 6. The merchant is the biggest (or else the first) name-like line at the top; the date is
///    the first date found.
///
/// Also handled: quantity, weight and unit lines in English and European formats; barcodes,
/// PLU codes and tax flags in names; discounts printed without a minus; cash rounding;
/// tax that's already included in the prices (common in Europe); tip guides under the total;
/// and total, tax and payment words in German, Spanish, French, Italian and Dutch.
struct RulesReceiptParser {

    func parse(_ scan: ScanResult) -> Receipt {
        // Try each tilt guess (usually just one) and keep the result whose
        // numbers agree best. Ties keep the earlier, geometrically better guess.
        var best: Receipt?
        var bestScore = Int.min
        for choice in 0..<LineGrouper.slopeChoiceCount(for: scan) {
            let receipt = parse(scan, slopeChoice: choice)
            let score = RulesReceiptParser.consistencyScore(of: receipt)
            if best == nil || score > bestScore {
                best = receipt
                bestScore = score
            }
        }
        return best ?? parse(scan, slopeChoice: 0)
    }

    /// Passed checks count for, failed checks against. Finding a total matters
    /// most, so a guess that loses the total can't win on a lucky match.
    static func consistencyScore(of receipt: Receipt) -> Int {
        var score = 0
        for check in ReceiptValidator.checks(for: receipt) {
            score += check.passed ? 3 : -2
        }
        if receipt.total != nil {
            score += 3
        }
        if receipt.subtotal != nil {
            score += 1
        }
        return score
    }

    private func parse(_ scan: ScanResult, slopeChoice: Int) -> Receipt {
        let lines = LineGrouper.lines(from: scan, slopeChoice: slopeChoice).map { line in AnalyzedLine(line) }
        var notes: [String] = []

        var subtotal = RulesReceiptParser.firstAmount(in: lines, role: .subtotal)

        // Only tax lines above the first total line count; some receipts repeat tax in a footer.
        let firstTotalIndex = lines.firstIndex(where: { line in
            (line.role == .total || line.role == .strongTotal) && line.amount != nil
        })
        let taxLines = Array(lines[0..<(firstTotalIndex ?? lines.count)])
        var tax = RulesReceiptParser.findTax(in: taxLines, notes: &notes)
        let tip = RulesReceiptParser.findTip(in: lines, firstTotalIndex: firstTotalIndex)
        let rounding = RulesReceiptParser.firstAmount(in: taxLines, role: .rounding) ?? Decimal(0)
        var fees = (tax ?? Decimal(0)) + (tip ?? Decimal(0)) + rounding

        var candidates = RulesReceiptParser.itemCandidates(in: lines)

        if subtotal == nil {
            let totals = RulesReceiptParser.totalAmounts(in: lines)
            if let inferred = RulesReceiptParser.inferSubtotal(from: &candidates, tax: fees, totals: totals) {
                subtotal = inferred.value
                notes.append("Read \"\(inferred.label)\" as the subtotal, because it equals the items above it.")
            }
        }

        // What the total should be, if the receipt adds up.
        var expectedTotal: Decimal?
        if let subtotal = subtotal {
            expectedTotal = subtotal + fees
        } else if candidates.contains(where: { candidate in candidate.included }) {
            expectedTotal = RulesReceiptParser.includedSum(candidates) + fees
        }
        var total = RulesReceiptParser.findTotal(in: lines, expected: expectedTotal)

        // Prices that already include the tax (usual in Europe): the items alone add up
        // to the total, and adding the tax would count it twice.
        if let foundTax = tax, foundTax != 0, subtotal == nil {
            let itemsSum = RulesReceiptParser.includedSum(candidates)
            let withoutTax = itemsSum + (tip ?? Decimal(0)) + rounding
            let totals = RulesReceiptParser.totalAmounts(in: lines)
            if let matching = totals.first(where: { value in ReceiptValidator.matches(value, withoutTax) }),
               !totals.contains(where: { value in ReceiptValidator.matches(value, withoutTax + foundTax) }) {
                tax = nil
                fees -= foundTax
                total = matching
                notes.append("The prices already include \(MoneyInput.editText(foundTax)) tax, so it isn't added again.")
            }
        }
        if let included = RulesReceiptParser.firstAmount(in: lines, role: .includedTax), tax == nil {
            if !notes.contains(where: { note in note.hasPrefix("The prices already include") }) {
                notes.append("The prices already include \(MoneyInput.editText(included)) tax.")
            }
        }

        // Make the items agree with the subtotal (or with total minus tax).
        if let subtotal = subtotal {
            if let note = RulesReceiptParser.reconcile(&candidates, target: subtotal, targetName: "subtotal") {
                notes.append(note)
            }
        } else if let total = total {
            let target = total - fees
            if let note = RulesReceiptParser.reconcile(&candidates, target: target, targetName: "total") {
                notes.append(note)
            }
        }

        let items = candidates.filter { candidate in candidate.included }.map { candidate in candidate.item }
        let merchant = RulesReceiptParser.findMerchant(in: lines)
        let date = ReceiptDateParser.firstDate(in: lines.map { line in line.text })

        return Receipt(
            merchant: merchant,
            date: date,
            lineItems: items,
            subtotal: subtotal,
            tax: tax,
            total: total,
            tip: tip,
            parser: .rules,
            notes: notes
        )
    }

    // MARK: - Lines

    struct AnalyzedLine {
        let text: String
        let pageIndex: Int
        let amount: AmountParser.ParsedAmount?
        let role: ReceiptLineRole
        /// The lowest Vision confidence among the line's blocks.
        let confidence: Float
        /// Text height (normalized), to spot the big store name at the top.
        let height: CGFloat

        init(_ line: TextLine) {
            self.text = line.text
            self.pageIndex = line.pageIndex
            let heights = line.blocks.map { block in block.boundingBox.height }
            self.height = heights.max() ?? line.boundingBox.height
            self.amount = AmountParser.trailingAmount(in: line.text)

            // If the top reading isn't a summary line but one of Vision's other
            // readings is (say "SUBTOTAL" for "SJBTCTAI"), trust the other reading.
            var role = ReceiptKeywords.role(for: line.text)
            if role == .other {
                for alternative in line.alternativeTexts {
                    let alternativeRole = ReceiptKeywords.role(for: alternative)
                    if ReceiptLineRole.summaryRoles.contains(alternativeRole) {
                        role = alternativeRole
                        break
                    }
                }
            }
            self.role = role

            let confidences = line.blocks.map { block in block.confidence }
            self.confidence = confidences.min() ?? 1
        }
    }

    private static func firstAmount(in lines: [AnalyzedLine], role: ReceiptLineRole) -> Decimal? {
        let line = lines.first(where: { candidate in candidate.role == role && candidate.amount != nil })
        return line?.amount?.value
    }

    private static func totalAmounts(in lines: [AnalyzedLine]) -> [Decimal] {
        return lines.compactMap { line in
            (line.role == .total || line.role == .strongTotal) ? line.amount?.value : nil
        }
    }

    // MARK: - Totals

    /// Picks the total from the "TOTAL"-like lines:
    /// 1. the first one that equals subtotal + tax (or items + tax), if known;
    /// 2. otherwise prefer "AMOUNT DUE"-style lines over a plain "TOTAL";
    /// 3. then the largest amount.
    /// Rule 1 handles receipts like "TOTAL 3.30 / GIFT CARD 2.00 / BALANCE DUE 1.30".
    private static func findTotal(in lines: [AnalyzedLine], expected: Decimal?) -> Decimal? {
        if let expected = expected {
            for line in lines where line.role == .total || line.role == .strongTotal {
                if let value = line.amount?.value, ReceiptValidator.matches(value, expected) {
                    return value
                }
            }
        }
        let strong = lines.compactMap { line in line.role == .strongTotal ? line.amount?.value : nil }
        let plain = lines.compactMap { line in line.role == .total ? line.amount?.value : nil }
        let candidates = strong.isEmpty ? plain : strong
        return candidates.max()
    }

    /// The tip, if the receipt has one. Above the total any tip line counts. Below it,
    /// lines with a "%" ("18% TIP 7.20") are a printed tip guide, not a tip, unless a later
    /// total includes them.
    private static func findTip(in lines: [AnalyzedLine], firstTotalIndex: Int?) -> Decimal? {
        let boundary = firstTotalIndex ?? lines.count
        for (index, line) in lines.enumerated() where line.role == .tip {
            guard let value = line.amount?.value else {
                continue
            }
            if index < boundary {
                return value
            }
            let isGuide = line.text.contains("%")
                || ReceiptKeywords.words(in: line.text).contains(where: { word in
                    word.hasPrefix("GUIDE") || word.hasPrefix("SUGGEST")
                })
            if isGuide {
                continue
            }
            // A tip written under the total counts when a later total includes it.
            let firstTotal = lines[boundary].amount?.value ?? Decimal(0)
            let laterTotals = lines[(index + 1)...].compactMap { later in
                (later.role == .total || later.role == .strongTotal) ? later.amount?.value : nil
            }
            if laterTotals.contains(where: { later in ReceiptValidator.matches(later, firstTotal + value) }) {
                return value
            }
        }
        return nil
    }

    /// Uses a "TOTAL TAX" line if there is one, otherwise adds up the tax lines
    /// (for example separate state and city tax).
    private static func findTax(in lines: [AnalyzedLine], notes: inout [String]) -> Decimal? {
        if let taxTotal = firstAmount(in: lines, role: .taxTotal) {
            return taxTotal
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

    /// A line that might be an item.
    struct ItemCandidate {
        var item: ReceiptLineItem
        /// Whether it's counted as a purchase.
        var included: Bool
        /// Could reasonably go either way (regular-price lines, deal lines);
        /// reconciliation may flip it.
        let ambiguous: Bool
        /// The line's text, for notes.
        let label: String
    }

    /// Item candidates: lines with a price above the first subtotal/tax/total line.
    /// - A price line with no name of its own ("2 @ 0.99   1.98") takes the name
    ///   from the line above, if that line has no price.
    /// - Info lines ("REG PRICE 4.99", "YOU SAVE 1.00") are left out, unless the
    ///   amount is negative, which makes them a discount.
    /// - Payment and "TOTAL SAVINGS"-style lines are skipped.
    private static func itemCandidates(in lines: [AnalyzedLine]) -> [ItemCandidate] {
        let summaryIndex = lines.firstIndex(where: { line in
            ReceiptLineRole.summaryRoles.contains(line.role) && line.amount != nil
        })
        let regionEnd = summaryIndex ?? lines.count

        var candidates: [ItemCandidate] = []
        var lineAbove: AnalyzedLine?
        for line in lines[0..<regionEnd] {
            guard let amount = line.amount else {
                lineAbove = hasLetters(line.text) ? line : nil
                continue
            }
            let above = lineAbove
            lineAbove = nil
            if line.role == .payment || line.role == .notATotal || line.role == .tip
                || line.role == .rounding || line.role == .includedTax {
                continue
            }

            let value = amount.value
            if line.role == .discount {
                // Money off. Printed without a minus it's still a deduction, but
                // reconciliation may leave it out if the numbers disagree.
                let name = itemName(from: amount.textBefore)
                candidates.append(makeCandidate(
                    name: name.isEmpty ? "Discount" : name, amount: value < 0 ? value : -value,
                    confidence: line.confidence, included: true, ambiguous: value > 0, label: line.text))
                continue
            }
            if ReceiptKeywords.isDetailOnly(amount.textBefore) {
                if let above = above {
                    // "AVOCADO" then "2 @ 0.99   1.98": the price belongs to the name above.
                    candidates.append(makeCandidate(
                        name: cleanName(above.text), amount: value,
                        confidence: min(above.confidence, line.confidence),
                        included: true, ambiguous: false, label: line.text))
                } else if value < 0 {
                    candidates.append(makeCandidate(
                        name: "Discount", amount: value, confidence: line.confidence,
                        included: true, ambiguous: false, label: line.text))
                } else {
                    // A deal or unit-price line under an item that already has a price,
                    // or a stray price. Left out unless the subtotal says otherwise.
                    candidates.append(makeCandidate(
                        name: itemName(from: line.text), amount: value, confidence: line.confidence,
                        included: false, ambiguous: true, label: line.text))
                }
            } else if line.role == .info {
                let isDiscount = value < 0
                candidates.append(makeCandidate(
                    name: itemName(from: amount.textBefore), amount: value, confidence: line.confidence,
                    included: isDiscount, ambiguous: !isDiscount, label: line.text))
            } else {
                candidates.append(makeCandidate(
                    name: itemName(from: amount.textBefore), amount: value, confidence: line.confidence,
                    included: true, ambiguous: false, label: line.text))
            }
        }
        return candidates
    }

    private static func makeCandidate(name: String, amount: Decimal, confidence: Float,
                                      included: Bool, ambiguous: Bool, label: String) -> ItemCandidate {
        let item = ReceiptLineItem(name: name.isEmpty ? "Item" : name, amount: amount, confidence: confidence)
        return ItemCandidate(item: item, included: included, ambiguous: ambiguous, label: label)
    }

    private static func includedSum(_ candidates: [ItemCandidate]) -> Decimal {
        var sum = Decimal(0)
        for candidate in candidates where candidate.included {
            sum += candidate.item.amount
        }
        return sum
    }

    /// When nothing is labelled subtotal (OCR garbled it), the last counted item may
    /// really be the subtotal. Taken as the subtotal only if its amount equals the
    /// items above it AND those items plus tax match a total on the receipt, so a
    /// real last item that happens to equal the others isn't lost.
    private static func inferSubtotal(from candidates: inout [ItemCandidate], tax: Decimal?,
                                      totals: [Decimal]) -> (value: Decimal, label: String)? {
        let includedIndices = candidates.indices.filter { index in candidates[index].included }
        guard includedIndices.count >= 3, let lastIndex = includedIndices.last else {
            return nil
        }
        let last = candidates[lastIndex]
        var othersSum = Decimal(0)
        for index in includedIndices.dropLast() {
            othersSum += candidates[index].item.amount
        }
        guard last.item.amount > 0, ReceiptValidator.matches(othersSum, last.item.amount) else {
            return nil
        }
        let expectedTotal = othersSum + (tax ?? Decimal(0))
        guard totals.contains(where: { total in ReceiptValidator.matches(total, expectedTotal) }) else {
            return nil
        }
        candidates.remove(at: lastIndex)
        return (value: last.item.amount, label: last.label)
    }

    /// If the counted items don't add up to `target`, tries counting or leaving out
    /// the ambiguous lines (up to 12 of them). Applies the change only if exactly one
    /// smallest set of changes makes them match, and returns a note describing it.
    private static func reconcile(_ candidates: inout [ItemCandidate], target: Decimal,
                                  targetName: String) -> String? {
        let currentSum = includedSum(candidates)
        if ReceiptValidator.matches(currentSum, target) {
            return nil
        }
        let ambiguousIndices = Array(candidates.indices.filter { index in candidates[index].ambiguous }.prefix(12))
        guard !ambiguousIndices.isEmpty else {
            return nil
        }

        var bestMasks: [Int] = []
        var bestFlipCount = Int.max
        let combinationCount = 1 << ambiguousIndices.count
        for mask in 1..<combinationCount {
            var sum = currentSum
            var flipCount = 0
            for (bit, index) in ambiguousIndices.enumerated() where mask & (1 << bit) != 0 {
                flipCount += 1
                let amount = candidates[index].item.amount
                if candidates[index].included {
                    sum -= amount
                } else {
                    sum += amount
                }
            }
            guard ReceiptValidator.matches(sum, target) else {
                continue
            }
            if flipCount < bestFlipCount {
                bestFlipCount = flipCount
                bestMasks = [mask]
            } else if flipCount == bestFlipCount {
                bestMasks.append(mask)
            }
        }

        guard bestMasks.count == 1, let mask = bestMasks.first else {
            return nil
        }
        var changes: [String] = []
        for (bit, index) in ambiguousIndices.enumerated() where mask & (1 << bit) != 0 {
            candidates[index].included.toggle()
            let verb = candidates[index].included ? "counted" : "left out"
            changes.append("\(verb) \"\(candidates[index].label)\"")
        }
        return "To match the \(targetName), " + changes.joined(separator: ", ") + "."
    }

    // MARK: - Names

    // Quantity and deal fragments inside an item name: "2 @ 0.99", "1.25 LB @ 0.99/LB",
    // "2 FOR 5.00", "2/5.00", and a dangling "2 FOR" at the end.
    private static let detailFragmentPattern = Patterns.make(
        #"\b\d+(?:[.,]\d+)?\s*(?:LBS?|KG|OZ|EA|PK|CT)?\s*(?:@|X|×|FOR)\s*[$€£]?\d+(?:[.,]\d+)?(?:\s*/\s*(?:LBS?|KG|OZ|EA))?|\b\d+\s*/\s*[$€£]?\d+[.,]\d{2}\b|\s\d+\s*(?:@|X|×|FOR)\s*$"#,
        caseInsensitive: true
    )

    // Barcodes, PLU and article numbers: 5 or more digits standing alone ("4011", short
    // PLUs, are kept only if they're the whole name). A tax flag right after a code goes too:
    // "GV MILK 007874235186 F".
    private static let codePattern = Patterns.make(#"(?:^|\s)\d{5,}(?:\s+[A-Z]{1,2})?(?=\s|$)"#)
    // Produce PLU codes run 3000–4999 ("4011 BANANAS").
    private static let leadingPLUPattern = Patterns.make(#"^[34]\d{3}\s+(?=[A-Za-z])"#)
    // "2 X BURGER", "2x Burger" → "2× Burger".
    private static let leadingQuantityPattern = Patterns.make(#"^(\d{1,2})\s*[xX×*]\s+(?=[A-Za-z])"#)

    /// The item name from the text before a price, without quantity/deal fragments,
    /// barcodes or tax flags.
    static func itemName(from text: String) -> String {
        var working = text
        working = replace(detailFragmentPattern, in: working, with: " ")
        working = replace(codePattern, in: working, with: " ")
        working = replace(leadingPLUPattern, in: working, with: "")
        working = replace(leadingQuantityPattern, in: working, with: "$1× ")
        let cleaned = cleanName(working)
        return hasLetters(cleaned) ? cleaned : cleanName(text)
    }

    private static func replace(_ pattern: NSRegularExpression, in text: String, with template: String) -> String {
        let length = (text as NSString).length
        return pattern.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: length),
                                                withTemplate: template)
    }

    // MARK: - Merchant

    private static let merchantNoisePattern = Patterns.make(
        #"\b(WELCOME|THANK|THANKS|RECEIPT|INVOICE|TEL|PHONE|FAX|CASHIER|REGISTER|TERMINAL|ORDER|TABLE|SERVER|GUEST|DATE|TIME|TRANS|TRANSACTION|COPY|MERCHANT|HOURS|OPEN|WIFI|PASSWORD|VAT|ABN|GST|NIF|CIF|UST|STEUERNR|KASSE|BON|BELEG|RECHNUNG|QUITTUNG|FACTURA|TICKET|CHECK|SALE|DUPLICATE|REPRINT)\b|\bSTORE\s*(#|NO\b)|WWW\.|HTTPS?:|\.COM\b"#
    )

    private static let contactDetector: NSDataDetector? = {
        let types = NSTextCheckingResult.CheckingType.phoneNumber.rawValue
            | NSTextCheckingResult.CheckingType.address.rawValue
            | NSTextCheckingResult.CheckingType.link.rawValue
            | NSTextCheckingResult.CheckingType.date.rawValue
        return try? NSDataDetector(types: types)
    }()

    /// A name-like line at the top of the first page, before any amounts: the store name
    /// is usually printed biggest, so a clearly taller line wins; otherwise the first one.
    private static func findMerchant(in lines: [AnalyzedLine]) -> String? {
        let header = lines.prefix(while: { line in line.amount == nil }).prefix(8)
        let candidates = header.filter { line in line.pageIndex == 0 && isMerchantCandidate(line.text) }
        guard let first = candidates.first else {
            return nil
        }
        let tallest = candidates.max { a, b in a.height < b.height } ?? first
        let chosen = tallest.height >= first.height * 1.3 ? tallest : first
        return cleanName(chosen.text)
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
        let separators = CharacterSet(charactersIn: " :$€£.-*#")
        return joined.trimmingCharacters(in: separators)
    }
}
