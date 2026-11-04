import Foundation

/// Turns a scan into a receipt to review: the fields it could read are filled in
/// and marked as autofilled; the ones it looked for but couldn't read are marked too.
enum ScanAutofill {

    static func record(from processed: ProcessedScan, source: ReceiptSource, groupID: UUID?,
                       paidBy: UUID = Person.meID, now: Date = Date()) -> ReceiptRecord {
        let parsed = processed.receipt
        var autofilled: Set<ReceiptField> = []
        var unreadable: Set<ReceiptField> = []

        let merchant = parsed.merchant ?? ""
        if merchant.isEmpty {
            unreadable.insert(.merchant)
        } else {
            autofilled.insert(.merchant)
        }

        var date = Calendar.current.startOfDay(for: now)
        if let found = parsed.date?.dateValue {
            date = found
            autofilled.insert(.date)
        } else {
            unreadable.insert(.date)
        }

        let category = CategoryGuesser.guess(merchant: merchant, items: parsed.lineItems.map { item in item.name })
        if category != .other {
            autofilled.insert(.category)
        }

        if parsed.total != nil {
            autofilled.insert(.total)
        } else {
            unreadable.insert(.total)
        }
        if parsed.tax != nil {
            autofilled.insert(.tax)
        }
        if parsed.tip != nil {
            autofilled.insert(.tip)
        }
        if parsed.lineItems.isEmpty {
            unreadable.insert(.items)
        } else {
            autofilled.insert(.items)
        }

        let items = parsed.lineItems.map { line in
            SplitItem(name: line.name, price: line.amount, assignees: [], confidence: line.confidence)
        }
        return ReceiptRecord(
            groupID: groupID,
            createdAt: now,
            updatedAt: now,
            merchant: merchant,
            date: date,
            category: category,
            paidBy: paidBy,
            items: items,
            tax: parsed.tax,
            tip: parsed.tip.map { value in TipValue.amount(value) },
            total: parsed.total,
            includeFees: true,
            source: source,
            autofilled: autofilled,
            unreadable: unreadable,
            pageImageCount: processed.pageJPEGs.count,
            scan: processed.scan,
            parsed: parsed,
            languageCorrection: processed.languageCorrection
        )
    }
}

/// Guesses a spending category from the merchant name and items.
enum CategoryGuesser {
    private static let rules: [(SpendCategory, [String])] = [
        (.food, ["cafe", "café", "coffee", "espresso", "bakery", "restaurant", "grill", "bistro", "pizza", "burger",
                 "sushi", "taco", "kitchen", "diner", "bar", "pub", "brew", "tea", "latte", "noodle", "deli"]),
        (.groceries, ["market", "grocery", "grocer", "supermarket", "foods", "mart", "trader joe", "whole foods",
                      "aldi", "kroger", "safeway", "costco", "produce"]),
        (.transport, ["uber", "lyft", "taxi", "cab", "fuel", "gas", "petrol", "shell", "chevron", "parking", "transit",
                      "metro", "rail", "airline", "airways", "toll"]),
        (.lodging, ["hotel", "inn", "motel", "hostel", "resort", "lodge", "airbnb", "suites"]),
        (.entertainment, ["cinema", "theater", "theatre", "movie", "museum", "tickets", "concert", "bowling", "arcade"]),
        (.health, ["pharmacy", "drug", "clinic", "dental", "health", "cvs", "walgreens"]),
        (.utilities, ["electric", "water", "utility", "internet", "phone", "mobile", "power"]),
        (.shopping, ["store", "shop", "outlet", "boutique", "hardware", "target", "walmart", "mall", "books"]),
    ]

    static func guess(merchant: String, items: [String]) -> SpendCategory {
        let merchantText = merchant.lowercased()
        for (category, keywords) in rules where keywords.contains(where: { keyword in merchantText.contains(keyword) }) {
            return category
        }
        let itemText = items.joined(separator: " ").lowercased()
        for (category, keywords) in rules where keywords.contains(where: { keyword in itemText.contains(keyword) }) {
            return category
        }
        return .other
    }
}
