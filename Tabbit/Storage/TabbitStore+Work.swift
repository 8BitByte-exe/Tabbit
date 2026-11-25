import Foundation
import PDFKit
import UIKit

/// Work: businesses, their jobs and invoices, and their receipts.
///
/// Businesses (with jobs and invoices) are saved together in `work.json`. An invoice's
/// own document is a PDF in `Work/<invoice id>.pdf`. A business's expenses are ordinary
/// receipts with `businessID` set, saved like every other receipt.
extension TabbitStore {

    static let workFileName = "work.json"
    static let workFolderName = "Work"

    // MARK: - Queries

    func business(_ id: UUID?) -> Business? {
        guard let id = id else {
            return nil
        }
        return businesses.first { business in business.id == id }
    }

    /// A business's receipts, or one job's. Newest first.
    func receipts(inBusiness businessID: UUID, job jobID: UUID? = nil) -> [ReceiptRecord] {
        return WorkSummary.receipts(of: businessID, jobID: jobID, in: receipts)
    }

    func workSummary(for business: Business, year: Int?, job jobID: UUID? = nil) -> WorkSummary {
        return WorkSummary.compute(business: business, receipts: receipts, year: year, jobID: jobID)
    }

    // MARK: - Businesses

    /// Adds a new business or saves changes to an existing one.
    func save(_ business: Business) {
        var updated = business
        updated.updatedAt = Date()
        if let index = businesses.firstIndex(where: { candidate in candidate.id == business.id }) {
            businesses[index] = updated
        } else {
            businesses.append(updated)
        }
        writeWork()
    }

    /// Deletes a business with its jobs, invoices and invoice files. Its receipts are
    /// deleted too, or moved to My Receipts.
    func deleteBusiness(_ id: UUID, keepReceipts: Bool) {
        guard let business = business(id) else {
            return
        }
        for receipt in receipts(inBusiness: id) {
            if keepReceipts {
                move(receipt.id, to: nil)
            } else {
                delete(receipt.id)
            }
        }
        for invoice in business.invoices {
            removeInvoiceFile(invoice)
        }
        businesses.removeAll { candidate in candidate.id == id }
        writeWork()
    }

    // MARK: - Jobs

    func save(_ job: Job, in businessID: UUID) {
        guard let index = businesses.firstIndex(where: { business in business.id == businessID }) else {
            return
        }
        if let jobIndex = businesses[index].jobs.firstIndex(where: { candidate in candidate.id == job.id }) {
            businesses[index].jobs[jobIndex] = job
        } else {
            businesses[index].jobs.insert(job, at: 0)
        }
        businesses[index].updatedAt = Date()
        writeWork()
    }

    /// Deletes a job. Its invoices and receipts stay with the business, without a job.
    func deleteJob(_ jobID: UUID, in businessID: UUID) {
        guard let index = businesses.firstIndex(where: { business in business.id == businessID }) else {
            return
        }
        businesses[index].jobs.removeAll { job in job.id == jobID }
        for invoiceIndex in businesses[index].invoices.indices where businesses[index].invoices[invoiceIndex].jobID == jobID {
            businesses[index].invoices[invoiceIndex].jobID = nil
        }
        businesses[index].updatedAt = Date()
        writeWork()
        for receipt in receipts(inBusiness: businessID, job: jobID) {
            var record = receipt
            record.jobID = nil
            _ = try? update(record)
        }
    }

    // MARK: - Invoices

    /// Adds or updates an invoice. `document` replaces its PDF when given; `removeDocument`
    /// deletes the one it has.
    func save(_ invoice: Invoice, in businessID: UUID, document: Data? = nil, removeDocument: Bool = false) throws {
        guard let index = businesses.firstIndex(where: { business in business.id == businessID }) else {
            return
        }
        var saved = invoice
        if let document = document {
            let name = "\(invoice.id.uuidString).pdf"
            try prepareWorkFolder()
            try document.write(to: workFolderURL().appendingPathComponent(name), options: TabbitStore.writeOptions)
            saved.fileName = name
        } else if removeDocument {
            removeInvoiceFile(saved)
            saved.fileName = nil
        }
        if let invoiceIndex = businesses[index].invoices.firstIndex(where: { candidate in candidate.id == invoice.id }) {
            businesses[index].invoices[invoiceIndex] = saved
        } else {
            businesses[index].invoices.append(saved)
        }
        businesses[index].updatedAt = Date()
        writeWork()
    }

    func deleteInvoice(_ invoiceID: UUID, in businessID: UUID) {
        guard let index = businesses.firstIndex(where: { business in business.id == businessID }),
              let invoice = businesses[index].invoice(invoiceID) else {
            return
        }
        removeInvoiceFile(invoice)
        businesses[index].invoices.removeAll { candidate in candidate.id == invoiceID }
        writeWork()
    }

