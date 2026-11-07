import Foundation

/// The parts of a receipt around the items: the time of purchase, the store's address,
/// how it was paid and a printed tax rate.
///
/// Receipts everywhere print the same things in different words and orders: the store
/// and its address at the top, then the date and time, the items, the totals, and how it
/// was paid at the bottom. These readers look for each one where it usually is.
enum ReceiptDetailsParser {

    // MARK: - Time

    // "14:32", "2:32 PM", "02:32:10 p.m.", "14h32" (French). Not "12.34" (a price) and not
    // part of a longer run like "01:23:45:67".
    private static let timePattern = Patterns.make(
        #"(?<![\d:])([01]?\d|2[0-3])(?::|h)([0-5]\d)(?::[0-5]\d)?(?![\d:])(?:\s{0,2}([AaPp])(?:\.?\s?[Mm]\b\.?|(?![A-Za-z])))?"#
    )

    private static let timeWords: Set<String> = ["TIME", "ZEIT", "HORA", "HEURE", "ORA", "TIJD", "UHRZEIT"]

    /// The time of purchase. A time on a line with a date or a TIME word wins; otherwise
    /// the first time on the receipt.
    static func time(in lines: [String]) -> ClockTime? {
        var first: ClockTime?
        for line in lines {
            guard let found = time(inLine: line) else {
                continue
            }
            let words = ReceiptKeywords.words(in: line)
            if ReceiptDateParser.date(in: line) != nil || words.contains(where: { word in timeWords.contains(word) }) {
                return found
            }
            if first == nil {
                first = found
            }
        }
        return first
    }

    /// The first time of day in one line.
    static func time(inLine text: String) -> ClockTime? {
        for match in timePattern.allMatches(in: text) {
            guard let hourText = match.group(1, in: text), let minuteText = match.group(2, in: text),
                  var hour = Int(hourText), let minute = Int(minuteText) else {
                continue
            }
            if let marker = match.group(3, in: text)?.uppercased(), hour >= 1, hour <= 12 {
                if marker == "P" && hour < 12 {
                    hour += 12
                } else if marker == "A" && hour == 12 {
                    hour = 0
                }
            }
            return ClockTime(hour: hour, minute: minute)
        }
        return nil
    }

    // MARK: - Location

    // "123 MAIN ST", "4500 W. Sunset Blvd", "12B High Street", "1 Infinite Loop Suite 4".
    private static let numberedStreetPattern = Patterns.make(
        #"^\s*\d{1,6}[A-Z]?(?:-\d{1,6})?\s+(?:[^\s]+\s+){0,5}?(?:ST|STREET|AVE|AV|AVENUE|RD|ROAD|BLVD|BOULEVARD|DR|DRIVE|LN|LANE|WAY|HWY|HIGHWAY|PKWY|PARKWAY|CT|COURT|PL|PLACE|SQ|SQUARE|TER|TERRACE|CIR|CIRCLE|CRES|CRESCENT|TRL|TRAIL|PIKE|ROUTE|RTE|LOOP|ROW|MALL|PLAZA|CENTRE|CENTER|SUITE|STE|UNIT|N|S|E|W|NE|NW|SE|SW)\b\.?"#,
        caseInsensitive: true
    )

    // Streets in Europe and Latin America: "Hauptstraße 12", "Calle Mayor 5", "12 Rue de Rivoli",
    // "Via Roma 10", "Kalverstraat 1".
    private static let europeanStreetPattern = Patterns.make(
        #"(?:STRASSE|STRAßE|STR\.|WEG\b|GASSE\b|PLATZ\b|ALLEE\b|DAMM\b|RING\b|STRAAT\b|LAAN\b|PLEIN\b|GRACHT\b|\bCALLE\b|\bC/|\bAVENIDA\b|\bAVDA\b|\bPASEO\b|\bRUE\b|\bBD\b|\bVIA\b|\bVIALE\b|\bCORSO\b|\bPIAZZA\b|\bPLAZA\b|\bRUA\b|\bCARRER\b)"#,
        caseInsensitive: true
    )

