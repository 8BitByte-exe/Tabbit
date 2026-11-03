import Foundation
import UIKit

/// Everything the app produced from one scan.
struct ProcessedScan {
    /// The raw OCR result.
    let scan: ScanResult
    /// What the parser made of it.
    let receipt: Receipt
    /// A JSON export of this scan in the temporary folder, ready to share.
    /// Nil if writing the file failed (the rest of the app still works).
    let exportURL: URL?
}

/// Runs OCR, parsing and export for one scan. Everything happens on the device.
///
/// Synchronous and can take a moment per page, so call it off the main thread.
enum ScanProcessor {

    static func process(images: [UIImage], options: RecognitionOptions) throws -> ProcessedScan {
        let scan = try TextRecognizer.recognizeText(in: images, options: options)
        let receipt = RulesReceiptParser().parse(scan)
        let exportURL = writeExport(scan: scan, receipt: receipt, options: options)
        return ProcessedScan(scan: scan, receipt: receipt, exportURL: exportURL)
    }

    private static let exportFilePrefix = "Tabbit-scan-"

    /// Writes the scan as JSON to the temporary folder and returns its URL.
    /// Personal numbers are blanked out first (ExportRedactor), and earlier
    /// exports are deleted so receipts don't pile up on the device.
    static func writeExport(scan: ScanResult, receipt: Receipt, options: RecognitionOptions) -> URL? {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory
        removeOldExports(in: folder)

        let now = Date()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let export = ScanExport(
            scan: ExportRedactor.redact(scan),
            parsed: receipt,
            exportedAt: now,
            appVersion: appVersion,
            languageCorrection: options.languageCorrection,
            redacted: true
        )
        let url = folder.appendingPathComponent(exportFilePrefix + timestamp(for: now) + ".json")
        do {
            let data = try ScanExport.makeEncoder().encode(export)
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    private static func removeOldExports(in folder: URL) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else {
            return
        }
        for name in names where name.hasPrefix(exportFilePrefix) {
            _ = try? fileManager.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private static func timestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }
}
