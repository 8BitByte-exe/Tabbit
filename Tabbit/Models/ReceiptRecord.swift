import Foundation

/// One line on a receipt, split evenly among its assignees.
struct SplitItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    var price: Decimal
    /// Who shares this item. Empty means everyone in the group.
    var assignees: [UUID]
    /// Vision's confidence in the scanned name (nil when typed).
    var confidence: Float?

    init(id: UUID = UUID(), name: String, price: Decimal, assignees: [UUID] = [], confidence: Float? = nil) {
        self.id = id
        self.name = name
        self.price = price
        self.assignees = assignees
        self.confidence = confidence
    }

    var isUncertain: Bool {
        guard let confidence = confidence else {
            return false
        }
        return confidence < ReceiptLineItem.uncertainBelow
    }
}

/// A tip as a fixed amount or a percentage of the items.
enum TipValue: Equatable {
    case amount(Decimal)
    case percent(Decimal)

    /// The tip in money, given the items subtotal.
    func amount(itemsSubtotal: Decimal) -> Decimal {
        switch self {
        case .amount(let value):
            return value
        case .percent(let percent):
            return Money.rounded(itemsSubtotal * percent / 100)
        }
    }
}

/// Fields that scanning can fill in (used for "autofilled" and "couldn't read" marks).
enum ReceiptField: String, Codable, CaseIterable {
    case merchant
    case location
    case date
    case time
    case category
    case payment
    case total
    case tax
    case tip
    case items
}

/// A scanned field Tabbit isn't sure about, and why ("could also mean Nov 26, 2008").
/// Shown as a "Check" mark in the editor until the field is changed or the receipt is saved.
struct FieldCheck: Equatable, Codable {
    var field: ReceiptField
    var reason: String
}

/// Where a receipt came from.
enum ReceiptSource: String, Codable {
    case camera
    case photo
    case manual
}

/// A receipt kept on the phone: in a group, in a business (Work), or in My Receipts
/// (`groupID == nil` and `businessID == nil`). It's never in a group and a business at once.
struct ReceiptRecord: Identifiable, Equatable {
    let id: UUID
    var groupID: UUID?
    /// The business this is an expense of (Work), with `groupID == nil`.
    var businessID: UUID?
    /// The job within that business, if any.
    var jobID: UUID?
    var createdAt: Date
    var updatedAt: Date

    var merchant: String
    /// The store's address, as printed. Empty if unknown.
    var location: String
    /// The purchase day (midnight, local time).
    var date: Date
    /// The time of purchase, if known.
    var time: ClockTime?
    /// How it was paid ("Visa", "Cash"…). Empty if unknown.
    var paymentMethod: String
    var category: SpendCategory
    /// Who paid. Defaults to me.
    var paidBy: UUID
    var items: [SplitItem]
    var tax: Decimal?
    var tip: TipValue?
    /// The total printed on the receipt. Nil means "add up items + tax + tip".
    var total: Decimal?
    /// Spread tax, tip and any other difference across people in proportion to
    /// their items. When off, the payer covers them.
    var includeFees: Bool

    var source: ReceiptSource
    /// Fields filled in by scanning (marked in the editor).
    var autofilled: Set<ReceiptField>
    /// Fields scanning looked for but couldn't read.
    var unreadable: Set<ReceiptField>
    /// Fields scanning filled in but isn't sure about, with the reason.
    var checks: [FieldCheck]

    var pageImageCount: Int
    /// Raw OCR and the parser's result, kept for exports and fixtures.
    var scan: ScanResult?
    var parsed: Receipt?
    var languageCorrection: Bool?
    /// Where the store is on the map, once Apple Maps has looked up its address (map turned on).
    var place: ReceiptPlace?

