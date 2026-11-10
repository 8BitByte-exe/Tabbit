import SwiftUI

/// The My Receipts tab: personal receipts that aren't in a group, with search and sorting.
struct MyReceiptsView: View {
    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var flow: ReceiptFlow

    @AppStorage("myReceipts.sort") private var sort: ReceiptSearch.SortOrder = .newest
    @State private var query = ""
    @State private var moving: ReceiptRecord?
    @State private var dialog: ClayDialog?
    @State private var choosingSort = false
    @State private var openRow: UUID?
    @State private var toast: String?

    var body: some View {
        let mine = store.receipts(in: nil)
        let shown = ReceiptSearch.sorted(mine.filter { receipt in ReceiptSearch.matches(receipt, query: query) },
                                         by: sort)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                ScreenHeader(title: "My Receipts", subtitle: subtitle(mine)) {
                    Button(action: {
                        choosingSort = true
                    }, label: {
                        Image(systemName: "arrow.up.arrow.down")
                    })
                    .buttonStyle(NeumorphicIconButtonStyle())
                    .accessibilityLabel("Sort, \(sort.title)")
                }

                if mine.isEmpty {
                    EmptyStateView(symbol: "doc.viewfinder", title: "No receipts yet",
                                   message: "Scan your own receipts here to keep them and see your spending.")
                        .padding(.top, Theme.Spacing.xl)
                } else {
                    ClaySearchField(text: $query, prompt: "Search merchant, item, date or amount")
                    if shown.isEmpty {
                        EmptyStateView(symbol: "magnifyingglass", title: "No matches",
                                       message: "No receipt matches “\(query)”.")
                    }
                    ForEach(shown) { receipt in
                        row(receipt)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollDismissesKeyboard(.immediately)
        .themedScreen()
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
        .clayDialog($dialog)
        .sheet(isPresented: $choosingSort) {
            SortSheet(selection: $sort)
        }
        .task {
            #if DEBUG
            if DemoMode.screen == "sort" {
                try? await Task.sleep(nanoseconds: 600_000_000)
                choosingSort = true
            }
            #endif
        }
        .sheet(item: $moving) { receipt in
            MoveReceiptSheet(receiptID: receipt.id, onMoved: { name in
                toast = "Moved to \(name)"
            })
            .environmentObject(store)
        }
    }

    private func row(_ receipt: ReceiptRecord) -> some View {
        SwipeRow(id: receipt.id, openRow: $openRow, actions: ReceiptActions.swipeActions(for: receipt, onEdit: {
            flow.edit(receipt)
        }, onMove: {
            moving = receipt
        }, onDelete: {
            dialog = ReceiptActions.deleteDialog(for: receipt, store: store)
        })) {
            Button(action: {
                if openRow != nil {
                    withAnimation(Theme.Motion.standard) {
                        openRow = nil
                    }
                } else {
                    router.push(.receipt(receipt.id, inGroup: receipt.groupID))
                }
            }, label: {
                ReceiptRow(receipt: receipt, people: [store.me])
            })
            .buttonStyle(NeumorphicCardButtonStyle())
        }
    }

    private func subtitle(_ receipts: [ReceiptRecord]) -> String {
        if receipts.isEmpty {
            return "Your own receipts"
        }
        let calendar = Calendar.current
        let total = receipts
            .filter { receipt in calendar.isDate(receipt.date, equalTo: Date(), toGranularity: .month) }
            .reduce(Decimal(0)) { sum, receipt in sum + receipt.effectiveTotal }
        return "\(Money.string(total)) this month"
    }
}

/// Choose how My Receipts is sorted.
struct SortSheet: View {
    @Binding var selection: ReceiptSearch.SortOrder

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SheetHeader(title: "Sort by", onClose: {
                dismiss()
            })
            ForEach(ReceiptSearch.SortOrder.allCases) { order in
                Button(action: {
                    selection = order
                    Haptics.selection()
                    dismiss()
                }, label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: order.symbol)
                            .frame(width: 24)
                        Text(order.title)
                        Spacer()
                        if order == selection {
                            IconBadge(symbol: "checkmark", tone: .positive, size: 26)
                        }
                    }
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.text)
                })
                .buttonStyle(NeumorphicCardButtonStyle(padding: Theme.Spacing.m, showsChevron: false))
                .accessibilityAddTraits(order == selection ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.xl)
        .frame(maxHeight: .infinity, alignment: .top)
        .themedScreen()
        .presentationDetents([.height(500), .large])
        .claySheet()
    }
}
