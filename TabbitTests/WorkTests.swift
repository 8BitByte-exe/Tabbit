import XCTest
@testable import Tabbit

/// Work: invoice status, the year's numbers, CSV, reading invoices, and saving businesses.
final class WorkTests: XCTestCase {

    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        return utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func temporaryFolder() -> URL {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkTests-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - Invoice status

    func testInvoiceStatus() {
        let today = day(2026, 11, 10)
        XCTAssertEqual(Invoice(amount: money("100")).status(today: today, calendar: utc), .waiting)
        XCTAssertEqual(Invoice(amount: money("100"), dueDate: day(2026, 11, 10)).status(today: today, calendar: utc),
                       .waiting, "Due today isn't overdue yet")
        XCTAssertEqual(Invoice(amount: money("100"), dueDate: day(2026, 11, 9)).status(today: today, calendar: utc),
                       .overdue)
        XCTAssertEqual(Invoice(amount: money("100"), dueDate: day(2026, 1, 1), paidDate: day(2026, 2, 1))
                        .status(today: today, calendar: utc), .paid)
    }

    func testInvoiceTitle() {
        XCTAssertEqual(Invoice(number: "").title, "Invoice")
        XCTAssertEqual(Invoice(number: "42").title, "Invoice 42")
        XCTAssertEqual(Invoice(number: "INV-0042").title, "INV-0042")
    }

    // MARK: - The year's numbers

    private let jobA = Job(name: "Website", client: "Harbor Dental")
    private let jobB = Job(name: "Logo", client: "Northwind")

    private func sampleBusiness() -> Business {
        return Business(name: "Studio", jobs: [jobA, jobB], invoices: [
            // Sent and paid in 2026.
            Invoice(jobID: jobA.id, amount: money("1000.00"), issueDate: day(2026, 2, 1), paidDate: day(2026, 3, 1)),
            // Sent in 2026, paid in 2027: invoiced in 2026, income in 2027.
            Invoice(jobID: jobB.id, amount: money("500.00"), issueDate: day(2026, 12, 20), paidDate: day(2027, 1, 5)),
            // Overdue.
            Invoice(jobID: jobA.id, amount: money("300.00"), issueDate: day(2026, 10, 1), dueDate: day(2026, 10, 31)),
            // Waiting, not yet due.
            Invoice(amount: money("200.00"), issueDate: day(2026, 11, 1), dueDate: day(2026, 12, 1)),
        ])
    }

    private func sampleReceipts(for business: Business) -> [ReceiptRecord] {
        return [
            ReceiptRecord(businessID: business.id, jobID: jobA.id, merchant: "Office Depot", date: day(2026, 4, 2),
                          total: money("120.50")),
            ReceiptRecord(businessID: business.id, merchant: "Adobe", date: day(2026, 6, 1), total: money("79.50")),
            ReceiptRecord(businessID: business.id, merchant: "Last year", date: day(2025, 6, 1), total: money("10.00")),
            ReceiptRecord(merchant: "Personal", date: day(2026, 6, 1), total: money("999.00")),
            ReceiptRecord(businessID: UUID(), merchant: "Another business", date: day(2026, 6, 1), total: money("55.00")),
        ]
    }

    func testYearSummary() {
        let business = sampleBusiness()
        let receipts = sampleReceipts(for: business)
        let summary = WorkSummary.compute(business: business, receipts: receipts, year: 2026,
                                          today: day(2026, 11, 10), calendar: utc)
        XCTAssertEqual(summary.incomeCents, 100_000)
        XCTAssertEqual(summary.invoicedCents, 200_000)
        XCTAssertEqual(summary.invoiceCount, 4)
        XCTAssertEqual(summary.waitingCents, 50_000)
        XCTAssertEqual(summary.overdueCents, 30_000)
        XCTAssertEqual(summary.overdueCount, 1)
        XCTAssertEqual(summary.expensesCents, 20_000)
        XCTAssertEqual(summary.receiptCount, 2)
        XCTAssertEqual(summary.profitCents, 80_000)

        let next = WorkSummary.compute(business: business, receipts: receipts, year: 2027,
                                       today: day(2027, 1, 10), calendar: utc)
        XCTAssertEqual(next.incomeCents, 50_000, "Income counts in the year it was paid")
        XCTAssertEqual(next.invoicedCents, 0)
        XCTAssertEqual(next.expensesCents, 0)
    }

    func testJobTotalsCoverEveryYear() {
        let business = sampleBusiness()
        let receipts = sampleReceipts(for: business)
        let job = WorkSummary.compute(business: business, receipts: receipts, year: nil, jobID: jobA.id,
                                      today: day(2026, 11, 10), calendar: utc)
        XCTAssertEqual(job.incomeCents, 100_000)
        XCTAssertEqual(job.invoicedCents, 130_000)
        XCTAssertEqual(job.overdueCount, 1)
        XCTAssertEqual(job.expensesCents, 12_050)
        XCTAssertNil(job.year)
    }

    func testTaxSetAside() {
        var summary = WorkSummary(year: 2026)
        summary.incomeCents = 100_000
        summary.expensesCents = 20_000
        XCTAssertEqual(summary.setAsideCents(percent: money("25")), 20_000)
        XCTAssertEqual(summary.setAsideCents(percent: money("12.5")), 10_000)
        XCTAssertNil(summary.setAsideCents(percent: nil))
        XCTAssertNil(summary.setAsideCents(percent: 0))
        summary.expensesCents = 150_000
        XCTAssertEqual(summary.setAsideCents(percent: money("25")), 0, "Nothing to put aside on a loss")
    }

    func testYearsAndUnpaid() {
        let business = sampleBusiness()
        let receipts = sampleReceipts(for: business)
        XCTAssertEqual(WorkSummary.years(business: business, receipts: receipts, today: day(2026, 11, 10), calendar: utc),
                       [2027, 2026, 2025])
        XCTAssertEqual(WorkSummary.years(business: Business(name: "New"), receipts: [], today: day(2026, 11, 10),
                                         calendar: utc), [2026])
        let unpaid = WorkSummary.unpaid(business: business, today: day(2026, 11, 10), calendar: utc)
        XCTAssertEqual(unpaid.cents, 50_000)
        XCTAssertEqual(unpaid.count, 2)
        XCTAssertEqual(unpaid.overdueCount, 1)
    }

    func testWorkCSV() {
        var business = sampleBusiness()
        business.invoices[0].client = "Harbor Dental, Inc."
        business.invoices[0].number = "INV-1"
        let csv = WorkCSV.csv(business: business, receipts: sampleReceipts(for: business), year: 2026,
                              today: day(2026, 11, 10), calendar: utc)
        let lines = csv.components(separatedBy: "\r\n").filter { line in !line.isEmpty }
        XCTAssertEqual(lines.first, WorkCSV.header.joined(separator: ","))
        XCTAssertEqual(lines.count, 1 + 4 + 2, "4 invoices and 2 expenses from 2026")
        XCTAssertEqual(lines[1], "Invoice,2026-02-01,Website,\"Harbor Dental, Inc.\",,INV-1,1000,,Paid,2026-03-01")
        XCTAssertEqual(lines[2], "Expense,2026-04-02,Website,Office Depot,Other,,120.5,,Paid,")
        XCTAssertTrue(lines.contains { line in line.hasPrefix("Invoice,2026-10-01") && line.contains(",Overdue,") })
        XCTAssertTrue(lines.contains { line in line.hasPrefix("Invoice,2026-11-01") && line.contains(",Waiting,") })
    }

    // MARK: - Reading invoices

    func testReadsAmountDueNumberAndDates() {
        let reading = InvoiceReader.read(lines: [
            "Sam Rivera Design",
            "INVOICE",
            "Invoice #: 2026-014",
            "Invoice Date: 2026-03-03",
            "Due Date: 2026-04-02",
            "Bill to: Harbor Dental",
            "Website design 40 hrs @ 75.00     3,000.00",
            "Hosting setup                       250.00",
            "Subtotal                          3,250.00",
            "Tax 13%                             422.50",
            "Total                             3,672.50",
            "Amount Due                    $3,672.50 CAD",
        ])
        XCTAssertEqual(reading.amount, money("3672.50"))
        XCTAssertEqual(reading.number, "2026-014")
        XCTAssertEqual(reading.issueDate, CalendarDate(year: 2026, month: 3, day: 3))
        XCTAssertEqual(reading.dueDate, CalendarDate(year: 2026, month: 4, day: 2))
    }

    func testReadsLabelsWithValuesOnTheNextLine() {
        let reading = InvoiceReader.read(lines: [
            "Invoice Number",
            "INV-0042",
            "Balance Due",
            "1.250,00 €",
            "Terms: Net 30",
        ])
        XCTAssertEqual(reading.number, "INV-0042")
        XCTAssertEqual(reading.amount, money("1250.00"))
        XCTAssertEqual(reading.dueInDays, 30)
        XCTAssertNil(reading.dueDate)
    }

    func testTotalSkipsSubtotalAndTaxAndFallsBackToTheLargestAmount() {
        XCTAssertEqual(InvoiceReader.amountDue(in: ["Subtotal 100.00", "Tax total 13.00", "Total 113.00"]),
                       money("113.00"))
        XCTAssertEqual(InvoiceReader.amountDue(in: ["Consulting 400.00", "Travel 85.50"]), money("400.00"))
        XCTAssertNil(InvoiceReader.amountDue(in: ["Thanks for your business"]))
    }

    func testInvoiceNumberNeedsADigit() {
        XCTAssertNil(InvoiceReader.number(in: ["Invoice No. pending", "Invoice notes: thanks"]))
        XCTAssertEqual(InvoiceReader.number(in: ["INVOICE # A12."]), "A12")
        XCTAssertEqual(InvoiceReader.number(in: ["Ref inv-77 for March"]), "inv-77")
        XCTAssertTrue(InvoiceReader.read(lines: []).isEmpty)
    }

    // MARK: - Saving

    func testBusinessRoundTripsThroughJSON() throws {
        let business = Business(name: "Studio", kind: .business, colorIndex: 3,
                                jobs: [Job(name: "Logo", client: "Northwind", isFinished: true)],
                                invoices: [Invoice(number: "7", client: "Northwind", amount: money("1234.56"),
                                                   dueDate: day(2026, 1, 1), paidDate: day(2026, 1, 5),
                                                   fileName: "x.pdf")],
                                taxSetAsidePercent: money("22.5"))
        let data = try JSONEncoder().encode(business)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"1234.56\""), "Money is stored as text")
        let decoded = try JSONDecoder().decode(Business.self, from: data)
        XCTAssertEqual(decoded, business)
    }

    func testReceiptKeepsItsBusinessAndJob() throws {
        let businessID = UUID()
        let jobID = UUID()
        let receipt = ReceiptRecord(businessID: businessID, jobID: jobID, merchant: "Office Depot", total: money("9.99"))
        let decoded = try JSONDecoder().decode(ReceiptRecord.self, from: JSONEncoder().encode(receipt))
        XCTAssertEqual(decoded.businessID, businessID)
        XCTAssertEqual(decoded.jobID, jobID)
        XCTAssertNil(decoded.groupID)
    }

    @MainActor
    func testWorkSurvivesARestartAndStaysOutOfMyReceipts() throws {
        let folder = temporaryFolder()
        let store = TabbitStore(folder: folder)
        let job = Job(name: "Website", client: "Harbor Dental")
        let business = Business(name: "Studio", jobs: [job])
        store.save(business)
        try store.save(Invoice(jobID: job.id, client: "Harbor Dental", amount: money("800.00")), in: business.id,
                       document: Data("%PDF-1.4".utf8))
        let expense = try store.add(ReceiptRecord(businessID: business.id, jobID: job.id, merchant: "Shell",
                                                  total: money("52.10")))
        let personal = try store.add(ReceiptRecord(merchant: "Cafe", total: money("4.50")))

        let reopened = TabbitStore(folder: folder)
        let loaded = try XCTUnwrap(reopened.business(business.id))
        XCTAssertEqual(loaded.jobs.map { saved in saved.name }, ["Website"])
        let invoice = try XCTUnwrap(loaded.invoices.first)
        XCTAssertEqual(invoice.amount, money("800.00"))
        let file = try XCTUnwrap(reopened.invoiceFileURL(invoice))
        XCTAssertEqual(try Data(contentsOf: file), Data("%PDF-1.4".utf8))

        XCTAssertEqual(reopened.receipts(in: nil).map { receipt in receipt.id }, [personal.id])
        XCTAssertEqual(reopened.receipts(inBusiness: business.id).map { receipt in receipt.id }, [expense.id])
        XCTAssertEqual(reopened.receipts(inBusiness: business.id, job: job.id).count, 1)
        XCTAssertEqual(reopened.personalReceipts.map { receipt in receipt.id }, [personal.id])
    }

    @MainActor
    func testTickingOffAnInvoice() throws {
        let store = TabbitStore(folder: temporaryFolder())
        let business = Business(name: "Studio")
        store.save(business)
        let invoice = Invoice(amount: money("100.00"))
        try store.save(invoice, in: business.id)
        store.setPaid(true, invoice: invoice.id, in: business.id, on: day(2026, 5, 1))
        XCTAssertEqual(store.business(business.id)?.invoice(invoice.id)?.isPaid, true)
        store.setPaid(false, invoice: invoice.id, in: business.id)
        XCTAssertEqual(store.business(business.id)?.invoice(invoice.id)?.isPaid, false)
    }

    @MainActor
    func testDeletingAJobKeepsItsInvoicesAndExpenses() throws {
        let store = TabbitStore(folder: temporaryFolder())
        let job = Job(name: "Logo")
        let business = Business(name: "Studio", jobs: [job])
        store.save(business)
        try store.save(Invoice(jobID: job.id, amount: money("100.00")), in: business.id)
        let expense = try store.add(ReceiptRecord(businessID: business.id, jobID: job.id, total: money("5.00")))

        store.deleteJob(job.id, in: business.id)
        let updated = try XCTUnwrap(store.business(business.id))
        XCTAssertTrue(updated.jobs.isEmpty)
        XCTAssertEqual(updated.invoices.count, 1)
        XCTAssertNil(updated.invoices.first?.jobID)
        XCTAssertEqual(store.receipt(expense.id)?.businessID, business.id)
        XCTAssertNil(store.receipt(expense.id)?.jobID)
    }

    @MainActor
    func testDeletingABusinessCanKeepItsExpenses() throws {
        let store = TabbitStore(folder: temporaryFolder())
        let business = Business(name: "Studio")
        store.save(business)
        try store.save(Invoice(amount: money("100.00")), in: business.id, document: Data("%PDF".utf8))
        let fileURL = try XCTUnwrap(store.business(business.id)?.invoices.first.flatMap { invoice in
            store.invoiceFileURL(invoice)
        })
        let expense = try store.add(ReceiptRecord(businessID: business.id, total: money("5.00")))

        store.deleteBusiness(business.id, keepReceipts: true)
        XCTAssertNil(store.business(business.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "Invoice files go with the business")
        XCTAssertEqual(store.receipts(in: nil).map { receipt in receipt.id }, [expense.id])
        XCTAssertNil(store.receipt(expense.id)?.businessID)
    }

    @MainActor
    func testMovingBetweenAGroupAndABusiness() throws {
        let store = TabbitStore(folder: temporaryFolder())
        let group = SplitGroup(name: "Trip", members: [store.me])
        store.save(group)
        let business = Business(name: "Studio")
        store.save(business)
        let receipt = try store.add(ReceiptRecord(groupID: group.id, total: money("10.00")))

        store.moveToBusiness(receipt.id, businessID: business.id)
        XCTAssertNil(store.receipt(receipt.id)?.groupID)
        XCTAssertEqual(store.receipts(inBusiness: business.id).count, 1)
        XCTAssertTrue(store.receipts(in: group.id).isEmpty)

        store.move(receipt.id, to: group.id)
        XCTAssertNil(store.receipt(receipt.id)?.businessID)
        XCTAssertEqual(store.receipts(in: group.id).count, 1)
    }
}
