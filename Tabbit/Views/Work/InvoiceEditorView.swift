import PDFKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

/// Opens the invoice editor for a new invoice (optionally for a job) or an existing one.
struct InvoiceEditorTarget: Identifiable {
    let businessID: UUID
    let invoice: Invoice?
    let jobID: UUID?

    var id: String {
        return invoice?.id.uuidString ?? "new-\(businessID.uuidString)-\(jobID?.uuidString ?? "")"
    }
}

/// Add or edit an invoice: attach the invoice itself (scan, photo or PDF, read on the device to
/// fill in the amount, number and dates) or just type the amount; tick it off when it's paid.
struct InvoiceEditorView: View {
    let target: InvoiceEditorTarget

    @EnvironmentObject private var store: TabbitStore
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var client: String
    @State private var jobID: UUID?
    @State private var number: String
    @State private var issueDate: Date
    @State private var dueDate: Date?
    @State private var isPaid: Bool
    @State private var paidDate: Date

    /// A newly attached document (PDF), saved with the invoice.
    @State private var newDocument: Data?
    @State private var removesDocument = false
    @State private var isReading = false
    @State private var filled: Set<FilledField> = []
    @State private var readMessage: String?

    @State private var choosingIssueDate = false
    @State private var choosingDueDate = false
    @State private var choosingPaidDate = false
    @State private var showsScanner = false
    @State private var showsPhotoPicker = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showsFileImporter = false
    @State private var viewingDocument: InvoiceDocumentSource?
    @State private var dialog: ClayDialog?
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case amount
        case client
        case number
    }

    enum FilledField: Hashable {
        case amount
        case number
        case issueDate
        case dueDate
    }

    init(target: InvoiceEditorTarget) {
        self.target = target
        let invoice = target.invoice
        _amountText = State(initialValue: invoice.map { value in MoneyInput.editText(value.amount) } ?? "")
        _client = State(initialValue: invoice?.client ?? "")
        _jobID = State(initialValue: invoice?.jobID ?? target.jobID)
        _number = State(initialValue: invoice?.number ?? "")
        _issueDate = State(initialValue: invoice?.issueDate ?? Calendar.current.startOfDay(for: Date()))
        _dueDate = State(initialValue: invoice?.dueDate)
        _isPaid = State(initialValue: invoice?.isPaid ?? false)
        _paidDate = State(initialValue: invoice?.paidDate ?? Calendar.current.startOfDay(for: Date()))
    }

    private var business: Business? {
        return store.business(target.businessID)
    }

    private var amount: Decimal? {
        return MoneyInput.parse(amountText)
    }

    private var amountIsInvalid: Bool {
        return !amountText.trimmingCharacters(in: .whitespaces).isEmpty && amount == nil
    }

    private var canSave: Bool {
        guard let amount = amount else {
            return false
        }
        return amount >= 0
    }

    /// The document shown in the form: a new one, or the saved one unless it's being removed.
    private var documentSource: InvoiceDocumentSource? {
        if let data = newDocument {
            return .data(data)
        }
        if !removesDocument, let invoice = target.invoice, let url = store.invoiceFileURL(invoice) {
            return .file(url)
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                SheetHeader(title: target.invoice == nil ? "New Invoice" : "Invoice", onClose: close)
                documentCard
                amountCard
                detailsCard
                paidCard
                if target.invoice != nil {
                    Button(action: askToDelete) {
                        Label("Delete Invoice", systemImage: "trash")
                    }
                    .buttonStyle(NeumorphicButtonStyle(prominence: .destructive))
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .themedScreen()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focus == nil {
                saveBar
            } else {
                KeyboardDoneBar {
                    focus = nil
                }
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .claySheet()
        .clayDialog($dialog)
        .sheet(isPresented: $choosingIssueDate) {
            DatePickerSheet(date: $issueDate)
        }
        .sheet(isPresented: $choosingDueDate) {
            DatePickerSheet(date: Binding(get: {
                dueDate ?? defaultDueDate(days: 30)
            }, set: { date in
                dueDate = date
            }))
        }
        .sheet(isPresented: $choosingPaidDate) {
            DatePickerSheet(date: $paidDate)
        }
        .sheet(item: $viewingDocument) { source in
            InvoiceDocumentSheet(source: source, title: number.isEmpty ? "Invoice" : number)
        }
        .fullScreenCover(isPresented: $showsScanner) {
            DocumentScannerView(onOutcome: { outcome in
                showsScanner = false
                if case .scanned(let images) = outcome {
                    attach(images: images)
                }
            })
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $photoSelection,
                      maxSelectionCount: 5, selectionBehavior: .ordered, matching: .images)
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else {
                return
            }
            photoSelection = []
            isReading = true
            Task {
                let images = await ReceiptFlow.loadImages(items)
                if images.isEmpty {
                    isReading = false
                    readMessage = "Couldn't open that photo."
                } else {
                    attach(images: images)
                }
            }
        }
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.pdf, .image],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                attach(fileAt: url)
            }
        }
    }

    // MARK: - Document

    private var documentCard: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionLabel(title: "The invoice")
                if isReading {
                    HStack(spacing: Theme.Spacing.m) {
                        ProgressView()
                            .tint(Theme.Colors.text)
                        Text("Reading the invoice…")
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.Colors.text)
                    }
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .accessibilityElement(children: .combine)
                } else if let source = documentSource {
                    HStack(spacing: Theme.Spacing.m) {
                        Button(action: {
                            viewingDocument = source
                        }, label: {
                            HStack(spacing: Theme.Spacing.m) {
                                IconBadge(symbol: "doc.richtext.fill", tone: .positive, size: 40)
                                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                    Text("Invoice attached")
                                        .font(Theme.Fonts.headline)
                                        .foregroundStyle(Theme.Colors.text)
                                    Text(pageCountText(source))
                                        .font(Theme.Fonts.caption)
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                }
                                Spacer(minLength: 0)
                            }
                        })
                        .buttonStyle(NeumorphicCardButtonStyle(padding: Theme.Spacing.m))
                        .accessibilityLabel("View the attached invoice")
                        Button(action: {
                            newDocument = nil
                            removesDocument = true
                            filled = []
                            readMessage = nil
                        }, label: {
                            Image(systemName: "trash")
                        })
                        .buttonStyle(NeumorphicIconButtonStyle(prominence: .destructive))
                        .accessibilityLabel("Remove the attached invoice")
                    }
                } else {
                    Text("Attach the invoice you sent, and Tabbit fills in what it can read. Or skip this and type the amount.")
                        .font(Theme.Fonts.callout)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Theme.Spacing.s) {
                        attachTile(symbol: "camera.viewfinder", title: "Scan") {
                            focus = nil
                            if VNDocumentCameraViewController.isSupported {
                                showsScanner = true
                            } else {
                                readMessage = "The camera scanner isn't available. Choose a photo or a PDF instead."
                            }
                        }
                        attachTile(symbol: "photo.on.rectangle.angled", title: "Photo") {
                            focus = nil
                            showsPhotoPicker = true
                        }
                        attachTile(symbol: "doc.fill", title: "PDF") {
                            focus = nil
                            showsFileImporter = true
                        }
                    }
                }
                if let message = readMessage {
                    Label(message, systemImage: filled.isEmpty ? "info.circle.fill" : "sparkles")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(filled.isEmpty ? Theme.Colors.warning : Theme.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Label("Read on this iPhone. Nothing is uploaded.", systemImage: "lock.fill")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }

    private func attachTile(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(Theme.Fonts.title3)
                    .foregroundStyle(Theme.Colors.text)
                Text(title)
                    .font(Theme.Fonts.subheadline)
                    .foregroundStyle(Theme.Colors.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xs)
        }
        .buttonStyle(NeumorphicCardButtonStyle(padding: Theme.Spacing.m, showsChevron: false))
        .accessibilityLabel("Attach with \(title)")
    }

    private func pageCountText(_ source: InvoiceDocumentSource) -> String {
        let count = source.document?.pageCount ?? 0
        let pages = count == 1 ? "1 page" : "\(count) pages"
        return "PDF · \(pages) · tap to view"
    }

    // MARK: - Fields

    private func label(_ title: String, _ field: FilledField?) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            SectionLabel(title: title)
            if let field = field, filled.contains(field) {
                IconBadge(symbol: "sparkles", tone: .positive, size: 20)
                    .accessibilityElement()
                    .accessibilityLabel("Filled in from the invoice")
            }
        }
    }

    private var amountCard: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                label("Amount", .amount)
                HStack(spacing: Theme.Spacing.s) {
                    Text(Money.currencySymbol)
                        .font(Theme.Fonts.title3)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(Theme.Fonts.title3.monospacedDigit())
                        .focused($focus, equals: .amount)
                        .insetField()
                        .accessibilityLabel("Amount")
                }
                if amountIsInvalid {
                    Label("That isn't an amount.", systemImage: "exclamationmark.circle.fill")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.danger)
                }
            }
        }
    }

    private var detailsCard: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if let business = business, !business.jobs.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        label("Job", nil)
                        FlowLayout {
                            jobChip(title: "No job", id: nil)
                            ForEach(business.jobs.filter { job in !job.isFinished || job.id == jobID }) { job in
                                jobChip(title: job.displayName, id: job.id)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    label("Client", nil)
                    TextField("Who you billed", text: $client)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focus, equals: .client)
                        .onSubmit {
                            focus = .number
                        }
                        .insetField()
                        .accessibilityLabel("Client")
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    label("Invoice number", .number)
                    TextField("Optional", text: $number)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focus, equals: .number)
                        .insetField()
                        .accessibilityLabel("Invoice number")
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    label("Sent", .issueDate)
                    DateRowButton(symbol: "paperplane.fill", text: DateText.long(issueDate)) {
                        focus = nil
                        choosingIssueDate = true
                    }
                    .accessibilityLabel("Sent, \(DateText.long(issueDate))")
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    label("Due", .dueDate)
                    HStack(spacing: Theme.Spacing.s) {
                        DateRowButton(symbol: "calendar.badge.clock",
                                      text: dueDate.map { date in DateText.long(date) } ?? "No due date",
                                      isPlaceholder: dueDate == nil) {
                            focus = nil
                            choosingDueDate = true
                        }
                        .accessibilityLabel(dueDate.map { date in "Due, \(DateText.long(date))" } ?? "Add a due date")
                        if dueDate != nil {
                            Button(action: {
                                dueDate = nil
                                filled.remove(.dueDate)
                            }, label: {
                                Image(systemName: "xmark")
                            })
                            .buttonStyle(NeumorphicIconButtonStyle())
                            .accessibilityLabel("Remove the due date")
                        }
                    }
                    FlowLayout {
                        dueChip(days: 14)
                        dueChip(days: 30)
                        dueChip(days: 60)
                    }
                }
            }
        }
    }

    private func jobChip(title: String, id: UUID?) -> some View {
        Button(action: {
            jobID = id
            if client.trimmingCharacters(in: .whitespaces).isEmpty, let job = business?.job(id), !job.client.isEmpty {
                client = job.client
            }
        }, label: {
            Text(title)
        })
        .buttonStyle(ClayChipStyle(isSelected: jobID == id))
        .accessibilityLabel(id == nil ? "No job" : "Job, \(title)")
        .accessibilityAddTraits(jobID == id ? [.isSelected] : [])
    }

    private func dueChip(days: Int) -> some View {
        let date = defaultDueDate(days: days)
        let isSelected = dueDate.map { value in Calendar.current.isDate(value, inSameDayAs: date) } ?? false
        return Button(action: {
            dueDate = date
            filled.remove(.dueDate)
        }, label: {
            Text("In \(days) days")
        })
        .buttonStyle(ClayChipStyle(isSelected: isSelected))
        .accessibilityLabel("Due \(days) days after it was sent")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func defaultDueDate(days: Int) -> Date {
        return Calendar.current.date(byAdding: .day, value: days, to: issueDate) ?? issueDate
    }

    private var paidCard: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Toggle(isOn: $isPaid.animation(Theme.Motion.standard)) {
                    Text("Paid")
                }
                .toggleStyle(ClayToggleStyle())
                if isPaid {
                    DateRowButton(symbol: "checkmark.circle.fill", text: "Paid \(DateText.long(paidDate))") {
                        focus = nil
                        choosingPaidDate = true
                    }
                    .accessibilityLabel("Paid on \(DateText.long(paidDate))")
                } else if let due = dueDate, Calendar.current.startOfDay(for: Date()) > due {
                    StatusPill(title: "Overdue since \(DateText.short(due))", symbol: "exclamationmark.triangle.fill",
                               tone: .danger)
                }
            }
        }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: Theme.Spacing.s) {
            if let errorMessage = errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.danger)
            }
            Button(action: save) {
                Label(target.invoice == nil ? "Save Invoice" : "Save Changes", systemImage: "checkmark")
            }
            .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
            .disabled(!canSave || isReading)
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    private var hasChanges: Bool {
        guard let invoice = target.invoice else {
            return !amountText.isEmpty || newDocument != nil || !client.isEmpty
        }
        return newDocument != nil || removesDocument || MoneyInput.parse(amountText) != invoice.amount
            || client != invoice.client || number != invoice.number || jobID != invoice.jobID
            || issueDate != invoice.issueDate || dueDate != invoice.dueDate || isPaid != invoice.isPaid
    }

    // MARK: - Attaching and reading

    private func attach(images: [UIImage]) {
        guard !images.isEmpty else {
            isReading = false
            return
        }
        isReading = true
        readMessage = nil
        Task {
            let pdf = await Task.detached(priority: .userInitiated) {
                return InvoiceDocument.pdfData(from: images)
            }.value
            let reading = await Task.detached(priority: .userInitiated) {
                return await InvoiceDocument.read(images: images)
            }.value
            finishAttaching(pdf: pdf, reading: reading)
        }
    }

    private func attach(fileAt url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: url)
        if accessing {
            url.stopAccessingSecurityScopedResource()
        }
        guard let data = data else {
            readMessage = "Couldn't open that file."
            return
        }
        isReading = true
        readMessage = nil
        if PDFDocument(data: data) != nil {
            Task {
                let reading = await Task.detached(priority: .userInitiated) {
                    return await InvoiceDocument.read(pdf: data)
                }.value
                finishAttaching(pdf: data, reading: reading)
            }
        } else if let image = UIImage(data: data) {
            attach(images: [image])
        } else {
            isReading = false
            readMessage = "That file isn't a PDF or a picture."
        }
    }

    /// Keeps the document and fills in the fields that are still empty.
    private func finishAttaching(pdf: Data?, reading: InvoiceReading) {
        isReading = false
        guard let pdf = pdf else {
            readMessage = "Couldn't attach that invoice."
            return
        }
        newDocument = pdf
        removesDocument = false
        var newlyFilled: Set<FilledField> = []
        if amount == nil, let value = reading.amount {
            amountText = MoneyInput.editText(value)
            newlyFilled.insert(.amount)
        }
        if number.trimmingCharacters(in: .whitespaces).isEmpty, let value = reading.number {
            number = value
            newlyFilled.insert(.number)
        }
        if target.invoice == nil, let value = reading.issueDate?.dateValue {
            issueDate = value
            newlyFilled.insert(.issueDate)
        }
        if dueDate == nil {
            if let value = reading.dueDate?.dateValue {
                dueDate = value
                newlyFilled.insert(.dueDate)
            } else if let days = reading.dueInDays {
                dueDate = defaultDueDate(days: days)
                newlyFilled.insert(.dueDate)
            }
        }
        filled = newlyFilled
        readMessage = newlyFilled.isEmpty
            ? "Attached. Tabbit couldn't read the amount, so type it in."
            : "Filled in from the invoice. Check the marked fields."
        Haptics.success()
    }

    // MARK: - Saving

    private func save() {
        focus = nil
        guard let amount = amount else {
            return
        }
        var invoice = target.invoice ?? Invoice()
        invoice.amount = amount
        invoice.client = client.trimmingCharacters(in: .whitespacesAndNewlines)
        invoice.number = number.trimmingCharacters(in: .whitespacesAndNewlines)
        invoice.jobID = jobID
        invoice.issueDate = Calendar.current.startOfDay(for: issueDate)
        invoice.dueDate = dueDate.map { date in Calendar.current.startOfDay(for: date) }
        invoice.paidDate = isPaid ? Calendar.current.startOfDay(for: paidDate) : nil
        do {
            try store.save(invoice, in: target.businessID, document: newDocument,
                           removeDocument: removesDocument && newDocument == nil)
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = "Couldn't save the invoice: \(error.localizedDescription)"
        }
    }

    private func close() {
        focus = nil
        guard hasChanges else {
            dismiss()
            return
        }
        dialog = ClayDialog(
            title: target.invoice == nil ? "Discard this invoice?" : "Discard your changes?",
            message: target.invoice == nil ? "It hasn't been saved yet." : "The invoice stays as it was.",
            actions: [
                ClayDialog.Action(title: target.invoice == nil ? "Discard Invoice" : "Discard Changes", symbol: "trash",
                                  kind: .destructive) {
                    dismiss()
                },
            ],
            cancelTitle: "Keep Editing"
        )
    }

    private func askToDelete() {
        guard let invoice = target.invoice else {
            return
        }
        dialog = ClayDialog(
            title: "Delete \(invoice.title)?",
            message: "The invoice and its attached file are deleted from this iPhone.",
            actions: [
                ClayDialog.Action(title: "Delete Invoice", symbol: "trash", kind: .destructive) {
                    store.deleteInvoice(invoice.id, in: target.businessID)
                    dismiss()
                },
            ]
        )
    }
}

