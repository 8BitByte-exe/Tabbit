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

    /// True if the query matches the merchant, category, date, an amount or an item.
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
        var parts: [String] = [receipt.merchant, receipt.category.title, receipt.category.rawValue]
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
