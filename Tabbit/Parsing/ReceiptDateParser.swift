import Foundation

/// Finds the purchase date in receipt text.
///
/// This uses explicit patterns instead of NSDataDetector because the detector
/// guesses: a lone time like "14:32" becomes today's date, which would be wrong.
enum ReceiptDateParser {

    private static let monthNames =
        "january|february|march|april|may|june|july|august|september|october|november|december"
        + "|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec"

    // 2026-11-03, 2026/11/03, 2026.11.03
    private static let yearFirst = Patterns.make(#"(?<!\d)(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)"#)

    // Nov 3, 2026 / NOV 03 2026 / November 3rd, 2026
    private static let monthNameFirst = Patterns.make(
        #"\b("# + monthNames + #")\b\.?[\s-]+(\d{1,2})(?:st|nd|rd|th)?,?[\s-]+(\d{4}|\d{2})(?!\d)"#,
        caseInsensitive: true
    )

    // 3 Nov 2026 / 03-NOV-26
    private static let dayFirstMonthName = Patterns.make(
        #"(?<!\d)(\d{1,2})(?:st|nd|rd|th)?[\s-]+("# + monthNames + #")\b\.?,?[\s-]+(\d{4}|\d{2})(?!\d)"#,
        caseInsensitive: true
    )

    // 11/03/2026, 11-03-26 (month first, unless the first number can't be a month)
    private static let slashed = Patterns.make(#"(?<!\d)(\d{1,2})[/-](\d{1,2})[/-](\d{4}|\d{2})(?!\d)"#)

    // 03.11.2026 (day first, as in Europe, unless the second number can't be a month)
    private static let dotted = Patterns.make(#"(?<!\d)(\d{1,2})\.(\d{1,2})\.(\d{4}|\d{2})(?!\d)"#)

    /// The first valid date found, scanning the lines in order.
    static func firstDate(in lines: [String]) -> CalendarDate? {
        for line in lines {
            if let date = date(in: line) {
                return date
            }
        }
        return nil
    }

    /// The first valid date in a single line of text.
    static func date(in text: String) -> CalendarDate? {
        for match in yearFirst.allMatches(in: text) {
            if let date = makeDate(year: match.group(1, in: text),
                                   month: match.group(2, in: text),
                                   day: match.group(3, in: text)) {
                return date
            }
        }
        for match in monthNameFirst.allMatches(in: text) {
            let month = monthNumber(match.group(1, in: text))
            if let date = makeDate(year: match.group(3, in: text),
                                   month: month,
                                   day: match.group(2, in: text)) {
                return date
            }
        }
        for match in dayFirstMonthName.allMatches(in: text) {
            let month = monthNumber(match.group(2, in: text))
            if let date = makeDate(year: match.group(3, in: text),
                                   month: month,
                                   day: match.group(1, in: text)) {
                return date
            }
        }
        for match in slashed.allMatches(in: text) {
            let first = Int(match.group(1, in: text) ?? "") ?? 0
            let second = Int(match.group(2, in: text) ?? "") ?? 0
            let firstIsMonth = !(first > 12 && second <= 12)
            if let date = makeDate(year: match.group(3, in: text),
                                   month: String(firstIsMonth ? first : second),
                                   day: String(firstIsMonth ? second : first)) {
                return date
            }
        }
        for match in dotted.allMatches(in: text) {
            let first = Int(match.group(1, in: text) ?? "") ?? 0
            let second = Int(match.group(2, in: text) ?? "") ?? 0
            let firstIsDay = !(second > 12 && first <= 12)
            if let date = makeDate(year: match.group(3, in: text),
                                   month: String(firstIsDay ? second : first),
                                   day: String(firstIsDay ? first : second)) {
                return date
            }
        }
        return nil
    }

    private static func monthNumber(_ name: String?) -> String? {
        guard let name = name else {
            return nil
        }
        let prefix = String(name.lowercased().prefix(3))
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard let index = months.firstIndex(of: prefix) else {
            return nil
        }
        return String(index + 1)
    }

    /// Builds a date from text parts, rejecting impossible dates like 02/30.
    private static func makeDate(year: String?, month: String?, day: String?) -> CalendarDate? {
        guard let yearText = year, let monthText = month, let dayText = day,
              var yearValue = Int(yearText), let monthValue = Int(monthText), let dayValue = Int(dayText) else {
            return nil
        }
        if yearText.count == 2 {
            yearValue += 2000
        }
        guard yearValue >= 1990 && yearValue <= 2099 else {
            return nil
        }

        var components = DateComponents()
        components.year = yearValue
        components.month = monthValue
        components.day = dayValue
        guard components.isValidDate(in: Calendar(identifier: .gregorian)) else {
            return nil
        }
        return CalendarDate(year: yearValue, month: monthValue, day: dayValue)
    }
}