// MARK: - Viewing the document

/// An invoice's PDF: a saved file, or one just attached.
enum InvoiceDocumentSource: Identifiable {
    case file(URL)
    case data(Data)

    var id: String {
        switch self {
        case .file(let url): return url.path
        case .data(let data): return "data-\(data.count)"
        }
    }

    var document: PDFDocument? {
        switch self {
        case .file(let url): return PDFDocument(url: url)
        case .data(let data): return PDFDocument(data: data)
        }
    }
}

/// The invoice full height in a clay sheet, with Share.
struct InvoiceDocumentSheet: View {
    let source: InvoiceDocumentSource
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var shareFile: ShareFile?

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                Text(title)
                    .font(Theme.Fonts.title)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: share) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .accessibilityLabel("Share the invoice")
                Button(action: {
                    dismiss()
                }, label: {
                    Image(systemName: "xmark")
                })
                .buttonStyle(NeumorphicIconButtonStyle())
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.xl)

            PDFKitView(document: source.document)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.s)
        }
        .themedScreen()
        .claySheet()
        .sheet(item: $shareFile) { file in
            ActivityView(items: [file.url])
                .presentationDetents([.medium, .large])
        }
    }

    private func share() {
        switch source {
        case .file(let url):
            shareFile = ShareFile(url: url)
        case .data(let data):
            let safeTitle = title.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { part in !part.isEmpty }
                .joined(separator: "-")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(safeTitle.isEmpty ? "Invoice" : safeTitle).pdf")
            if (try? data.write(to: url, options: [.atomic])) != nil {
                shareFile = ShareFile(url: url)
            }
        }
    }
}

/// PDFKit's viewer, scaled to fit the width.
struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument?

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = Theme.Palette.inset.uiColor
        view.document = document
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // The document is set once; re-renders pass a fresh copy of the same file.
        if uiView.document == nil, let document = document {
            uiView.document = document
        }
    }
}
