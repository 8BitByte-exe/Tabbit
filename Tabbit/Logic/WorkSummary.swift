import Foundation

/// A business's numbers for one calendar year, in whole cents.
///
/// - Income is what clients paid during the year (by the day it was paid).
/// - Invoiced is what was billed during the year (by the day the invoice was sent).
/// - Waiting is what's still unpaid on invoices sent that year; overdue is the part past its due date.
/// - Expenses are the business's receipts dated that year.
/// - Profit is income minus expenses.
struct WorkSummary: Equatable {
    /// The calendar year, or nil for all years (a job's totals).
    var year: Int?
    var incomeCents: Int = 0
    var invoicedCents: Int = 0
    var waitingCents: Int = 0
    var overdueCents: Int = 0
    var overdueCount: Int = 0
    var expensesCents: Int = 0
    var invoiceCount: Int = 0
    var receiptCount: Int = 0

    var profitCents: Int {
        return incomeCents - expensesCents
    }

    /// The share of a positive profit to put aside for tax, or nil when no rate is set.
    func setAsideCents(percent: Decimal?) -> Int? {
        guard let percent = percent, percent > 0 else {
            return nil
        }
        guard profitCents > 0 else {
            return 0
        }
        return Money.cents(Money.fromCents(profitCents) * percent / 100)
    }

    /// The year's numbers for a business, or for one of its jobs (`jobID`); `year == nil` counts every year.
    /// `receipts` may hold any receipts: only the business's (and the job's) are counted.
    static func compute(business: Business, receipts: [ReceiptRecord], year: Int?, jobID: UUID? = nil,
                        today: Date = Date(), calendar: Calendar = .current) -> WorkSummary {
        var summary = WorkSummary(year: year)
        func inYear(_ date: Date) -> Bool {
            guard let year = year else {
                return true
            }
            return calendar.component(.year, from: date) == year
        }
        let invoices = jobID == nil ? business.invoices : business.invoices.filter { invoice in invoice.jobID == jobID }
        for invoice in invoices {
            let cents = Money.cents(invoice.amount)
            if let paid = invoice.paidDate, inYear(paid) {
                summary.incomeCents += cents
            }
            guard inYear(invoice.issueDate) else {
                continue
            }
            summary.invoiceCount += 1
            summary.invoicedCents += cents
            switch invoice.status(today: today, calendar: calendar) {
            case .paid:
                break
            case .waiting:
                summary.waitingCents += cents
            case .overdue:
                summary.waitingCents += cents
                summary.overdueCents += cents
                summary.overdueCount += 1
            }
        }
        for receipt in WorkSummary.receipts(of: business.id, jobID: jobID, in: receipts) where inYear(receipt.date) {
            summary.receiptCount += 1
            summary.expensesCents += Money.cents(receipt.effectiveTotal)
        }
        return summary
    }

    /// Everything unpaid right now, whatever year it was sent: the total and how many.
    static func unpaid(business: Business, today: Date = Date(),
                       calendar: Calendar = .current) -> (cents: Int, count: Int, overdueCount: Int) {
        var cents = 0
        var count = 0
        var overdue = 0
        for invoice in business.invoices where !invoice.isPaid {
            cents += Money.cents(invoice.amount)
            count += 1
            if invoice.status(today: today, calendar: calendar) == .overdue {
                overdue += 1
            }
        }
        return (cents: cents, count: count, overdueCount: overdue)
    }

    /// The business's receipts (or one job's), from any list of receipts.
    static func receipts(of businessID: UUID, jobID: UUID? = nil, in receipts: [ReceiptRecord]) -> [ReceiptRecord] {
        return receipts.filter { receipt in
            receipt.businessID == businessID && (jobID == nil || receipt.jobID == jobID)
        }
    }

    /// Years with any invoice or receipt, plus the current year. Newest first.
    static func years(business: Business, receipts: [ReceiptRecord], today: Date = Date(),
                      calendar: Calendar = .current) -> [Int] {
        var years: Set<Int> = [calendar.component(.year, from: today)]
        for invoice in business.invoices {
            years.insert(calendar.component(.year, from: invoice.issueDate))
            if let paid = invoice.paidDate {
                years.insert(calendar.component(.year, from: paid))
            }
        }
        for receipt in WorkSummary.receipts(of: business.id, in: receipts) {
            years.insert(calendar.component(.year, from: receipt.date))
        }
        return years.sorted(by: >)
    }
}

/// A year of a business as CSV, for an accountant or a tax return: every invoice and expense,
/// one per row, oldest first.
enum WorkCSV {
    static let header = ["Type", "Date", "Job", "Client or merchant", "Category", "Invoice number", "Amount",
                         "Tax", "Status", "Paid on"]

    static func csv(business: Business, receipts: [ReceiptRecord], year: Int, today: Date = Date(),
                    calendar: Calendar = .current) -> String {
        var rows: [(date: Date, fields: [String])] = []
        for invoice in business.invoices where calendar.component(.year, from: invoice.issueDate) == year {
            let status: String
            switch invoice.status(today: today, calendar: calendar) {
            case .paid: status = "Paid"
            case .waiting: status = "Waiting"
            case .overdue: status = "Overdue"
            }
            rows.append((date: invoice.issueDate, fields: [
                "Invoice", isoDate(invoice.issueDate, calendar: calendar), business.job(invoice.jobID)?.displayName ?? "",
                invoice.client, "", invoice.number, MoneyCoding.text(Money.rounded(invoice.amount)), "", status,
                invoice.paidDate.map { date in isoDate(date, calendar: calendar) } ?? "",
            ]))
        }
        for receipt in WorkSummary.receipts(of: business.id, in: receipts)
        where calendar.component(.year, from: receipt.date) == year {
            rows.append((date: receipt.date, fields: [
                "Expense", isoDate(receipt.date, calendar: calendar), business.job(receipt.jobID)?.displayName ?? "",
                receipt.displayTitle, receipt.category.title, "", MoneyCoding.text(Money.rounded(receipt.effectiveTotal)),
                receipt.tax.map { tax in MoneyCoding.text(Money.rounded(tax)) } ?? "", "Paid", "",
            ]))
        }
        let sorted = rows.sorted { first, second in first.date < second.date }
        let lines = [header] + sorted.map { row in row.fields }
        return lines.map { line in line.map(CSVExporter.escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// Writes the CSV to the temporary folder and returns its URL.
    static func write(business: Business, receipts: [ReceiptRecord], year: Int) -> URL? {
        let text = csv(business: business, receipts: receipts, year: year)
        let safeName = business.displayName.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { part in !part.isEmpty }
            .joined(separator: "-")
        let name = "\(safeName.isEmpty ? "Work" : safeName)-\(year).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try Data(text.utf8).write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    private static func isoDate(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return CalendarDate(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1).isoString
    }
}
