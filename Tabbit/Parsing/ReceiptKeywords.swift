import Foundation

/// What a receipt line is, judged from its words.
enum ReceiptLineRole: Equatable {
    case subtotal
    /// A line that states the overall tax, like "TOTAL TAX".
    case taxTotal
    case tax
    /// Tax that's already in the prices: "INCL. VAT 1.50", "MwSt enthalten", "IVA INCLUIDO".
    /// Informational only; it must not be added on top.
    case includedTax
    /// "GRAND TOTAL", "AMOUNT DUE", "BALANCE DUE", "ZU ZAHLEN", "A PAGAR".
    case strongTotal
    case total
    /// "TOTAL SAVINGS", "TOTAL ITEMS" and similar: not the amount paid.
    case notATotal
    /// "TIP", "GRATUITY", "SERVICE CHARGE".
    case tip
    /// Card, cash, change and similar lines.
    case payment
    /// "MEMBER DISCOUNT", "COUPON", "RABATT": money off, even when printed without a minus.
    case discount
    /// Cash rounding ("ROUNDING -0.02"): part of the total, not a purchase.
    case rounding
    /// Price information that usually isn't a separate purchase:
    /// "REG PRICE 4.99", "YOU SAVE 1.00", "CLUB CARD SAVINGS". With a negative
    /// amount it's a discount, and it counts.
    case info
    case other

    /// Roles that end the list of items.
    static let summaryRoles: [ReceiptLineRole] = [.subtotal, .taxTotal, .tax, .strongTotal, .total]
}

/// Keyword matching that tolerates OCR mistakes ("SJETOTAL" → SUBTOTAL, "T0TAL" → TOTAL).
enum ReceiptKeywords {

    // MARK: - Words

    /// The upper-case words of a line. Inside words, digits that OCR often confuses
    /// with letters are turned back into letters ("T0TAL" → "TOTAL", "5UBTOTAL" →
    /// "SUBTOTAL"), and trailing digits are dropped ("TAX1" → "TAX").
    /// Pure numbers stay as they are.
    static func words(in text: String) -> [String] {
        let separators = CharacterSet.alphanumerics.inverted
        let pieces = text.uppercased().components(separatedBy: separators)
        return pieces.filter { piece in !piece.isEmpty }.map { piece in normalizedWord(piece) }
    }

    static func normalizedWord(_ word: String) -> String {
        guard word.rangeOfCharacter(from: .letters) != nil else {
            return word
        }
        var characters = Array(word)
        while characters.count > 1, let last = characters.last, last.isNumber {
            characters.removeLast()
        }
        let fixed = characters.map { (character: Character) -> Character in
            switch character {
            case "0": return "O"
            case "1": return "I"
            case "5": return "S"
            case "8": return "B"
            default: return character
            }
        }
        return String(fixed)
    }

    /// True if `word` is `keyword` give or take OCR errors: up to 2 edits for
    /// keywords of 7+ letters, 1 edit for 5–6 letters, exact for shorter ones.
    static func isLike(_ word: String, _ keyword: String) -> Bool {
        let allowed: Int
        if keyword.count >= 7 {
            allowed = 2
        } else if keyword.count >= 5 {
            allowed = 1
        } else {
            allowed = 0
        }
        if abs(word.count - keyword.count) > allowed {
            return false
        }
        if allowed == 0 {
            return word == keyword
        }
        return editDistance(word, keyword) <= allowed
    }

