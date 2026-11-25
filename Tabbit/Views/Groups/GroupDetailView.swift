import SwiftUI

/// One group: total, my balance, Settle Up, and its receipts.
struct GroupDetailView: View {
    let groupID: UUID

    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var flow: ReceiptFlow

    @State private var editing: GroupEditorTarget?
    @State private var moving: ReceiptRecord?
    @State private var dialog: ClayDialog?
    @State private var openRow: UUID?
    @State private var toast: String?

    var body: some View {
        Group {
            if let group = store.group(groupID) {
                content(group)
                    .clayNavigation(group.displayName, titleInset: 116) {
                        Button(action: {
                            router.push(.map(group.id))
                        }, label: {
                            Image(systemName: "map.fill")
                        })
                        .buttonStyle(NeumorphicIconButtonStyle())
                        .accessibilityLabel("Map of this group's receipts")
                        Button(action: {
                            editing = .edit(group)
                        }, label: {
                            Image(systemName: "pencil")
                        })
                        .buttonStyle(NeumorphicIconButtonStyle())
                        .accessibilityLabel("Edit group")
                    }
            } else {
                EmptyStateView(symbol: "person.3", title: "Group deleted", message: "This group is no longer here.")
                    .frame(maxHeight: .infinity)
                    .themedScreen()
                    .clayNavigation("Group")
            }
        }
        .toast($toast)
        .clayDialog($dialog)
        .onAppear {
            #if DEBUG
            if DemoMode.screen == "swipe" {
                openRow = store.receipts(in: groupID).first?.id
            }
            #endif
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
    }

    private func content(_ group: SplitGroup) -> some View {
        let receipts = store.receipts(in: group.id)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                GroupHeroCard(group: group, total: store.total(of: group),
                              myBalanceCents: store.balances(in: group)[Person.meID] ?? 0)

                if group.members.count > 1 {
                    Button(action: {
                        router.push(.settleUp(group.id))
                    }, label: {
                        Label("Settle Up", systemImage: "arrow.left.arrow.right")
                    })
                    .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
                }

                SectionLabel(title: receipts.isEmpty ? "Receipts" : "Receipts · \(receipts.count)")
                    .padding(.top, Theme.Spacing.s)

                if receipts.isEmpty {
                    EmptyStateView(symbol: "doc.viewfinder", title: "No receipts yet",
                                   message: "Tap + to scan a receipt, choose a photo or type one in.")
                }
                ForEach(receipts) { receipt in
                    receiptRow(receipt, group: group)
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
                FloatingAddButton(accessibilityName: "Add receipt") {
                    flow.addReceipt(to: group.id)
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, Theme.Spacing.s)
        }
    }

    private func receiptRow(_ receipt: ReceiptRecord, group: SplitGroup) -> some View {
        SwipeRow(id: receipt.id, openRow: $openRow, actions: receiptActions(receipt)) {
            Button(action: {
                if openRow != nil {
                    withAnimation(Theme.Motion.standard) {
                        openRow = nil
                    }
                } else {
                    router.push(.receipt(receipt.id, inGroup: receipt.groupID))
                }
            }, label: {
                ReceiptRow(receipt: receipt, people: group.members,
                           myShareCents: store.split(receipt).share(for: Person.meID)?.totalCents)
            })
            .buttonStyle(NeumorphicCardButtonStyle())
        }
    }

    private func receiptActions(_ receipt: ReceiptRecord) -> [SwipeAction] {
        return ReceiptActions.swipeActions(for: receipt, onEdit: {
            flow.edit(receipt)
        }, onMove: {
            moving = receipt
        }, onDelete: {
            dialog = ReceiptActions.deleteDialog(for: receipt, store: store)
        })
    }
}

/// The swipe buttons and delete question shared by every receipt list.
enum ReceiptActions {
    static func swipeActions(for receipt: ReceiptRecord, onEdit: @escaping () -> Void,
                             onMove: @escaping () -> Void, onDelete: @escaping () -> Void) -> [SwipeAction] {
        return [
            SwipeAction(id: "edit", symbol: "pencil", label: "Edit", action: onEdit),
            SwipeAction(id: "move", symbol: "folder", label: "Move", action: onMove),
            SwipeAction(id: "delete", symbol: "trash", label: "Delete", isDestructive: true, action: onDelete),
        ]
    }

    @MainActor
    static func deleteDialog(for receipt: ReceiptRecord, store: TabbitStore) -> ClayDialog {
        return ClayDialog(
            title: "Delete “\(receipt.displayTitle)”?",
            message: "The receipt and its photos are deleted from this iPhone.",
            actions: [
                ClayDialog.Action(title: "Delete Receipt", symbol: "trash", kind: .destructive) {
                    withAnimation(Theme.Motion.standard) {
                        store.delete(receipt.id)
                    }
                },
            ]
        )
    }
}

/// The top of a group: badge, name, total spent, people and my balance. Information only.
struct GroupHeroCard: View {
    let group: SplitGroup
    let total: Decimal
    let myBalanceCents: Int

    var body: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack(spacing: Theme.Spacing.m) {
                    CategoryBadge(symbol: group.category.symbol, colorIndex: group.category.colorIndex, size: 52)
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
                    BalancePill(cents: myBalanceCents)
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
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
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
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                if receipt.expense == .business {
                    StatusPill(title: ExpenseKind.business.title, symbol: ExpenseKind.business.symbol, tone: .neutral)
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
