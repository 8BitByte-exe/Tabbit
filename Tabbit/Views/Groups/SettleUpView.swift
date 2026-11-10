import SwiftUI
import UIKit

/// The fewest payments that make a group even. Each payment opens to show the
/// receipts behind it, with a button to mark it paid.
struct SettleUpView: View {
    let groupID: UUID

    @EnvironmentObject private var store: TabbitStore
    @State private var expanded: Set<String> = []
    @State private var toast: String?
    @State private var paidCount = 0

    var body: some View {
        Group {
            if let group = store.group(groupID) {
                content(group)
            } else {
                EmptyStateView(symbol: "person.3", title: "Group deleted", message: "This group is no longer here.")
                    .frame(maxHeight: .infinity)
                    .themedScreen()
            }
        }
        .clayNavigation("Settle Up")
        .toast($toast)
        .onAppear {
            #if DEBUG
            if DemoMode.screen == "settle", let group = store.group(groupID),
               let first = store.transfers(in: group).first {
                expanded.insert(first.id)
            }
            #endif
        }
        .sensoryFeedback(.success, trigger: paidCount)
    }

    private func content(_ group: SplitGroup) -> some View {
        let transfers = store.transfers(in: group)
        let summary = SettleUp.summary(groupName: group.displayName, transfers: transfers, people: group.members)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                summaryCard(transfers: transfers)

                if !transfers.isEmpty {
                    SectionLabel(title: "Payments")
                        .padding(.top, Theme.Spacing.s)
                    ForEach(transfers) { transfer in
                        transferCard(transfer, group: group)
                    }
                }

                HStack(spacing: Theme.Spacing.m) {
                    Button(action: {
                        UIPasteboard.general.string = summary
                        toast = "Copied"
                    }, label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    })
                    .buttonStyle(NeumorphicButtonStyle(prominence: .secondary))

                    ShareLink(item: summary) {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
                }
                .padding(.top, Theme.Spacing.s)

                if !group.settlements.isEmpty {
                    SectionLabel(title: "Paid")
                        .padding(.top, Theme.Spacing.s)
                    ForEach(Array(group.settlements.reversed())) { settlement in
                        settlementRow(settlement, group: group)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .themedScreen()
    }

    // MARK: - Summary

    private func summaryCard(transfers: [Transfer]) -> some View {
        InfoCard {
            HStack(spacing: Theme.Spacing.l) {
                IconBadge(symbol: transfers.isEmpty ? "checkmark.seal.fill" : "arrow.left.arrow.right",
                          tone: transfers.isEmpty ? .positive : .neutral, size: 56)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(transfers.isEmpty ? "Everyone's even" : paymentsTitle(transfers.count))
                        .font(Theme.Fonts.title3)
                        .foregroundStyle(Theme.Colors.text)
                    Text(transfers.isEmpty
                         ? "Nothing to pay back. Nice."
                         : "The fewest payments that settle everything.")
                        .font(Theme.Fonts.callout)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func paymentsTitle(_ count: Int) -> String {
        return count == 1 ? "1 payment to go" : "\(count) payments to go"
    }

    // MARK: - Transfers

    private func transferCard(_ transfer: Transfer, group: SplitGroup) -> some View {
        Expandable(isExpanded: expansionBinding(transfer.id)) {
            TransferHeadline(transfer: transfer, people: group.members)
        } content: {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                TransferDetails(details: SettleUp.details(debtor: transfer.from, creditor: transfer.to,
                                                          receipts: store.receipts(in: group.id),
                                                          members: group.memberIDs))
                Button(action: {
                    markPaid(transfer, group: group)
                }, label: {
                    Label("Mark Paid", systemImage: "checkmark")
                })
                .buttonStyle(NeumorphicButtonStyle(prominence: .primary, compact: true))
            }
            .padding(.top, Theme.Spacing.m)
        }
        .padding(Theme.Spacing.l)
        .clayPlate()
        .accessibilityAction(named: "Mark paid") {
            markPaid(transfer, group: group)
        }
    }

    private func expansionBinding(_ id: String) -> Binding<Bool> {
        return Binding(get: {
            expanded.contains(id)
        }, set: { isOpen in
            if isOpen {
                expanded.insert(id)
            } else {
                expanded.remove(id)
            }
        })
    }

    private func markPaid(_ transfer: Transfer, group: SplitGroup) {
        withAnimation(Theme.Motion.standard) {
            store.markPaid(transfer, in: group.id)
            expanded.remove(transfer.id)
        }
        paidCount += 1
        toast = "Marked as paid"
    }

    // MARK: - History

    private func settlementRow(_ settlement: Settlement, group: SplitGroup) -> some View {
        let from = group.members.displayName(settlement.from)
        let toName = group.members.displayName(settlement.to)
        let to = toName == "You" ? "you" : toName
        return HStack(spacing: Theme.Spacing.m) {
            IconBadge(symbol: "checkmark", tone: .positive, size: 32)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("\(from) paid \(to)")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.text)
                Text("\(Money.string(settlement.amount)) · \(DateText.short(settlement.date))")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button(action: {
                undo(settlement, group: group)
            }, label: {
                Image(systemName: "arrow.uturn.backward")
            })
            .buttonStyle(NeumorphicIconButtonStyle())
            .accessibilityLabel("Undo payment")
        }
        .padding(Theme.Spacing.m)
        .clayPlate(cornerRadius: Theme.Radius.tile)
    }

    private func undo(_ settlement: Settlement, group: SplitGroup) {
        withAnimation(Theme.Motion.standard) {
            store.removeSettlement(settlement.id, in: group.id)
        }
        toast = "Payment undone"
    }
}

/// "Blair pays Alex · $24.00" with both avatars.
struct TransferHeadline: View {
    let transfer: Transfer
    let people: [Person]

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.xs) {
                avatar(transfer.from)
                Image(systemName: "arrow.right")
                    .font(Theme.Fonts.caption.weight(.heavy))
                    .foregroundStyle(Theme.Colors.secondaryText)
                avatar(transfer.to)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(sentence)
                    .font(Theme.Fonts.headline)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                MoneyText(amount: transfer.amount, font: Theme.Fonts.money)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func avatar(_ id: UUID) -> some View {
        if let person = people.person(id) {
            AvatarView(person: person, size: 34)
        } else {
            AvatarView(person: Person(id: id, name: "?", colorIndex: 8), size: 34)
        }
    }

    private var sentence: String {
        let from = people.displayName(transfer.from)
        let to = people.displayName(transfer.to)
        if from == "You" {
            return "You pay \(to)"
        }
        if to == "You" {
            return "\(from) pays you"
        }
        return "\(from) pays \(to)"
    }
}

/// The receipts and items behind one payment.
struct TransferDetails: View {
    let details: [DebtDetail]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if details.isEmpty {
                Text("This payment balances out several receipts and earlier payments.")
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            ForEach(details) { detail in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Text(detail.merchant)
                            .font(Theme.Fonts.subheadline.weight(.bold))
                            .foregroundStyle(Theme.Colors.text)
                        Text(DateText.short(detail.date))
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Spacer()
                        Text(Money.string(Money.fromCents(detail.totalCents)))
                            .font(Theme.Fonts.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.Colors.text)
                    }
                    ForEach(detail.items, id: \.itemID) { item in
                        HStack {
                            Text(item.splitWays > 1 ? "\(item.name) (÷\(item.splitWays))" : item.name)
                            Spacer()
                            Text(Money.string(Money.fromCents(item.cents)))
                                .monospacedDigit()
                        }
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    if detail.feeCents != 0 {
                        HStack {
                            Text("Tax & tip share")
                            Spacer()
                            Text(Money.string(Money.fromCents(detail.feeCents)))
                                .monospacedDigit()
                        }
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clayInset(cornerRadius: Theme.Radius.tile)
    }
}
