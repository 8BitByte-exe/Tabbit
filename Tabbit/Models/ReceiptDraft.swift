import Foundation

/// Reads an amount the user typed: "7.76", "1,234.56", "1.234,56", "12,34",
/// "$4", "-0.50", "0.50-". Returns nil for empty or unreadable text.
enum MoneyInput {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func parse(_ text: String) -> Decimal? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return nil
        }
        var negative = false
        if cleaned.hasPrefix("-") || cleaned.hasPrefix("−") {
            negative = true
            cleaned.removeFirst()
        }
        if cleaned.hasSuffix("-") {
            negative = true
            cleaned.removeLast()
        }
        let removable = CharacterSet(charactersIn: "$€£ \u{00A0}")
        cleaned = String(cleaned.unicodeScalars.filter { scalar in !removable.contains(scalar) })
        if cleaned.hasPrefix("-") {
            negative = true
            cleaned.removeFirst()
        }
        guard !cleaned.isEmpty else {
            return nil
        }
        let allowed = CharacterSet(charactersIn: "0123456789.,")
        guard cleaned.unicodeScalars.allSatisfy({ scalar in allowed.contains(scalar) }) else {
            return nil
        }

        // Work out the decimal separator: the last "." or "," if 1–2 digits follow it.
        var normalized = cleaned
        if let separatorIndex = cleaned.lastIndex(where: { character in character == "." || character == "," }) {
            let fraction = cleaned[cleaned.index(after: separatorIndex)...]
            let whole = cleaned[..<separatorIndex]
            if fraction.count >= 1 && fraction.count <= 2 {
                let wholeDigits = String(whole).filter { character in character != "." && character != "," }
                normalized = wholeDigits + "." + String(fraction)
            } else {
                normalized = cleaned.filter { character in character != "." && character != "," }
            }
        }
        guard !normalized.isEmpty, normalized != ".", var value = Decimal(string: normalized, locale: posix) else {
            return nil
        }
        if negative {
            value = -value
        }
        return value
    }

    /// How an amount appears in an edit field: "7.76", "-0.50".
    static func editText(_ value: Decimal?) -> String {
        guard let value = value else {
            return ""
        }
        let formatter = NumberFormatter()
        formatter.locale = posix
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? MoneyCoding.text(value)
    }
}

/// The receipt screen's editable copy of a receipt. Amounts are kept as the text
/// the user typed, and `receipt` turns them back into numbers, so the checks
/// update while typing.
struct ReceiptDraft: Equatable {
    struct Item: Identifiable, Equatable {
        let id: UUID
        var name: String
        var amountText: String
        var confidence: Float?
    }

    var merchant: String
    var date: CalendarDate?
    var items: [Item]
    var subtotalText: String
    var taxText: String
    var totalText: String
    let parser: ReceiptParserKind
    let notes: [String]

    init(_ receipt: Receipt) {
        merchant = receipt.merchant ?? ""
        date = receipt.date
        items = receipt.lineItems.map { item in
            Item(id: UUID(), name: item.name, amountText: MoneyInput.editText(item.amount), confidence: item.confidence)
        }
        subtotalText = MoneyInput.editText(receipt.subtotal)
        taxText = MoneyInput.editText(receipt.tax)
        totalText = MoneyInput.editText(receipt.total)
        parser = receipt.parser
        notes = receipt.notes
    }

    /// The draft as a Receipt. Items whose amount can't be read are left out;
    /// `invalidFields` lists them so the screen can flag them.
    var receipt: Receipt {
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        var lineItems: [ReceiptLineItem] = []
        for item in items {
            guard let amount = MoneyInput.parse(item.amountText) else {
                continue
            }
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            lineItems.append(ReceiptLineItem(name: name.isEmpty ? "Item" : name, amount: amount,
                                             confidence: item.confidence))
        }
        return Receipt(
            merchant: trimmedMerchant.isEmpty ? nil : trimmedMerchant,
            date: date,
            lineItems: lineItems,
            subtotal: MoneyInput.parse(subtotalText),
            tax: MoneyInput.parse(taxText),
            total: MoneyInput.parse(totalText),
            parser: parser,
            notes: notes
        )
    }

    /// True if some typed amount can't be read as a number.
    var hasInvalidAmounts: Bool {
        for item in items where !ReceiptDraft.isValid(item.amountText) {
            return true
        }
        return !ReceiptDraft.isValid(subtotalText)
            || !ReceiptDraft.isValid(taxText)
            || !ReceiptDraft.isValid(totalText)
    }

    /// Empty is fine (the field is just missing); otherwise it must be a number.
    static func isValid(_ text: String) -> Bool {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return MoneyInput.parse(text) != nil
    }

    mutating func addItem() {
        items.append(Item(id: UUID(), name: "", amountText: "", confidence: nil))
    }

    mutating func removeItem(id: UUID) {
        items.removeAll { item in item.id == id }
    }
}
