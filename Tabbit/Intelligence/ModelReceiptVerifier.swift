import Foundation

/// What Apple Intelligence read from a receipt, before Tabbit checks it.
/// Amounts are text, exactly as the model wrote them.
struct ModelReceiptDraft: Equatable {
    struct Item: Equatable {
        /// The item's text as printed ("ORG BNNA 4011").
        var printedText: String
        /// A readable name ("Organic bananas").
        var name: String
        /// The line's price as printed ("1.29", "-0.50").
        var price: String
    }

    var merchant: String?
    /// "YYYY-MM-DD", if a date is printed.
    var date: String?
    var items: [Item]
    var subtotal: String?
    var tax: String?
    var tip: String?
    var total: String?
    /// The receipt says the prices already include tax (VAT, MwSt, IVA, TVA, BTW).
    var pricesIncludeTax: Bool
    /// One of SpendCategory's raw values.
    var category: String?
}

/// The result of reading a scan with Apple Intelligence.
struct IntelligenceOutcome: Equatable {
    /// The receipt to show: the model's if it checked out, otherwise the rules'.
    let receipt: Receipt
    /// The model's guess at what the receipt was for (nil if it had none).
    let suggestedCategory: SpendCategory?
}

/// The text and amounts actually printed on a scan.
struct ScanEvidence {
    /// Every amount found in the OCR text (positive values, in cents).
    let amountCents: Set<Int>
    /// Lowercased words and numbers from the OCR text.
    let words: Set<String>
    /// The OCR text lowercased with everything but letters and digits removed.
    let squashed: String

    init(_ scan: ScanResult) {
        var texts: [String] = []
        for block in scan.blocks {
            texts.append(block.text)
            texts.append(contentsOf: block.alternatives)
        }
        // Lines joined left to right, so "BANANAS" and "1.29" in separate blocks still count.
        texts.append(contentsOf: LineGrouper.lines(from: scan).map { line in line.text })

        var cents: Set<Int> = []
        var words: Set<String> = []
        var squashed = ""
        for text in texts {
            for amount in AmountParser.allAmounts(in: text) {
                cents.insert(Money.cents(amount))
            }
            words.formUnion(ScanEvidence.words(in: text))
            squashed += ScanEvidence.squash(text) + " "
        }
        self.amountCents = cents
        self.words = words
        self.squashed = squashed
    }

    /// True if this amount (or its positive value, for discounts) is printed on the receipt.
    func contains(amount: Decimal) -> Bool {
        let cents = Money.cents(amount)
        return amountCents.contains(abs(cents))
    }

