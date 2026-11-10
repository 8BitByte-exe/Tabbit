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

    /// The tilt guess whose lines add up best, so Apple Intelligence reads the same lines.
    static func bestSlopeChoice(for scan: ScanResult) -> Int {
        let count = LineGrouper.slopeChoiceCount(for: scan)
        guard count > 1 else {
            return 0
        }
        let parser = RulesReceiptParser()
        var bestChoice = 0
        var bestScore = Int.min
        for choice in 0..<count {
            let score = consistencyScore(of: parser.parse(scan, slopeChoice: choice))
            if score > bestScore {
                bestChoice = choice
                bestScore = score
            }
        }
        return bestChoice
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
        let lines = RulesReceiptParser.analyze(LineGrouper.lines(from: scan, slopeChoice: slopeChoice))
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
        let paid = RulesReceiptParser.paidAmount(in: lines, after: firstTotalIndex)
        var total = RulesReceiptParser.findTotal(in: lines, expected: expectedTotal, paid: paid)
        if total == nil, let paid = paid {
            // No total line could be read, but the payment says what was paid.
            total = paid
            notes.append("Took the total from the payment, \(MoneyInput.editText(paid)).")
        }

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
        var includedTax: Decimal?
        if let included = RulesReceiptParser.firstAmount(in: lines, role: .includedTax), tax == nil {
            includedTax = included
            if !notes.contains(where: { note in note.hasPrefix("The prices already include") }) {
                notes.append("The prices already include \(MoneyInput.editText(included)) tax.")
            }
        } else if tax == nil, notes.contains(where: { note in note.hasPrefix("The prices already include") }) {
            includedTax = RulesReceiptParser.firstAmount(in: taxLines, role: .tax)
                ?? RulesReceiptParser.firstAmount(in: taxLines, role: .taxTotal)
        }

        // Tax is always less than what it's added to; a bigger "tax" is a misread line.
        if let foundTax = tax, foundTax > 0, let base = subtotal ?? total, foundTax >= base {
            tax = nil
            fees -= foundTax
            notes.append("Left out the tax line (\(MoneyInput.editText(foundTax))): tax is always less than the total.")
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

        let counted = candidates.filter { candidate in candidate.included }
        let computed = counted.filter { candidate in candidate.isComputed }
        if computed.count == 1, let line = computed.first {
            notes.append("Worked out the price of \"\(line.label)\" from its quantity and unit price.")
        } else if computed.count > 1 {
            notes.append("Worked out \(computed.count) prices from their quantity and unit price.")
        }
        let items = counted.map { candidate in candidate.item }
        if total == nil && subtotal == nil && tax == nil && tip == nil,
           let only = RulesReceiptParser.singleAmountTotal(of: items) {
            total = only
            notes.append(RulesReceiptParser.singleAmountNote)
        }
        let merchant = RulesReceiptParser.findMerchant(in: lines)
        let texts = lines.map { line in line.text }
        let date = ReceiptDateParser.firstDate(in: texts)

        return Receipt(
            merchant: merchant,
            date: date,
            lineItems: items,
            subtotal: subtotal,
            tax: tax,
            total: total,
            tip: tip,
            location: RulesReceiptParser.findLocation(in: lines),
            time: ReceiptDetailsParser.time(in: texts),
            paymentMethod: ReceiptDetailsParser.paymentMethod(in: texts),
            includedTax: includedTax,
            parser: .rules,
            notes: notes
        )
    }

    /// A card slip or ticket that prints one amount ("Amount: $13.50") and no subtotal, tax or
    /// total: that amount is what was paid. Nil unless there's exactly one positive item.
    static func singleAmountTotal(of items: [ReceiptLineItem]) -> Decimal? {
        guard items.count == 1, let amount = items.first?.amount, amount > 0 else {
            return nil
        }
        return amount
    }

    static let singleAmountNote = "Only one amount is printed, so it's the total."

    // MARK: - Lines

    /// The receipt's lines with their roles, amounts and where the amounts sit.
    static func analyze(_ textLines: [TextLine]) -> [AnalyzedLine] {
        var lines = textLines.map { line in AnalyzedLine(line) }
        let columns = ReceiptLayout.inPriceColumn(textLines, hasAmount: lines.map { line in line.amount != nil })
        for index in lines.indices where index < columns.count {
            lines[index].inPriceColumn = columns[index]
        }
        return lines
    }

    struct AnalyzedLine {
        let text: String
        let pageIndex: Int
        let amount: AmountParser.ParsedAmount?
        /// Quantity, unit price and a second reading of the amount, for lines that may be items.
        let detail: LineAmount?
        let role: ReceiptLineRole
        /// The lowest Vision confidence among the line's blocks.
        let confidence: Float
        /// Text height (normalized), to spot the big store name at the top.
        let height: CGFloat
        /// The amount ends in the receipt's price column (see `ReceiptLayout`).
        var inPriceColumn: Bool = true

        init(_ line: TextLine) {
            self.text = line.text
            self.pageIndex = line.pageIndex
            let heights = line.blocks.map { block in block.boundingBox.height }
            self.height = heights.max() ?? line.boundingBox.height

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

            // Lines that may be items also read quantities and unit prices: "2 @ 1.99", "2 BANANAS 1.99/EA".
            if RulesReceiptParser.itemRoles.contains(role), let detail = LineAmountParser.read(line.text) {
                self.detail = detail
                self.amount = AmountParser.ParsedAmount(value: detail.value, textBefore: detail.textBefore)
            } else {
                self.detail = nil
                self.amount = AmountParser.trailingAmount(in: line.text)
            }

            let confidences = line.blocks.map { block in block.confidence }
            self.confidence = confidences.min() ?? 1
        }
    }

    /// Roles of lines that can be purchases (or money off them).
    static let itemRoles: [ReceiptLineRole] = [.other, .info, .discount]

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
    private static func findTotal(in lines: [AnalyzedLine], expected: Decimal?, paid: Decimal?) -> Decimal? {
        // The total that adds up wins; then the one the payment confirms.
        for target in [expected, paid] {
            guard let target = target else {
                continue
            }
            for line in lines where line.role == .total || line.role == .strongTotal {
                if let value = line.amount?.value, ReceiptValidator.matches(value, target) {
                    return value
                }
            }
        }
        let strong = lines.compactMap { line in line.role == .strongTotal ? line.amount?.value : nil }
        let plain = lines.compactMap { line in line.role == .total ? line.amount?.value : nil }
        let candidates = strong.isEmpty ? plain : strong
        return candidates.max()
    }

    /// What the customer paid, from the payment lines after the first total: a single card
    /// payment, or cash given minus the change. Nil if it isn't clear.
    static func paidAmount(in lines: [AnalyzedLine], after firstTotalIndex: Int?) -> Decimal? {
        let start = (firstTotalIndex ?? -1) + 1
        guard start < lines.count else {
            return nil
        }
        var card: [Decimal] = []
        var cash = Decimal(0)
        var change = Decimal(0)
        for line in lines[start...] where line.role == .payment {
            guard let value = line.amount?.value, value > 0 else {
                continue
            }
            let words = ReceiptKeywords.words(in: line.text)
            if words.contains(where: { word in changeWords.contains(word) }) {
                change += value
            } else if words.contains(where: { word in cashWords.contains(word) }) {
                cash += value
            } else if words.contains(where: { word in cardWords.contains(word) }) {
                card.append(value)
            }
        }
        if cash > 0 {
            return card.isEmpty && cash > change ? cash - change : nil
        }
        let distinct = Set(card)
        return distinct.count == 1 ? distinct.first : nil
    }

    private static let changeWords: Set<String> = [
        "CHANGE", "RÜCKGELD", "RUCKGELD", "RUECKGELD", "WECHSELGELD", "CAMBIO", "RENDU", "RESTO",
    ]
    private static let cashWords: Set<String> = [
        "CASH", "TEND", "TENDER", "TENDERED", "BARGELD", "GEGEBEN", "EFECTIVO", "ENTREGADO", "ESPECES", "CONTANTI",
    ]
    private static let cardWords: Set<String> = [
        "VISA", "MASTERCARD", "MC", "AMEX", "DISCOVER", "DEBIT", "CREDIT", "INTERAC", "GIROCARD", "MAESTRO",
        "KARTENZAHLUNG", "TARJETA", "PAYPAL", "CONTACTLESS", "CARD", "EC",
    ]

    /// The store's address from the lines above the first amount on the first page.
    private static func findLocation(in lines: [AnalyzedLine]) -> String? {
        let header = lines.prefix(while: { line in line.amount == nil }).filter { line in line.pageIndex == 0 }
        return ReceiptDetailsParser.location(in: header.map { line in line.text })
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

    /// How sure Tabbit is that a line is a purchase. Above 0 it's counted. The size is what it
    /// costs to change that when the items don't add up (`ItemReconciler`); lines at 6 or more
    /// either way never change on the rules' word alone.
    enum Evidence {
        /// A name and a price in the price column, among the items: something bought.
        static let item = 6
        /// Money off with a minus ("COUPON -0.50").
        static let discount = 4
        /// A minus amount with no name of its own ("-1.00" under an item).
        static let unnamedDiscount = 3
        /// A money-off word without a minus ("MEMBER DISCOUNT 1.00"): taken off unless the subtotal disagrees.
        static let unsignedDiscount = 2
        /// "REG PRICE 4.99", "SALE PRICE 2.99": usually information, sometimes the price paid.
        static let priceInfo = -2
        /// A department heading that picked up a stray price.
        static let heading = -3
        /// A quantity or price with no name ("1 @ 2/ $9.00") under an item that already has its price.
        static let detail = -3
        /// A deal description ("2 FOR 1", "MIX & MATCH").
        static let deal = -4
        /// "YOU SAVED 2.98": money not spent. Never a purchase.
        static let savings = -9
        /// The amount isn't in the price column, so it's not a line's price.
        static let outsideColumn = -5
        /// A named line right under an item whose amount is outside the column describes that item.
        static let underItem = -3
    }

    /// A line that might be an item.
    struct ItemCandidate {
        var item: ReceiptLineItem
        /// See `Evidence`.
        let evidence: Int
        /// Whether it's counted as a purchase.
        var included: Bool
        /// The line's text, for notes.
        let label: String
        /// Where the line is in the receipt's lines.
        let lineIndex: Int
        /// It sits under an item and describes it: a quantity, deal, regular price or savings.
        let isDetail: Bool
        /// Another reading of the amount ("2 BANANAS 1.99" as 2 × 1.99); reconciliation may use it.
        var alternative: Decimal? = nil
        /// No line total was printed: the amount is quantity × unit price.
        var isComputed: Bool = false
    }

    /// Item candidates: lines with an amount between the top of the receipt and the first
    /// subtotal/tax/total line, each with its evidence.
    /// - A price line with no name of its own ("2 @ 0.99   1.98") takes the name from the line
    ///   above, if that line has no price.
    /// - Lines under an item that only describe it (quantities, deals, "YOU SAVED", amounts in
    ///   the middle of the line) are details: left out unless the subtotal needs them.
    /// - Payment, tip, rounding, unit-price and "TOTAL SAVINGS"-style lines are never items.
    static func itemCandidates(in lines: [AnalyzedLine]) -> [ItemCandidate] {
        let summaryIndex = lines.firstIndex(where: { line in
            ReceiptLineRole.summaryRoles.contains(line.role) && line.amount != nil
        })
        let regionEnd = summaryIndex ?? lines.count

        var candidates: [ItemCandidate] = []
        var lineAbove: AnalyzedLine?
        // True while the lines being read sit under an item that has its own price.
        var underItem = false
        for index in 0..<regionEnd {
            let line = lines[index]
            guard let amount = line.amount else {
                // A department heading ("PRODUCE") never lends its name to a price below it.
                if hasLetters(line.text) {
                    lineAbove = !ReceiptKeywords.isHeading(line.text) && !ReceiptKeywords.isDeal(line.text) ? line : nil
                    underItem = false
                } else {
                    lineAbove = nil
                }
                continue
            }
            let above = lineAbove
            lineAbove = nil
            if line.role == .payment || line.role == .notATotal || line.role == .tip
                || line.role == .rounding || line.role == .includedTax || line.role == .unitPrice {
                continue
            }

            let value = amount.value
            if value == 0 {
                // "BAG 0.00", "MEMBER PRICE 0.00": nothing to split.
                continue
            }
            let position = line.inPriceColumn ? 0 : Evidence.outsideColumn
            let detailUnderItem = underItem
            if ReceiptKeywords.isHeading(amount.textBefore) {
                // A heading that picked up a stray price. Left out unless the subtotal needs it.
                candidates.append(makeCandidate(
                    name: itemName(from: amount.textBefore), amount: value, confidence: line.confidence,
                    evidence: Evidence.heading + position, label: line.text, lineIndex: index, isDetail: false))
                underItem = false
                continue
            }
            if line.role == .discount {
                // Money off. Printed without a minus it's still a deduction, but
                // reconciliation may leave it out if the numbers disagree.
                let name = itemName(from: amount.textBefore)
                let evidence = (value < 0 ? Evidence.discount : Evidence.unsignedDiscount) + position
                candidates.append(makeCandidate(
                    name: name.isEmpty ? "Discount" : name, amount: value < 0 ? value : -value,
                    confidence: line.confidence, evidence: evidence, label: line.text, lineIndex: index,
                    isDetail: false))
                continue
            }
            if ReceiptKeywords.isDetailOnly(amount.textBefore) {
                if let above = above {
                    // "AVOCADO" then "2 @ 0.99   1.98": the price belongs to the name above.
                    let evidence = Evidence.item + position
                    candidates.append(makeCandidate(
                        name: cleanName(above.text), amount: value,
                        confidence: min(above.confidence, line.confidence),
                        evidence: evidence, label: line.text, lineIndex: index, isDetail: false,
                        detail: line.detail))
                    underItem = evidence > 0
                } else if value < 0 {
                    candidates.append(makeCandidate(
                        name: "Discount", amount: value, confidence: line.confidence,
                        evidence: Evidence.unnamedDiscount + position, label: line.text, lineIndex: index,
                        isDetail: false))
                } else {
                    // A deal or unit-price line under an item that already has a price,
                    // or a stray price. Left out unless the subtotal says otherwise.
                    candidates.append(makeCandidate(
                        name: itemName(from: line.text), amount: value, confidence: line.confidence,
                        evidence: Evidence.detail + position, label: line.text, lineIndex: index,
                        isDetail: detailUnderItem))
                }
            } else if line.role == .info {
                // "REG PRICE 4.99" could still be the price paid; "YOU SAVED 2.98" never is.
                let isSavings = ReceiptKeywords.isSavings(line.text)
                var evidence = Evidence.priceInfo
                if value < 0 {
                    evidence = Evidence.unnamedDiscount
                } else if isSavings {
                    evidence = Evidence.savings
                } else if ReceiptKeywords.isDeal(line.text) {
                    evidence = Evidence.deal
                }
                candidates.append(makeCandidate(
                    name: itemName(from: amount.textBefore), amount: value, confidence: line.confidence,
                    evidence: evidence + position, label: line.text, lineIndex: index,
                    isDetail: value > 0 && (detailUnderItem || isSavings)))
            } else {
                // A named line. Right under an item with its amount outside the price column, it
                // describes that item ("VOU SAVED $1.04" that OCR garbled); otherwise it's an item.
                let describesItemAbove = detailUnderItem && !line.inPriceColumn
                let evidence = Evidence.item + position + (describesItemAbove ? Evidence.underItem : 0)
                candidates.append(makeCandidate(
                    name: itemName(from: amount.textBefore), amount: value, confidence: line.confidence,
                    evidence: evidence, label: line.text, lineIndex: index, isDetail: describesItemAbove,
                    detail: line.detail))
                if !describesItemAbove {
                    underItem = evidence > 0
                }
            }
        }
        return candidates
    }

    /// A candidate; for a purchase, `detail` adds its quantity and unit price ("2× BANANAS").
    private static func makeCandidate(name: String, amount: Decimal, confidence: Float, evidence: Int,
                                      label: String, lineIndex: Int, isDetail: Bool,
                                      detail: LineAmount? = nil) -> ItemCandidate {
        let baseName = name.isEmpty ? "Item" : name
        guard let detail = detail, amount > 0 else {
            let item = ReceiptLineItem(name: baseName, amount: amount, confidence: confidence)
            return ItemCandidate(item: item, evidence: evidence, included: evidence > 0, label: label,
                                 lineIndex: lineIndex, isDetail: isDetail)
        }
        var item = ReceiptLineItem(name: LineAmountParser.name(baseName, quantity: detail.quantity),
                                   amount: amount, confidence: confidence)
        item.quantity = detail.quantity
        item.unitPrice = detail.unitPrice
        return ItemCandidate(item: item, evidence: evidence, included: evidence > 0, label: label,
                             lineIndex: lineIndex, isDetail: isDetail,
                             alternative: detail.alternative, isComputed: detail.isComputed)
    }

    /// The item with another amount (reconciliation chose the line's other reading).
    static func withAmount(_ item: ReceiptLineItem, _ amount: Decimal) -> ReceiptLineItem {
        var changed = ReceiptLineItem(name: item.name, amount: amount, confidence: item.confidence)
        changed.quantity = item.quantity
        if let quantity = item.quantity, quantity > 0 {
            let each = amount / quantity
            changed.unitPrice = Money.rounded(each) == each ? each : nil
        }
        return changed
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

    /// If the counted items don't add up to `target`, makes the cheapest set of changes that
    /// does (`ItemReconciler`): counting or leaving out lines Tabbit isn't sure about, or reading
    /// quantity lines the other way ("2 BANANAS 1.99" as 2 × 1.99). Applies it only if no other
    /// equally cheap change works, and returns a note describing it.
    private static func reconcile(_ candidates: inout [ItemCandidate], target: Decimal,
                                  targetName: String) -> String? {
        if ReceiptValidator.matches(includedSum(candidates), target) {
            return nil
        }
        let choices = candidates.map { candidate in
            ItemReconciler.Choice(amount: candidate.item.amount, alternative: candidate.alternative,
                                  evidence: candidate.included ? max(candidate.evidence, 1) : min(candidate.evidence, 0))
        }
        let moves = ItemReconciler.moves(for: choices)
        guard !moves.isEmpty else {
            return nil
        }
        let fixes = ItemReconciler.reachableSums(choices, moves: moves)
        guard let fix = ItemReconciler.lookup(target, in: fixes), fix.cost > 0 else {
            return nil
        }
        var changes: [String] = []
        for move in ItemReconciler.applied(fix, moves: moves) {
            let index = move.index
            if move.swap, let alternative = candidates[index].alternative {
                let old = candidates[index].item.amount
                candidates[index].item = withAmount(candidates[index].item, alternative)
                candidates[index].alternative = old
                candidates[index].isComputed = false
                changes.append("read \"\(candidates[index].label)\" as \(MoneyInput.editText(alternative))")
            } else if !move.swap {
                candidates[index].included.toggle()
                let verb = candidates[index].included ? "counted" : "left out"
                changes.append("\(verb) \"\(candidates[index].label)\"")
            }
        }
        guard !changes.isEmpty else {
            return nil
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
        let name = storeName(from: chosen.text)
        return name.isEmpty ? nil : name
    }

    // Store numbers after the name: "#1234", "STORE 0412", "NO. 12", or a number at the end.
    private static let storeNumberPattern = Patterns.make(
        #"\s*#\s*\d+|\s+(?:STORE|STORE\s+NO|NO|BRANCH|LOC)\.?\s*#?\s*\d+|\s+\d{3,}\s*$"#,
        caseInsensitive: true
    )

    /// A store's name without its store number or the branch after a comma or dash:
    /// "SHELL #1234" → "SHELL", "Walmart Supercentre, Toronto" → "Walmart Supercentre".
    static func storeName(from text: String) -> String {
        var name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [",", " - ", " – ", " | ", " · "] {
            if let range = name.range(of: separator) {
                let head = String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                if head.count >= 2 {
                    name = head
                }
            }
        }
        name = replace(storeNumberPattern, in: name, with: "")
        return cleanName(name)
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
