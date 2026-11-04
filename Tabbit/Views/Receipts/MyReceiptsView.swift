import SwiftUI

/// The My Receipts tab: personal receipts that aren't in a group, with search and sorting.
struct MyReceiptsView: View {
    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var flow: ReceiptFlow

    @AppStorage("myReceipts.sort") private var sort: ReceiptSearch.SortOrder = .newest
    @State private var query = ""
    @State private var moving: ReceiptRecord?
    @State private var deleting: ReceiptRecord?
    @State private var toast: String?

    var body: some View {
        let mine = store.receipts(in: nil)
        let shown = ReceiptSearch.sorted(mine.filter { receipt in ReceiptSearch.matches(receipt, query: query) },
                                         by: sort)
        return List {
            ScreenHeader(title: "My Receipts", subtitle: subtitle(mine)) {
                sortMenu
            }
            .clayRow(top: Theme.Spacing.l)

            if mine.isEmpty {
                EmptyStateView(symbol: "doc.viewfinder", title: "No receipts yet",
                               message: "Scan your own receipts here to keep them and see your spending.")
                    .clayRow(top: Theme.Spacing.xl)
            } else {
                ClaySearchField(text: $query, prompt: "Search merchant, item, date or amount")
                    .clayRow()
                if shown.isEmpty {
                    EmptyStateView(symbol: "magnifyingglass", title: "No matches",
                                   message: "No receipt matches “\(query)”.")
                        .clayRow()
                }
                ForEach(shown) { receipt in
                    row(receipt)
                }
            }
        }
        .clayList()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Spacer()
                FloatingAddButton(accessibilityName: "Add receipt") {
                    flow.addReceipt(to: nil)
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, Theme.Size.tabBarHeight + Theme.Spacing.l)
        }
        .toast($toast)
        .sheet(item: $moving) { receipt in
            MoveReceiptSheet(receiptID: receipt.id, onMoved: { name in
                toast = "Moved to \(name)"
            })
            .environmentObject(store)
        }
        .confirmationDialog("Delete this receipt?", isPresented: deletingBinding, titleVisibility: .visible,
                            presenting: deleting, actions: { receipt in
            Button("Delete Receipt", role: .destructive) {
                withAnimation(Theme.Motion.standard) {
                    store.delete(receipt.id)
                }
            }
            Button("Cancel", role: .cancel) {
            }
        }, message: { receipt in
            Text("“\(receipt.displayTitle)” and its photos will be deleted from this iPhone.")
        })
    }

    private func row(_ receipt: ReceiptRecord) -> some View {
        Button(action: {
            router.push(.receipt(receipt.id, inGroup: receipt.groupID))
        }, label: {
            ReceiptRow(receipt: receipt, people: [store.me])
        })
        .buttonStyle(NeumorphicCardButtonStyle())
        .clayRow()
        .receiptSwipeActions(onEdit: {
            flow.edit(receipt)
        }, onMove: {
            moving = receipt
        }, onDelete: {
            deleting = receipt
        })
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sort) {
                ForEach(ReceiptSearch.SortOrder.allCases) { order in
                    Label(order.title, systemImage: order.symbol)
                        .tag(order)
                }
            }
        } label: {
            ClayIconLabel(symbol: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort, \(sort.title)")
    }

    private func subtitle(_ receipts: [ReceiptRecord]) -> String {
        let calendar = Calendar.current
        let thisMonth = receipts.filter { receipt in
            calendar.isDate(receipt.date, equalTo: Date(), toGranularity: .month)
        }
        let total = thisMonth.reduce(Decimal(0)) { sum, receipt in sum + receipt.effectiveTotal }
        if receipts.isEmpty {
            return "Your own receipts"
        }
        return "\(Money.string(total)) this month"
    }

    private var deletingBinding: Binding<Bool> {
        return Binding(get: {
            deleting != nil
        }, set: { isShowing in
            if !isShowing {
                deleting = nil
            }
        })
    }
}
