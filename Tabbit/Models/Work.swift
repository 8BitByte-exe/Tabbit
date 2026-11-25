import Foundation

/// Working for yourself, or as a business with its own name.
enum BusinessKind: String, Codable, CaseIterable, Identifiable {
    case freelance
    case business

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freelance: return "Freelance"
        case .business: return "Business"
        }
    }

    var symbol: String {
        switch self {
        case .freelance: return "person.crop.square.fill"
        case .business: return "building.2.fill"
        }
    }
}

/// A business (or "Freelance", working under your own name), with the jobs done
/// for it, the invoices sent and, through `ReceiptRecord.businessID`, its expenses.
struct Business: Identifiable, Equatable {
    let id: UUID
    var name: String
    var kind: BusinessKind
    /// Index into Theme.pastels for its badge.
    var colorIndex: Int
    /// Newest first.
    var jobs: [Job]
    var invoices: [Invoice]
    /// Share of the profit to put aside for income tax, in percent (nil = not shown).
    var taxSetAsidePercent: Decimal?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, kind: BusinessKind = .freelance, colorIndex: Int = 6,
         jobs: [Job] = [], invoices: [Invoice] = [], taxSetAsidePercent: Decimal? = nil,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.colorIndex = colorIndex
        self.jobs = jobs
        self.invoices = invoices
        self.taxSetAsidePercent = taxSetAsidePercent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.title : trimmed
    }

    func job(_ id: UUID?) -> Job? {
        guard let id = id else {
            return nil
        }
        return jobs.first { job in job.id == id }
    }

    func invoice(_ id: UUID) -> Invoice? {
        return invoices.first { invoice in invoice.id == id }
    }

    /// A job's invoices, newest first.
    func invoices(for jobID: UUID?) -> [Invoice] {
        let list = jobID == nil ? invoices : invoices.filter { invoice in invoice.jobID == jobID }
        return Invoice.sorted(list)
    }
}

/// A piece of work done for a client: a project, a contract, a gig.
struct Job: Identifiable, Equatable {
    let id: UUID
    var name: String
    var client: String
    var startDate: Date
    var isFinished: Bool
    var createdAt: Date

    init(id: UUID = UUID(), name: String, client: String = "", startDate: Date = Calendar.current.startOfDay(for: Date()),
         isFinished: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.client = client
        self.startDate = startDate
        self.isFinished = isFinished
        self.createdAt = createdAt
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Job" : trimmed
    }
}

/// Where an invoice stands.
enum InvoiceStatus: Equatable {
    case paid
    /// Sent, not paid, not yet past its due date (or no due date).
    case waiting
    /// Not paid and past its due date.
    case overdue
}

/// An invoice sent to a client: the amount, when it was sent and due, and when it was paid.
struct Invoice: Identifiable, Equatable {
    let id: UUID
    /// The job it bills for (nil = not tied to a job).
    var jobID: UUID?
    /// The invoice's own number ("INV-0042"). Empty if none.
    var number: String
    var client: String
    var amount: Decimal
    /// When it was sent (local midnight).
    var issueDate: Date
    var dueDate: Date?
    /// When it was paid; nil = not paid yet.
    var paidDate: Date?
    var notes: String
    /// The invoice itself, as a PDF in the Work folder (nil = none attached).
    var fileName: String?
    var createdAt: Date

    init(id: UUID = UUID(), jobID: UUID? = nil, number: String = "", client: String = "", amount: Decimal = 0,
         issueDate: Date = Calendar.current.startOfDay(for: Date()), dueDate: Date? = nil, paidDate: Date? = nil,
         notes: String = "", fileName: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.jobID = jobID
        self.number = number
        self.client = client
        self.amount = amount
        self.issueDate = issueDate
        self.dueDate = dueDate
        self.paidDate = paidDate
        self.notes = notes
        self.fileName = fileName
        self.createdAt = createdAt
    }

    var isPaid: Bool {
        return paidDate != nil
    }

    /// Paid, waiting, or overdue once `today` is past the due date.
    func status(today: Date = Date(), calendar: Calendar = .current) -> InvoiceStatus {
        if isPaid {
            return .paid
        }
        if let due = dueDate, calendar.startOfDay(for: today) > calendar.startOfDay(for: due) {
            return .overdue
        }
        return .waiting
    }

    /// "Invoice INV-0042", or "Invoice" without a number.
    var title: String {
        let trimmed = number.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Invoice"
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("inv") || lower.hasPrefix("#") {
            return trimmed
        }
        return "Invoice \(trimmed)"
    }

    /// Newest first: by date sent, then when added.
    static func sorted(_ invoices: [Invoice]) -> [Invoice] {
        return invoices.sorted { first, second in
            first.issueDate != second.issueDate ? first.issueDate > second.issueDate : first.createdAt > second.createdAt
        }
    }
}

// MARK: - JSON (money as text, like receipts; missing keys get defaults so files stay readable)

extension Business: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, kind, colorIndex, jobs, invoices, taxSetAsidePercent, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            kind: (try? container.decodeIfPresent(BusinessKind.self, forKey: .kind)) ?? .freelance,
            colorIndex: try container.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 6,
            jobs: try container.decodeIfPresent([Job].self, forKey: .jobs) ?? [],
            invoices: try container.decodeIfPresent([Invoice].self, forKey: .invoices) ?? [],
            taxSetAsidePercent: try MoneyCoding.decodeIfPresent(container, forKey: .taxSetAsidePercent),
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(colorIndex, forKey: .colorIndex)
        try container.encode(jobs, forKey: .jobs)
        try container.encode(invoices, forKey: .invoices)
        try container.encodeIfPresent(taxSetAsidePercent.map { value in MoneyCoding.text(value) },
                                      forKey: .taxSetAsidePercent)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

extension Job: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, client, startDate, isFinished, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let created = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            client: try container.decodeIfPresent(String.self, forKey: .client) ?? "",
            startDate: try container.decodeIfPresent(Date.self, forKey: .startDate) ?? created,
            isFinished: try container.decodeIfPresent(Bool.self, forKey: .isFinished) ?? false,
            createdAt: created
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(client, forKey: .client)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(isFinished, forKey: .isFinished)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

extension Invoice: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, jobID, number, client, amount, issueDate, dueDate, paidDate, notes, fileName, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let created = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            jobID: try container.decodeIfPresent(UUID.self, forKey: .jobID),
            number: try container.decodeIfPresent(String.self, forKey: .number) ?? "",
            client: try container.decodeIfPresent(String.self, forKey: .client) ?? "",
            amount: try MoneyCoding.decodeIfPresent(container, forKey: .amount) ?? 0,
            issueDate: try container.decodeIfPresent(Date.self, forKey: .issueDate) ?? created,
            dueDate: try container.decodeIfPresent(Date.self, forKey: .dueDate),
            paidDate: try container.decodeIfPresent(Date.self, forKey: .paidDate),
            notes: try container.decodeIfPresent(String.self, forKey: .notes) ?? "",
            fileName: try container.decodeIfPresent(String.self, forKey: .fileName),
            createdAt: created
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(jobID, forKey: .jobID)
        try container.encode(number, forKey: .number)
        try container.encode(client, forKey: .client)
        try container.encode(MoneyCoding.text(amount), forKey: .amount)
        try container.encode(issueDate, forKey: .issueDate)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(paidDate, forKey: .paidDate)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(fileName, forKey: .fileName)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
