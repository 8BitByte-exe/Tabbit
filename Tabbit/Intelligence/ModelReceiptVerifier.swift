import Foundation

/// What a numbered receipt line is, according to Apple Intelligence.
enum ModelLineKind: String, Equatable, CaseIterable {
    case item
    case discount
    case subtotal
    case tax
    case taxTotal
    case tip
    case total
    case payment
    case savings
    case unitPrice
    case other

    /// Items and discounts are what the items list is made of.
    var isPurchase: Bool {
        return self == .item || self == .discount
    }
}

/// Apple Intelligence's answer for one receipt, before Tabbit checks it.
/// It holds no amounts: those come from the scan (`NumberedReceipt`).
struct ModelReceiptReading: Equatable {
    struct Label: Equatable {
        /// The number in brackets in the prompt.
        var line: Int
        var kind: ModelLineKind
        /// A readable name for an item or discount ("Organic bananas"), otherwise empty.
        var name: String
    }

    /// The brand name ("Best Buy"), or empty.
    var storeName: String
    var labels: [Label]
    /// The receipt says the prices already include tax (VAT, MwSt, "HST included").
    var pricesIncludeTax: Bool
    /// One of SpendCategory's raw values, or empty.
    var category: String
    /// "YYYY-MM-DD", or empty.
    var date: String
}

/// The result of reading a scan with Apple Intelligence.
struct IntelligenceOutcome: Equatable {
    /// The receipt to show: the model's if it adds up at least as well, otherwise the rules'.
    let receipt: Receipt
    /// The model's guess at what the receipt was for (nil if it had none).
    let suggestedCategory: SpendCategory?
    /// True if the model's reading was used for the items and amounts.
    let usedModel: Bool
}

/// The words actually printed on a scan, to check the store name Apple Intelligence gives.
struct ScanEvidence {
    /// Lowercased words and numbers from the OCR text (Vision's other readings included).
    let words: Set<String>
    /// The OCR text lowercased with everything but letters and digits removed.
    let squashed: String

    init(_ scan: ScanResult) {
        self.init(lines: LineGrouper.lines(from: scan))
    }

    init(lines: [TextLine]) {
        var texts: [String] = []
        for line in lines {
            texts.append(line.text)
            for block in line.blocks {
                texts.append(contentsOf: block.alternatives)
            }
        }
        var words: Set<String> = []
        var squashed = ""
        for text in texts {
            words.formUnion(ScanEvidence.words(in: text))
            squashed += ScanEvidence.squash(text) + " "
        }
        self.words = words
        self.squashed = squashed
    }

    /// True if the phrase was printed: enough of its words appear in the scan (allowing
    /// an OCR slip in longer words), or the whole phrase does once spaces are ignored
    /// ("bestbuy.ca" backs up "Best Buy").
    func mentions(_ phrase: String, minimumShare: Double = 0.6) -> Bool {
        let phraseWords = ScanEvidence.words(in: phrase)
        guard !phraseWords.isEmpty else {
            return false
        }
        let squashedPhrase = ScanEvidence.squash(phrase)
        if squashedPhrase.count >= 3 && squashed.contains(squashedPhrase) {
            return true
        }
        let found = phraseWords.filter { word in contains(word) }.count
        return Double(found) / Double(phraseWords.count) >= minimumShare
    }

    private func contains(_ word: String) -> Bool {
        if words.contains(word) {
            return true
        }
        guard word.count >= 5 else {
            return false
        }
        let allowed = word.count >= 8 ? 2 : 1
        return words.contains(where: { printed in
            abs(printed.count - word.count) <= allowed
                && ReceiptKeywords.editDistance(printed, word) <= allowed
        })
    }

    static func words(in text: String) -> [String] {
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in word.count >= 2 }
    }

    static func squash(_ text: String) -> String {
        return String(text.lowercased().unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }.map { scalar in Character(scalar) })
    }
}

