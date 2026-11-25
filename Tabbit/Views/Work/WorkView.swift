import SwiftUI

/// Opens the business editor for a new business or an existing one.
enum BusinessEditorTarget: Identifiable {
    case new
    case edit(Business)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let business): return business.id.uuidString
        }
    }
}

/// The Work tab: your business (or freelance work), with this year's income at a glance.
struct WorkView: View {
    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var router: AppRouter

    @State private var editing: BusinessEditorTarget?
    @State private var dialog: ClayDialog?
    @State private var openRow: UUID?

    private var year: Int {
        return Calendar.current.component(.year, from: Date())
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                ScreenHeader(title: "Work", subtitle: subtitle) {
                    if !store.businesses.isEmpty {
                        Button(action: {
                            editing = .new
                        }, label: {
                            Image(systemName: "plus")
                        })
                        .buttonStyle(NeumorphicIconButtonStyle())
                        .accessibilityLabel("New business")
                    }
                }

                if store.businesses.isEmpty {
                    emptyState
                } else {
                    ForEach(store.businesses) { business in
                        row(business)
                    }
                    Label("Invoices, jobs and expenses stay on this iPhone.", systemImage: "lock.fill")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .padding(.top, Theme.Spacing.s)
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .themedScreen()
        .toolbar(.hidden, for: .navigationBar)
        .tabBarClearance()
        .sheet(item: $editing) { target in
            BusinessEditorView(target: target)
                .environmentObject(store)
        }
        .clayDialog($dialog)
    }

    private var subtitle: String {
        if store.businesses.isEmpty {
            return "Jobs, invoices and expenses"
        }
        let income = store.businesses.reduce(0) { sum, business in
            sum + store.workSummary(for: business, year: year).incomeCents
        }
        return "\(Money.string(Money.fromCents(income))) earned in \(String(year))"
    }

    private func row(_ business: Business) -> some View {
        SwipeRow(id: business.id, openRow: $openRow, actions: [
            SwipeAction(id: "edit", symbol: "pencil", label: "Edit", action: {
                editing = .edit(business)
            }),
            SwipeAction(id: "delete", symbol: "trash", label: "Delete", isDestructive: true, action: {
                dialog = BusinessActions.deleteDialog(for: business, store: store, onDeleted: {})
            }),
        ]) {
            Button(action: {
                if openRow != nil {
                    withAnimation(Theme.Motion.standard) {
                        openRow = nil
                    }
                } else {
                    router.push(.business(business.id))
                }
            }, label: {
                BusinessCard(business: business, summary: store.workSummary(for: business, year: year),
                             unpaid: WorkSummary.unpaid(business: business))
            })
            .buttonStyle(NeumorphicCardButtonStyle())
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.l) {
            EmptyStateView(symbol: "briefcase.fill", title: "Set up your work",
                           message: "Add your business, or work as a freelancer under your own name. Then keep track of jobs, invoices and expenses through the year.")
            Button(action: {
                editing = .new
            }, label: {
                Label("Set Up Work", systemImage: "plus")
            })
            .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                hint(symbol: "hammer.fill", text: "Jobs for each client or project")
                hint(symbol: "doc.text.fill", text: "Invoices you tick off when they're paid")
                hint(symbol: "doc.viewfinder", text: "Scanned receipts that add up your expenses for the year")
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clayPlate(cornerRadius: Theme.Radius.tile)
        }
        .padding(.top, Theme.Spacing.l)
    }

    private func hint(symbol: String, text: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            IconBadge(symbol: symbol, tone: .neutral, size: 32)
            Text(text)
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Colors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Delete a business: with its expenses, or keeping them in My Receipts.
enum BusinessActions {
    @MainActor
    static func deleteDialog(for business: Business, store: TabbitStore, onDeleted: @escaping () -> Void) -> ClayDialog {
        return ClayDialog(
            title: "Delete “\(business.displayName)”?",
            message: "Its jobs and invoices (and attached invoice files) are deleted from this iPhone.",
            actions: [
                ClayDialog.Action(title: "Delete Everything", symbol: "trash", kind: .destructive) {
                    withAnimation(Theme.Motion.standard) {
                        store.deleteBusiness(business.id, keepReceipts: false)
                    }
                    onDeleted()
                },
                ClayDialog.Action(title: "Keep Expenses in My Receipts", symbol: "tray.and.arrow.down") {
                    withAnimation(Theme.Motion.standard) {
                        store.deleteBusiness(business.id, keepReceipts: true)
                    }
                    onDeleted()
                },
            ]
        )
    }
}

/// A business in the Work list: name, this year's income and expenses, and what's unpaid.
struct BusinessCard: View {
    let business: Business
    let summary: WorkSummary
    let unpaid: (cents: Int, count: Int, overdueCount: Int)

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.m))
            layout {
                CategoryBadge(symbol: business.kind.symbol, colorIndex: business.colorIndex, size: 48)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(business.displayName)
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .lineLimit(2)
                    Text(countsText)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: Theme.Spacing.s)
                }
                VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: Theme.Spacing.xxs) {
                    MoneyText(amount: Money.fromCents(summary.incomeCents), font: Theme.Fonts.headline.monospacedDigit())
                    Text("Earned this year")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            HStack(spacing: Theme.Spacing.s) {
                UnpaidPill(cents: unpaid.cents, count: unpaid.count, overdueCount: unpaid.overdueCount)
                Spacer(minLength: Theme.Spacing.s)
                Text("Expenses \(Money.string(Money.fromCents(summary.expensesCents)))")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var countsText: String {
        let active = business.jobs.filter { job in !job.isFinished }.count
        let jobs = active == 1 ? "1 active job" : "\(active) active jobs"
        return "\(business.kind.title) · \(jobs)"
    }
}

/// "2 overdue" (rose), "$1,200 waiting" (amber) or "All paid" (grey), always with an icon.
struct UnpaidPill: View {
    let cents: Int
    let count: Int
    let overdueCount: Int

    var body: some View {
        if overdueCount > 0 {
            StatusPill(title: overdueCount == 1 ? "1 overdue" : "\(overdueCount) overdue",
                       symbol: "exclamationmark.triangle.fill", tone: .danger)
        } else if count > 0 {
            StatusPill(title: "\(Money.string(Money.fromCents(cents))) waiting", symbol: "clock.fill", tone: .caution)
        } else {
            StatusPill(title: "All paid", symbol: "checkmark", tone: .neutral)
        }
    }
}
