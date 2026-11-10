import CoreGraphics
import Foundation
import UIKit
import Vision

/// Vision's document reader (iOS 26, roadmap tier 2), on the device like the text recognizer.
///
/// It reads a page as a document: lines of text, plus tables when the page has columns.
/// A receipt's items and prices often come back as a table, and each table row says which
/// name and price were printed side by side. Those rows go into `RecognizedTextBlock.row`,
/// so `LineGrouper` keeps a price with its name even on tilted or curled paper.
@available(iOS 26.0, *)
enum DocumentReader {

    /// The page's text lines, as blocks in Vision's coordinates (origin bottom-left, 0–1).
    static func read(_ image: UIImage, pageIndex: Int, options: RecognitionOptions) async throws -> [RecognizedTextBlock] {
        guard let cgImage = image.cgImage else {
            throw TextRecognizerError.unreadableImage(page: pageIndex)
        }
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = options.languageCorrection
        request.textRecognitionOptions.maximumCandidateCount = 3
        // Left to detect the language itself, the reader fills a faint letter in from any
        // alphabet ("13.00名", "$24.9îŚ"). Receipts are in the phone's languages, so it reads
        // only those (and English), like the text recognizer reads only English.
        let supported = request.supportedRecognitionLanguages.map { language in language.minimalIdentifier }
        let languages = ReaderLanguages.pick(preferred: Locale.preferredLanguages, supported: supported)
        request.textRecognitionOptions.automaticallyDetectLanguage = false
        request.textRecognitionOptions.recognitionLanguages = languages.map { identifier in
            Locale.Language(identifier: identifier)
        }
        if options.languageCorrection {
            request.textRecognitionOptions.customWords = TextRecognizer.receiptWords
        }
        let orientation = TextRecognizer.cgImageOrientation(for: image.imageOrientation)
        let observations = try await request.perform(on: cgImage, orientation: orientation)
        guard let document = observations.first?.document else {
            return []
        }

        // Each table row's cells, as rectangles, so lines can be matched to their row.
        var rows: [[CGRect]] = []
        for table in document.tables {
            for row in table.rows {
                var cells: [CGRect] = []
                for cell in row {
                    let box = cell.content.boundingRegion.normalizedPath.boundingBox
                    if !box.isNull && !box.isEmpty {
                        cells.append(box)
                    }
                }
                if !cells.isEmpty {
                    rows.append(cells)
                }
            }
        }

        var blocks: [RecognizedTextBlock] = []
        for line in document.text.lines {
            let candidates = line.topCandidates(3)
            let text = candidates.first?.string ?? line.transcript
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            var alternatives: [String] = []
            for candidate in candidates.dropFirst() {
                if candidate.string != text && !alternatives.contains(candidate.string) {
                    alternatives.append(candidate.string)
                }
            }
            let box = line.boundingBox.cgRect
            let confidence = candidates.first?.confidence ?? line.confidence
            blocks.append(RecognizedTextBlock(
                text: text,
                confidence: confidence,
                boundingBox: box,
                pageIndex: pageIndex,
                alternatives: alternatives,
                row: DocumentRows.row(for: box, in: rows)
            ))
        }
        return blocks
    }
}

/// Matching lines to the table rows the document reader found. Plain geometry, so tests cover it.
enum DocumentRows {

    /// The index of the row with a cell around the box's center, or nil. A box that sits in
    /// more than one row's cells (overlapping rows) gets the row whose cell center is closest.
    static func row(for box: CGRect, in rows: [[CGRect]]) -> Int? {
        let center = CGPoint(x: box.midX, y: box.midY)
        var best: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, cells) in rows.enumerated() {
            for cell in cells where cell.insetBy(dx: -0.002, dy: -0.002).contains(center) {
                let distance = abs(cell.midY - center.y)
                if distance < bestDistance {
                    bestDistance = distance
                    best = index
                }
            }
        }
        return best
    }
}

/// Which languages the document reader reads. Plain strings, so tests cover it.
enum ReaderLanguages {

    /// The phone's languages that the reader supports, in order, then English if it isn't
    /// among them. Matched by base language ("fr-CA" uses "fr"). Each is given as the
    /// supported identifier.
    static func pick(preferred: [String], supported: [String]) -> [String] {
        var picked: [String] = []
        for identifier in preferred + ["en-US"] {
            let base = baseLanguage(identifier)
            let exact = supported.first { language in normalized(language) == normalized(identifier) }
            let sameBase = supported.first { language in baseLanguage(language) == base }
            if let match = exact ?? sameBase, !picked.contains(match) {
                picked.append(match)
            }
        }
        if picked.isEmpty {
            picked = ["en-US"]
        }
        return picked
    }

    private static func normalized(_ identifier: String) -> String {
        return identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func baseLanguage(_ identifier: String) -> String {
        return normalized(identifier).components(separatedBy: "-").first ?? ""
    }
}
