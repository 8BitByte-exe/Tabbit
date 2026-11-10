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

    // MARK: - Partly unreadable prices

    /// A price at the end of a line whose last digits OCR couldn't read ("$24.9îŚ").
    struct DamagedAmount: Equatable {
        /// The amount with zeros for the unreadable digits (24.90).
        let low: Decimal
        /// The amount with nines for the unreadable digits (24.99).
        let high: Decimal
        /// The amount if the unreadable characters are digits that look like them ("S" for 5), or nil.
        let lookAlike: Decimal?
        /// The text in front of the amount.
        let textBefore: String
        /// The amount as printed.
        let printed: String
    }

    // Digits, a decimal point and fewer than two readable cents, then 1–3 characters that
    // aren't digits, optionally followed by a tax flag. Groups: 1 = currency symbol,
    // 2 = whole part, 3 = readable cents (0 or 1 digit), 4 = the unreadable characters.
    private static let damagedPattern = Patterns.make(
        #"(?<![\d.,])([$€£]?)\s?(\d{1,3}(?:[.,]\d{3})+|\d+)[.,](\d?)([^\s\d.,%/@()+\-]{1,3})(?:\s+[A-Za-z*]{1,3})?\s*$"#
    )

    /// Characters OCR reads in place of a digit, by shape (accents removed first).
    static let digitLookAlikes: [Character: Character] = [
        "O": "0", "o": "0", "D": "0", "Q": "0",
        "l": "1", "I": "1", "i": "1", "|": "1", "!": "1", "]": "1", "[": "1",
        "Z": "2", "z": "2", "S": "5", "s": "5", "§": "5",
        "b": "6", "G": "6", "T": "7", "B": "8", "g": "9", "q": "9",
    ]

    /// A price whose cents OCR garbled, if `text` ends with one. Characters that are all
    /// plain letters only count after a currency symbol, so units ("45.3L", "1.5KG") aren't prices.
    static func damagedAmount(in text: String) -> DamagedAmount? {
        guard trailingAmount(in: text) == nil, let match = damagedPattern.allMatches(in: text).last,
              let wholePart = match.group(2, in: text), let readable = match.group(3, in: text),
              let unreadable = match.group(4, in: text) else {
            return nil
        }
        let symbol = match.group(1, in: text) ?? ""
        let plainLetters = unreadable.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && CharacterSet.letters.contains(scalar)
        }
        if plainLetters && symbol.isEmpty {
            return nil
        }
        let digits = wholePart
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
        let missing = 2 - readable.count
        guard missing > 0,
              let low = Decimal(string: digits + "." + readable + String(repeating: "0", count: missing), locale: posix),
              let high = Decimal(string: digits + "." + readable + String(repeating: "9", count: missing), locale: posix) else {
            return nil
        }
        // "S" or "Ś" for 5: a reading by shape, used when the arithmetic can't decide.
        let folded = unreadable.folding(options: [.diacriticInsensitive], locale: posix)
        var shaped = ""
        for character in folded {
            guard let digit = digitLookAlikes[character] else {
                shaped = ""
                break
            }
            shaped.append(digit)
        }
        var lookAlike: Decimal?
        if shaped.count == missing {
            lookAlike = Decimal(string: digits + "." + readable + shaped, locale: posix)
        }
        let nsText = text as NSString
        let printed = nsText.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
        let before = nsText.substring(to: match.range.location).trimmingCharacters(in: .whitespacesAndNewlines)
        return DamagedAmount(low: low, high: high, lookAlike: lookAlike, textBefore: before, printed: printed)
    }
}