/// Turns Apple Intelligence's line labels into a receipt, and checks it.
///
/// The model is good at the messy part: what a line means, which "TOTAL" is the one to
/// pay, abbreviations, the store's name. The layout and the arithmetic keep it honest:
/// 1. Every amount comes from the scan line the model pointed at, never from the model.
/// 2. Purchases are the items part's lines (`NumberedReceipt`). Each has evidence from the
///    layout and keywords, and the model's label adds to it (`modelEvidence`); the lines
///    that add up to the subtotal win (`ItemReconciler`). So the model decides what the
///    layout can't, but a detail line, a savings line or the card slip can't become an item.
/// 3. Subtotal, tax, tip and total are chosen by the arithmetic. The model's labels go
///    first, the keywords are a second opinion, so a "TOTAL TAX" line labelled as the
///    total loses to the TOTAL that equals subtotal + tax.
/// 4. The result is compared with the rules parser's; the model's is used unless the
///    rules' adds up better.
enum ModelReceiptVerifier {

    static let usedNote = "Read with Apple Intelligence on this iPhone. Every amount comes from the scan, and they add up."
    static let usedUncheckedNote = "Read with Apple Intelligence on this iPhone. Every amount comes from the scan, but they don't all add up, so check them."
    static let unavailableNote = "Apple Intelligence couldn't read this receipt, so Tabbit used its built-in rules."
    static let timedOutNote = "Apple Intelligence took too long with this receipt, so Tabbit used its built-in rules."
    static let noItemsNote = "Apple Intelligence found no items on this receipt, so Tabbit used its built-in rules."
    static let rulesAddUpBetterNote = "Tabbit's built-in rules made the amounts add up better than Apple Intelligence's reading, so it used the rules."

    static func evaluate(_ reading: ModelReceiptReading, numbered: NumberedReceipt, rules: Receipt) -> IntelligenceOutcome {
        let evidence = ScanEvidence(lines: numbered.lines)
        let category = suggestedCategory(reading.category)
        let merchant = groundedMerchant(reading.storeName, evidence: evidence)

        guard var receipt = assemble(reading, numbered: numbered) else {
            var fallback = rules
            fallback.merchant = merchant ?? rules.merchant
            fallback.notes.append(noItemsNote)
            return IntelligenceOutcome(receipt: fallback, suggestedCategory: category, usedModel: false)
        }
        receipt.merchant = merchant ?? rules.merchant
        receipt.date = rules.date ?? calendarDate(reading.date)
        // The address, time and payment are read straight from the scan.
        receipt.location = rules.location
        receipt.time = rules.time
        receipt.paymentMethod = rules.paymentMethod
        if receipt.tax == nil && receipt.includedTax == nil {
            receipt.includedTax = rules.includedTax
        }

        let modelScore = RulesReceiptParser.consistencyScore(of: receipt)
        let rulesScore = RulesReceiptParser.consistencyScore(of: rules)
        if modelScore >= rulesScore {
            return IntelligenceOutcome(receipt: receipt, suggestedCategory: category, usedModel: true)
        }
        var fallback = rules
        fallback.merchant = merchant ?? rules.merchant
        fallback.notes.append(rulesAddUpBetterNote)
        return IntelligenceOutcome(receipt: fallback, suggestedCategory: category, usedModel: false)
    }

    // MARK: - Assembling

    /// What one Apple Intelligence label counts for or against a line being a purchase: as much
    /// as a clean item line in the price column. So the model settles the lines the layout and
    /// keywords aren't sure about, and where it disagrees with clear evidence, the arithmetic decides.
    static let modelEvidence = 6

    /// One numbered line with the model's label and the keywords' opinion, for choosing the
    /// subtotal, tax, tip and total.
    private struct Line {
        let entry: NumberedReceipt.Entry
        /// The model's label (nil if it skipped the line).
        let modelKind: ModelLineKind?
        /// What the keywords make of the line.
        let ruleKind: ModelLineKind

        var kind: ModelLineKind {
            return modelKind ?? ruleKind
        }
    }

