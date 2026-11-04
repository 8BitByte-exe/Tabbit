import SwiftUI

/// One group: total, my balance, Settle Up, and its receipts.
struct GroupDetailView: View {
    let groupID: UUID

    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var flow: ReceiptFlow
    @Environment(\.dismiss) private var dismiss

    @State private var editing: GroupEditorTarget?
    @State private var moving: ReceiptRecord?
    @State private var deleting: ReceiptRecord?
    @State private var toast: String?

    var body: some View {
        Group {
            if let group = store.group(groupID) {
                content(group)
            } else {
                EmptyStateView(symbol: "person.3", title: "Group deleted", message: "This group is no longer here.")
                    .themedScreen()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
    }

    private func content(_ group: SplitGroup) -> some View {
        let receipts = store.receipts(in: group.id)
        return List {
            GroupHeroCard(group: group, total: store.total(of: group),
                          myBalanceCents: store.balances(in: group)[Person.meID] ?? 0)
                .clayRow(top: Theme.Spacing.l)

            if group.members.count > 1 {
                Button(action: {
                    router.push(.settleUp(group.id))
                }, label: {
                    Label("Settle Up", systemImage: "arrow.left.arrow.right")
                })
                .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
                .clayRow(top: Theme.Spacing.m)
            }

            SectionLabel(title: receipts.isEmpty ? "Receipts" : "Receipts · \(receipts.count)")
                .clayRow(top: Theme.Spacing.l, bottom: 0)

            if receipts.isEmpty {
                EmptyStateView(symbol: "doc.viewfinder", title: "No receipts yet",
                               message: "Tap + to scan a receipt, choose a photo or type one in.")
                    .clayRow()
            }
            ForEach(receipts) { receipt in
                receiptRow(receipt, group: group)
            }
        }
        .clayList()
        .navigationTitle(group.displayName)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Spacer()
                FloatingAddButton(accessibilityName: "Add receipt") {
                    flow.addReceipt(to: group.id)
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, Theme.Spacing.s)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    editing = .edit(group)
                }, label: {
                    Image(systemName: "pencil")
                })
                .accessibilityLabel("Edit group")
            }
        }
        .sheet(item: $editing) { target in
            GroupEditorView(target: target)
                .environmentObject(store)
        }
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

    private func receiptRow(_ receipt: ReceiptRecord, group: SplitGroup) -> some View {
        Button(action: {
            router.push(.receipt(receipt.id, inGroup: receipt.groupID))
        }, label: {
            ReceiptRow(receipt: receipt, people: group.members,
                       myShareCents: store.split(receipt).share(for: Person.meID)?.totalCents)
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

extension View {
    /// Swipe left on a receipt: delete, move, edit (also offered as accessibility actions).
    func receiptSwipeActions(onEdit: @escaping () -> Void, onMove: @escaping () -> Void,
                             onDelete: @escaping () -> Void) -> some View {
        self
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .tint(Theme.Colors.swipeDelete)
                Button(action: onMove) {
                    Label("Move", systemImage: "folder")
                }
                .tint(Theme.Colors.swipeMove)
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(Theme.Colors.swipeEdit)
            }
            .accessibilityAction(named: "Edit", onEdit)
            .accessibilityAction(named: "Move", onMove)
            .accessibilityAction(named: "Delete", onDelete)
    }
}

/// The top of a group: badge, name, total spent, people and my balance.
struct GroupHeroCard: View {
    let group: SplitGroup
    let total: Decimal
    let myBalanceCents: Int

    var body: some View {
        NeumorphicCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack(spacing: Theme.Spacing.m) {
                    CategoryBadge(symbol: group.category.symbol, colorIndex: group.category.colorIndex, size: 56)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(group.displayName)
                            .font(Theme.Fonts.title)
                            .foregroundStyle(Theme.Colors.text)
                        Text(group.category.title)
                            .font(Theme.Fonts.subheadline)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("Total spent")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    MoneyText(amount: total, font: Theme.Fonts.bigMoney)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .accessibilityElement(children: .combine)
                HStack {
                    AvatarStack(people: group.members, size: 32, limit: 5)
                    Spacer(minLength: Theme.Spacing.s)
                    BalanceChip(cents: myBalanceCents)
                }
            }
        }
    }
}

/// A receipt in a list: category, merchant, date, payer, total and my share.
struct ReceiptRow: View {
    let receipt: ReceiptRecord
    let people: [Person]
    /// Nil for personal receipts (it's all mine).
    var myShareCents: Int?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.m))
        return layout {
            CategoryBadge(symbol: receipt.category.symbol, colorIndex: receipt.category.colorIndex)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(receipt.displayTitle)
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .lineLimit(1)
                    if receipt.pageImageCount > 0 {
                        Image(systemName: "photo")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .accessibilityLabel("Has a photo")
                    }
                }
                Text(subtitle)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: Theme.Spacing.s)
            }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: Theme.Spacing.xxs) {
                MoneyText(amount: receipt.effectiveTotal, font: Theme.Fonts.money)
                if let mine = myShareCents, people.count > 1 {
                    Text("Yours \(Money.string(Money.fromCents(mine)))")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.accentInk)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [DateText.short(receipt.date)]
        if people.count > 1 {
            let payer = people.displayName(receipt.paidBy)
            parts.append(payer == "You" ? "You paid" : "\(payer) paid")
        } else {
            parts.append(receipt.category.title)
        }
        return parts.joined(separator: " · ")
    }
}
