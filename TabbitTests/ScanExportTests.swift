import CoreGraphics
import XCTest
@testable import Tabbit

final class ScanExportTests: XCTestCase {

    func testRoundTripKeepsTheScan() throws {
        let scan = ScanResult(pageCount: 2, blocks: [
            RecognizedTextBlock(text: "SHOP", confidence: 0.9,
                                boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.25, height: 0.02), pageIndex: 0),
            RecognizedTextBlock(text: "TOTAL 1.00", confidence: 0.5,
                                boundingBox: CGRect(x: 0.05, y: 0.5, width: 0.5, height: 0.025), pageIndex: 1,
                                alternatives: ["TOTAL 1.08", "T0TAL 1.00"]),
        ])
        let export = ScanExport(scan: scan, parsed: nil, exportedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                appVersion: "0.2.0", languageCorrection: false, redacted: true)

        let data = try ScanExport.makeEncoder().encode(export)
        let decoded = try ScanExport.makeDecoder().decode(ScanExport.self, from: data)

        XCTAssertEqual(decoded.format, "tabbit-scan")
        XCTAssertEqual(decoded.version, ScanExport.currentVersion)
        XCTAssertEqual(decoded.appVersion, "0.2.0")
        XCTAssertEqual(decoded.exportedAt, export.exportedAt)
        XCTAssertEqual(decoded.scan, scan)
        XCTAssertNil(decoded.parsed)
        XCTAssertEqual(decoded.languageCorrection, false)
        XCTAssertEqual(decoded.redacted, true)
    }

    func testExportIncludesParsedReceipt() throws {
        let scan = ReceiptLayoutBuilder().row("SHOP").row("TOTAL", "1.00").build()
        let receipt = RulesReceiptParser().parse(scan)
        let export = ScanExport(scan: scan, parsed: receipt, exportedAt: Date(), appVersion: nil)

        let data = try ScanExport.makeEncoder().encode(export)
        let decoded = try ScanExport.makeDecoder().decode(ScanExport.self, from: data)
        XCTAssertEqual(decoded.parsed?.merchant, "SHOP")
        XCTAssertEqual(decoded.parsed?.total, money("1.00"))
        XCTAssertEqual(decoded.parsed?.parser, .rules)
    }

    func testFixtureFileLoads() throws {
        let export = try Fixtures.export(named: "corner-market")
        XCTAssertEqual(export.format, "tabbit-scan")
        XCTAssertEqual(export.scan.pageCount, 1)
        XCTAssertEqual(export.scan.blocks.count, 8)
    }
}
