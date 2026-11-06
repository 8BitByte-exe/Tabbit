import Foundation

/// Reads an amount the user typed: "7.76", "1,234.56", "1.234,56", "12,34",
/// "$4", "-0.50", "0.50-". Returns nil for empty or unreadable text.
enum MoneyInput {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func parse(_ text: String) -> Decimal? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return nil
        }
        var negative = false
        if cleaned.hasPrefix("-") || cleaned.hasPrefix("−") {
            negative = true
            cleaned.removeFirst()
        }
        if cleaned.hasSuffix("-") {
            negative = true
            cleaned.removeLast()
        }
        let removable = CharacterSet(charactersIn: "$€£ \u{00A0}")
        cleaned = String(cleaned.unicodeScalars.filter { scalar in !removable.contains(scalar) })
        if cleaned.hasPrefix("-") {
            negative = true
            cleaned.removeFirst()
        }
        guard !cleaned.isEmpty else {
            return nil
        }
        let allowed = CharacterSet(charactersIn: "0123456789.,")
        guard cleaned.unicodeScalars.allSatisfy({ scalar in allowed.contains(scalar) }) else {
            return nil
        }

        // Work out the decimal separator: the last "." or "," if 1–2 digits follow it.
        var normalized = cleaned
        if let separatorIndex = cleaned.lastIndex(where: { character in character == "." || character == "," }) {
            let fraction = cleaned[cleaned.index(after: separatorIndex)...]
            let whole = cleaned[..<separatorIndex]
            if fraction.count >= 1 && fraction.count <= 2 {
                let wholeDigits = String(whole).filter { character in character != "." && character != "," }
                normalized = wholeDigits + "." + String(fraction)
            } else {
                normalized = cleaned.filter { character in character != "." && character != "," }
            }
        }
        guard !normalized.isEmpty, normalized != ".", var value = Decimal(string: normalized, locale: posix) else {
            return nil
        }
        if negative {
            value = -value
        }
        return value
    }

    /// How an amount appears in an edit field: "7.76", "-0.50".
    static func editText(_ value: Decimal?) -> String {
        guard let value = value else {
            return ""
        }
        let formatter = NumberFormatter()
        formatter.locale = posix
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? MoneyCoding.text(value)
    }
}
