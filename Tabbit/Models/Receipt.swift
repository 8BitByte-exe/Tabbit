import Foundation

/// A calendar day with no time or time zone, as printed on a receipt.
struct CalendarDate: Equatable, Codable {
    let year: Int
    let month: Int
    let day: Int

    /// "2026-11-03"
    var isoString: String {
        return CalendarDate.padded(year, width: 4) + "-"
            + CalendarDate.padded(month, width: 2) + "-"
            + CalendarDate.padded(day, width: 2)
    }

    private static func padded(_ value: Int, width: Int) -> String {
        let digits = String(value)
        let zeros = String(repeating: "0", count: max(0, width - digits.count))
        return zeros + digits
    }
}

/// One purchased item (or a discount, which has a negative amount).
struct ReceiptLineItem: Equatable, Codable {
    let name: String
    let amount: Decimal
}

/// Which parser produced a receipt.
enum ReceiptParserKind: String, Equatable, Codable {
    /// Hand-written rules (RulesReceiptParser). Works on every supported iPhone.
    case rules

    var displayName: String {
        switch self {
        case .rules:
            return "Rules (on-device)"
        }
    }
}

/// The structured result of parsing one scanned receipt.
/// Every field is optional because real receipts don't always show it
/// (or OCR didn't read it).
struct Receipt: Equatable, Codable {
    var merchant: String?
    var date: CalendarDate?
    var lineItems: [ReceiptLineItem]
    var subtotal: Decimal?
    var tax: Decimal?
    var total: Decimal?
    var parser: ReceiptParserKind
    /// Short remarks about how the result was produced, shown to the user.
    var notes: [String]

    /// The sum of all line item amounts (discounts included).
    var itemsTotal: Decimal {
        return lineItems.reduce(Decimal(0)) { sum, item in sum + item.amount }
    }
}
