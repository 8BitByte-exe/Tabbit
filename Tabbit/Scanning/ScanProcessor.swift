import Foundation
import UIKit

/// Everything the app produced from one scan, ready to be saved.
struct ProcessedScan {
    /// The raw OCR result.
    let scan: ScanResult
    /// What the parser made of it.
    let receipt: Receipt
    /// One JPEG per page (long side at most 2000 px).
    let pageJPEGs: [Data]
    /// A small JPEG of the first page for the home screen.
    let thumbnailJPEG: Data?
    let languageCorrection: Bool
}

/// Runs OCR, parsing and photo compression for one scan. Everything happens on the device.
///
/// Synchronous and can take a moment per page, so call it off the main thread.
enum ScanProcessor {

    static func process(images: [UIImage], options: RecognitionOptions) throws -> ProcessedScan {
        let scan = try TextRecognizer.recognizeText(in: images, options: options)
        let receipt = RulesReceiptParser().parse(scan)
        let pages = images.compactMap { image in jpegData(for: image, maxDimension: 2000, quality: 0.7) }
        let thumbnail = images.first.flatMap { image in jpegData(for: image, maxDimension: 320, quality: 0.75) }
        return ProcessedScan(
            scan: scan,
            receipt: receipt,
            pageJPEGs: pages,
            thumbnailJPEG: thumbnail,
            languageCorrection: options.languageCorrection
        )
    }

    /// The image scaled down to `maxDimension` on its long side, as JPEG.
    static func jpegData(for image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    // MARK: - Export

    private static let exportFilePrefix = "Tabbit-scan-"

    /// Writes a receipt as a JSON export to the temporary folder and returns its URL.
    /// Personal numbers are blanked out first (ExportRedactor), and earlier
    /// exports are deleted so receipt data doesn't pile up on the device.
    /// The receipt as it stands now is included as `corrected` (the right answer
    /// when the export becomes a test fixture). Nil for receipts without a scan.
    static func writeExport(for record: ReceiptRecord) -> URL? {
        guard let scan = record.scan else {
            return nil
        }
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory
        removeOldExports(in: folder)

        let now = Date()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let export = ScanExport(
            scan: ExportRedactor.redact(scan),
            parsed: record.parsed,
            exportedAt: now,
            appVersion: appVersion,
            languageCorrection: record.languageCorrection,
            redacted: true,
            corrected: record.asReceipt()
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
