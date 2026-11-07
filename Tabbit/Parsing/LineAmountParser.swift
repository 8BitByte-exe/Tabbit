import Foundation

/// What a receipt line costs, with its quantity and unit price when the receipt shows them.
struct LineAmount: Equatable {
    /// What the line costs in total (negative for a discount).
    let value: Decimal
    /// The text in front of the amount, usually the item's name.
    let textBefore: String
    /// How many were bought: "2 @ 1.99", "2 BANANAS", "QTY 3", "1.25 LB @ 0.99".
    var quantity: Decimal? = nil
    /// The price of one.
    var unitPrice: Decimal? = nil
    /// True if no line total is printed and Tabbit worked out quantity × unit price.
    var isComputed: Bool = false
    /// Another reading of the amount: "2 BANANAS 1.99" usually means 1.99 for both, but
    /// could mean 1.99 each (3.98). Only used if the receipt doesn't add up otherwise.
    var alternative: Decimal? = nil
}

/// Reads the amount of a receipt line, including lines that only print a unit price.
///
/// Receipts show quantities in a few ways:
/// - "2 @ 0.99   1.98" or "1.25 LB @ 0.99/LB   1.24": quantity, unit price and line total.
/// - "2 @ 1.99" or "2 BANANAS 1.99/EA": only the unit price; the total is worked out.
/// - "2 BANANAS 3.98", "2X BURGER 24.00", "QTY 2 … 3.98": a quantity and the line total.
/// Deals like "2 FOR 5.00" or "BUY 1 GET 1" are not unit prices.
enum LineAmountParser {

    private static let units = #"(?:LBS?|KG|G|GR|OZ|EA|PCS?|PK|CT|STK|ST|L|LTR)"#

    // "2 @ 1.99", "2 X 1.99", "1.25 LB @ 0.99", "0,456 kg x 3,99" (anywhere in the text).
    private static let quantityAtPrice = Patterns.make(
        #"(?<![\d.,])(\d{1,3}(?:[.,]\d{1,3})?)\s*"# + units + #"?\s*(?:@|X|×|\*)\s*[$€£]?\s*(\d{1,4}[.,]\d{2,3})(?!\d)"#,
        caseInsensitive: true
    )

    // Text that ends in "2 @", or is only "2 X" / "2 Stk x" (the price that follows is a unit
    // price). "BOUNTY 6X 12.99" is a 6-pack, not six of them.
    private static let endsWithQuantityAt = Patterns.make(
        #"(?<![\d.,])(\d{1,3}(?:[.,]\d{1,3})?)\s*"# + units + #"?\s*@\s*[$€£]?\s*$|^\s*(\d{1,3}(?:[.,]\d{1,3})?)\s*"#
            + units + #"?\s*(?:X|×)\s*[$€£]?\s*$"#,
        caseInsensitive: true
    )

    // A unit price at the very end: "1.99/EA", "1.99 EA", "1.99 EACH", "$1.99/ea", "1,29 €/Stk".
    private static let trailingUnitPrice = Patterns.make(
        #"[$€£]?\s*(\d{1,4}[.,]\d{2})\s*[$€£]?\s*(?:/\s*|\s+)(?:EA|EACH|PC|PCS|STK|UN|UNIT)\.?\s*$"#,
        caseInsensitive: true
    )

    // A quantity in front of the name: "2 BANANAS", "2X BURGER", "2 x Latte". Not a size
    // like "12 PACK", "6 INCH" or "2 LITRE", and not a deal like "2 FOR 5.00".
    private static let leadingQuantity = Patterns.make(
        #"^\s*(\d{1,2})(?:\s*[xX×*])?\s+(?!(?:FOR|PER|PACK|PK|CT|COUNT|INCH|IN|OZ|L|LT|LTR|LITRE|LITER|ML|LB|LBS|KG|G|PC|PCS|PIECE|PIECES|ROLL|ROLLS|SLICE|SLICES|%)\b)(?=[A-Za-zÀ-ÿ])"#,
        caseInsensitive: true
    )

    // "QTY 2", "QTY: 2", "MENGE 2", "CANT 2".
    private static let quantityWord = Patterns.make(
        #"\b(?:QTY|QUANTITY|MENGE|CANT)\.?\s*:?\s*(\d{1,3})\b"#,
        caseInsensitive: true
    )