    /// Levenshtein distance: the number of single-letter insertions, deletions
    /// or substitutions that turn one word into the other.
    static func editDistance(_ first: String, _ second: String) -> Int {
        let a = Array(first)
        let b = Array(second)
        if a.isEmpty {
            return b.count
        }
        if b.isEmpty {
            return a.count
        }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: - Line roles

    /// Tax names in English and the common European and Latin American ones
    /// (MwSt/USt in Germany, IVA in Spain, Italy and Portugal, TVA in France, BTW in the Netherlands…).
    private static let taxWords: Set<String> = [
        "TAX", "TAXES", "HST", "GST", "PST", "QST", "VAT",
        "MWST", "UST", "IVA", "TVA", "BTW", "MOMS", "IGV", "DPH", "PTU", "KDV",
    ]

    /// Words for the total besides TOTAL itself (TOTALE, TOTAAL and TOTALT are within
    /// TOTAL's OCR tolerance already). Matched exactly: fuzzy "SUMME" would catch "SUMMER".
    private static let exactTotalWords: Set<String> = [
        "SUMME", "SUMA", "GESAMT", "GESAMTSUMME", "GESAMTBETRAG", "IMPORTE",
    ]

    /// "Included" in several languages: INCL, INCLUDED, INCLUIDO, INCLUS, INKL, ENTHALTEN, INBEGREPEN.
    private static let includedPrefixes = ["INCL", "INKL", "ENTHALT", "INBEGR", "COMPRIS"]

    private static let notATotalWords = [
        "SAVINGS", "SAVED", "SAVE", "DISCOUNT", "DISCOUNTS", "ITEMS", "ITEM",
        "QTY", "QUANTITY", "NUMBER", "POINTS", "COUNT",
    ]

    private static let paymentWords: Set<String> = [
        "CHANGE", "CASH", "TEND", "TENDER", "TENDERED", "VISA", "MASTERCARD", "AMEX",
        "DISCOVER", "DEBIT", "CREDIT", "PAYMENT", "PAID", "AUTH", "APPROVAL", "APPROVED",
        "ACCOUNT", "ACCT", "REFUND", "POINTS", "REWARDS", "EBT",
        // German, Spanish, French, Italian
        "BARGELD", "GEGEBEN", "RÜCKGELD", "RUCKGELD", "RUECKGELD", "WECHSELGELD", "GIROCARD",
        "MAESTRO", "KARTENZAHLUNG", "TARJETA", "EFECTIVO", "ENTREGADO", "CAMBIO", "ESPECES",
        "RENDU", "CONTANTI", "PAYPAL", "CONTACTLESS",
    ]

    /// Money-off words. A line with one of these is a discount even without a minus sign.
    private static let discountWords = [
        "DISCOUNT", "COUPON", "RABATT", "NACHLASS", "DESCUENTO", "REMISE", "SCONTO", "MARKDOWN",
    ]

    private static let roundingWords = ["ROUNDING", "RUNDUNG", "ARRONDI", "REDONDEO", "ARROTONDAMENTO"]

    private static let infoWords = [
        "REG", "REGULAR", "WAS", "ORIG", "ORIGINAL", "SAVE", "SAVED", "SAVES",
        "SAVING", "SAVINGS", "SALE", "MSRP",
    ]

    /// Words that may sit next to an info word without making the line an item.
    private static let infoFillerWords: Set<String> = [
        "PRICE", "YOU", "YOUR", "MEMBER", "CARD", "CLUB", "INSTANT", "STORE",
        "THIS", "ITEM", "ON", "TODAY", "PROMO", "DIGITAL",
    ]

    /// Words in quantity and deal lines like "2 @ 0.99" or "2 FOR 5.00".
    private static let detailWords: Set<String> = [
        "FOR", "EA", "EACH", "LB", "LBS", "KG", "G", "GR", "OZ", "L", "ML", "X", "AT", "QTY", "PK", "CT",
        "STK", "ST", "PC", "PCS", "UN", "UDS", "U", "EUR", "USD", "GBP", "CAD", "AUD", "CHF",
    ]

    /// What kind of line this is.
    static func role(for text: String) -> ReceiptLineRole {
        let words = self.words(in: text)
        guard !words.isEmpty else {
            return .other
        }
        if isSubtotal(words) {
            return .subtotal
        }

        let hasTotal = words.contains(where: { word in
            isLike(word, "TOTAL") || exactTotalWords.contains(word)
        })
        let hasTax = words.contains(where: { word in taxWords.contains(word) })
        let saysIncluded = words.contains(where: { word in
            includedPrefixes.contains(where: { prefix in word.hasPrefix(prefix) })
        })

        if hasTotal && hasTax && !saysIncluded {
            return .taxTotal
        }
        if hasTotal && words.contains(where: { word in matchesAny(word, notATotalWords) }) {
            return .notATotal
        }
        if isStrongTotal(words) {
            return .strongTotal
        }
        if hasTax && !saysIncluded {
            return .tax
        }
        if hasTax && !hasTotal {
            // "INCL. VAT 1.50": the tax is already in the prices. ("TOTAL INCL. VAT" is the total.)
            return .includedTax
        }
        if hasTotal {
            return .total
        }
        if words.contains(where: { word in matchesAny(word, roundingWords) }) {
            return .rounding
        }
        if isTip(words) {
            return .tip
        }
        if words.contains(where: { word in paymentWords.contains(word) }) {
            return .payment
        }
        if words.contains(where: { word in word == "OFF" || matchesAny(word, discountWords) }) {
            return .discount
        }
        if isInfo(words) {
            return .info
        }
        return .other
    }

    /// "SUBTOTAL", "SUB TOTAL", "SUB-TOTAL", "SUBTTL", "SOUS-TOTAL", "ZWISCHENSUMME"
    /// and misreads like "SJETOTAL".
    private static func isSubtotal(_ words: [String]) -> Bool {
        for (index, word) in words.enumerated() {
            if isLike(word, "SUBTOTAL") || word == "SUBTTL" || word == "SUBTL" || word.hasPrefix("ZWISCHENSUM") {
                return true
            }
            if index + 1 < words.count {
                let joined = word + words[index + 1]
                if word.count <= 4 && (isLike(joined, "SUBTOTAL") || joined == "SUBTTL") {
                    return true
                }
            }
        }
        return false
    }

    /// "TIP", "GRATUITY", "SERVICE CHARGE" (but not "TIPS SUGGESTED" style guides with a %).
    private static func isTip(_ words: [String]) -> Bool {
        if words.contains(where: { word in word == "TIP" || word == "TIPS" || isLike(word, "GRATUITY") }) {
            return !words.contains("SUGGESTED")
        }
        for index in 0..<max(words.count - 1, 0) where isLike(words[index], "SERVICE") {
            if isLike(words[index + 1], "CHARGE") {
                return true
            }
        }
        return false
    }

    /// "GRAND TOTAL", "AMOUNT DUE", "BALANCE DUE", "TOTAL DUE", "TOTAL AMOUNT", "AMOUNT TOTAL",
    /// and "to pay" in other languages: "ZU ZAHLEN", "A PAGAR", "NET A PAYER", "TE BETALEN".
    private static func isStrongTotal(_ words: [String]) -> Bool {
        if words.contains(where: { word in isLike(word, "ZAHLEN") || isLike(word, "BETALEN") || word == "PAGAR"
            || word == "PAYER" }) {
            return true
        }
        guard words.count >= 2 else {
            return false
        }
        for index in 0..<(words.count - 1) {
            let first = words[index]
            let second = words[index + 1]
            if isLike(first, "GRAND") && isLike(second, "TOTAL") {
                return true
            }
            if isLike(first, "AMOUNT") && (second == "DUE" || isLike(second, "TOTAL")) {
                return true
            }
            if isLike(first, "BALANCE") && second == "DUE" {
                return true
            }
            if isLike(first, "TOTAL") && (second == "DUE" || isLike(second, "AMOUNT")) {
                return true
            }
        }
        return false
    }

    /// True if every word with letters is an info word or filler, and at least one is an info word.
    private static func isInfo(_ words: [String]) -> Bool {
        let letterWords = words.filter { word in word.rangeOfCharacter(from: .letters) != nil }
        guard !letterWords.isEmpty else {
            return false
        }
        var sawInfoWord = false
        for word in letterWords {
            if matchesAny(word, infoWords) {
                sawInfoWord = true
            } else if !infoFillerWords.contains(word) {
                return false
            }
        }
        return sawInfoWord
    }

    /// True if `text` (what comes before a price) has no item name of its own:
    /// it's empty, or only a quantity/deal like "2 @ 0.99", "2 FOR", "1.25 LB @ 0.99/LB".
    static func isDetailOnly(_ text: String) -> Bool {
        let words = self.words(in: text)
        for word in words where word.rangeOfCharacter(from: .letters) != nil {
            if !detailWords.contains(word) {
                return false
            }
        }
        return true
    }

    private static func matchesAny(_ word: String, _ keywords: [String]) -> Bool {
        for keyword in keywords where isLike(word, keyword) {
            return true
        }
        return false
    }
}
