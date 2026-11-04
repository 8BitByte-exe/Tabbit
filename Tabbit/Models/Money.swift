import Foundation

/// Money helpers. Amounts are `Decimal`; splitting works in whole cents (`Int`)
/// so every share adds up exactly.
enum Money {
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter
    }()

    private static let wholeCurrencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// "$12.50" in the phone's currency and format.
    static func string(_ value: Decimal) -> String {
        return currencyFormatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    /// "$13" — for compact chart labels.
    static func wholeString(_ value: Decimal) -> String {
        return wholeCurrencyFormatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    /// The phone's currency symbol, e.g. "$".
    static var currencySymbol: String {
        return currencyFormatter.currencySymbol ?? "$"
    }

    /// The amount in whole cents, rounded half away from zero.
    static func cents(_ value: Decimal) -> Int {
        var input = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    static func fromCents(_ cents: Int) -> Decimal {
        return Decimal(cents) / 100
    }

    /// The amount rounded to cents.
    static func rounded(_ value: Decimal) -> Decimal {
        return fromCents(cents(value))
    }
}
