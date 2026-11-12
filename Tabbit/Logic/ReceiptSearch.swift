import Foundation

/// Search and sort for receipt lists.
enum ReceiptSearch {

    enum SortOrder: String, CaseIterable, Identifiable {
        case newest
        case oldest
        case highest
        case lowest
        case merchant

        var id: String { rawValue }

        var title: String {
            switch self {
            case .newest: return "Newest"
            case .oldest: return "Oldest"
            case .highest: return "Highest amount"
            case .lowest: return "Lowest amount"
            case .merchant: return "Merchant A–Z"
            }
        }

        var symbol: String {
            switch self {
            case .newest: return "arrow.down.circle"
            case .oldest: return "arrow.up.circle"
            case .highest: return "chart.bar.fill"
            case .lowest: return "chart.bar"
            case .merchant: return "textformat"
            }
        }
    }

    /// My Receipts' Personal / Business / All filter.
    enum ExpenseFilter: String, CaseIterable, Identifiable {
        case all
        case personal
        case business

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .personal: return ExpenseKind.personal.title
            case .business: return ExpenseKind.business.title
            }
        }

        func includes(_ receipt: ReceiptRecord) -> Bool {
            switch self {
            case .all: return true
            case .personal: return receipt.expense == .personal
            case .business: return receipt.expense == .business
            }
        }
    }

    /// The total of the receipts dated in the given calendar year.
    static func total(of receipts: [ReceiptRecord], inYearOf date: Date, calendar: Calendar = .current) -> Decimal {
        return receipts
            .filter { receipt in calendar.isDate(receipt.date, equalTo: date, toGranularity: .year) }
            .reduce(Decimal(0)) { sum, receipt in sum + receipt.effectiveTotal }
    }

    /// True if the query matches the merchant, location, payment method, category, date, an amount or an item.
    /// Every word of the query must match something.
    static func matches(_ receipt: ReceiptRecord, query: String) -> Bool {
        let words = query.lowercased().split(separator: " ").map { word in String(word) }
        guard !words.isEmpty else {
            return true
        }
        let haystack = searchableText(for: receipt)
        return words.allSatisfy { word in haystack.contains(word) }
    }

    static func searchableText(for receipt: ReceiptRecord) -> String {
        var parts: [String] = [receipt.merchant, receipt.location, receipt.paymentMethod,
                               receipt.category.title, receipt.category.rawValue,
                               receipt.expense.title]
        parts.append(contentsOf: receipt.items.map { item in item.name })
        parts.append(contentsOf: dateStrings(receipt.date))
        parts.append(contentsOf: amountStrings(receipt.effectiveTotal))
        for item in receipt.items {
            parts.append(contentsOf: amountStrings(item.price))
        }
        return parts.joined(separator: " ").lowercased()
    }

    static func sorted(_ receipts: [ReceiptRecord], by order: SortOrder) -> [ReceiptRecord] {
        switch order {
        case .newest:
            return receipts.sorted { first, second in
                first.date != second.date ? first.date > second.date : first.createdAt > second.createdAt
            }
        case .oldest:
            return receipts.sorted { first, second in
                first.date != second.date ? first.date < second.date : first.createdAt < second.createdAt
            }
        case .highest:
            return receipts.sorted { first, second in first.effectiveTotal > second.effectiveTotal }
        case .lowest:
            return receipts.sorted { first, second in first.effectiveTotal < second.effectiveTotal }
        case .merchant:
            return receipts.sorted { first, second in
                first.displayTitle.localizedCaseInsensitiveCompare(second.displayTitle) == .orderedAscending
            }
        }
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    private static func dateStrings(_ date: Date) -> [String] {
        let formats = ["MMMM d yyyy", "MMM d", "MMMM", "yyyy-MM-dd", "M/d/yyyy", "d/M/yyyy"]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = format.contains("M/") || format.contains("-") ? posix : Locale.current
            formatter.dateFormat = format
            return formatter.string(from: date)
        }
    }

    private static func amountStrings(_ value: Decimal) -> [String] {
        let cents = abs(Money.cents(value))
        let whole = cents / 100
        let fraction = cents % 100
        let fractionText = fraction < 10 ? "0\(fraction)" : "\(fraction)"
        return ["\(whole).\(fractionText)", "\(whole),\(fractionText)", Money.string(value)]
    }
}