    init(id: UUID = UUID(), groupID: UUID? = nil, businessID: UUID? = nil, jobID: UUID? = nil, createdAt: Date = Date(), updatedAt: Date = Date(),
         merchant: String = "", location: String = "", date: Date = Calendar.current.startOfDay(for: Date()),
         time: ClockTime? = nil, paymentMethod: String = "", category: SpendCategory = .other, paidBy: UUID = Person.meID, items: [SplitItem] = [],
         tax: Decimal? = nil, tip: TipValue? = nil, total: Decimal? = nil, includeFees: Bool = true,
         source: ReceiptSource = .manual, autofilled: Set<ReceiptField> = [], unreadable: Set<ReceiptField> = [],
         checks: [FieldCheck] = [], pageImageCount: Int = 0, scan: ScanResult? = nil, parsed: Receipt? = nil, languageCorrection: Bool? = nil,
         place: ReceiptPlace? = nil) {
        self.id = id
        self.groupID = groupID
        self.businessID = businessID
        self.jobID = jobID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.merchant = merchant
        self.location = location
        self.date = date
        self.time = time
        self.paymentMethod = paymentMethod
        self.category = category
        self.paidBy = paidBy
        self.items = items
        self.tax = tax
        self.tip = tip
        self.total = total
        self.includeFees = includeFees
        self.source = source
        self.autofilled = autofilled
        self.unreadable = unreadable
        self.checks = checks
        self.pageImageCount = pageImageCount
        self.scan = scan
        self.parsed = parsed
        self.languageCorrection = languageCorrection
        self.place = place
    }

    // MARK: - Amounts

    var itemsSubtotal: Decimal {
        return items.reduce(Decimal(0)) { sum, item in sum + item.price }
    }

    var tipAmount: Decimal {
        return tip?.amount(itemsSubtotal: itemsSubtotal) ?? 0
    }

    /// Items + tax + tip.
    var computedTotal: Decimal {
        return itemsSubtotal + (tax ?? 0) + tipAmount
    }

    /// The amount actually paid: the printed total, or the computed one.
    var effectiveTotal: Decimal {
        return total ?? computedTotal
    }

    /// True when a printed total doesn't match items + tax + tip.
    var totalMismatch: Decimal? {
        guard let total = total, !items.isEmpty else {
            return nil
        }
        let difference = total - computedTotal
        return Money.cents(difference) == 0 ? nil : difference
    }

    var displayTitle: String {
        let trimmed = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Receipt" : trimmed
    }

    /// The receipt in the parser's format (for exports and checks).
    func asReceipt() -> Receipt {
        return Receipt(
            merchant: merchant.isEmpty ? nil : merchant,
            date: CalendarDate(date),
            lineItems: items.map { item in ReceiptLineItem(name: item.name, amount: item.price, confidence: item.confidence) },
            subtotal: items.isEmpty ? nil : itemsSubtotal,
            tax: tax,
            total: effectiveTotal,
            tip: tip == nil ? nil : tipAmount,
            location: location.isEmpty ? nil : location,
            time: time,
            paymentMethod: paymentMethod.isEmpty ? nil : paymentMethod,
            includedTax: parsed?.includedTax,
            parser: parsed?.parser ?? .rules,
            notes: parsed?.notes ?? []
        )
    }
}

// MARK: - Settlements

/// A recorded payment between two people ("Mark Paid").
struct Settlement: Identifiable, Equatable {
    let id: UUID
    let from: UUID
    let to: UUID
    let amount: Decimal
    let date: Date

    init(id: UUID = UUID(), from: UUID, to: UUID, amount: Decimal, date: Date = Date()) {
        self.id = id
        self.from = from
        self.to = to
        self.amount = amount
        self.date = date
    }
}

// MARK: - JSON (money as text, like Receipt)

extension SplitItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, price, assignees, confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            price: try MoneyCoding.decode(container, forKey: .price),
            assignees: try container.decodeIfPresent([UUID].self, forKey: .assignees) ?? [],
            confidence: try container.decodeIfPresent(Float.self, forKey: .confidence)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(MoneyCoding.text(price), forKey: .price)
        try container.encode(assignees, forKey: .assignees)
        try container.encodeIfPresent(confidence, forKey: .confidence)
    }
}

extension TipValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let value = try MoneyCoding.decode(container, forKey: .value)
        self = kind == "percent" ? .percent(value) : .amount(value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .amount(let value):
            try container.encode("amount", forKey: .kind)
            try container.encode(MoneyCoding.text(value), forKey: .value)
        case .percent(let value):
            try container.encode("percent", forKey: .kind)
            try container.encode(MoneyCoding.text(value), forKey: .value)
        }
    }
}

extension Settlement: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, from, to, amount, date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            from: try container.decode(UUID.self, forKey: .from),
            to: try container.decode(UUID.self, forKey: .to),
            amount: try MoneyCoding.decode(container, forKey: .amount),
            date: try container.decode(Date.self, forKey: .date)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(MoneyCoding.text(amount), forKey: .amount)
        try container.encode(date, forKey: .date)
    }
}