    /// A line that may be a purchase: the layout and keywords' candidate, plus the model's label.
    private struct Purchase {
        let candidate: RulesReceiptParser.ItemCandidate
        /// The numbered line, if the model was shown it (detail lines aren't numbered).
        let entry: NumberedReceipt.Entry?
        let label: ModelReceiptReading.Label?
        let evidence: Int
    }

    /// A possible value for the subtotal, tax, tip or total.
    private struct Option {
        let value: Decimal?
        /// Backed by the model's labels (+1), only by the keywords (0), or going against them (-1).
        let prior: Int
        let note: String?
        /// For "no tax": the printed tax that's already in the prices.
        let included: Decimal?

        init(_ value: Decimal?, prior: Int, note: String? = nil, included: Decimal? = nil) {
            self.value = value
            self.prior = prior
            self.note = note
            self.included = included
        }
    }

    /// Tips are usually a round share of the bill.
    private static let usualTipPercents: [Decimal] = [10, 12, 15, 18, 20, 22, 25]

    /// The model's first label for each numbered line (it sometimes repeats itself).
    private static func firstLabels(_ reading: ModelReceiptReading,
                                    numbered: NumberedReceipt) -> [Int: ModelReceiptReading.Label] {
        var labels: [Int: ModelReceiptReading.Label] = [:]
        for label in reading.labels where labels[label.line] == nil && numbered.entry(number: label.line) != nil {
            labels[label.line] = label
        }
        return labels
    }