    private static let posix = Locale(identifier: "en_US_POSIX")
    private static let cent = Decimal(string: "0.01", locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(0)

    static func read(_ text: String) -> LineAmount? {
        // "2 BANANAS 1.99/EA", "2 @ 1.99 EA": only the unit price is printed.
        if let match = trailingUnitPrice.allMatches(in: text).last, let unitText = match.group(1, in: text),
           let unit = number(unitText), unit > 0 {
            let before = (text as NSString).substring(to: match.range.location)
            let name = removingQuantity(from: before)
            guard let quantity = quantityIn(before) else {
                return LineAmount(value: unit, textBefore: name, unitPrice: unit)
            }
            let total = Money.rounded(quantity * unit)
            return LineAmount(value: total, textBefore: name, quantity: quantity, unitPrice: unit,
                              isComputed: total != unit, alternative: total != unit ? unit : nil)
        }
        guard let printed = AmountParser.trailingAmount(in: text) else {
            return nil
        }
        return readPrinted(printed)
    }

    private static func readPrinted(_ printed: AmountParser.ParsedAmount) -> LineAmount {
        let before = printed.textBefore
        var result = LineAmount(value: printed.value, textBefore: before)
        let magnitude = printed.value < 0 ? -printed.value : printed.value

        // "2 @ 1.99": the printed amount is the unit price, and nothing follows it.
        if let found = quantityAtEnd(of: before) {
            let quantity = found.quantity
            let name = (before as NSString).substring(to: found.location)
            let total = Money.rounded(quantity * magnitude)
            let isComputed = total != magnitude
            return LineAmount(value: printed.value < 0 ? -total : total,
                              textBefore: name.trimmingCharacters(in: .whitespaces),
                              quantity: quantity, unitPrice: magnitude, isComputed: isComputed,
                              alternative: isComputed ? printed.value : nil)
        }

        // "2 BANANAS 1.99/EA 3.98": a unit price with the line total after it.
        if let match = trailingUnitPrice.allMatches(in: before).last, let unitText = match.group(1, in: before),
           let unit = number(unitText), unit > 0 {
            let rest = (before as NSString).substring(to: match.range.location)
            let each = magnitude / unit
            let quantity = quantityIn(rest) ?? (Money.rounded(each) == each ? each : nil)
            if let quantity = quantity, quantity > 0, isClose(quantity * unit, magnitude) {
                result.quantity = quantity
                result.unitPrice = unit
            }
            return LineAmount(value: printed.value, textBefore: removingQuantity(from: rest),
                              quantity: result.quantity, unitPrice: result.unitPrice)
        }

        // "2 @ 0.99   1.98": quantity and unit price that give the printed total.
        if let match = quantityAtPrice.allMatches(in: before).last, let quantityText = match.group(1, in: before),
           let unitText = match.group(2, in: before), let quantity = number(quantityText), let unit = number(unitText) {
            if isClose(quantity * unit, magnitude) {
                result.quantity = quantity
                result.unitPrice = unit
            }
            return result
        }

        // "2 BANANAS 3.98": a quantity and (usually) the line total.
        if let quantity = quantityIn(before), quantity > 1, magnitude > 0 {
            result.quantity = quantity
            let each = magnitude / quantity
            if Money.rounded(each) == each {
                result.unitPrice = each
            }
            result.alternative = printed.value < 0 ? -Money.rounded(magnitude * quantity) : Money.rounded(magnitude * quantity)
        }
        return result
    }

    /// A whole-number quantity in front of the name or after "QTY", or a "2 @"-style quantity.
    private static func quantityIn(_ text: String) -> Decimal? {
        if let match = quantityWord.allMatches(in: text).first, let digits = match.group(1, in: text),
           let value = Decimal(string: digits, locale: posix), value > 0 {
            return value
        }
        if let match = leadingQuantity.allMatches(in: text).first, let digits = match.group(1, in: text),
           let value = Decimal(string: digits, locale: posix), value > 0 {
            return value
        }
        return quantityAtEnd(of: text)?.quantity
    }

    /// A trailing "2 @" (or a lone "2 X"): the quantity and where the fragment starts.
    private static func quantityAtEnd(of text: String) -> (quantity: Decimal, location: Int)? {
        guard let match = endsWithQuantityAt.allMatches(in: text).last,
              let digits = match.group(1, in: text) ?? match.group(2, in: text),
              let value = number(digits), value > 0 else {
            return nil
        }
        return (quantity: value, location: match.range.location)
    }

    /// The text without a trailing "2 @" fragment.
    private static func removingQuantity(from text: String) -> String {
        if let found = quantityAtEnd(of: text) {
            return (text as NSString).substring(to: found.location).trimmingCharacters(in: .whitespaces)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// "2 BANANAS" bought twice reads "2× BANANAS"; "QTY 2 BURGER" reads "2× BURGER".
    /// Weights and single items keep their name.
    static func name(_ name: String, quantity: Decimal?) -> String {
        guard let quantity = quantity, quantity > 1, quantity < 100 else {
            return name
        }
        let count = NSDecimalNumber(decimal: quantity).intValue
        guard Decimal(count) == quantity else {
            return name
        }
        let bare = withoutLeadingQuantity(name)
        guard bare.rangeOfCharacter(from: .letters) != nil else {
            return name
        }
        return "\(count)× " + bare
    }

    /// The name without a quantity in front: "2 BANANAS" → "BANANAS", "2X BURGER" → "BURGER",
    /// "QTY 2 BURGER" → "BURGER", "2× Latte" → "Latte".
    static func withoutLeadingQuantity(_ name: String) -> String {
        var text = name.trimmingCharacters(in: .whitespaces)
        if let match = leadingQuantityWord.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) {
            text = (text as NSString).substring(from: match.range.location + match.range.length)
        } else if let match = leadingQuantity.allMatches(in: text).first {
            text = (text as NSString).substring(from: match.range.location + match.range.length)
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " -:"))
    }

    // "QTY 2 " at the start of a name.
    private static let leadingQuantityWord = Patterns.make(
        #"^\s*(?:QTY|QUANTITY|MENGE|CANT)\.?\s*:?\s*\d{1,3}\s+"#,
        caseInsensitive: true
    )

    private static func isClose(_ first: Decimal, _ second: Decimal) -> Bool {
        let difference = first - second
        return (difference < 0 ? -difference : difference) <= cent
    }

    /// "1,25" or "1.25" or "2" as a number.
    private static func number(_ text: String) -> Decimal? {
        return Decimal(string: text.replacingOccurrences(of: ",", with: "."), locale: posix)
    }
}
