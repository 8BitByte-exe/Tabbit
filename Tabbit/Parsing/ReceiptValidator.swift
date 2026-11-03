import Foundation

/// One arithmetic check on a parsed receipt, like "the items add up to the subtotal".
struct ReceiptCheck: Equatable {
    enum Kind: Equatable {
        /// The line items add up to the subtotal.
        case itemsMatchSubtotal
        /// Subtotal + tax equals the total.
        case subtotalPlusTaxMatchesTotal
        /// Items + tax equals the total (used when there's no subtotal).
        case itemsPlusTaxMatchesTotal
    }

    let kind: Kind
    let passed: Bool
    /// The amount printed on the receipt (the subtotal or the total).
    let printed: Decimal
    /// What the other numbers add up to.
    let computed: Decimal
}

/// Checks that a receipt's numbers agree with each other.
///
/// The rules parser shows these to the user; the Apple Intelligence parser
/// (next roadmap step) will also use them to reject made-up numbers.
enum ReceiptValidator {

    /// Differences of up to one cent count as a match (rounding on the receipt).
    static let tolerance = Decimal(string: "0.01", locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(0)

    static func checks(for receipt: Receipt) -> [ReceiptCheck] {
        var checks: [ReceiptCheck] = []
        let hasItems = !receipt.lineItems.isEmpty
        let itemsTotal = receipt.itemsTotal

        if let subtotal = receipt.subtotal, hasItems {
            checks.append(ReceiptCheck(
                kind: .itemsMatchSubtotal,
                passed: matches(itemsTotal, subtotal),
                printed: subtotal,
                computed: itemsTotal
            ))
        }

        if let total = receipt.total {
            let tax = receipt.tax ?? Decimal(0)
            if let subtotal = receipt.subtotal {
                let computed = subtotal + tax
                checks.append(ReceiptCheck(
                    kind: .subtotalPlusTaxMatchesTotal,
                    passed: matches(computed, total),
                    printed: total,
                    computed: computed
                ))
            } else if hasItems {
                let computed = itemsTotal + tax
                checks.append(ReceiptCheck(
                    kind: .itemsPlusTaxMatchesTotal,
                    passed: matches(computed, total),
                    printed: total,
                    computed: computed
                ))
            }
        }
        return checks
    }

    static func matches(_ first: Decimal, _ second: Decimal) -> Bool {
        let difference = first - second
        let magnitude = difference < 0 ? -difference : difference
        return magnitude <= tolerance
    }
}