    /// The model's receipt, or nil if it found no items at all.
    static func assemble(_ reading: ModelReceiptReading, numbered: NumberedReceipt) -> Receipt? {
        let labels = firstLabels(reading, numbered: numbered)

        let firstSummary = numbered.entries.firstIndex(where: { entry in
            ReceiptLineRole.summaryRoles.contains(entry.role)
        }) ?? numbered.entries.count
        let lines: [Line] = numbered.entries.enumerated().map { position, entry in
            Line(
                entry: entry,
                modelKind: labels[entry.number]?.kind,
                ruleKind: ruleKind(for: entry.role, amount: entry.amount, beforeSummary: position < firstSummary)
            )
        }

        // Purchases: what the layout and keywords found, with the model's label as more evidence.
        var entryByLine: [Int: NumberedReceipt.Entry] = [:]
        for entry in numbered.entries {
            entryByLine[entry.lineIndex] = entry
        }
        let purchases: [Purchase] = numbered.candidates.map { candidate in
            let entry = entryByLine[candidate.lineIndex]
            let label = entry.flatMap { found in labels[found.number] }
            var evidence = candidate.evidence
            if let label = label {
                evidence += label.kind.isPurchase ? modelEvidence : -modelEvidence
            }
            return Purchase(candidate: candidate, entry: entry, label: label, evidence: evidence)
        }
        guard !purchases.isEmpty else {
            return nil
        }
        let choices = purchases.map { purchase in
            ItemReconciler.Choice(amount: purchase.candidate.item.amount, alternative: purchase.candidate.alternative,
                                  evidence: purchase.evidence)
        }
        let moves = ItemReconciler.moves(for: choices)
        let fixes = ItemReconciler.reachableSums(choices, moves: moves)

        var paidAmounts = numbered.paidAmounts
        for line in lines where (line.kind == .payment || line.ruleKind == .payment) && line.entry.amount > 0 {
            paidAmounts.insert(line.entry.amount)
        }
        let taxRates = lines.filter { line in line.kind == .tax || line.ruleKind == .tax }.compactMap { line in
            ReceiptDetailsParser.percent(in: line.entry.text)
        }

        let subtotals = options(lines, kind: .subtotal, none: Option(nil, prior: hasModel(lines, .subtotal) ? -1 : 0))
        let totals = options(lines, kind: .total, none: nil)
        let tips = [Option(Decimal(0), prior: 0)] + options(lines, kind: .tip, none: nil)
        let taxes = taxOptions(lines, pricesIncludeTax: reading.pricesIncludeTax)

        let totalChoices = totals.isEmpty ? [Option(nil, prior: 0)] : totals
        var bestScore = Int.min
        var best: (subtotal: Option, tax: Option, tip: Option, total: Option, fix: ItemReconciler.Fix?)?
        for subtotal in subtotals {
            for total in totalChoices {
                for tax in taxes {
                    for tip in tips {
                        let taxValue = tax.value ?? 0
                        let tipValue = tip.value ?? 0
                        var score = subtotal.prior + total.prior + tax.prior + tip.prior
                        var fix: ItemReconciler.Fix?
                        if let subtotalValue = subtotal.value {
                            fix = ItemReconciler.lookup(subtotalValue, in: fixes)
                            if let found = fix {
                                score += found.cost == 0 ? 3 : 2
                            } else {
                                score -= 2
                            }
                            if let totalValue = total.value {
                                score += ReceiptValidator.matches(subtotalValue + taxValue + tipValue, totalValue) ? 4 : -3
                            } else {
                                score -= 4
                            }
                        } else if let totalValue = total.value {
                            fix = ItemReconciler.lookup(totalValue - taxValue - tipValue, in: fixes)
                            if let found = fix {
                                score += found.cost == 0 ? 4 : 3
                            } else {
                                score -= 3
                            }
                        } else {
                            score -= 4
                        }
                        score += plausibility(subtotal: subtotal.value, tax: taxValue, tip: tipValue,
                                              total: total.value, paid: paidAmounts, taxRates: taxRates)
                        if score > bestScore {
                            bestScore = score
                            best = (subtotal: subtotal, tax: tax, tip: tip, total: total, fix: fix)
                        }
                    }
                }
            }
        }
        guard let chosen = best else {
            return nil
        }

        var counted = choices.map { choice in ItemReconciler.isCounted(choice) }
        var swapped: Set<Int> = []
        var notes: [String] = []
        if let fix = chosen.fix, fix.cost > 0 {
            var changes: [String] = []
            for move in ItemReconciler.applied(fix, moves: moves) {
                let candidate = purchases[move.index].candidate
                if move.swap {
                    swapped.insert(move.index)
                    let amount = candidate.alternative ?? candidate.item.amount
                    changes.append("read \"\(candidate.label)\" as \(MoneyInput.editText(amount))")
                } else {
                    counted[move.index].toggle()
                    changes.append("\(counted[move.index] ? "counted" : "left out") \"\(candidate.label)\"")
                }
            }
            let target = chosen.subtotal.value == nil ? "total" : "subtotal"
            notes.append("To match the \(target), " + changes.joined(separator: ", ") + ".")
        }
        if let note = chosen.tax.note {
            notes.append(note)
        }

        var items: [ReceiptLineItem] = []
        var computed: [String] = []
        for (index, purchase) in purchases.enumerated() where counted[index] {
            var printed = purchase.candidate.item
            if swapped.contains(index), let alternative = purchase.candidate.alternative {
                printed = RulesReceiptParser.withAmount(printed, alternative)
            } else if purchase.candidate.isComputed {
                computed.append(purchase.candidate.label)
            }
            var item = ReceiptLineItem(name: displayName(for: purchase, printed: printed.name, numbered: numbered),
                                       amount: printed.amount, confidence: printed.confidence)
            item.quantity = printed.quantity
            item.unitPrice = printed.unitPrice
            items.append(item)
        }
        guard !items.isEmpty else {
            return nil
        }
        if computed.count == 1, let text = computed.first {
            notes.append("Worked out the price of \"\(text)\" from its quantity and unit price.")
        } else if computed.count > 1 {
            notes.append("Worked out \(computed.count) prices from their quantity and unit price.")
        }

        let tax = chosen.tax.value.flatMap { value in value == 0 ? nil : value }
        let tip = chosen.tip.value.flatMap { value in value == 0 ? nil : value }
        var receipt = Receipt(
            merchant: nil,
            date: nil,
            lineItems: items,
            subtotal: chosen.subtotal.value,
            tax: tax,
            total: chosen.total.value,
            tip: tip,
            includedTax: chosen.tax.value == 0 ? chosen.tax.included : nil,
            parser: .appleIntelligence,
            notes: []
        )
        if receipt.total == nil && receipt.subtotal == nil && receipt.tax == nil && receipt.tip == nil,
           let only = RulesReceiptParser.singleAmountTotal(of: items) {
            receipt.total = only
            notes.append(RulesReceiptParser.singleAmountNote)
        }
        let addsUp = !ReceiptValidator.checks(for: receipt).contains(where: { check in !check.passed })
            && receipt.total != nil
        receipt.notes = [addsUp ? usedNote : usedUncheckedNote] + notes
        return receipt
    }

