import XCTest
@testable import Tabbit

final class ReceiptStoreTests: XCTestCase {

    private func temporaryFolder() -> URL {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("ReceiptStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func sampleScan(total: String = "8.38") -> ProcessedScan {
        let scan = ReceiptLayoutBuilder()
            .row("FRESH MART")
            .row("BANANAS", "1.29")
            .row("MILK", "6.47")
            .row("SUBTOTAL", "7.76")
            .row("TAX", "0.62")
            .row("TOTAL", total)
            .build()
        return ProcessedScan(
            scan: scan,
            receipt: RulesReceiptParser().parse(scan),
            pageJPEGs: [Data([0xFF, 0xD8, 0x01]), Data([0xFF, 0xD8, 0x02])],
            thumbnailJPEG: Data([0xFF, 0xD8, 0x03]),
            languageCorrection: false
        )
    }

    @MainActor
    func testSavedReceiptsSurviveARestart() throws {
        let folder = temporaryFolder()
        let store = ReceiptStore(folder: folder)
        let saved = try store.add(sampleScan())

        // A new store reading the same folder is what the app sees after relaunch.
        let reopened = ReceiptStore(folder: folder)
        XCTAssertEqual(reopened.receipts.count, 1)
        XCTAssertEqual(reopened.receipts.first?.id, saved.id)
        XCTAssertEqual(reopened.receipts.first?.createdAt, saved.createdAt)
        XCTAssertEqual(reopened.receipts.first?.receipt, saved.receipt)
        XCTAssertEqual(reopened.receipts.first?.parsed, saved.parsed)
        XCTAssertEqual(reopened.receipts.first?.scan.plainText, saved.scan.plainText)
        XCTAssertEqual(reopened.receipts.first?.receipt.total, money("8.38"))
        XCTAssertEqual(reopened.receipts.first?.receipt.tax, money("0.62"))
        XCTAssertEqual(reopened.receipts.first?.pageImageCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reopened.pageImageURL(for: saved.id, page: 1).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: reopened.thumbnailURL(for: saved.id).path))
    }

    @MainActor
    func testNewestFirst() throws {
        let folder = temporaryFolder()
        let store = ReceiptStore(folder: folder)
        let older = try store.add(sampleScan(), now: Date(timeIntervalSince1970: 1_000))
        let newer = try store.add(sampleScan(), now: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(ReceiptStore(folder: folder).receipts.map { saved in saved.id }, [newer.id, older.id])
    }

    @MainActor
    func testEditsAreSavedAndCanBeUndone() throws {
        let folder = temporaryFolder()
        let store = ReceiptStore(folder: folder)
        var saved = try store.add(sampleScan())
        XCTAssertFalse(saved.isEdited)

        saved.receipt.merchant = "Fresh Mart Downtown"
        saved.receipt.total = money("8.40")
        try store.update(saved)

        let reopened = ReceiptStore(folder: folder)
        let edited = try XCTUnwrap(reopened.receipt(id: saved.id))
        XCTAssertEqual(edited.receipt.merchant, "Fresh Mart Downtown")
        XCTAssertEqual(edited.receipt.total, money("8.40"))
        XCTAssertEqual(edited.parsed.merchant, "FRESH MART")
        XCTAssertTrue(edited.isEdited)
    }

    @MainActor
    func testDeleteRemovesFilesAndPhotos() throws {
        let folder = temporaryFolder()
        let store = ReceiptStore(folder: folder)
        let saved = try store.add(sampleScan())
        store.delete(id: saved.id)
        XCTAssertTrue(store.receipts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directoryURL(for: saved.id).path))
        XCTAssertTrue(ReceiptStore(folder: folder).receipts.isEmpty)
    }

    @MainActor
    func testStorageIsExcludedFromICloudBackup() throws {
        let folder = temporaryFolder()
        _ = ReceiptStore(folder: folder)
        let values = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    @MainActor
    func testUnreadableFileIsSkippedNotDeleted() throws {
        let folder = temporaryFolder()
        let store = ReceiptStore(folder: folder)
        let saved = try store.add(sampleScan())
        let broken = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        let brokenFile = broken.appendingPathComponent("receipt.json")
        try Data("not json".utf8).write(to: brokenFile)

        let reopened = ReceiptStore(folder: folder)
        XCTAssertEqual(reopened.receipts.map { receipt in receipt.id }, [saved.id])
        XCTAssertEqual(reopened.unreadableCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: brokenFile.path))
    }

    func testMoneyIsStoredAsExactText() throws {
        let receipt = Receipt(merchant: "Shop", date: nil,
                              lineItems: [ReceiptLineItem(name: "Thing", amount: money("0.62"))],
                              subtotal: money("0.62"), tax: money("0.05"), total: money("0.67"),
                              parser: .rules, notes: [])
        let data = try JSONEncoder().encode(receipt)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"0.62\""), json)
        XCTAssertEqual(try JSONDecoder().decode(Receipt.self, from: data), receipt)
    }

    func testOlderNumberFormatStillLoads() throws {
        let json = #"{"merchant":"Shop","lineItems":[{"name":"Thing","amount":1.5}],"total":1.5,"parser":"rules","notes":[]}"#
        let receipt = try JSONDecoder().decode(Receipt.self, from: Data(json.utf8))
        XCTAssertEqual(receipt.total, money("1.5"))
        XCTAssertEqual(receipt.lineItems.first?.amount, money("1.5"))
    }
}
