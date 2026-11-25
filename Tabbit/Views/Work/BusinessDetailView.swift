import SwiftUI

/// What a business screen lists below its year card.
enum WorkSection: String, CaseIterable, Identifiable {
    case jobs
    case invoices
    case expenses

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jobs: return "Jobs"
        case .invoices: return "Invoices"
        case .expenses: return "Expenses"
        }
    }
}

/// One business: the year's income, expenses and profit, then its jobs, invoices or expenses.
struct BusinessDetailView: View {
    let businessID: UUID

    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var flow: ReceiptFlow
    @Environment(\.dismiss) private var dismiss

    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var section: WorkSection = .jobs
    @State private var editingBusiness: BusinessEditorTarget?
    @State private var editingJob: JobEditorTarget?
    @State private var editingInvoice: InvoiceEditorTarget?
    @State private var moving: ReceiptRecord?
    @State private var dialog: ClayDialog?
    @State private var openRow: UUID?
    @State private var shareFile: ShareFile?
    @State private var toast: String?

    var body: some View {
        Group {
            if let business = store.business(businessID) {
                content(business)
                    .clayNavigation(business.displayName, titleInset: 116) {
                        Button(action: {
                            if let url = WorkCSV.write(business: business, receipts: store.receipts, year: year) {
                                shareFile = ShareFile(url: url)
                            }
                        }, label: {
                            Image(systemName: "square.and.arrow.up")
                        })
                        .buttonStyle(NeumorphicIconButtonStyle())
                        .accessibilityLabel("Export \(String(year)) as a spreadsheet")
                        Button(action: {
                            dialog = moreDialog(business)
                        }, label: {
                            Image(systemName: "ellipsis")
                        })
                        .buttonStyle(NeumorphicIconButtonStyle())
                        .accessibilityLabel("More")
                    }
            } else {
                EmptyStateView(symbol: "briefcase", title: "Deleted", message: "This business is no longer here.")
                    .frame(maxHeight: .infinity)
                    .themedScreen()
                    .clayNavigation("Work")
            }
        }
        .toast($toast)
        .clayDialog($dialog)
        .sheet(item: $editingBusiness) { target in
            BusinessEditorView(target: target)
                .environmentObject(store)
        }
        .sheet(item: $editingJob) { target in
            JobEditorView(target: target)
                .environmentObject(store)
        }
        .sheet(item: $editingInvoice) { target in
            InvoiceEditorView(target: target)
                .environmentObject(store)
        }
        .sheet(item: $moving) { receipt in
            MoveReceiptSheet(receiptID: receipt.id, onMoved: { name in
                toast = "Moved to \(name)"
            })
            .environmentObject(store)
        }
        .sheet(item: $shareFile) { file in
            ActivityView(items: [file.url])
                .presentationDetents([.medium, .large])
        }
        .task {
            #if DEBUG
            if let screen = DemoMode.screen {
                if screen == "invoices" {
                    section = .invoices
                } else if screen == "expenses" {
                    section = .expenses
                } else if screen == "invoice", let business = store.business(businessID),
                          let invoice = business.invoice(DemoMode.overdueInvoiceID) {
                    section = .invoices
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    editingInvoice = InvoiceEditorTarget(businessID: business.id, invoice: invoice, jobID: invoice.jobID)
                }
            }
            #endif
        }
    }

