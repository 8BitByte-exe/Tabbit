import Foundation

/// One person's part of one item.
struct ItemShare: Equatable {
    let itemID: UUID
    let name: String
    /// This person's part, in cents.
    let cents: Int
    /// How many people share the item.
    let splitWays: Int
}

/// What one person owes for one receipt.
struct PersonShare: Equatable {
    let personID: UUID
    var items: [ItemShare]
    /// Tax, tip and any other difference to the printed total, in cents.
    var feeCents: Int

    var itemCents: Int {
        return items.reduce(0) { sum, item in sum + item.cents }
    }

    var totalCents: Int {
        return itemCents + feeCents
    }

    var total: Decimal {
        return Money.fromCents(totalCents)
    }
}

/// How one receipt splits across a group's members.
struct ReceiptSplit: Equatable {
    /// One entry per member, in member order. Members who owe nothing are included with 0.
    let shares: [PersonShare]

    func share(for personID: UUID) -> PersonShare? {
        return shares.first { share in share.personID == personID }
    }

    var totalCents: Int {
        return shares.reduce(0) { sum, share in sum + share.totalCents }
    }
}

/// Splits receipts. Pure and deterministic, so unit tests cover it fully.
///
/// Rules:
/// - Each item splits evenly among its assignees (no assignees = everyone).
/// - Fees = the receipt's total − its items (tax, tip, service charges, rounding).
///   With "Include fees" on they're spread in proportion to each person's items;
///   off, the payer covers them.
/// - A receipt without items splits its total evenly among everyone.
/// - Everything is in whole cents and leftover cents go out by largest
///   remainder, so shares always add up exactly to the total.
enum SplitCalculator {

    static func split(_ receipt: ReceiptRecord, members: [UUID]) -> ReceiptSplit {
        let everyone = members.isEmpty ? [receipt.paidBy] : members
        var shares: [UUID: PersonShare] = [:]
        for id in everyone {
            shares[id] = PersonShare(personID: id, items: [], feeCents: 0)
        }

        let totalCents = Money.cents(receipt.effectiveTotal)
        let pricedItems = receipt.items.filter { item in Money.cents(item.price) != 0 }

        if pricedItems.isEmpty {
            let parts = allocate(totalCents, weights: everyone.map { _ in 1 })
            for (index, id) in everyone.enumerated() {
                shares[id]?.feeCents += parts[index]
            }
            return ReceiptSplit(shares: everyone.compactMap { id in shares[id] })
        }

        var itemsCents = 0
        for item in pricedItems {
            let cents = Money.cents(item.price)
            itemsCents += cents
            let assignees = validAssignees(item.assignees, everyone: everyone)
            let parts = allocate(cents, weights: assignees.map { _ in 1 })
            for (index, id) in assignees.enumerated() {
                shares[id]?.items.append(ItemShare(itemID: item.id, name: item.name, cents: parts[index],
                                                   splitWays: assignees.count))
            }
        }

        let feeCents = totalCents - itemsCents
        if feeCents != 0 {
            if receipt.includeFees {
                let weights = everyone.map { id in max(shares[id]?.itemCents ?? 0, 0) }
                let useWeights = weights.reduce(0, +) > 0 ? weights : everyone.map { _ in 1 }
                let parts = allocate(feeCents, weights: useWeights)
                for (index, id) in everyone.enumerated() {
                    shares[id]?.feeCents += parts[index]
                }
            } else {
                let payer = everyone.contains(receipt.paidBy) ? receipt.paidBy : everyone[0]
                shares[payer]?.feeCents += feeCents
            }
        }

        return ReceiptSplit(shares: everyone.compactMap { id in shares[id] })
    }

    /// The item's assignees that are in the group, in group order; everyone if none.
    static func validAssignees(_ assignees: [UUID], everyone: [UUID]) -> [UUID] {
        let chosen = everyone.filter { id in assignees.contains(id) }
        return chosen.isEmpty ? everyone : chosen
    }

    /// Splits `cents` in proportion to `weights` (all ≥ 0, at least one > 0), handing
    /// leftover cents to the largest remainders (ties to the earlier person).
    /// The parts always add up exactly to `cents`. Negative amounts split the same way.
    static func allocate(_ cents: Int, weights: [Int]) -> [Int] {
        guard !weights.isEmpty else {
            return []
        }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0, cents != 0 else {
            return weights.map { _ in 0 }
        }
        let sign = cents < 0 ? -1 : 1
        let amount = abs(cents)
        var parts: [Int] = []
        var remainders: [(index: Int, remainder: Int)] = []
        for (index, weight) in weights.enumerated() {
            let exact = amount * weight
            parts.append(exact / totalWeight)
            remainders.append((index: index, remainder: exact % totalWeight))
        }
        var leftover = amount - parts.reduce(0, +)
        let order = remainders.sorted { first, second in
            if first.remainder != second.remainder {
                return first.remainder > second.remainder
            }
            return first.index < second.index
        }
        var position = 0
        while leftover > 0 && !order.isEmpty {
            parts[order[position % order.count].index] += 1
            leftover -= 1
            position += 1
        }
        return parts.map { part in part * sign }
    }
}
