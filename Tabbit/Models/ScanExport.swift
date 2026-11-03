import Foundation

/// The JSON file produced by the Export button.
///
/// It holds the raw OCR result (text plus positions, no images) and what
/// the parser made of it. Exports double as unit-test fixtures: drop one
/// into `TabbitTests/Fixtures/` and load it with `Fixtures.scan(named:)`.
struct ScanExport: Codable {
    static let formatName = "tabbit-scan"
    static let currentVersion = 1

    /// Always "tabbit-scan".
    let format: String
    /// Bumped if the file layout ever changes.
    let version: Int
    let exportedAt: Date
    let appVersion: String?
    /// The raw OCR result.
    let scan: ScanResult
    /// What the parser produced. Optional so hand-written fixtures can leave it out.
    let parsed: Receipt?

    init(scan: ScanResult, parsed: Receipt?, exportedAt: Date, appVersion: String?) {
        self.format = ScanExport.formatName
        self.version = ScanExport.currentVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.scan = scan
        self.parsed = parsed
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
