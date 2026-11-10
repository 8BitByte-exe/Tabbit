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

    /// A date found on a receipt, and the other dates the same digits could mean.
    struct Reading: Equatable {
        let date: CalendarDate
        /// Other valid readings of the same printed date ("26-11-08" is also 2008-11-26).
        let alternatives: [CalendarDate]
        /// The date as printed.
        let printed: String
    }

    /// How far back a receipt is normally scanned. A reading inside this window beats one
    /// outside it: "26-11-08" scanned in November 2026 is 2026-11-08, not 2008-11-26.
    static let recentDays = 365

    /// The first valid date found, scanning the lines in order.
    static func firstDate(in lines: [String], reference: Date = Date()) -> CalendarDate? {
        return firstReading(in: lines, reference: reference)?.date
    }

    /// The first date found, with the other ways its digits could be read.
    static func firstReading(in lines: [String], reference: Date = Date()) -> Reading? {
        for line in lines {
            if let reading = reading(in: line, reference: reference) {
                return reading
            }
        }
        return nil
    }

    /// The first valid date in a single line of text.
    static func date(in text: String, reference: Date = Date()) -> CalendarDate? {
        return reading(in: text, reference: reference)?.date
    }

    /// The first valid date in a line. Dates with a month name or a four-digit year first are
    /// clear. All-number dates ("11/03/26", "26-11-08", "03.11.2026") can be read several ways:
    /// month first for slashes, day first for dots, and year first when the year has two digits.
    /// The usual reading wins unless it's in the future or long ago and another reading is recent.
    static func reading(in text: String, reference: Date = Date()) -> Reading? {
        for match in yearFirst.allMatches(in: text) {
            if let date = makeDate(year: match.group(1, in: text),
                                   month: match.group(2, in: text),
                                   day: match.group(3, in: text)) {
                return Reading(date: date, alternatives: [], printed: match.group(0, in: text) ?? "")
            }
        }
        for match in monthNameFirst.allMatches(in: text) {
            let month = monthNumber(match.group(1, in: text))
            if let date = makeDate(year: match.group(3, in: text),
                                   month: month,
                                   day: match.group(2, in: text)) {
                return Reading(date: date, alternatives: [], printed: match.group(0, in: text) ?? "")
            }
        }
        for match in dayFirstMonthName.allMatches(in: text) {
            let month = monthNumber(match.group(2, in: text))
            if let date = makeDate(year: match.group(3, in: text),
                                   month: month,
                                   day: match.group(1, in: text)) {
                return Reading(date: date, alternatives: [], printed: match.group(0, in: text) ?? "")
            }
        }
        for match in slashed.allMatches(in: text) {
            let first = Int(match.group(1, in: text) ?? "") ?? 0
            let second = Int(match.group(2, in: text) ?? "") ?? 0
            let firstIsMonth = !(first > 12 && second <= 12)
            if let reading = choose(numbers: match, in: text, dayFirst: !firstIsMonth, reference: reference) {
                return reading
            }
        }
        for match in dotted.allMatches(in: text) {
            let first = Int(match.group(1, in: text) ?? "") ?? 0
            let second = Int(match.group(2, in: text) ?? "") ?? 0
            let firstIsDay = !(second > 12 && first <= 12)
            if let reading = choose(numbers: match, in: text, dayFirst: firstIsDay, reference: reference) {
                return reading
            }
        }
        return nil
    }

    /// Every valid reading of "a/b/c", the usual one first, and the one to use.
    private static func choose(numbers match: NSTextCheckingResult, in text: String, dayFirst: Bool,
                               reference: Date) -> Reading? {
        let a = match.group(1, in: text)
        let b = match.group(2, in: text)
        let c = match.group(3, in: text)
        var candidates: [CalendarDate?] = dayFirst
            ? [makeDate(year: c, month: b, day: a), makeDate(year: c, month: a, day: b)]
            : [makeDate(year: c, month: a, day: b), makeDate(year: c, month: b, day: a)]
        // "26-11-08": a two-digit year can also come first.
        if (c ?? "").count == 2 {
            candidates.append(makeDate(year: a, month: b, day: c))
        }
        var valid: [CalendarDate] = []
        for candidate in candidates {
            if let date = candidate, !valid.contains(date) {
                valid.append(date)
            }
        }
        guard var chosen = valid.first else {
            return nil
        }
        if !isRecent(chosen, reference: reference) {
            if let recent = valid.first(where: { date in isRecent(date, reference: reference) }) {
                chosen = recent
            }
        }
        return Reading(date: chosen, alternatives: valid.filter { date in date != chosen },
                       printed: match.group(0, in: text) ?? "")
    }

    /// Not in the future (a day or two of slack) and within `recentDays` before the reference.
    static func isRecent(_ date: CalendarDate, reference: Date) -> Bool {
        guard let days = daysBefore(reference, date) else {
            return false
        }
        return days >= -2 && days <= recentDays
    }

    /// How many days the date is before the reference (negative for later dates).
    static func daysBefore(_ reference: Date, _ date: CalendarDate) -> Int? {
        guard let value = date.dateValue else {
            return nil
        }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: value),
                                       to: calendar.startOfDay(for: reference)).day
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