    private func content(_ business: Business) -> some View {
        let years = WorkSummary.years(business: business, receipts: store.receipts)
        let summary = store.workSummary(for: business, year: year)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                YearSwitcher(year: $year, years: years)
                WorkYearCard(summary: summary, setAsidePercent: business.taxSetAsidePercent)
                ClaySegmentedPicker(selection: $section, options: WorkSection.allCases.map { option in
                    ClaySegmentedPicker<WorkSection>.Option(value: option, title: option.title, symbol: nil,
                                                            accessibilityName: option.title)
                })
                .padding(.top, Theme.Spacing.s)

                switch section {
                case .jobs:
                    jobsList(business)
                case .invoices:
                    invoicesList(business)
                case .expenses:
                    expensesList(business)
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .themedScreen()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Spacer()
                FloatingAddButton(accessibilityName: "Add a job, invoice or expense") {
                    dialog = WorkAdd.dialog(onJob: {
                        editingJob = JobEditorTarget(businessID: business.id, job: nil)
                    }, onInvoice: {
                        editingInvoice = InvoiceEditorTarget(businessID: business.id, invoice: nil, jobID: nil)
                    }, onExpense: {
                        flow.addReceipt(toBusiness: business.id, job: nil)
                    })
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, Theme.Spacing.s)
        }
    }

    // MARK: - Jobs

    @ViewBuilder
    private func jobsList(_ business: Business) -> some View {
        if business.jobs.isEmpty {
            WorkEmptyCard(symbol: "hammer.fill", title: "No jobs yet",
                          message: "Add a job for each client or project, then keep its invoices and expenses together.",
                          buttonTitle: "New Job") {
                editingJob = JobEditorTarget(businessID: business.id, job: nil)
            }
        } else {
            let ordered = business.jobs.filter { job in !job.isFinished } + business.jobs.filter { job in job.isFinished }
            ForEach(ordered) { job in
                SwipeRow(id: job.id, openRow: $openRow, actions: [
                    SwipeAction(id: "edit", symbol: "pencil", label: "Edit", action: {
                        editingJob = JobEditorTarget(businessID: business.id, job: job)
                    }),
                    SwipeAction(id: "delete", symbol: "trash", label: "Delete", isDestructive: true, action: {
                        dialog = WorkAdd.deleteJobDialog(job, businessID: business.id, store: store)
                    }),
                ]) {
                    Button(action: {
                        if openRow != nil {
                            withAnimation(Theme.Motion.standard) {
                                openRow = nil
                            }
                        } else {
                            router.push(.job(job.id, business: business.id))
                        }
                    }, label: {
                        JobCard(job: job, summary: store.workSummary(for: business, year: nil, job: job.id))
                    })
                    .buttonStyle(NeumorphicCardButtonStyle())
                }
            }
        }
    }

    // MARK: - Invoices

    @ViewBuilder
    private func invoicesList(_ business: Business) -> some View {
        let invoices = Invoice.sorted(business.invoices.filter { invoice in
            Calendar.current.component(.year, from: invoice.issueDate) == year
        })
        if invoices.isEmpty {
            WorkEmptyCard(symbol: "doc.text.fill", title: "No invoices in \(String(year))",
                          message: "Attach an invoice you sent, or just enter the amount. Tick it off when you're paid.",
                          buttonTitle: "Add Invoice") {
                editingInvoice = InvoiceEditorTarget(businessID: business.id, invoice: nil, jobID: nil)
            }
        } else {
            ForEach(invoices) { invoice in
                InvoiceRow(invoice: invoice, jobName: business.job(invoice.jobID)?.displayName, onTogglePaid: {
                    togglePaid(invoice, business: business)
                }, onOpen: {
                    editingInvoice = InvoiceEditorTarget(businessID: business.id, invoice: invoice, jobID: invoice.jobID)
                })
            }
        }
    }

    private func togglePaid(_ invoice: Invoice, business: Business) {
        withAnimation(Theme.Motion.standard) {
            store.setPaid(!invoice.isPaid, invoice: invoice.id, in: business.id)
        }
        if !invoice.isPaid {
            Haptics.success()
            toast = "Marked paid: \(Money.string(invoice.amount))"
        }
    }

    // MARK: - Expenses