    /// Ticks an invoice off as paid (today), or back to unpaid.
    func setPaid(_ paid: Bool, invoice invoiceID: UUID, in businessID: UUID, on date: Date = Date()) {
        guard let index = businesses.firstIndex(where: { business in business.id == businessID }),
              let invoiceIndex = businesses[index].invoices.firstIndex(where: { invoice in invoice.id == invoiceID }) else {
            return
        }
        businesses[index].invoices[invoiceIndex].paidDate = paid ? Calendar.current.startOfDay(for: date) : nil
        writeWork()
    }

    /// The invoice's PDF, if it has one on this iPhone.
    func invoiceFileURL(_ invoice: Invoice) -> URL? {
        guard let name = invoice.fileName else {
            return nil
        }
        let url = workFolderURL().appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Receipts

    /// Files a receipt under a business (and job), out of any group.
    func moveToBusiness(_ receiptID: UUID, businessID: UUID, jobID: UUID? = nil) {
        guard var record = receipt(receiptID) else {
            return
        }
        record.groupID = nil
        record.businessID = businessID
        record.jobID = jobID
        do {
            try update(record)
        } catch {
            lastError = "Couldn't move the receipt: \(error.localizedDescription)"
        }
    }

    // MARK: - Files

    func workFolderURL() -> URL {
        return folder.appendingPathComponent(TabbitStore.workFolderName, isDirectory: true)
    }

    func loadWork() {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(TabbitStore.workFileName)),
              let stored = try? JSONDecoder().decode([Business].self, from: data) else {
            return
        }
        businesses = stored.sorted { first, second in first.createdAt < second.createdAt }
    }

    private func writeWork() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(businesses)
            try data.write(to: folder.appendingPathComponent(TabbitStore.workFileName),
                           options: TabbitStore.writeOptions)
        } catch {
            lastError = "Couldn't save your work: \(error.localizedDescription)"
        }
    }

    private func prepareWorkFolder() throws {
        let url = workFolderURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                    attributes: TabbitStore.protection)
        }
    }

    private func removeInvoiceFile(_ invoice: Invoice) {
        guard let name = invoice.fileName else {
            return
        }
        _ = try? FileManager.default.removeItem(at: workFolderURL().appendingPathComponent(name))
    }
}

/// Turns what the person attached to an invoice into one PDF, and reads its text.
enum InvoiceDocument {

    /// Scanned pages or photos as a PDF, one page each (long side at most 1700 pt, JPEG inside).
    static func pdfData(from images: [UIImage]) -> Data? {
        guard !images.isEmpty else {
            return nil
        }
        let pages: [UIImage] = images.compactMap { image in
            guard let data = ScanProcessor.jpegData(for: image, maxDimension: 1700, quality: 0.75) else {
                return nil
            }
            return UIImage(data: data)
        }
        guard let first = pages.first else {
            return nil
        }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: first.size))
        return renderer.pdfData { context in
            for page in pages {
                let bounds = CGRect(origin: .zero, size: page.size)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                page.draw(in: bounds)
            }
        }
    }

    /// The PDF's own text, line by line (empty for a PDF that is only pictures).
    static func textLines(ofPDF data: Data) -> [String] {
        guard let document = PDFDocument(data: data) else {
            return []
        }
        var lines: [String] = []
        for index in 0..<document.pageCount {
            guard let text = document.page(at: index)?.string else {
                continue
            }
            lines.append(contentsOf: text.components(separatedBy: .newlines))
        }
        return lines.filter { line in !line.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The PDF's pages as pictures (at most 3), for reading a PDF that has no text.
    static func pageImages(ofPDF data: Data) -> [UIImage] {
        guard let document = PDFDocument(data: data) else {
            return []
        }
        var images: [UIImage] = []
        for index in 0..<min(document.pageCount, 3) {
            guard let page = document.page(at: index) else {
                continue
            }
            let bounds = page.bounds(for: .mediaBox)
            let longSide = max(bounds.width, bounds.height)
            guard longSide > 0 else {
                continue
            }
            let scale = 2000 / longSide
            images.append(page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale),
                                         for: .mediaBox))
        }
        return images
    }

    /// Reads an invoice PDF: its own text when it has some, otherwise the text recognized
    /// in its pages (on the device). Call off the main thread.
    static func read(pdf data: Data, reference: Date = Date()) async -> InvoiceReading {
        var lines = textLines(ofPDF: data)
        if lines.count < 3 {
            let images = pageImages(ofPDF: data)
            if !images.isEmpty, let scan = try? await TextRecognizer.read(images, options: OCRSettings.current) {
                lines = LineGrouper.lines(from: scan).map { line in line.text }
            }
        }
        return InvoiceReader.read(lines: lines, reference: reference)
    }

    /// Reads a scanned or photographed invoice (on the device). Call off the main thread.
    static func read(images: [UIImage], reference: Date = Date()) async -> InvoiceReading {
        guard !images.isEmpty, let scan = try? await TextRecognizer.read(images, options: OCRSettings.current) else {
            return InvoiceReading()
        }
        let lines = LineGrouper.lines(from: scan).map { line in line.text }
        return InvoiceReader.read(lines: lines, reference: reference)
    }
}
