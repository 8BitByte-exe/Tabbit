import SwiftUI

/// One job: what it has earned and cost, whether it's finished, and its invoices and expenses.
struct JobDetailView: View {
    let jobID: UUID
    let businessID: UUID

    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var flow: ReceiptFlow
    @Environment(\.dismiss) private var dismiss

    @State private var editingJob: JobEditorTarget?
    @State private var editingInvoice: InvoiceEditorTarget?
    @State private var moving: ReceiptRecord?
    @State private var dialog: ClayDialog?
    @State private var openRow: UUID?
    @State private var toast: String?

    var body: some View {
        Group {
            if let business = store.business(businessID), let job = business.job(jobID) {
                content(job, business: business)
                    .clayNavigation(job.displayName, titleInset: 116) {
                        Button(action: {
                            editingJob = JobEditorTarget(businessID: business.id, job: job)
                        }, label: {
                            Image(systemName: "pencil")
                        })
                        .buttonStyle(NeumorphicIconButtonStyle())
                        .accessibilityLabel("Edit job")
                        Button(action: {
                            dialog = WorkAdd.deleteJobDialog(job, businessID: business.id, store: store, onDeleted: {
                                dismiss()
                            })
                        }, label: {
                            Image(systemName: "trash")
                        })
                        .buttonStyle(NeumorphicIconButtonStyle(prominence: .destructive))
                        .accessibilityLabel("Delete job")
                    }
            } else {
                EmptyStateView(symbol: "hammer", title: "Job deleted", message: "This job is no longer here.")
                    .frame(maxHeight: .infinity)
                    .themedScreen()
                    .clayNavigation("Job")
            }
        }
        .toast($toast)
        .clayDialog($dialog)
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
    }

    private func content(_ job: Job, business: Business) -> some View {
        let summary = store.workSummary(for: business, year: nil, job: job.id)
        let invoices = business.invoices(for: job.id)
        let receipts = store.receipts(inBusiness: business.id, job: job.id)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                hero(job, business: business, summary: summary)

                Toggle(isOn: Binding(get: {
                    job.isFinished
                }, set: { finished in
                    var updated = job
                    updated.isFinished = finished
                    store.save(updated, in: business.id)
                })) {
                    Text("Job finished")
                }
                .toggleStyle(ClayToggleStyle())
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
                .clayPlate(cornerRadius: Theme.Radius.tile)

                SectionLabel(title: invoices.isEmpty ? "Invoices" : "Invoices · \(invoices.count)")
                    .padding(.top, Theme.Spacing.s)
                if invoices.isEmpty {
                    WorkEmptyCard(symbol: "doc.text.fill", title: "No invoices yet",
                                  message: "Add the invoices you send for this job and tick them off when they're paid.",
                                  buttonTitle: "Add Invoice") {
                        editingInvoice = InvoiceEditorTarget(businessID: business.id, invoice: nil, jobID: job.id)
                    }
                }
                ForEach(invoices) { invoice in
                    InvoiceRow(invoice: invoice, jobName: nil, onTogglePaid: {
                        withAnimation(Theme.Motion.standard) {
                            store.setPaid(!invoice.isPaid, invoice: invoice.id, in: business.id)
                        }
                        if !invoice.isPaid {
                            Haptics.success()
                            toast = "Marked paid: \(Money.string(invoice.amount))"
                        }
                    }, onOpen: {
                        editingInvoice = InvoiceEditorTarget(businessID: business.id, invoice: invoice, jobID: job.id)
                    })
                }

                SectionLabel(title: receipts.isEmpty ? "Expenses" : "Expenses · \(receipts.count)")
                    .padding(.top, Theme.Spacing.s)
                if receipts.isEmpty {
                    WorkEmptyCard(symbol: "doc.viewfinder", title: "No expenses yet",
                                  message: "Scan receipts for materials, travel or tools you bought for this job.",
                                  buttonTitle: "Scan a Receipt") {
                        flow.addReceipt(toBusiness: business.id, job: job.id)
                    }
                }
                ForEach(receipts) { receipt in
                    WorkReceiptRow(receipt: receipt, business: business, jobID: job.id, openRow: $openRow,
                                   onMove: { moving = receipt }, onDelete: {
                                       dialog = ReceiptActions.deleteDialog(for: receipt, store: store)
                                   })
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
                FloatingAddButton(accessibilityName: "Add an invoice or expense") {
                    dialog = WorkAdd.dialog(onJob: nil, onInvoice: {
                        editingInvoice = InvoiceEditorTarget(businessID: business.id, invoice: nil, jobID: job.id)
                    }, onExpense: {
                        flow.addReceipt(toBusiness: business.id, job: job.id)
                    })
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, Theme.Spacing.s)
        }
    }

    private func hero(_ job: Job, business: Business, summary: WorkSummary) -> some View {
        InfoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack(spacing: Theme.Spacing.m) {
                    CategoryBadge(symbol: "hammer.fill", colorIndex: business.colorIndex, size: 52)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(job.displayName)
                            .font(Theme.Fonts.title)
                            .foregroundStyle(Theme.Colors.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(job.client.isEmpty ? business.displayName : "\(job.client) · \(business.displayName)")
                            .font(Theme.Fonts.subheadline)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.m),
                                    GridItem(.flexible(), spacing: Theme.Spacing.m)],
                          alignment: .leading, spacing: Theme.Spacing.m) {
                    WorkFigure(title: "Earned", cents: summary.incomeCents, symbol: "checkmark.circle.fill")
                    WorkFigure(title: "Waiting", cents: summary.waitingCents, symbol: "clock.fill")
                    WorkFigure(title: "Expenses", cents: summary.expensesCents, symbol: "cart.fill")
                    WorkFigure(title: summary.profitCents < 0 ? "Loss" : "Profit", cents: abs(summary.profitCents),
                               symbol: summary.profitCents < 0 ? "arrow.down.right" : "arrow.up.right")
                }
                Text("Started \(DateText.long(job.startDate)). Totals cover the whole job.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }
}
