import Foundation

/// Personal spending figures for the Profile screen: my share of every receipt.
struct SpendingStats: Equatable {
    struct CategoryTotal: Identifiable, Equatable {
        let category: SpendCategory
        let cents: Int

        var id: String { category.rawValue }
        var amount: Decimal { Money.fromCents(cents) }
    }

    struct MonthTotal: Identifiable, Equatable {
        /// The first day of the month.
        let month: Date
        let cents: Int

        var id: Date { month }
        var amount: Decimal { Money.fromCents(cents) }
    }

    /// My share this calendar month and last month.
    let thisMonthCents: Int
    let lastMonthCents: Int
    /// This month's spending by category, largest first.
    let categories: [CategoryTotal]
    /// The last six months, oldest first.
    let months: [MonthTotal]
    let receiptCount: Int
    /// Average of my share per receipt, over all time.
    let averageCents: Int
    /// Across all groups: what others owe me, and what I owe.
    let owedToMeCents: Int
    let iOweCents: Int

    /// Change from last month, as a fraction (0.12 = +12%). Nil without last month.
    var monthChange: Double? {
        guard lastMonthCents > 0 else {
            return nil
        }
        return Double(thisMonthCents - lastMonthCents) / Double(lastMonthCents)
    }

    static func compute(receipts: [ReceiptRecord], groups: [SplitGroup], me: UUID = Person.meID,
                        now: Date = Date(), calendar: Calendar = .current) -> SpendingStats {
        let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { group in (group.id, group) })
        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth

        var thisMonthCents = 0
        var lastMonthCents = 0
        var byCategory: [SpendCategory: Int] = [:]
        var byMonth: [Date: Int] = [:]
        var total = 0
        var counted = 0

        for receipt in receipts {
            let mine: Int
            if let groupID = receipt.groupID, let group = groupsByID[groupID] {
                let split = SplitCalculator.split(receipt, members: group.memberIDs)
                mine = split.share(for: me)?.totalCents ?? 0
            } else {
                mine = Money.cents(receipt.effectiveTotal)
            }
            guard mine != 0 else {
                continue
            }
            counted += 1
            total += mine
            let month = calendar.dateInterval(of: .month, for: receipt.date)?.start ?? receipt.date
            byMonth[month, default: 0] += mine
            if month == thisMonth {
                thisMonthCents += mine
                byCategory[receipt.category, default: 0] += mine
            } else if month == lastMonth {
                lastMonthCents += mine
            }
        }

        var months: [MonthTotal] = []
        for offset in (0..<6).reversed() {
            if let month = calendar.date(byAdding: .month, value: -offset, to: thisMonth) {
                months.append(MonthTotal(month: month, cents: byMonth[month] ?? 0))
            }
        }

        var owedToMe = 0
        var iOwe = 0
        for group in groups {
            let groupReceipts = receipts.filter { receipt in receipt.groupID == group.id }
            let balances = SettleUp.balances(receipts: groupReceipts, members: group.memberIDs,
                                             settlements: group.settlements)
            let mine = balances[me] ?? 0
            if mine > 0 {
                owedToMe += mine
            } else {
                iOwe += -mine
            }
        }

        let categories = byCategory
            .map { entry in CategoryTotal(category: entry.key, cents: entry.value) }
            .sorted { first, second in first.cents > second.cents }

        return SpendingStats(
            thisMonthCents: thisMonthCents,
            lastMonthCents: lastMonthCents,
            categories: categories,
            months: months,
            receiptCount: counted,
            averageCents: counted > 0 ? total / counted : 0,
            owedToMeCents: owedToMe,
            iOweCents: iOwe
        )
    }
}
