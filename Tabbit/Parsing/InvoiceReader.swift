import Foundation

/// What Tabbit could read from an invoice's text, to fill in the invoice form.
/// Every field is a suggestion the person checks before saving.
struct InvoiceReading: Equatable {
    var amount: Decimal?
    var number: String?
    var issueDate: CalendarDate?
    var dueDate: CalendarDate?
    /// "Net 30" / "due in 30 days" without a printed due date.
    var dueInDays: Int?

    var isEmpty: Bool {
        return amount == nil && number == nil && issueDate == nil && dueDate == nil && dueInDays == nil
    }
}

/// Reads the amount due, invoice number and dates from an invoice's lines of text
/// (from a PDF's text, or from OCR of a scan or photo). Plain rules, on the device.
enum InvoiceReader {

    /// Labels of the amount to pay, strongest first.
    private static let dueLabels = [
        "amount due", "balance due", "total due", "amount payable", "total payable", "please pay",
        "pay this amount", "amount to pay", "invoice total", "grand total", "total amount",
    ]

    // An amount with two decimals: 1,250.00, 1.250,00, 980.5 isn't one. Optional symbol in front.
    private static let amountPattern = Patterns.make(
        #"(?<![\d.,])[$€£]?\s?(\d{1,3}(?:[.,]\d{3})+|\d+)[.,](\d{2})(?![\d%])"#
    )

    // "Invoice # 0042", "Invoice No. INV-7", "Invoice number: 2026-014", "INVOICE #A12".
    private static let numberAfterLabel = Patterns.make(
        #"\binvoice\s*(?:number|num\.?|no\.?|nr\.?|#|id)\s*[:.#]?\s*#?\s*([A-Za-z0-9][A-Za-z0-9\-/_.]*)"#,
        caseInsensitive: true
    )

    // "INV-0042" anywhere.
    private static let invoiceCode = Patterns.make(#"\b(INV[-#]?\s?\d[A-Za-z0-9\-/_]*)"#, caseInsensitive: true)

    // A line that only labels the number ("Invoice Number"), with the value on the next line.
    private static let numberLabelOnly = Patterns.make(
        #"^\s*invoice\s*(?:number|num\.?|no\.?|nr\.?|#)\s*:?\s*$"#, caseInsensitive: true
    )

    private static let netDays = Patterns.make(
        #"\b(?:net|due\s+(?:with)?in)\s*(\d{1,3})(?:\s*days)?\b"#, caseInsensitive: true
    )

    private static let posix = Locale(identifier: "en_US_POSIX")

    static func read(lines rawLines: [String], reference: Date = Date()) -> InvoiceReading {
        let lines = rawLines
            .map { line in line.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in !line.isEmpty }
        var reading = InvoiceReading()
        reading.amount = amountDue(in: lines)
        reading.number = number(in: lines)

        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            if reading.dueDate == nil && isDueDateLabel(lower) {
                reading.dueDate = ReceiptDateParser.date(in: line, reference: reference)
                    ?? nextLine(after: index, in: lines).flatMap { next in ReceiptDateParser.date(in: next, reference: reference) }
            }
            if reading.issueDate == nil && isIssueDateLabel(lower) {
                reading.issueDate = ReceiptDateParser.date(in: line, reference: reference)
                    ?? nextLine(after: index, in: lines).flatMap { next in ReceiptDateParser.date(in: next, reference: reference) }
            }
            if reading.dueInDays == nil, let match = netDays.allMatches(in: line).first,
               let days = Int(match.group(1, in: line) ?? ""), days > 0 {
                reading.dueInDays = days
            }
        }
        if reading.issueDate == nil {
            // The first date that isn't the due date.
            for line in lines where !isDueDateLabel(line.lowercased()) {
                if let date = ReceiptDateParser.date(in: line, reference: reference), date != reading.dueDate {
                    reading.issueDate = date
                    break
                }
            }
        }
        return reading
    }

    /// The amount on the line labelled as the amount to pay (or the line after it), else
    /// a plain "Total" line, else the largest amount on the invoice.
    static func amountDue(in lines: [String]) -> Decimal? {
        for label in dueLabels {
            for (index, line) in lines.enumerated() where line.lowercased().contains(label) {
                if let value = lastAmount(in: line) ?? nextLine(after: index, in: lines).flatMap({ next in lastAmount(in: next) }) {
                    return value
                }
            }
        }
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard lower.contains("total"), !isSubtotalOrTax(lower) else {
                continue
            }
            if let value = lastAmount(in: line) ?? nextLine(after: index, in: lines).flatMap({ next in lastAmount(in: next) }) {
                return value
            }
        }
        return lines.compactMap { line in lastAmount(in: line) }.max()
    }

    static func number(in lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            for match in numberAfterLabel.allMatches(in: line) {
                if let token = match.group(1, in: line).map({ text in cleanToken(text) }), token.contains(where: { character in character.isNumber }) {
                    return token
                }
            }
            if numberLabelOnly.hasMatch(in: line), let next = nextLine(after: index, in: lines) {
                let token = cleanToken(next)
                if !token.contains(" "), token.contains(where: { character in character.isNumber }),
                   ReceiptDateParser.date(in: token) == nil {
                    return token
                }
            }
        }
        for line in lines {
            if let match = invoiceCode.allMatches(in: line).first, let token = match.group(1, in: line) {
                return cleanToken(token)
            }
        }
        return nil
    }

    /// The last two-decimal amount in a line.
    static func lastAmount(in line: String) -> Decimal? {
        guard let match = amountPattern.allMatches(in: line).last,
              let whole = match.group(1, in: line), let cents = match.group(2, in: line) else {
            return nil
        }
        let digits = whole.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "")
        return Decimal(string: digits + "." + cents, locale: posix)
    }

    private static func cleanToken(_ token: String) -> String {
        var cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = cleaned.last, last == "." || last == "," || last == ":" {
            cleaned.removeLast()
        }
        return cleaned
    }

    private static func nextLine(after index: Int, in lines: [String]) -> String? {
        return index + 1 < lines.count ? lines[index + 1] : nil
    }

    private static func isSubtotalOrTax(_ lower: String) -> Bool {
        let words = ["subtotal", "sub total", "sub-total", "tax", "vat", "gst", "hst", "net total", "total excl"]
        return words.contains { word in lower.contains(word) }
    }

    private static func isDueDateLabel(_ lower: String) -> Bool {
        return lower.contains("due date") || lower.contains("payment due") || lower.contains("due by")
            || lower.contains("due on") || lower.contains("pay by")
    }

    private static func isIssueDateLabel(_ lower: String) -> Bool {
        return lower.contains("invoice date") || lower.contains("issue date") || lower.contains("date of issue")
            || lower.contains("issued") || lower.contains("date issued")
    }
}
