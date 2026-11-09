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
    /// Read with Vision's document reader on iOS 26 and later (roadmap tier 2). It finds
    /// the receipt's rows, which keeps prices with their names on tilted paper. On by default.
    var documentReader: Bool = true
}

/// The user's text-recognition settings, stored in UserDefaults.
enum OCRSettings {
    static let languageCorrectionKey = "ocr.languageCorrection"
    static let documentReaderKey = "ocr.documentReader"

    /// Read when a scan starts. Language correction defaults to off, the document reader to on.
    static var current: RecognitionOptions {
        let defaults = UserDefaults.standard
        let correction = defaults.object(forKey: languageCorrectionKey) as? Bool
        let documents = defaults.object(forKey: documentReaderKey) as? Bool
        return RecognitionOptions(languageCorrection: correction ?? false, documentReader: documents ?? true)
    }

    /// True if this iPhone has Vision's document reader (iOS 26 and later).
    static var hasDocumentReader: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }
}

/// Runs Vision text recognition on scanned page images.
///
/// Vision's text recognition always runs on the device; nothing is sent
/// over the network.
///
/// `read` is async and reads the pages in parallel; the other functions are synchronous
/// and can take a moment per page, so call them off the main thread.
enum TextRecognizer {

    /// Words that appear on most receipts. Vision only uses these hints
    /// when language correction is on.
    static let receiptWords = [
        "SUBTOTAL", "TOTAL", "TAX", "BALANCE", "DUE", "CHANGE", "CASH",
        "VISA", "MASTERCARD", "DEBIT", "CREDIT", "SAVINGS", "COUPON", "QTY",
    ]

    /// Reads every page at the same time, with the best reader this iPhone has: Vision's
    /// document reader on iOS 26 and later (unless it's switched off), otherwise the text
    /// recognizer. A page the document reader can't read is read again with the text recognizer.
    static func read(_ images: [UIImage], options: RecognitionOptions) async throws -> ScanResult {
        let started = Date()
        var tryDocuments = false
        if #available(iOS 26.0, *) {
            tryDocuments = options.documentReader
        }
        let useDocuments = tryDocuments
        let pages: [PageReading] = try await withThrowingTaskGroup(of: PageReading.self) { group in
            for (pageIndex, image) in images.enumerated() {
                group.addTask {
                    if useDocuments {
                        if #available(iOS 26.0, *) {
                            let blocks = try? await DocumentReader.read(image, pageIndex: pageIndex, options: options)
                            if let blocks = blocks, !blocks.isEmpty {
                                return PageReading(pageIndex: pageIndex, blocks: blocks, fromDocuments: true)
                            }
                        }
                    }
                    let blocks = try recognizeText(in: image, pageIndex: pageIndex, options: options)
                    return PageReading(pageIndex: pageIndex, blocks: blocks, fromDocuments: false)
                }
            }
            var results: [PageReading] = []
            for try await page in group {
                results.append(page)
            }
            return results.sorted { first, second in first.pageIndex < second.pageIndex }
        }
        let allDocuments = !pages.isEmpty && pages.allSatisfy { page in page.fromDocuments }
        return ScanResult(
            pageCount: images.count,
            blocks: pages.flatMap { page in page.blocks },
            reader: allDocuments ? "documents" : "text",
            seconds: Date().timeIntervalSince(started)
        )
    }

    private struct PageReading: Sendable {
        let pageIndex: Int
        let blocks: [RecognizedTextBlock]
        let fromDocuments: Bool
    }

    /// Recognizes the text on every page, in page order, with the text recognizer.
    static func recognizeText(in images: [UIImage], options: RecognitionOptions) throws -> ScanResult {
        var allBlocks: [RecognizedTextBlock] = []
        for (pageIndex, image) in images.enumerated() {
            let pageBlocks = try recognizeText(in: image, pageIndex: pageIndex, options: options)
            allBlocks.append(contentsOf: pageBlocks)
        }
        return ScanResult(pageCount: images.count, blocks: allBlocks, reader: "text")
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
    static func cgImageOrientation(for orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
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
