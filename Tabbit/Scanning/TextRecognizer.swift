import Foundation
import ImageIO
import UIKit
import Vision

enum TextRecognizerError: LocalizedError {
    case unreadableImage(page: Int)

    var errorDescription: String? {
        switch self {
        case .unreadableImage(let page):
            return "Page \(page + 1) of the scan could not be read."
        }
    }
}

/// Settings for one text-recognition run.
struct RecognitionOptions: Equatable {
    /// Vision's language correction. When on, Vision replaces letters it isn't
    /// sure about with dictionary words, which can turn receipt abbreviations
    /// into different words. Off by default; see OCRSettings.
    var languageCorrection: Bool = false
}

/// The user's text-recognition settings, stored in UserDefaults.
enum OCRSettings {
    static let languageCorrectionKey = "ocr.languageCorrection"

    /// Read when a scan starts. Defaults to off.
    static var current: RecognitionOptions {
        let stored = UserDefaults.standard.object(forKey: languageCorrectionKey) as? Bool
        return RecognitionOptions(languageCorrection: stored ?? false)
    }
}

/// Runs Vision text recognition on scanned page images.
///
/// Vision's text recognition always runs on the device; nothing is sent
/// over the network.
///
/// These functions are synchronous and can take a moment per page,
/// so call them off the main thread.
enum TextRecognizer {

    /// Words that appear on most receipts. Vision only uses these hints
    /// when language correction is on.
    private static let receiptWords = [
        "SUBTOTAL", "TOTAL", "TAX", "BALANCE", "DUE", "CHANGE", "CASH",
        "VISA", "MASTERCARD", "DEBIT", "CREDIT", "SAVINGS", "COUPON", "QTY",
    ]

    /// Recognizes the text on every page, in page order.
    static func recognizeText(in images: [UIImage], options: RecognitionOptions) throws -> ScanResult {
        var allBlocks: [RecognizedTextBlock] = []
        for (pageIndex, image) in images.enumerated() {
            let pageBlocks = try recognizeText(in: image, pageIndex: pageIndex, options: options)
            allBlocks.append(contentsOf: pageBlocks)
        }
        return ScanResult(pageCount: images.count, blocks: allBlocks)
    }

    /// Recognizes the text on a single page.
    static func recognizeText(in image: UIImage, pageIndex: Int, options: RecognitionOptions) throws -> [RecognizedTextBlock] {
        guard let cgImage = image.cgImage else {
            throw TextRecognizerError.unreadableImage(page: pageIndex)
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = options.languageCorrection
        if options.languageCorrection {
            request.customWords = receiptWords
        }

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: cgImageOrientation(for: image.imageOrientation),
            options: [:]
        )
        try handler.perform([request])

        var blocks: [RecognizedTextBlock] = []
        let observations: [VNRecognizedTextObservation] = request.results ?? []
        for observation in observations {
            let candidates = observation.topCandidates(3)
            guard let best = candidates.first else {
                continue
            }
            var alternatives: [String] = []
            for candidate in candidates.dropFirst() {
                if candidate.string != best.string && !alternatives.contains(candidate.string) {
                    alternatives.append(candidate.string)
                }
            }
            let block = RecognizedTextBlock(
                text: best.string,
                confidence: best.confidence,
                boundingBox: observation.boundingBox,
                pageIndex: pageIndex,
                alternatives: alternatives
            )
            blocks.append(block)
        }
        return blocks
    }

    /// Vision needs the image orientation as a CGImagePropertyOrientation.
    private static func cgImageOrientation(for orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up:
            return .up
        case .upMirrored:
            return .upMirrored
        case .down:
            return .down
        case .downMirrored:
            return .downMirrored
        case .left:
            return .left
        case .leftMirrored:
            return .leftMirrored
        case .right:
            return .right
        case .rightMirrored:
            return .rightMirrored
        @unknown default:
            return .up
        }
    }
}
