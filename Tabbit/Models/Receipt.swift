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
    /// Vision's confidence in the text this item came from (0...1), if known.
    var confidence: Float? = nil

    /// Below this confidence the app marks the name as uncertain.
    static let uncertainBelow: Float = 0.6

    var isUncertain: Bool {
        guard let confidence = confidence else {
            return false
        }
        return confidence < ReceiptLineItem.uncertainBelow
    }
}

/// Which parser produced a receipt.
enum ReceiptParserKind: String, Equatable, Codable {
    /// Hand-written rules (RulesReceiptParser). Works on every supported iPhone.
    case rules
    /// Apple Intelligence's on-device model, checked against the scan (iOS 26).
    case appleIntelligence

    var displayName: String {
        switch self {
        case .rules:
            return "Rules (on-device)"
        case .appleIntelligence:
            return "Apple Intelligence (on-device)"
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
    /// A printed tip or gratuity, if the receipt shows one.
    var tip: Decimal? = nil
    var parser: ReceiptParserKind
    /// Short remarks about how the result was produced, shown to the user.
    var notes: [String]

    /// The sum of all line item amounts (discounts included).
    var itemsTotal: Decimal {
        return lineItems.reduce(Decimal(0)) { sum, item in sum + item.amount }
    }
}

// MARK: - JSON

/// Money is written to JSON as text ("7.76"), so saved receipts never pick up
/// floating-point rounding. Older files that stored plain numbers still load.
enum MoneyCoding {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func text(_ value: Decimal) -> String {
        return NSDecimalNumber(decimal: value).stringValue
    }

    static func decode<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> Decimal {
        if let text = try? container.decode(String.self, forKey: key) {
            guard let value = Decimal(string: text, locale: posix) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key, in: container, debugDescription: "Not an amount: \(text)")
            }
            return value
        }
        return try container.decode(Decimal.self, forKey: key)
    }

    static func decodeIfPresent<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>,
                                                forKey key: Key) throws -> Decimal? {
        guard container.contains(key) else {
            return nil
        }
        if try container.decodeNil(forKey: key) {
            return nil
        }
        return try decode(container, forKey: key)
    }
}

extension ReceiptLineItem {
    private enum CodingKeys: String, CodingKey {
        case name
        case amount
        case confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let amount = try MoneyCoding.decode(container, forKey: .amount)
        let confidence = try container.decodeIfPresent(Float.self, forKey: .confidence)
        self.init(name: name, amount: amount, confidence: confidence)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(MoneyCoding.text(amount), forKey: .amount)
        try container.encodeIfPresent(confidence, forKey: .confidence)
    }
}

extension Receipt {
    private enum CodingKeys: String, CodingKey {
        case merchant
        case date
        case lineItems
        case subtotal
        case tax
        case total
        case tip
        case parser
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            merchant: try container.decodeIfPresent(String.self, forKey: .merchant),
            date: try container.decodeIfPresent(CalendarDate.self, forKey: .date),
            lineItems: try container.decodeIfPresent([ReceiptLineItem].self, forKey: .lineItems) ?? [],
            subtotal: try MoneyCoding.decodeIfPresent(container, forKey: .subtotal),
            tax: try MoneyCoding.decodeIfPresent(container, forKey: .tax),
            total: try MoneyCoding.decodeIfPresent(container, forKey: .total),
            tip: try MoneyCoding.decodeIfPresent(container, forKey: .tip),
            parser: try container.decodeIfPresent(ReceiptParserKind.self, forKey: .parser) ?? .rules,
            notes: try container.decodeIfPresent([String].self, forKey: .notes) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(merchant, forKey: .merchant)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encode(lineItems, forKey: .lineItems)
        try container.encodeIfPresent(subtotal.map { value in MoneyCoding.text(value) }, forKey: .subtotal)
        try container.encodeIfPresent(tax.map { value in MoneyCoding.text(value) }, forKey: .tax)
        try container.encodeIfPresent(total.map { value in MoneyCoding.text(value) }, forKey: .total)
        try container.encodeIfPresent(tip.map { value in MoneyCoding.text(value) }, forKey: .tip)
        try container.encode(parser, forKey: .parser)
        try container.encode(notes, forKey: .notes)
    }
}

extension CalendarDate {
    /// Midnight of this day in the current calendar.
    var dateValue: Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)
    }

    init(_ date: Date) {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 2000, month: components.month ?? 1, day: components.day ?? 1)
    }
}
