import Foundation

/// Blanks out personal numbers before a scan is exported: card and account
/// numbers, auth codes, phone numbers and long digit runs. Digits become "#".
///
/// Prices, dates and times are kept so the export still works as a test fixture.
/// Store names and addresses are kept; they're printed on every receipt from that store.
enum ExportRedactor {

    // Lines that usually carry card, account or transaction numbers.
    private static let sensitiveLinePattern = Patterns.make(
        #"\b(VISA|MASTERCARD|MASTER\s*CARD|AMEX|AMERICAN\s+EXPRESS|DISCOVER|DEBIT|CREDIT|CARD|ACCT|ACCOUNT|AUTH|APPROVAL|APPR|REF|TRAN|TRANS|TRANSACTION|TERMINAL|TERM|MEMBER|LOYALTY|REWARDS?|AID|MID|TID|SEQ|INVOICE|ORDER)\b|\*{3,}|X{4,}"#,
        caseInsensitive: true
    )

    // 555-123-4567, (555) 123-4567, 555.123.4567, +1 555 123 4567
    private static let phonePattern = Patterns.make(
        #"(?<!\d)(?:\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]\d{4}(?!\d)"#
    )

    private static let longDigitRunPattern = Patterns.make(#"\d{8,}"#)

    // Parts of a sensitive line to keep: prices, dates, times.
    private static let keepPattern = Patterns.make(
        #"(?<!\d)-?[$€£]?\d{1,3}(?:[.,]\d{3})*[.,]\d{2}(?![\d%])|\d{1,4}[/.-]\d{1,2}[/.-]\d{2,4}|\d{1,2}:\d{2}(?::\d{2})?"#
    )

    static func redact(_ scan: ScanResult) -> ScanResult {
        let blocks = scan.blocks.map { block in
            RecognizedTextBlock(
                text: redact(block.text),
                confidence: block.confidence,
                boundingBox: block.boundingBox,
                pageIndex: block.pageIndex,
                alternatives: block.alternatives.map { alternative in redact(alternative) },
                row: block.row
            )
        }
        return ScanResult(pageCount: scan.pageCount, blocks: blocks, reader: scan.reader, seconds: scan.seconds)
    }

    static func redact(_ text: String) -> String {
        var characters = Array(text.utf16)
        var masked = [Bool](repeating: false, count: characters.count)

        func mask(_ range: NSRange) {
            let end = min(range.location + range.length, characters.count)
            if range.location < end {
                for index in range.location..<end {
                    masked[index] = true
                }
            }
        }

        for match in phonePattern.allMatches(in: text) {
            mask(match.range)
        }
        for match in longDigitRunPattern.allMatches(in: text) {
            mask(match.range)
        }
        if sensitiveLinePattern.hasMatch(in: text) {
            var keep = [Bool](repeating: false, count: characters.count)
            for match in keepPattern.allMatches(in: text) {
                let end = min(match.range.location + match.range.length, characters.count)
                if match.range.location < end {
                    for index in match.range.location..<end {
                        keep[index] = true
                    }
                }
            }
            for index in 0..<characters.count where !keep[index] {
                masked[index] = true
            }
        }

        // Replace masked ASCII digits with "#".
        let zero = UInt16(UInt8(ascii: "0"))
        let nine = UInt16(UInt8(ascii: "9"))
        let hash = UInt16(UInt8(ascii: "#"))
        for index in 0..<characters.count where masked[index] {
            if characters[index] >= zero && characters[index] <= nine {
                characters[index] = hash
            }
        }
        return String(decoding: characters, as: UTF16.self)
    }
}