extension ReceiptRecord: Codable {
    /// Stored files carry `schema: 2`; v0.4 files (no schema) are migrated by TabbitStore.
    static let schemaVersion = 2

    private enum CodingKeys: String, CodingKey {
        case schema, id, groupID, businessID, jobID, createdAt, updatedAt, merchant, location, date, time, paymentMethod, category
        case paidBy, items
        case tax, tip, total, includeFees, source, autofilled, unreadable, checks, pageImageCount
        case scan, parsed, languageCorrection, place
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            groupID: try container.decodeIfPresent(UUID.self, forKey: .groupID),
            businessID: try container.decodeIfPresent(UUID.self, forKey: .businessID),
            jobID: try container.decodeIfPresent(UUID.self, forKey: .jobID),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            merchant: try container.decodeIfPresent(String.self, forKey: .merchant) ?? "",
            location: try container.decodeIfPresent(String.self, forKey: .location) ?? "",
            date: try container.decode(Date.self, forKey: .date),
            time: try? container.decodeIfPresent(ClockTime.self, forKey: .time),
            paymentMethod: try container.decodeIfPresent(String.self, forKey: .paymentMethod) ?? "",
            category: try container.decodeIfPresent(SpendCategory.self, forKey: .category) ?? .other,
            paidBy: try container.decodeIfPresent(UUID.self, forKey: .paidBy) ?? Person.meID,
            items: try container.decodeIfPresent([SplitItem].self, forKey: .items) ?? [],
            tax: try MoneyCoding.decodeIfPresent(container, forKey: .tax),
            tip: try container.decodeIfPresent(TipValue.self, forKey: .tip),
            total: try MoneyCoding.decodeIfPresent(container, forKey: .total),
            includeFees: try container.decodeIfPresent(Bool.self, forKey: .includeFees) ?? true,
            source: try container.decodeIfPresent(ReceiptSource.self, forKey: .source) ?? .manual,
            autofilled: try container.decodeIfPresent(Set<ReceiptField>.self, forKey: .autofilled) ?? [],
            unreadable: try container.decodeIfPresent(Set<ReceiptField>.self, forKey: .unreadable) ?? [],
            checks: (try? container.decodeIfPresent([FieldCheck].self, forKey: .checks)) ?? [],
            pageImageCount: try container.decodeIfPresent(Int.self, forKey: .pageImageCount) ?? 0,
            scan: try container.decodeIfPresent(ScanResult.self, forKey: .scan),
            parsed: try container.decodeIfPresent(Receipt.self, forKey: .parsed),
            languageCorrection: try container.decodeIfPresent(Bool.self, forKey: .languageCorrection),
            place: try? container.decodeIfPresent(ReceiptPlace.self, forKey: .place)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ReceiptRecord.schemaVersion, forKey: .schema)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(groupID, forKey: .groupID)
        try container.encodeIfPresent(businessID, forKey: .businessID)
        try container.encodeIfPresent(jobID, forKey: .jobID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(merchant, forKey: .merchant)
        try container.encode(location, forKey: .location)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(time, forKey: .time)
        try container.encode(paymentMethod, forKey: .paymentMethod)
        try container.encode(category, forKey: .category)
        try container.encode(paidBy, forKey: .paidBy)
        try container.encode(items, forKey: .items)
        try container.encodeIfPresent(tax.map { value in MoneyCoding.text(value) }, forKey: .tax)
        try container.encodeIfPresent(tip, forKey: .tip)
        try container.encodeIfPresent(total.map { value in MoneyCoding.text(value) }, forKey: .total)
        try container.encode(includeFees, forKey: .includeFees)
        try container.encode(source, forKey: .source)
        try container.encode(autofilled, forKey: .autofilled)
        try container.encode(unreadable, forKey: .unreadable)
        if !checks.isEmpty {
            try container.encode(checks, forKey: .checks)
        }
        try container.encode(pageImageCount, forKey: .pageImageCount)
        try container.encodeIfPresent(scan, forKey: .scan)
        try container.encodeIfPresent(parsed, forKey: .parsed)
        try container.encodeIfPresent(languageCorrection, forKey: .languageCorrection)
        try container.encodeIfPresent(place, forKey: .place)
    }
}
