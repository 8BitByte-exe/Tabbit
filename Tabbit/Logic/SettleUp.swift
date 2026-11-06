import Foundation

/// One payment that settles part of a group's debts.
struct Transfer: Identifiable, Equatable {
    let from: UUID
    let to: UUID
    let cents: Int

    var id: String {
        return "\(from.uuidString)>\(to.uuidString)"
    }

    var amount: Decimal {
        return Money.fromCents(cents)
    }
}

/// What a debtor owes on one receipt the creditor paid (the "why" behind a transfer).
struct DebtDetail: Identifiable, Equatable {
    let receiptID: UUID
    let merchant: String
    let date: Date
    let items: [ItemShare]
    let feeCents: Int

    var id: UUID {
        return receiptID
    }

    var totalCents: Int {
        return items.reduce(0) { sum, item in sum + item.cents } + feeCents
    }
}

/// Balances and the fewest payments to settle them.
enum SettleUp {

    /// Each member's balance in cents: paid − owed, adjusted by recorded payments.
    /// Positive = is owed money; negative = owes money. Always sums to zero.
    static func balances(receipts: [ReceiptRecord], members: [UUID], settlements: [Settlement]) -> [UUID: Int] {
        var balance: [UUID: Int] = [:]
        for id in members {
            balance[id] = 0
        }
        for receipt in receipts {
            let split = SplitCalculator.split(receipt, members: members)
            // Count what was paid as the sum of the shares, so balances stay exact
            // even if the payer has since left the group.
            let payer = members.contains(receipt.paidBy) ? receipt.paidBy : (members.first ?? receipt.paidBy)
            balance[payer, default: 0] += split.totalCents
            for share in split.shares {
                balance[share.personID, default: 0] -= share.totalCents
            }
        }
        for settlement in settlements {
            let cents = Money.cents(settlement.amount)
            balance[settlement.from, default: 0] += cents
            balance[settlement.to, default: 0] -= cents
        }
        return balance
    }

    /// The fewest payments that settle the balances: repeatedly match the largest
    /// debtor with the largest creditor. Ties go to the earlier member, so the
    /// result is stable.
    static func transfers(balances: [UUID: Int], order: [UUID]) -> [Transfer] {
        func rank(_ id: UUID) -> Int {
            return order.firstIndex(of: id) ?? Int.max
        }
        var debtors = balances.filter { entry in entry.value < 0 }.map { entry in (id: entry.key, cents: -entry.value) }
        var creditors = balances.filter { entry in entry.value > 0 }.map { entry in (id: entry.key, cents: entry.value) }
        var result: [Transfer] = []

        func sortDescending(_ list: inout [(id: UUID, cents: Int)]) {
            list.sort { first, second in
                if first.cents != second.cents {
                    return first.cents > second.cents
                }
                return rank(first.id) < rank(second.id)
            }
        }

        sortDescending(&debtors)
        sortDescending(&creditors)
        while let debtor = debtors.first, let creditor = creditors.first {
            let cents = min(debtor.cents, creditor.cents)
            if cents > 0 {
                result.append(Transfer(from: debtor.id, to: creditor.id, cents: cents))
            }
            debtors[0].cents -= cents
            creditors[0].cents -= cents
            debtors.removeAll { entry in entry.cents == 0 }
            creditors.removeAll { entry in entry.cents == 0 }
            sortDescending(&debtors)
            sortDescending(&creditors)
        }
        return result
    }

    /// The fewest payments that settle a group.
    static func transfers(for group: SplitGroup, receipts: [ReceiptRecord]) -> [Transfer] {
        let ids = group.memberIDs
        let groupBalances = balances(receipts: receipts, members: ids, settlements: group.settlements)
        return transfers(balances: groupBalances, order: ids)
    }

    /// The receipts behind a transfer: those `creditor` paid where `debtor` has a share.
    static func details(debtor: UUID, creditor: UUID, receipts: [ReceiptRecord], members: [UUID]) -> [DebtDetail] {
        var result: [DebtDetail] = []
        for receipt in receipts where receipt.paidBy == creditor {
            let split = SplitCalculator.split(receipt, members: members)
            guard let share = split.share(for: debtor), share.totalCents != 0 else {
                continue
            }
            result.append(DebtDetail(receiptID: receipt.id, merchant: receipt.displayTitle, date: receipt.date,
                                     items: share.items, feeCents: share.feeCents))
        }
        return result.sorted { first, second in first.date > second.date }
    }

    /// A plain-text summary to paste into a message.
    static func summary(groupName: String, transfers: [Transfer], people: [Person]) -> String {
        if transfers.isEmpty {
            return "\(groupName): everyone is settled up. 🎉"
        }
        var lines = ["\(groupName): settle up"]
        for transfer in transfers {
            let from = people.person(transfer.from)?.name ?? "Someone"
            let to = people.person(transfer.to)?.name ?? "someone"
            lines.append("• \(from) → \(to): \(Money.string(transfer.amount))")
        }
        lines.append("")
        lines.append("Split with Tabbit")
        return lines.joined(separator: "\n")
    }
}