    @ViewBuilder
    private func expensesList(_ business: Business) -> some View {
        let receipts = store.receipts(inBusiness: business.id).filter { receipt in
            Calendar.current.component(.year, from: receipt.date) == year
        }
        if receipts.isEmpty {
            WorkEmptyCard(symbol: "doc.viewfinder", title: "No expenses in \(String(year))",
                          message: "Scan receipts for things you bought for work. They add up here for the year.",
                          buttonTitle: "Scan a Receipt") {
                flow.addReceipt(toBusiness: business.id, job: nil)
            }
        } else {
            ForEach(receipts) { receipt in
                WorkReceiptRow(receipt: receipt, business: business, jobID: nil, openRow: $openRow,
                               onMove: { moving = receipt }, onDelete: {
                                   dialog = ReceiptActions.deleteDialog(for: receipt, store: store)
                               })
            }
        }
    }

    // MARK: - More

    private func moreDialog(_ business: Business) -> ClayDialog {
        return ClayDialog(title: business.displayName, message: nil, actions: [
            ClayDialog.Action(title: "Edit Business", symbol: "pencil") {
                editingBusiness = .edit(business)
            },
            ClayDialog.Action(title: "Delete Business", symbol: "trash", kind: .destructive) {
                dialog = BusinessActions.deleteDialog(for: business, store: store, onDeleted: {
                    dismiss()
                })
            },
        ])
    }
}

/// The "+" choices and the delete question shared by the business and job screens.
enum WorkAdd {
    static func dialog(onJob: (() -> Void)?, onInvoice: @escaping () -> Void,
                       onExpense: @escaping () -> Void) -> ClayDialog {
        var actions = [
            ClayDialog.Action(title: "Scan an Expense Receipt", symbol: "doc.viewfinder", kind: .primary, handler: onExpense),
            ClayDialog.Action(title: "Add an Invoice", symbol: "doc.text.fill", handler: onInvoice),
        ]
        if let onJob = onJob {
            actions.append(ClayDialog.Action(title: "New Job", symbol: "hammer.fill", handler: onJob))
        }
        return ClayDialog(title: "Add", message: nil, actions: actions)
    }

    @MainActor
    static func deleteJobDialog(_ job: Job, businessID: UUID, store: TabbitStore,
                                onDeleted: @escaping () -> Void = {}) -> ClayDialog {
        return ClayDialog(
            title: "Delete “\(job.displayName)”?",
            message: "Its invoices and expenses stay with the business, without a job.",
            actions: [
                ClayDialog.Action(title: "Delete Job", symbol: "trash", kind: .destructive) {
                    withAnimation(Theme.Motion.standard) {
                        store.deleteJob(job.id, in: businessID)
                    }
                    onDeleted()
                },
            ]
        )
    }
}

// MARK: - Pieces

/// "‹ 2026 ›": steps through the years that have work in them.
struct YearSwitcher: View {
    @Binding var year: Int
    let years: [Int]

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button(action: {
                step(to: older)
            }, label: {
                Image(systemName: "chevron.left")
            })
            .buttonStyle(NeumorphicIconButtonStyle(size: 40))
            .disabled(older == nil)
            .accessibilityLabel(older.map { value in "Show \(String(value))" } ?? "No earlier year")

            Text(String(year))
                .font(Theme.Fonts.title3.monospacedDigit())
                .foregroundStyle(Theme.Colors.text)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
                .accessibilityLabel("Year \(String(year))")

            Button(action: {
                step(to: newer)
            }, label: {
                Image(systemName: "chevron.right")
            })
            .buttonStyle(NeumorphicIconButtonStyle(size: 40))
            .disabled(newer == nil)
            .accessibilityLabel(newer.map { value in "Show \(String(value))" } ?? "No later year")
        }
        .padding(Theme.Spacing.xs)
        .frame(minHeight: Theme.Size.tapTarget)
    }

    private var older: Int? {
        return years.filter { value in value < year }.max()
    }

    private var newer: Int? {
        return years.filter { value in value > year }.min()
    }

    private func step(to value: Int?) {
        guard let value = value else {
            return
        }
        withAnimation(Theme.Motion.standard) {
            year = value
        }
    }
}

