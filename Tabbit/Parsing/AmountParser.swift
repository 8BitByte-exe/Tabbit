import Foundation

/// Finds money amounts in a line of receipt text.
enum AmountParser {

    struct ParsedAmount: Equatable {
        /// The amount, negative for discounts ("-0.50" or "0.50-").
        let value: Decimal
        /// The text in front of the amount, trimmed (usually the item name).
        let textBefore: String
    }

    // An amount with exactly two decimals: 12.34, 1,234.56, 1.234,56, 12,34,
    // optionally with a currency symbol and a leading or trailing minus.
    // Groups: 1 = leading minus, 2 = minus after the symbol, 3 = whole part,
    // 4 = cents, 5 = trailing minus.
    // Not followed by another digit or "%", so "8.875%" and "3.499" are not amounts.
    private static let amountPattern = Patterns.make(
        #"(?<!\d)(-)?\s?[$€£]?\s?(-)?(\d{1,3}(?:[.,]\d{3})+|\d+)[.,](\d{2})(?![\d%])(-)?"#
    )

    // What may follow the amount at the end of a line: a short tax flag
    // such as "T", "F", "N", "*" or a currency code like "USD".
    private static let allowedSuffix = Patterns.make(#"^\s*-?\s*[A-Za-z*]{0,3}\s*$"#)

    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Every amount anywhere in `text`, as positive values ("-1.00" gives 1.00).
    /// Used to check that numbers Apple Intelligence reports are really printed on the receipt.
    static func allAmounts(in text: String) -> [Decimal] {
        var values: [Decimal] = []
        for match in amountPattern.allMatches(in: text) {
            guard let wholePart = match.group(3, in: text), let cents = match.group(4, in: text) else {
                continue
            }
            let digits = wholePart
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: ".", with: "")
            if let value = Decimal(string: digits + "." + cents, locale: posix) {
                values.append(value)
            }
        }
        return values
    }

    /// The amount at the end of `text`, if the text ends with one.
    static func trailingAmount(in text: String) -> ParsedAmount? {
        guard let match = amountPattern.allMatches(in: text).last else {
            return nil
        }
        let nsText = text as NSString
        let matchEnd = match.range.location + match.range.length
        let remainder = nsText.substring(from: matchEnd)
        guard allowedSuffix.hasMatch(in: remainder) else {
            return nil
        }
        guard let wholePart = match.group(3, in: text), let cents = match.group(4, in: text) else {
            return nil
        }

        let digits = wholePart
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
        guard var value = Decimal(string: digits + "." + cents, locale: posix) else {
            return nil
        }

        let isNegative = match.group(1, in: text) != nil
            || match.group(2, in: text) != nil
            || match.group(5, in: text) != nil
            || remainder.contains("-")
        if isNegative {
            value = -value
        }

        let before = nsText.substring(to: match.range.location)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedAmount(value: value, textBefore: before)
    }
}
