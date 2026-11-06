import Foundation

/// What Tabbit tells Apple Intelligence about a receipt.
enum ReceiptPrompt {

    /// The on-device model has a small context window (about 4,000 tokens for
    /// instructions, receipt and answer), so very long receipts are cut short.
    static let maxCharacters = 3_000

    static let categories = SpendCategory.allCases.map { category in category.rawValue }.joined(separator: ", ")

    static let instructions = """
    You read shopping and restaurant receipts that were scanned with a phone camera. \
    The text comes from OCR, so words can be misspelled and a line's price can end up on the next line.

    Rules:
    - Only use what is printed on the receipt. Never invent items, amounts or names.
    - Copy every amount exactly as printed, with its decimals, for example 4.99 or 12,50.
    - Items are the things bought, in the order printed. A discount or coupon is its own item with a negative price.
    - These are not items: subtotal, tax, VAT, tip, total, balance, payment, card, cash, change, \
    "you saved", regular price, points, and tip suggestions such as "18% = 7.20".
    - For an item with a quantity, use the line's total price, not the unit price.
    - Leave subtotal, tax, tip and total empty when they aren't printed.
    - The tip is only a tip or gratuity that was actually charged.
    - Write each item's name the way a person would say it: expand abbreviations, \
    use normal capitalization, and drop codes and tax letters. Keep it short.
    - The category is one of: \(categories).
    """

    /// The receipt's lines, top to bottom, as the prompt.
    static func make(for scan: ScanResult) -> String {
        let lines = LineGrouper.lines(from: scan)
        var body = ""
        var lastPage = 0
        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }
            if line.pageIndex != lastPage {
                body += "--- next page ---\n"
                lastPage = line.pageIndex
            }
            if body.count + text.count + 1 > maxCharacters {
                break
            }
            body += text + "\n"
        }
        guard !body.isEmpty else {
            return ""
        }
        return "Read this receipt. Its lines, top to bottom:\n\n" + body
    }
}