/// The year at a glance: income (paid invoices), then invoiced, waiting, expenses and profit.
struct WorkYearCard: View {
    let summary: WorkSummary
    let setAsidePercent: Decimal?

    var body: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("Earned")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    MoneyText(amount: Money.fromCents(summary.incomeCents), font: Theme.Fonts.bigMoney)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("Paid invoices in \(summary.year.map { value in String(value) } ?? "all years")")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .accessibilityElement(children: .combine)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.m),
                                    GridItem(.flexible(), spacing: Theme.Spacing.m)],
                          alignment: .leading, spacing: Theme.Spacing.m) {
                    WorkFigure(title: "Invoiced", cents: summary.invoicedCents, symbol: "doc.text.fill")
                    WorkFigure(title: "Waiting", cents: summary.waitingCents, symbol: "clock.fill")
                    WorkFigure(title: "Expenses", cents: summary.expensesCents, symbol: "cart.fill")
                    WorkFigure(title: summary.profitCents < 0 ? "Loss" : "Profit", cents: abs(summary.profitCents),
                               symbol: summary.profitCents < 0 ? "arrow.down.right" : "arrow.up.right")
                }

                if summary.overdueCount > 0 || summary.setAsideCents(percent: setAsidePercent) != nil {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        if summary.overdueCount > 0 {
                            StatusPill(title: summary.overdueCount == 1
                                       ? "1 invoice overdue: \(Money.string(Money.fromCents(summary.overdueCents)))"
                                       : "\(summary.overdueCount) invoices overdue: \(Money.string(Money.fromCents(summary.overdueCents)))",
                                       symbol: "exclamationmark.triangle.fill", tone: .danger)
                        }
                        if let setAside = summary.setAsideCents(percent: setAsidePercent), let percent = setAsidePercent {
                            Label("Put aside \(Money.string(Money.fromCents(setAside))) for tax (\(NSDecimalNumber(decimal: percent).stringValue)% of profit)",
                                  systemImage: "building.columns.fill")
                                .font(Theme.Fonts.callout)
                                .foregroundStyle(Theme.Colors.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

/// A small labelled amount on an inset tile.
struct WorkFigure: View {
    let title: String
    let cents: Int
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Label(title, systemImage: symbol)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .lineLimit(1)
            MoneyText(amount: Money.fromCents(cents), font: Theme.Fonts.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clayPlate(cornerRadius: Theme.Radius.small)
        .accessibilityElement(children: .combine)
    }
}

/// A job in a list: name, client, and what it has earned and cost so far.
struct JobCard: View {
    let job: Job
    /// All years.
    let summary: WorkSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(job.displayName)
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .lineLimit(2)
                    Text(job.client.isEmpty ? "Started \(DateText.short(job.startDate))"
                         : "\(job.client) · started \(DateText.short(job.startDate))")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: Theme.Spacing.s)
                MoneyText(amount: Money.fromCents(summary.incomeCents), font: Theme.Fonts.headline.monospacedDigit())
            }
            HStack(spacing: Theme.Spacing.s) {
                if job.isFinished {
                    StatusPill(title: "Finished", symbol: "checkmark", tone: .neutral)
                } else if summary.overdueCount > 0 {
                    StatusPill(title: "Overdue", symbol: "exclamationmark.triangle.fill", tone: .danger)
                } else if summary.waitingCents > 0 {
                    StatusPill(title: "\(Money.string(Money.fromCents(summary.waitingCents))) waiting",
                               symbol: "clock.fill", tone: .caution)
                } else {
                    StatusPill(title: "Active", symbol: "hammer.fill", tone: .positive)
                }
                Spacer(minLength: Theme.Spacing.s)
                Text("Expenses \(Money.string(Money.fromCents(summary.expensesCents)))")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// An invoice with a clay check button beside it: tick it off when it's paid. Tap the card to open it.
struct InvoiceRow: View {
    let invoice: Invoice
    let jobName: String?
    let onTogglePaid: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button(action: onTogglePaid) {
                Image(systemName: invoice.isPaid ? "checkmark" : "circle.dotted")
            }
            .buttonStyle(NeumorphicIconButtonStyle(prominence: invoice.isPaid ? .accent : .plain))
            .accessibilityLabel(invoice.isPaid ? "Paid. Mark \(invoice.title) as not paid" : "Mark \(invoice.title) as paid")

            Button(action: onOpen) {
                HStack(alignment: .center, spacing: Theme.Spacing.s) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(invoice.client.isEmpty ? invoice.title : invoice.client)
                                .font(Theme.Fonts.headline)
                                .foregroundStyle(Theme.Colors.text)
                                .lineLimit(1)
                            if invoice.fileName != nil {
                                Image(systemName: "paperclip")
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                                    .accessibilityLabel("Invoice attached")
                            }
                        }
                        Text(subtitle)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Theme.Spacing.xs)
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                        MoneyText(amount: invoice.amount, font: Theme.Fonts.money)
                        InvoiceStatusPill(invoice: invoice)
                    }
                }
            }
            .buttonStyle(NeumorphicCardButtonStyle(padding: Theme.Spacing.m, showsChevron: false))
            .accessibilityHint("Opens the invoice")
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !invoice.client.isEmpty && !invoice.number.isEmpty {
            parts.append(invoice.number)
        }
        if let jobName = jobName {
            parts.append(jobName)
        }
        if let paid = invoice.paidDate {
            parts.append("Paid \(DateText.short(paid))")
        } else if let due = invoice.dueDate {
            parts.append("Due \(DateText.short(due))")
        } else {
            parts.append("Sent \(DateText.short(invoice.issueDate))")
        }
        return parts.joined(separator: " · ")
    }
}

