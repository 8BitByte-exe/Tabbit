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

/// Runs Vision text recognition on scanned page images.
///
/// Vision's text recognition always runs on the device; nothing is sent
/// over the network.
///
/// These functions are synchronous and can take a moment per page,
/// so call them off the main thread.
enum TextRecognizer {

    /// Recognizes the text on every page, in page order.
    static func recognizeText(in images: [UIImage]) throws -> ScanResult {
        var allBlocks: [RecognizedTextBlock] = []
        for (pageIndex, image) in images.enumerated() {
            let pageBlocks = try recognizeText(in: image, pageIndex: pageIndex)
            allBlocks.append(contentsOf: pageBlocks)
        }
        return ScanResult(pageCount: images.count, blocks: allBlocks)
    }

    /// Recognizes the text on a single page.
    static func recognizeText(in image: UIImage, pageIndex: Int) throws -> [RecognizedTextBlock] {
        guard let cgImage = image.cgImage else {
            throw TextRecognizerError.unreadableImage(page: pageIndex)
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: cgImageOrientation(for: image.imageOrientation),
            options: [:]
        )
        try handler.perform([request])

        var blocks: [RecognizedTextBlock] = []
        let observations: [VNRecognizedTextObservation] = request.results ?? []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else {
                continue
            }
            let block = RecognizedTextBlock(
                text: candidate.string,
                confidence: candidate.confidence,
                boundingBox: observation.boundingBox,
                pageIndex: pageIndex
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
