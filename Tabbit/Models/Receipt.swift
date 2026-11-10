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

/// A time of day as printed on a receipt ("2:32 PM", "14:32"), with no time zone.
struct ClockTime: Equatable, Codable, Comparable {
    /// 0–23.
    let hour: Int
    /// 0–59.
    let minute: Int

    /// "14:32"
    var text24: String {
        return (hour < 10 ? "0" : "") + String(hour) + ":" + (minute < 10 ? "0" : "") + String(minute)
    }

    /// The time on a given day, in the current calendar.
    func date(on day: Date) -> Date {
        let start = Calendar.current.startOfDay(for: day)
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: start) ?? start
    }

    init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    init(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        self.init(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    static func < (first: ClockTime, second: ClockTime) -> Bool {
        return first.hour != second.hour ? first.hour < second.hour : first.minute < second.minute
    }
}

/// One purchased item (or a discount, which has a negative amount).
struct ReceiptLineItem: Equatable, Codable {
    let name: String
    /// What the line costs in total (quantity × unit price).
    let amount: Decimal
    /// Vision's confidence in the text this item came from (0...1), if known.
    var confidence: Float? = nil
    /// How many were bought, if the receipt says ("2 @ 1.99", "2 X", "QTY 2", "1.25 LB").
    var quantity: Decimal? = nil
    /// The price of one, if the receipt prints it.
    var unitPrice: Decimal? = nil

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

/// What Apple Intelligence answered for a scan. Not shown in the app: it goes into
/// Export Scan Data, so a receipt it misread can be looked into and turned into a test.
struct IntelligenceTrace: Equatable, Codable {
    /// "used", "rules", or what went wrong.
    var outcome: String
    /// How long the model took, in seconds.
    var seconds: Double?
    var storeName: String?
    var category: String?
    var date: String?
    var pricesIncludeTax: Bool?
    /// False when the model said the receipt lists no products (a card slip).
    var isItemized: Bool? = nil
    /// One per labelled line: "[3] item: Organic bananas".
    var labels: [String] = []
    /// The photo the model saw ("896×640, 2 section(s)"), "off", or why it couldn't use it.
    var photo: String? = nil
    /// Which reader read the text ("documents" or "text") and how long it took (seconds).
    var reader: String? = nil
    var readSeconds: Double? = nil
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
    /// The store's address as printed ("123 MAIN ST, SPRINGFIELD, IL 62701").
    var location: String? = nil
    /// The time of purchase.
    var time: ClockTime? = nil
    /// How it was paid: "Visa", "Debit", "Cash"…
    var paymentMethod: String? = nil
    /// Tax the receipt says is already in the prices ("HST INCLUDED 6.32"); not added on top.
    var includedTax: Decimal? = nil
    var parser: ReceiptParserKind
    /// Short remarks about how the result was produced, shown to the user.
    var notes: [String]
    /// What Apple Intelligence answered, if it read this scan. Kept for Export Scan Data.
    var intelligence: IntelligenceTrace? = nil

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
        case quantity
        case unitPrice
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let amount = try MoneyCoding.decode(container, forKey: .amount)
        let confidence = try container.decodeIfPresent(Float.self, forKey: .confidence)
        self.init(name: name, amount: amount, confidence: confidence)
        self.quantity = try MoneyCoding.decodeIfPresent(container, forKey: .quantity)
        self.unitPrice = try MoneyCoding.decodeIfPresent(container, forKey: .unitPrice)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(MoneyCoding.text(amount), forKey: .amount)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encodeIfPresent(quantity.map { value in MoneyCoding.text(value) }, forKey: .quantity)
        try container.encodeIfPresent(unitPrice.map { value in MoneyCoding.text(value) }, forKey: .unitPrice)
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
        case location
        case time
        case paymentMethod
        case includedTax
        case parser
        case notes
        case intelligence
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
            location: try container.decodeIfPresent(String.self, forKey: .location),
            time: try? container.decodeIfPresent(ClockTime.self, forKey: .time),
            paymentMethod: try container.decodeIfPresent(String.self, forKey: .paymentMethod),
            includedTax: try MoneyCoding.decodeIfPresent(container, forKey: .includedTax),
            parser: try container.decodeIfPresent(ReceiptParserKind.self, forKey: .parser) ?? .rules,
            notes: try container.decodeIfPresent([String].self, forKey: .notes) ?? [],
            intelligence: try? container.decodeIfPresent(IntelligenceTrace.self, forKey: .intelligence)
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
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(time, forKey: .time)
        try container.encodeIfPresent(paymentMethod, forKey: .paymentMethod)
        try container.encodeIfPresent(includedTax.map { value in MoneyCoding.text(value) }, forKey: .includedTax)
        try container.encode(parser, forKey: .parser)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(intelligence, forKey: .intelligence)
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