    /// What the keywords make of a line, in the model's terms.
    static func ruleKind(for role: ReceiptLineRole, amount: Decimal, beforeSummary: Bool) -> ModelLineKind {
        switch role {
        case .subtotal: return .subtotal
        case .taxTotal: return .taxTotal
        case .tax: return .tax
        case .includedTax: return .other
        case .strongTotal, .total: return .total
        case .notATotal: return .savings
        case .tip: return .tip
        case .payment: return .payment
        case .unitPrice: return .unitPrice
        case .discount: return .discount
        case .rounding: return .other
        case .info: return amount < 0 ? .discount : .savings
        case .other: return beforeSummary ? .item : .other
        }
    }

    private static func hasModel(_ lines: [Line], _ kind: ModelLineKind) -> Bool {
        return lines.contains(where: { line in line.kind == kind })
    }

    /// The amounts of the lines labelled `kind` (prior 1), then of lines only the keywords
    /// call that (prior 0), each amount once, biggest first.
    private static func options(_ lines: [Line], kind: ModelLineKind, none: Option?) -> [Option] {
        var result: [Option] = []
        let primary = lines.filter { line in line.kind == kind }.map { line in line.entry.amount }
        let secondary = lines.filter { line in line.kind != kind && line.ruleKind == kind }.map { line in line.entry.amount }
        for (values, prior) in [(primary, 1), (secondary, 0)] {
            for value in values.sorted(by: >) where value > 0 {
                if !result.contains(where: { option in option.value == value }) {
                    result.append(Option(value, prior: prior))
                }
            }
        }
        if let none = none {
            result.append(none)
        }
        return result
    }

    /// Tax options: all the tax lines added up, a "TOTAL TAX" line, single tax lines
    /// (a receipt may repeat its tax in a footer), the keywords' version, and no tax
    /// (tax already in the prices).
    private static func taxOptions(_ lines: [Line], pricesIncludeTax: Bool) -> [Option] {
        var result: [Option] = []
        func add(_ value: Decimal, prior: Int, note: String? = nil) {
            if value > 0 && !result.contains(where: { option in option.value == value }) {
                result.append(Option(value, prior: prior, note: note))
            }
        }
        let taxLines = lines.filter { line in line.kind == .tax }.map { line in line.entry.amount }
        let totalLines = lines.filter { line in line.kind == .taxTotal }.map { line in line.entry.amount }
        let ruleTaxLines = lines.filter { line in line.ruleKind == .tax }.map { line in line.entry.amount }
        let ruleTotalLines = lines.filter { line in line.kind != .taxTotal && line.ruleKind == .taxTotal }
            .map { line in line.entry.amount }

        let taxSum = taxLines.reduce(Decimal(0), +)
        add(taxSum, prior: 1, note: taxLines.count > 1 ? "Added up \(taxLines.count) tax lines." : nil)
        for value in totalLines {
            add(value, prior: 1)
        }
        for value in taxLines where taxLines.count > 1 {
            add(value, prior: 0)
        }
        let ruleSum = ruleTaxLines.reduce(Decimal(0), +)
        add(ruleSum, prior: 0, note: ruleTaxLines.count > 1 ? "Added up \(ruleTaxLines.count) tax lines." : nil)
        for value in ruleTotalLines + ruleTaxLines {
            add(value, prior: 0)
        }

        let printedTax = result.first?.value ?? 0
        if printedTax > 0 {
            let note = "The prices already include \(MoneyInput.editText(printedTax)) tax, so it isn't added again."
            result.append(Option(Decimal(0), prior: pricesIncludeTax ? 1 : -1, note: note, included: printedTax))
        } else {
            result.append(Option(Decimal(0), prior: 0))
        }
        return result
    }