    // City lines: "SPRINGFIELD, IL 62701", "TORONTO ON M5V 2T6", "LONDON SW1A 1AA",
    // "10115 Berlin", "75001 PARIS", "1012 AB Amsterdam".
    private static let postalPatterns: [NSRegularExpression] = [
        Patterns.make(#"\b[A-Z]{2}\s*\d{5}(?:-\d{4})?\b"#),
        Patterns.make(#"\b[A-Z]\d[A-Z]\s?\d[A-Z]\d\b"#, caseInsensitive: true),
        Patterns.make(#"\b[A-Z]{1,2}\d[A-Z\d]?\s+\d[A-Z]{2}\b"#),
        Patterns.make(#"^\s*(?:[A-Z]{1,2}-)?\d{4,5}\s+[A-Za-zÀ-ÿ]{3,}"#),
        Patterns.make(#"^\s*\d{4}\s?[A-Z]{2}\s+[A-Za-zÀ-ÿ]{3,}"#),
        // "SPRINGFIELD, IL" with no postal code.
        Patterns.make(#"^[A-Za-z .'-]{3,},\s*[A-Z]{2}\s*$"#),
    ]

    // Lines that are contact details or receipt details, never the address.
    private static let notAddressPattern = Patterns.make(
        #"\b(?:TEL|PHONE|FAX|PH|WWW|HTTP|HTTPS|EMAIL|E-MAIL|STORE\s*#|STORE\s+NO|CASHIER|REGISTER|TERMINAL|TRANS|ORDER|TABLE|SERVER|GUEST|RECEIPT|INVOICE|VAT|GST|HST|ABN|NIF|CIF|USt|MANAGER|OPEN|HOURS)\b|@|\.COM\b"#,
        caseInsensitive: true
    )

    private static let addressDetector: NSDataDetector? = {
        return try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)
    }()

    /// The store's address from the lines above the items: a street line and the city
    /// line after it, joined with ", ". Nil if no line looks like an address.
    static func location(in header: [String]) -> String? {
        var parts: [String] = []
        for line in header.prefix(12) {
            let text = tidy(line)
            if text.isEmpty {
                continue
            }
            let isStreet = isStreetLine(text)
            let isCity = isCityLine(text)
            if parts.isEmpty {
                if isStreet || isCity || isDetectedAddress(text) {
                    parts.append(text)
                }
            } else if (isCity || isStreet) && parts.count < 3 {
                // "123 MAIN ST" then "SPRINGFIELD, IL 62701".
                parts.append(text)
            } else {
                break
            }
        }
        guard !parts.isEmpty else {
            return nil
        }
        let joined = parts.joined(separator: ", ")
        return joined.count <= 120 ? joined : String(joined.prefix(120))
    }

    static func isStreetLine(_ text: String) -> Bool {
        guard !notAddressPattern.hasMatch(in: text), ReceiptDateParser.date(in: text) == nil else {
            return false
        }
        if numberedStreetPattern.hasMatch(in: text) {
            return true
        }
        // European streets carry a house number: "Hauptstraße 12" (not "CATERING").
        return europeanStreetPattern.hasMatch(in: text) && text.rangeOfCharacter(from: .decimalDigits) != nil
    }

    static func isCityLine(_ text: String) -> Bool {
        guard !notAddressPattern.hasMatch(in: text), ReceiptDateParser.date(in: text) == nil,
              text.rangeOfCharacter(from: .letters) != nil else {
            return false
        }
        return postalPatterns.contains(where: { pattern in pattern.hasMatch(in: text) })
    }

    /// Apple's address detector, for layouts the patterns don't know. Most of the line must be the address.
    private static func isDetectedAddress(_ text: String) -> Bool {
        guard let detector = addressDetector, !notAddressPattern.hasMatch(in: text) else {
            return false
        }
        let length = (text as NSString).length
        guard length >= 8 else {
            return false
        }
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: length))
        let covered = matches.reduce(0) { sum, match in sum + match.range.length }
        return Double(covered) >= 0.6 * Double(length)
    }

    /// Single spaces, no stray separators at the ends.
    private static func tidy(_ text: String) -> String {
        let pieces = text.split(separator: " ", omittingEmptySubsequences: true)
        return pieces.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,;:*-|"))
    }

    // MARK: - Payment method

    /// Payment names in the order they're preferred: a card brand says more than "Debit",
    /// and "CASH BACK" on a card receipt isn't a cash payment.
    private static let paymentNames: [(name: String, words: [[String]])] = [
        ("Amex", [["AMEX"], ["AMERICAN", "EXPRESS"]]),
        ("Mastercard", [["MASTERCARD"], ["MASTER", "CARD"], ["MC"], ["M", "C"]]),
        ("Visa", [["VISA"]]),
        ("Discover", [["DISCOVER"]]),
        ("Interac", [["INTERAC"]]),
        ("Maestro", [["MAESTRO"]]),
        ("Apple Pay", [["APPLE", "PAY"], ["APPLEPAY"]]),
        ("Google Pay", [["GOOGLE", "PAY"], ["GPAY"], ["ANDROID", "PAY"]]),
        ("PayPal", [["PAYPAL"]]),
        ("Gift card", [["GIFT", "CARD"], ["GIFTCARD"], ["GIFT", "CERT"]]),
        ("EBT", [["EBT"]]),
        ("Debit", [["DEBIT"], ["GIROCARD"], ["EC", "KARTE"], ["BANKOMAT"]]),
        ("Cash", [["CASH"], ["BARGELD"], ["BAR"], ["GEGEBEN"], ["EFECTIVO"], ["ESPECES"], ["CONTANTI"], ["CONTANT"]]),
        ("Credit card", [["CREDIT"], ["KREDITKARTE"], ["TARJETA"], ["CARTE"], ["KARTENZAHLUNG"], ["CARD"]]),
    ]

    /// Payment words that are also ordinary words or short codes.
    private static let looseWords: Set<String> = ["MC", "M C", "BAR", "CARD", "CREDIT", "CARTE", "TARJETA", "GEGEBEN"]

    /// How the receipt was paid ("Visa", "Debit", "Cash"), from the lines after the first
    /// total (or the whole receipt if there's no total). The card number is never kept.
    static func paymentMethod(in lines: [String]) -> String? {
        let start = lines.firstIndex(where: { line in
            let role = ReceiptKeywords.role(for: line)
            return role == .total || role == .strongTotal
        }) ?? 0
        var found: [String] = []
        for line in lines[start...] {
            let role = ReceiptKeywords.role(for: line)
            if role == .tip || ReceiptKeywords.isSavings(line) {
                continue
            }
            var words = ReceiptKeywords.words(in: line)
            // "CASH BACK" is money taken out with a card, not how it was paid.
            if let index = words.firstIndex(of: "CASH"), index + 1 < words.count, words[index + 1] == "BACK" {
                words.remove(at: index)
            }
            let isPaymentLine = role == .payment || words.contains("PAYMENT")
                || AmountParser.trailingAmount(in: line) != nil
            for (name, phrases) in paymentNames {
                let matched = phrases.filter { phrase in ReceiptDetailsParser.containsPhrase(words, phrase) }
                guard !matched.isEmpty else {
                    continue
                }
                // Short or everyday words ("MC", "BAR", "CARD") only count on a line that pays something.
                let onlyLoose = matched.allSatisfy { phrase in looseWords.contains(phrase.joined(separator: " ")) }
                if onlyLoose && !isPaymentLine {
                    continue
                }
                found.append(name)
            }
        }
        for (name, _) in paymentNames where found.contains(name) {
            return name
        }
        return nil
    }

    /// True if `phrase` appears in `words` as consecutive words.
    private static func containsPhrase(_ words: [String], _ phrase: [String]) -> Bool {
        guard !phrase.isEmpty, words.count >= phrase.count else {
            return false
        }
        for start in 0...(words.count - phrase.count) {
            var matches = true
            for (offset, word) in phrase.enumerated() where words[start + offset] != word {
                matches = false
                break
            }
            if matches {
                return true
            }
        }
        return false
    }

    // MARK: - Tax rate

    private static let percentPattern = Patterns.make(#"(?<![\d.,])(\d{1,2}(?:[.,]\d{1,3})?)\s*%"#)
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// A rate printed on a line: "HST 13% 6.50" → 13, "MwSt 19,0 %" → 19.
    static func percent(in text: String) -> Decimal? {
        guard let match = percentPattern.allMatches(in: text).first, let digits = match.group(1, in: text),
              let value = Decimal(string: digits.replacingOccurrences(of: ",", with: "."), locale: posix),
              value > 0 else {
            return nil
        }
        return value
    }
}