    /// True if the phrase was printed: most of its words appear in the scan, or the
    /// whole phrase does once spaces and punctuation are ignored.
    func mentions(_ phrase: String) -> Bool {
        let phraseWords = ScanEvidence.words(in: phrase)
        guard !phraseWords.isEmpty else {
            return false
        }
        let squashedPhrase = ScanEvidence.squash(phrase)
        if squashedPhrase.count >= 3 && squashed.contains(squashedPhrase) {
            return true
        }
        let found = phraseWords.filter { word in words.contains(word) }.count
        return Double(found) / Double(phraseWords.count) >= 0.6
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

/// Checks Apple Intelligence's reading against the scan before Tabbit uses it.
///
/// The model is good at the messy parts (which lines are items, abbreviations, the
/// store's name), but a language model can misread or invent a number. So:
/// 1. Every amount it reports must be printed on the receipt.
/// 2. Every item must match text on the receipt.
/// 3. The numbers must add up (`ReceiptValidator`): items = subtotal, subtotal + tax + tip = total.
/// If any check fails, the rules parser's result is used instead, and a note says why.
/// The store name and category are taken from the model when they check out, either way.
enum ModelReceiptVerifier {

    static let usedNote = "Read with Apple Intelligence on this iPhone. Every amount was found on the receipt, and they add up."
    static let unavailableNote = "Apple Intelligence couldn't read this receipt, so Tabbit used its built-in rules."

    static func evaluate(_ draft: ModelReceiptDraft, scan: ScanResult, rules: Receipt) -> IntelligenceOutcome {
        let evidence = ScanEvidence(scan)
        let category = suggestedCategory(draft.category)
        let merchant = groundedMerchant(draft.merchant, evidence: evidence)

        switch build(draft, evidence: evidence, rules: rules) {
        case .success(var receipt):
            if receipt.merchant == nil {
                receipt.merchant = rules.merchant
            }
            return IntelligenceOutcome(receipt: receipt, suggestedCategory: category)
        case .failure(let problem):
            var receipt = rules
            if let merchant = merchant {
                receipt.merchant = merchant
            }
            receipt.notes.append("Apple Intelligence's reading didn't check out (\(problem.text)), so Tabbit used its built-in rules.")
            return IntelligenceOutcome(receipt: receipt, suggestedCategory: category)
        }
    }

    struct Problem: Error, Equatable {
        let text: String
    }

    /// The model's receipt, if it passes every check.
    static func build(_ draft: ModelReceiptDraft, evidence: ScanEvidence, rules: Receipt) -> Result<Receipt, Problem> {
        var items: [ReceiptLineItem] = []
        for item in draft.items {
            let printed = item.printedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let price = MoneyInput.parse(item.price) else {
                return .failure(Problem(text: "“\(item.price)” isn't a price"))
            }
            if price == 0 {
                continue
            }
            guard evidence.contains(amount: price) else {
                return .failure(Problem(text: "\(MoneyInput.editText(price)) isn't on the receipt"))
            }
            guard evidence.mentions(printed) || evidence.mentions(item.name) else {
                return .failure(Problem(text: "“\(printed.isEmpty ? item.name : printed)” isn't on the receipt"))
            }
            items.append(ReceiptLineItem(name: displayName(for: item), amount: price,
                                         confidence: rulesConfidence(for: price, in: rules)))
        }
        guard !items.isEmpty else {
            return .failure(Problem(text: "it found no items"))
        }

        var amounts: [String: Decimal] = [:]
        for (key, text) in [("subtotal", draft.subtotal), ("tax", draft.tax), ("tip", draft.tip), ("total", draft.total)] {
            guard let text = text, let value = MoneyInput.parse(text) else {
                continue
            }
            if value == 0 && key != "total" {
                continue
            }
            guard evidence.contains(amount: value) else {
                return .failure(Problem(text: "the \(key) \(MoneyInput.editText(value)) isn't on the receipt"))
            }
            amounts[key] = value
        }
        guard let total = amounts["total"], total != 0 else {
            return .failure(Problem(text: "it found no total"))
        }

        var notes = [usedNote]
        var tax = amounts["tax"]
        let tip = amounts["tip"] ?? 0
        let itemsTotal = items.reduce(Decimal(0)) { sum, item in sum + item.amount }
        // Tax that's already in the prices (usual in Europe) mustn't be added again.
        if let foundTax = tax {
            let base = amounts["subtotal"] ?? itemsTotal
            let addsUpWithout = ReceiptValidator.matches(base + tip, total)
            let addsUpWith = ReceiptValidator.matches(base + foundTax + tip, total)
            if addsUpWithout && (draft.pricesIncludeTax || !addsUpWith) {
                tax = nil
                notes.append("The prices already include \(MoneyInput.editText(foundTax)) tax, so it isn't added again.")
            }
        }

        let receipt = Receipt(
            merchant: groundedMerchant(draft.merchant, evidence: evidence),
            date: rules.date ?? calendarDate(draft.date),
            lineItems: items,
            subtotal: amounts["subtotal"],
            tax: tax,
            total: total,
            tip: amounts["tip"],
            parser: .appleIntelligence,
            notes: notes
        )
        let checks = ReceiptValidator.checks(for: receipt)
        if let failed = checks.first(where: { check in !check.passed }) {
            return .failure(Problem(text: describe(failed)))
        }
        return .success(receipt)
    }

    // MARK: - Pieces

    /// The model's readable name, or the printed text tidied up if the name is missing or odd.
    private static func displayName(for item: ModelReceiptDraft.Item) -> String {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && name.count <= 48 {
            return name
        }
        let printed = RulesReceiptParser.itemName(from: item.printedText)
        return printed.isEmpty ? item.printedText : printed
    }

    /// Vision's confidence for the rules item with the same price, so unsure names keep their "?" mark.
    private static func rulesConfidence(for price: Decimal, in rules: Receipt) -> Float? {
        return rules.lineItems.first(where: { item in item.amount == price })?.confidence
    }

    static func groundedMerchant(_ merchant: String?, evidence: ScanEvidence) -> String? {
        guard let merchant = merchant?.trimmingCharacters(in: .whitespacesAndNewlines),
              !merchant.isEmpty, merchant.count <= 60, evidence.mentions(merchant) else {
            return nil
        }
        return merchant
    }

    static func suggestedCategory(_ raw: String?) -> SpendCategory? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else {
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

    private static func describe(_ check: ReceiptCheck) -> String {
        let printed = MoneyInput.editText(check.printed)
        let computed = MoneyInput.editText(check.computed)
        switch check.kind {
        case .itemsMatchSubtotal:
            return "the items add up to \(computed), but the subtotal is \(printed)"
        case .subtotalPlusTaxMatchesTotal, .itemsPlusTaxMatchesTotal:
            return "the amounts add up to \(computed), but the total is \(printed)"
        }
    }
}