    /// Points for a combination that looks like a real receipt, and against one that can't be:
    /// - the tax is always less than the total, and rarely more than 30% of what it's on;
    /// - a printed rate ("HST 13%") that gives the tax backs it up;
    /// - tips are usually 10, 15, 18, 20… percent of the bill, before or after tax, and rarely
    ///   more than 40% of it;
    /// - a total that equals a card payment is confirmed by it.
    private static func plausibility(subtotal: Decimal?, tax: Decimal, tip: Decimal, total: Decimal?,
                                     paid: Set<Decimal>, taxRates: [Decimal]) -> Int {
        var score = 0
        var base = subtotal
        if base == nil, let total = total {
            base = total - tax - tip
        }
        if tax > 0 {
            if let total = total, tax >= total {
                score -= 6
            }
            if let base = base, base > 0 {
                if tax * 10 > base * 3 {
                    score -= 3
                } else if matchesRate(tax, base: base, rates: taxRates) {
                    score += 1
                }
            }
        }
        if tip > 0, let base = base, base > 0 {
            if tip * 10 > base * 4 {
                score -= 2
            } else if isUsualTip(tip, base: base) || isUsualTip(tip, base: base + tax) {
                score += 1
            }
        }
        if let total = total, paid.contains(where: { amount in ReceiptValidator.matches(amount, total) }) {
            score += 1
        }
        return score
    }

    /// True if one printed rate, or all of them together (GST 5% + PST 7%), gives the tax within 3 cents.
    private static func matchesRate(_ tax: Decimal, base: Decimal, rates: [Decimal]) -> Bool {
        guard !rates.isEmpty else {
            return false
        }
        let combined = rates.reduce(Decimal(0), +)
        let tolerance = Decimal(3) / 100
        for rate in rates + [combined] {
            let expected = base * rate / 100
            let difference = expected - tax
            if (difference < 0 ? -difference : difference) <= tolerance {
                return true
            }
        }
        return false
    }

    /// True if the tip is a usual whole percentage of `base`, to the cent.
    private static func isUsualTip(_ tip: Decimal, base: Decimal) -> Bool {
        let tolerance = Decimal(1) / 100
        for percent in usualTipPercents {
            let expected = base * percent / 100
            let difference = expected - tip
            if (difference < 0 ? -difference : difference) <= tolerance {
                return true
            }
        }
        return false
    }

    // MARK: - Names

    /// The model's name if it labelled the line a purchase and the name plausibly spells out
    /// text printed on the line or just above it (gas receipts print the grade above the fuel
    /// line), otherwise the printed name, tidied the way the rules parser does it.
    private static func displayName(for purchase: Purchase, printed: String, numbered: NumberedReceipt) -> String {
        guard let label = purchase.label, label.kind.isPurchase, let entry = purchase.entry else {
            return printed
        }
        let name = tidyName(label.name)
        let nearby = ([entry.textBefore] + numbered.textsAbove(entry, count: 2)).joined(separator: " ")
        guard !name.isEmpty, name.count <= 48, isPlausibleName(name, printed: nearby) else {
            return printed
        }
        if purchase.candidate.item.amount > 0 {
            return LineAmountParser.name(name, quantity: purchase.candidate.item.quantity)
        }
        return name
    }

