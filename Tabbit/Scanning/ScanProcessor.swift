import Foundation
import UIKit

/// Everything the app produced from one scan, ready to be saved.
struct ProcessedScan {
    /// The raw OCR result.
    let scan: ScanResult
    /// What the parser made of it (the rules, or Apple Intelligence once it's checked).
    var receipt: Receipt
    /// One JPEG per page (long side at most 2000 px).
    let pageJPEGs: [Data]
    /// A small JPEG of the first page for the home screen.
    let thumbnailJPEG: Data?
    let languageCorrection: Bool
    /// Apple Intelligence's guess at the category, if it read the receipt.
    var suggestedCategory: SpendCategory? = nil
    /// The receipt cut into sections side by side for Apple Intelligence (iOS 27), when it
    /// will look at the photo. Never saved.
    var modelPhoto: UIImage? = nil
    /// How many sections `modelPhoto` has.
    var modelPhotoColumns: Int = 0
}

/// Runs OCR, parsing and photo compression for one scan. Everything happens on the device.
///
/// Synchronous and can take a moment per page, so call it off the main thread.
enum ScanProcessor {

    /// Reads the text of every page while the photos are compressed, then parses it.
    /// `modelPhoto` also prepares the picture Apple Intelligence will look at.
    static func process(images: [UIImage], options: RecognitionOptions, modelPhoto: Bool = false) async throws -> ProcessedScan {
        // Compressing the photos doesn't need the text, so it runs alongside the reading.
        async let pages = compressPages(images)
        async let thumbnail = compressThumbnail(images)
        let scan = try await TextRecognizer.read(images, options: options)
        let receipt = RulesReceiptParser().parse(scan)
        var photo: (image: UIImage, columns: Int)?
        if modelPhoto {
            photo = ReceiptPhoto.make(images: images, scan: scan)
        }
        return ProcessedScan(
            scan: scan,
            receipt: receipt,
            pageJPEGs: await pages,
            thumbnailJPEG: await thumbnail,
            languageCorrection: options.languageCorrection,
            modelPhoto: photo?.image,
            modelPhotoColumns: photo?.columns ?? 0
        )
    }

    private static func compressPages(_ images: [UIImage]) -> [Data] {
        return images.compactMap { image in jpegData(for: image, maxDimension: 2000, quality: 0.7) }
    }

    private static func compressThumbnail(_ images: [UIImage]) -> Data? {
        return images.first.flatMap { image in jpegData(for: image, maxDimension: 320, quality: 0.75) }
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