/// Paid (mint), Waiting (amber) or Overdue (rose), with an icon.
struct InvoiceStatusPill: View {
    let invoice: Invoice

    var body: some View {
        switch invoice.status() {
        case .paid:
            StatusPill(title: "Paid", symbol: "checkmark", tone: .positive)
        case .waiting:
            StatusPill(title: "Waiting", symbol: "clock.fill", tone: .caution)
        case .overdue:
            StatusPill(title: "Overdue", symbol: "exclamationmark.triangle.fill", tone: .danger)
        }
    }
}

/// A business's receipt with the usual swipe actions; opens in the receipt pager.
struct WorkReceiptRow: View {
    let receipt: ReceiptRecord
    let business: Business
    /// The job whose receipts the pager pages through (nil = the whole business).
    let jobID: UUID?
    @Binding var openRow: UUID?
    let onMove: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var flow: ReceiptFlow

    var body: some View {
        SwipeRow(id: receipt.id, openRow: $openRow, actions: ReceiptActions.swipeActions(for: receipt, onEdit: {
            flow.edit(receipt)
        }, onMove: onMove, onDelete: onDelete)) {
            Button(action: {
                if openRow != nil {
                    withAnimation(Theme.Motion.standard) {
                        openRow = nil
                    }
                } else {
                    router.push(.workReceipt(receipt.id, business: business.id, job: jobID))
                }
            }, label: {
                ReceiptRow(receipt: receipt, people: [store.me])
            })
            .buttonStyle(NeumorphicCardButtonStyle())
        }
    }
}

/// An empty list inside a Work screen, with the one button that fills it.
struct WorkEmptyCard: View {
    let symbol: String
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            IconBadge(symbol: symbol, tone: .positive, size: 56)
            Text(title)
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.Colors.text)
            Text(message)
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                Label(buttonTitle, systemImage: "plus")
            }
            .buttonStyle(NeumorphicButtonStyle(prominence: .secondary, fullWidth: false, compact: true))
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .clayPlate(cornerRadius: Theme.Radius.tile)
    }
}
