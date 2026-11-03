#if DEBUG
import SwiftUI
import UIKit

/// Screenshot mode for CI (Debug builds only; the Release IPA doesn't contain it).
///
/// Launch arguments: `-TabbitDemo -TabbitScreen <home|detail|edit|empty|settings|processing>`.
/// Sample receipts go into a throwaway folder, never the real store.
enum DemoMode {

    static var isEnabled: Bool {
        return ProcessInfo.processInfo.arguments.contains("-TabbitDemo")
    }

    static var screen: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard isEnabled, let index = arguments.firstIndex(of: "-TabbitScreen"), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    static func freshFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TabbitDemo", isDirectory: true)
        _ = try? FileManager.default.removeItem(at: folder)
        return folder
    }

    @MainActor
    static func populate(_ store: ReceiptStore) {
        guard screen != "empty" else {
            return
        }
        let now = Date()
        // Oldest first, so the newest ends up at the top of the list.
        for (offset, sample) in samples.enumerated().reversed() {
            let date = now.addingTimeInterval(-Double(offset) * 86_400)
            guard let saved = try? store.add(processedScan(for: sample), now: date) else {
                continue
            }
            if let correctedMerchant = sample.correctedMerchant {
                var edited = saved
                edited.receipt.merchant = correctedMerchant
                _ = try? store.update(edited)
            }
        }
    }

    @MainActor
    static func prepare(_ scanner: ScanViewModel, store: ReceiptStore) {
        switch screen {
        case "detail", "edit":
            if let first = store.receipts.first {
                scanner.path = [first.id]
            }
        case "processing":
            scanner.showProcessingForScreenshots()
        default:
            break
        }
    }

    // MARK: - Samples

    private struct Sample {
        let merchant: String
        let date: CalendarDate
        let items: [(String, String, Float)]
        let subtotal: String
        let tax: String
        let total: String
        var correctedMerchant: String?
    }

    private static let samples: [Sample] = [
        Sample(
            merchant: "Fresh Mart",
            date: CalendarDate(year: 2026, month: 11, day: 2),
            items: [
                ("Organic Bananas", "1.29", 1),
                ("Whole Milk", "4.99", 1),
                ("Sourdough Loaf", "5.49", 1),
                ("BNLS CHKN THGH", "8.47", 0.4),
                ("Avocados", "1.98", 1),
                ("Club Card Savings", "-1.00", 1),
            ],
            subtotal: "21.22", tax: "1.06", total: "22.28"
        ),
        Sample(
            merchant: "The Daily Grind",
            date: CalendarDate(year: 2026, month: 11, day: 1),
            items: [("Oat Latte", "5.25", 1), ("Almond Croissant", "4.50", 1)],
            subtotal: "9.75", tax: "0.87", total: "10.62"
        ),
        Sample(
            merchant: "Hardware Plus",
            date: CalendarDate(year: 2026, month: 10, day: 30),
            items: [("Extension Cord 25 ft", "12.99", 1), ("Wood Screws", "6.49", 1)],
            subtotal: "19.48", tax: "1.56", total: "21.40"
        ),
        Sample(
            merchant: "CITY DEL1",
            date: CalendarDate(year: 2026, month: 10, day: 28),
            items: [("Turkey Club", "11.50", 1)],
            subtotal: "11.50", tax: "0.92", total: "12.42",
            correctedMerchant: "City Deli"
        ),
    ]

    private static func amount(_ text: String) -> Decimal {
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    private static func processedScan(for sample: Sample) -> ProcessedScan {
        var lines: [String] = [sample.merchant.uppercased(), sample.date.isoString, ""]
        for (name, price, _) in sample.items {
            lines.append(name.uppercased().padding(toLength: 24, withPad: " ", startingAt: 0) + price)
        }
        lines.append("")
        lines.append("SUBTOTAL".padding(toLength: 24, withPad: " ", startingAt: 0) + sample.subtotal)
        lines.append("TAX".padding(toLength: 24, withPad: " ", startingAt: 0) + sample.tax)
        lines.append("TOTAL".padding(toLength: 24, withPad: " ", startingAt: 0) + sample.total)

        let receipt = Receipt(
            merchant: sample.merchant,
            date: sample.date,
            lineItems: sample.items.map { item in
                ReceiptLineItem(name: item.0, amount: amount(item.1), confidence: item.2)
            },
            subtotal: amount(sample.subtotal),
            tax: amount(sample.tax),
            total: amount(sample.total),
            parser: .rules,
            notes: []
        )
        let image = receiptImage(lines: lines)
        return ProcessedScan(
            scan: scan(lines: lines),
            receipt: receipt,
            pageJPEGs: [ScanProcessor.jpegData(for: image, maxDimension: 2000, quality: 0.8)].compactMap { data in data },
            thumbnailJPEG: ScanProcessor.jpegData(for: image, maxDimension: 320, quality: 0.8),
            languageCorrection: false
        )
    }

    private static func scan(lines: [String]) -> ScanResult {
        var blocks: [RecognizedTextBlock] = []
        for (index, line) in lines.enumerated() where !line.isEmpty {
            let y = 0.92 - Double(index) * 0.05
            blocks.append(RecognizedTextBlock(
                text: line, confidence: 1,
                boundingBox: CGRect(x: 0.06, y: y, width: 0.88, height: 0.03),
                pageIndex: 0
            ))
        }
        return ScanResult(pageCount: 1, blocks: blocks)
    }

    /// A plain "paper receipt" picture for the photo and thumbnail.
    private static func receiptImage(lines: [String]) -> UIImage {
        let lineHeight: CGFloat = 34
        let size = CGSize(width: 600, height: CGFloat(lines.count) * lineHeight + 140)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor(white: 0.98, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 22, weight: .regular),
                .foregroundColor: UIColor(white: 0.18, alpha: 1),
            ]
            for (index, line) in lines.enumerated() {
                let point = CGPoint(x: 44, y: 70 + CGFloat(index) * lineHeight)
                (line as NSString).draw(at: point, withAttributes: attributes)
            }
        }
    }
}
#endif
