import CoreGraphics
import Foundation
import UIKit

/// The receipt photo Apple Intelligence sees next to the OCR text (iOS 27).
///
/// The on-device model shrinks every image to under about 900 pixels on its long side.
/// A whole receipt is long and thin, so shrunk as it is, its text would be a few pixels
/// tall. Instead Tabbit:
/// 1. crops each page to the text the scan found (no table or background),
/// 2. stacks the pages, then cuts the strip into 1 to 4 sections with a small overlap,
/// 3. lays the sections side by side, so the picture is about square,
/// 4. and renders it at `longSide` pixels, the size the model would shrink it to anyway.
/// That keeps the print about twice as large as a straight downscale, and a small image
/// is quick to send to the model.
enum ReceiptPhoto {

    /// The picture's long side in pixels.
    static let longSide: CGFloat = 896
    /// At most this many sections side by side.
    static let maxColumns = 4
    /// Each section repeats this share of the strip's height from the one before, so a line
    /// cut at a section edge is whole in one of them.
    static let overlap: CGFloat = 0.03
    /// The gap between sections, as a share of a section's width.
    static let gap: CGFloat = 0.04
    /// Room kept around the text when cropping, as a share of the page.
    static let margin: CGFloat = 0.02

    /// How many sections make the picture closest to square: the strip's height divided by
    /// its width, square-rooted (a strip 4 times taller than wide becomes 2 sections).
    static func columnCount(heightOverWidth ratio: CGFloat) -> Int {
        guard ratio.isFinite, ratio > 0 else {
            return 1
        }
        let columns = Int(ratio.squareRoot().rounded())
        return min(max(columns, 1), maxColumns)
    }

    /// The part of a page with text on it, in UIKit's normalized coordinates (origin top-left,
    /// 0–1), with a margin. Nil when the page has no text.
    static func textArea(of blocks: [RecognizedTextBlock]) -> CGRect? {
        var box = CGRect.null
        for block in blocks {
            box = box.union(block.boundingBox)
        }
        guard !box.isNull, box.width > 0, box.height > 0 else {
            return nil
        }
        // Vision's origin is at the bottom-left; UIKit's at the top-left.
        let flipped = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        let padded = flipped.insetBy(dx: -margin, dy: -margin)
        return padded.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Where each section starts in the strip, as a share of its height, and how tall each is.
    static func sections(columns: Int) -> (starts: [CGFloat], height: CGFloat) {
        guard columns > 1 else {
            return (starts: [0], height: 1)
        }
        let height = min(1 / CGFloat(columns) + overlap, 1)
        let step = (1 - height) / CGFloat(columns - 1)
        let starts = (0..<columns).map { index in CGFloat(index) * step }
        return (starts: starts, height: height)
    }

    /// The picture for the model, and how many sections it has. Nil if no page has text.
    static func make(images: [UIImage], scan: ScanResult) -> (image: UIImage, columns: Int)? {
        // Each page's text area, in the page's points.
        var pieces: [(image: UIImage, crop: CGRect)] = []
        for (pageIndex, image) in images.enumerated() {
            let size = image.size
            guard size.width > 0, size.height > 0, let area = textArea(of: scan.blocks(onPage: pageIndex)) else {
                continue
            }
            let crop = CGRect(x: area.minX * size.width, y: area.minY * size.height,
                              width: area.width * size.width, height: area.height * size.height)
            if crop.width > 1 && crop.height > 1 {
                pieces.append((image: image, crop: crop))
            }
        }
        guard !pieces.isEmpty else {
            return nil
        }

        // The strip: every piece scaled to one width (1 unit), stacked.
        let stripHeight = pieces.reduce(CGFloat(0)) { sum, piece in sum + piece.crop.height / piece.crop.width }
        let columns = columnCount(heightOverWidth: stripHeight)
        let layout = sections(columns: columns)
        let sectionHeight = layout.height * stripHeight
        let width = CGFloat(columns) + CGFloat(columns - 1) * gap
        // Pixels per unit, so the long side is `longSide`, never enlarging the photo.
        let widest = pieces.map { piece in piece.crop.width * piece.image.scale }.max() ?? longSide
        let unit = min(longSide / max(width, sectionHeight), widest)
        let size = CGSize(width: (width * unit).rounded(), height: (sectionHeight * unit).rounded())
        guard size.width >= 1, size.height >= 1 else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let picture = renderer.image { context in
            let cg = context.cgContext
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for column in 0..<columns {
                let left = CGFloat(column) * (1 + gap) * unit
                cg.saveGState()
                cg.clip(to: CGRect(x: left, y: 0, width: unit, height: size.height))
                // Where this section's top is in the strip, in pixels.
                var top = -layout.starts[column] * stripHeight * unit
                for piece in pieces {
                    let scale = unit / piece.crop.width
                    let height = piece.crop.height * scale
                    if top + height > 0 && top < size.height {
                        cg.saveGState()
                        cg.clip(to: CGRect(x: left, y: top, width: unit, height: height))
                        let drawn = CGRect(x: left - piece.crop.minX * scale,
                                           y: top - piece.crop.minY * scale,
                                           width: piece.image.size.width * scale,
                                           height: piece.image.size.height * scale)
                        piece.image.draw(in: drawn)
                        cg.restoreGState()
                    }
                    top += height
                }
                cg.restoreGState()
            }
        }
        return (image: picture, columns: columns)
    }
}