    /// Trims quotes and spaces. A name in all lower case ("chips lime black pepper") gets
    /// capital letters, the way shelf labels write them.
    static func tidyName(_ name: String) -> String {
        let quotes = CharacterSet(charactersIn: "\"“”")
        let trimmed = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(quotes))
        let words = trimmed.split(separator: " ", omittingEmptySubsequences: true).map { word in String(word) }
        guard trimmed.rangeOfCharacter(from: .uppercaseLetters) == nil else {
            return words.joined(separator: " ")
        }
        return words.map { word -> String in
            String(word.prefix(1)).uppercased() + String(word.dropFirst())
        }.joined(separator: " ")
    }

    /// True if the model's name could be a rewrite of the printed text: one of its words
    /// spells out a printed word ("BNNA" → "Bananas", "ORG" → "Organic") or the other way round.
    static func isPlausibleName(_ name: String, printed: String) -> Bool {
        let nameWords = ScanEvidence.words(in: name).filter { word in word.rangeOfCharacter(from: .letters) != nil }
        let printedWords = ScanEvidence.words(in: printed).filter { word in
            word.rangeOfCharacter(from: .letters) != nil
        }
        for printedWord in printedWords {
            for nameWord in nameWords {
                if isAbbreviation(printedWord, of: nameWord) || isAbbreviation(nameWord, of: printedWord) {
                    return true
                }
            }
        }
        return false
    }

    /// Same first letter, and every letter of `short` appears in `long` in order.
    private static func isAbbreviation(_ short: String, of long: String) -> Bool {
        guard let first = short.first, first == long.first, short.count <= long.count else {
            return false
        }
        var index = long.startIndex
        for character in short {
            guard let found = long[index...].firstIndex(of: character) else {
                return false
            }
            index = long.index(after: found)
        }
        return true
    }

    // MARK: - Store, category, date

    static func groundedMerchant(_ name: String?, evidence: ScanEvidence) -> String? {
        guard let name = name else {
            return nil
        }
        let quotes = CharacterSet(charactersIn: "\"“”")
        let tidied = RulesReceiptParser.storeName(from: name.trimmingCharacters(in: quotes))
        guard !tidied.isEmpty, tidied.count <= 40, evidence.mentions(tidied, minimumShare: 0.5) else {
            return nil
        }
        return tidied
    }

    static func suggestedCategory(_ raw: String?) -> SpendCategory? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let lowered = raw.lowercased()
        let match = SpendCategory.allCases.first(where: { category in
            category.rawValue.lowercased() == lowered || category.title.lowercased() == lowered
        })
        guard let category = match, category != .other else {
            return nil
        }
        return category
    }

    /// "2026-11-03" as a calendar date, if it's a plausible purchase date.
    static func calendarDate(_ text: String?) -> CalendarDate? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        let parts = text.split(separator: "-").map { part in Int(part) }
        guard parts.count == 3, let year = parts[0], let month = parts[1], let day = parts[2],
              (2000...2100).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }
        let date = CalendarDate(year: year, month: month, day: day)
        guard let value = date.dateValue, value <= Date().addingTimeInterval(2 * 86_400) else {
            return nil
        }
        return date
    }

    // MARK: - Trace

    /// What the model said, for Export Scan Data.
    static func trace(of reading: ModelReceiptReading, numbered: NumberedReceipt, outcome: IntelligenceOutcome,
                      seconds: Double) -> IntelligenceTrace {
        // One entry per numbered line: the model sometimes repeats its whole answer.
        var seen: Set<Int> = []
        var labels: [String] = []
        for label in reading.labels where !seen.contains(label.line) {
            seen.insert(label.line)
            let text = numbered.entry(number: label.line)?.text ?? "?"
            let name = label.name.isEmpty ? "" : " → \(label.name)"
            labels.append("[\(label.line)] \(label.kind.rawValue): \(text)\(name)")
        }
        return IntelligenceTrace(
            outcome: outcome.usedModel ? "used" : "rules",
            seconds: seconds,
            storeName: reading.storeName,
            category: reading.category,
            date: reading.date,
            pricesIncludeTax: reading.pricesIncludeTax,
            labels: labels
        )
    }
}
