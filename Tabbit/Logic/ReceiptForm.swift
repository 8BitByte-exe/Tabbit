import Foundation

/// The receipt editor's state: amounts are kept as typed text, so half-typed
/// numbers ("4.") don't jump around. `record(updating:)` turns it back into a receipt.
struct ReceiptForm: Equatable {

    struct Item: Identifiable, Equatable {
        let id: UUID
        var name: String
        var priceText: String
        /// Empty means everyone.
        var assignees: [UUID]
        var confidence: Float?

        var isUncertain: Bool {
            guard let confidence = confidence else {
                return false
            }
            return confidence < ReceiptLineItem.uncertainBelow
        }
    }

    /// Amount fields that can hold unreadable text.
    enum AmountField: Hashable {
        case itemPrice(UUID)
        case tax
        case tip
        case total
    }

    var merchant: String
    var date: Date
    var category: SpendCategory
    var paidBy: UUID
    var items: [Item]
    var taxText: String
    var tipText: String
    var tipIsPercent: Bool
    var totalText: String
    var includeFees: Bool

    init(_ record: ReceiptRecord) {
        merchant = record.merchant
        date = record.date
        category = record.category
        paidBy = record.paidBy
        items = record.items.map { item in
            Item(id: item.id, name: item.name, priceText: MoneyInput.editText(item.price),
                 assignees: item.assignees, confidence: item.confidence)
        }
        taxText = MoneyInput.editText(record.tax)
        switch record.tip {
        case .some(.percent(let percent)):
            tipIsPercent = true
            tipText = NSDecimalNumber(decimal: percent).stringValue
        case .some(.amount(let amount)):
            tipIsPercent = false
            tipText = MoneyInput.editText(amount)
        case .none:
            tipIsPercent = false
            tipText = ""
        }
        totalText = MoneyInput.editText(record.total)
        includeFees = record.includeFees
    }

    // MARK: - Editing

    /// Adds an empty item and returns its ID (to focus it).
    @discardableResult
    mutating func addItem() -> UUID {
        let item = Item(id: UUID(), name: "", priceText: "", assignees: [], confidence: nil)
        items.append(item)
        return item.id
    }

    mutating func removeItem(_ id: UUID) {
        items.removeAll { item in item.id == id }
    }

    /// Tapping a person on an item: adds or removes them. Choosing everyone (or
    /// nobody) goes back to "Everyone".
    static func toggled(_ assignees: [UUID], person: UUID, members: [UUID]) -> [UUID] {
        var chosen = assignees
        if let index = chosen.firstIndex(of: person) {
            chosen.remove(at: index)
        } else {
            chosen.append(person)
        }
        let ordered = members.filter { id in chosen.contains(id) }
        return ordered.count == members.count ? [] : ordered
    }

    // MARK: - Checking

    /// Fields whose text isn't a readable amount. An item with a name needs a price.
    var invalidFields: Set<AmountField> {
        var invalid: Set<AmountField> = []
        for item in items {
            let hasName = !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let priceEmpty = item.priceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if priceEmpty {
                if hasName {
                    invalid.insert(.itemPrice(item.id))
                }
            } else if MoneyInput.parse(item.priceText) == nil {
                invalid.insert(.itemPrice(item.id))
            }
        }
        if ReceiptForm.isUnreadable(taxText) {
            invalid.insert(.tax)
        }
        if ReceiptForm.isUnreadable(tipText) || (MoneyInput.parse(tipText) ?? 0) < 0 {
            invalid.insert(.tip)
        }
        if ReceiptForm.isUnreadable(totalText) {
            invalid.insert(.total)
        }
        return invalid
    }

    var isValid: Bool {
        return invalidFields.isEmpty
    }

    private static func isUnreadable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && MoneyInput.parse(trimmed) == nil
    }

    // MARK: - Result

    /// The receipt with the form's values. Scan marks ("autofilled", "couldn't
    /// read") are dropped for fields the user changed, and an item's
    /// uncertain-name mark goes once its name is edited.
    func record(updating base: ReceiptRecord) -> ReceiptRecord {
        var record = base
        record.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        record.date = Calendar.current.startOfDay(for: date)
        record.category = category
        record.paidBy = paidBy
        record.items = items.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let price = MoneyInput.parse(item.priceText)
            if name.isEmpty && price == nil {
                return nil
            }
            let original = base.items.first { candidate in candidate.id == item.id }
            let confidence = original?.name == name ? item.confidence : nil
            return SplitItem(id: item.id, name: name.isEmpty ? "Item" : name, price: price ?? 0,
                             assignees: item.assignees, confidence: confidence)
        }
        record.tax = MoneyInput.parse(taxText)
        if let tip = MoneyInput.parse(tipText) {
            record.tip = tipIsPercent ? .percent(tip) : .amount(tip)
        } else {
            record.tip = nil
        }
        record.total = MoneyInput.parse(totalText)
        record.includeFees = includeFees

        for field in ReceiptForm.changedFields(from: base, to: record) {
            record.autofilled.remove(field)
            record.unreadable.remove(field)
        }
        return record
    }

    static func changedFields(from old: ReceiptRecord, to new: ReceiptRecord) -> Set<ReceiptField> {
        var changed: Set<ReceiptField> = []
        if old.merchant != new.merchant {
            changed.insert(.merchant)
        }
        if old.date != new.date {
            changed.insert(.date)
        }
        if old.category != new.category {
            changed.insert(.category)
        }
        if old.total != new.total {
            changed.insert(.total)
        }
        if old.tax != new.tax {
            changed.insert(.tax)
        }
        if old.tip != new.tip {
            changed.insert(.tip)
        }
        let oldItems = old.items.map { item in "\(item.name)|\(item.price)" }
        let newItems = new.items.map { item in "\(item.name)|\(item.price)" }
        if oldItems != newItems {
            changed.insert(.items)
        }
        return changed
    }
}
