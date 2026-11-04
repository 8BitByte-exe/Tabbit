import Foundation
import SwiftUI
import UIKit

/// Saved receipts, kept on this iPhone only.
///
/// Layout: `Application Support/Receipts/<id>/` holds `receipt.json`,
/// `page-1.jpg`, `page-2.jpg`, … and `thumbnail.jpg`.
/// - The whole folder is excluded from iCloud Backup (the owner chose device-only).
/// - Files use complete data protection: encrypted whenever the phone is locked.
/// - Everything survives closing the app, restarting the phone and installing
///   updates (re-sideloading with the same bundle ID). Deleting the app deletes it.
@MainActor
final class ReceiptStore: ObservableObject {

    /// Newest first.
    @Published private(set) var receipts: [SavedReceipt] = []
    /// Receipt files that couldn't be read at launch. They stay on disk, untouched.
    @Published private(set) var unreadableCount: Int = 0

    let folder: URL

    /// Thumbnails are small but read often by the home screen, so keep them in memory.
    private let thumbnailCache = NSCache<NSUUID, UIImage>()

    private static let receiptFileName = "receipt.json"
    private static let thumbnailFileName = "thumbnail.jpg"
    private static let protection: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
    private static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtection]

    init(folder: URL = ReceiptStore.defaultFolder()) {
        self.folder = folder
        prepareFolder()
        reload()
    }

    nonisolated static func defaultFolder() -> URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Receipts", isDirectory: true)
    }

    // MARK: - Reading

    func receipt(id: UUID) -> SavedReceipt? {
        return receipts.first { saved in saved.id == id }
    }

    func reload() {
        let fileManager = FileManager.default
        let decoder = JSONDecoder()
        var loaded: [SavedReceipt] = []
        var unreadable = 0
        let directories = (try? fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for directory in directories {
            let file = directory.appendingPathComponent(ReceiptStore.receiptFileName)
            guard fileManager.fileExists(atPath: file.path) else {
                continue
            }
            do {
                let data = try Data(contentsOf: file)
                loaded.append(try decoder.decode(SavedReceipt.self, from: data))
            } catch {
                unreadable += 1
            }
        }
        receipts = loaded.sorted { first, second in first.createdAt > second.createdAt }
        unreadableCount = unreadable
    }

    // MARK: - Writing

    /// Saves a new scan with its photos and returns it.
    @discardableResult
    func add(_ processed: ProcessedScan, now: Date = Date()) throws -> SavedReceipt {
        let saved = SavedReceipt(
            id: UUID(),
            createdAt: now,
            updatedAt: now,
            receipt: processed.receipt,
            parsed: processed.receipt,
            scan: processed.scan,
            pageImageCount: processed.pageJPEGs.count,
            languageCorrection: processed.languageCorrection
        )
        let directory = directoryURL(for: saved.id)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: ReceiptStore.protection)
            for (index, data) in processed.pageJPEGs.enumerated() {
                try data.write(to: pageImageURL(for: saved.id, page: index), options: ReceiptStore.writeOptions)
            }
            if let thumbnail = processed.thumbnailJPEG {
                try thumbnail.write(to: thumbnailURL(for: saved.id), options: ReceiptStore.writeOptions)
            }
            try write(saved)
        } catch {
            // Don't leave half a receipt behind.
            _ = try? FileManager.default.removeItem(at: directory)
            throw error
        }
        receipts.insert(saved, at: 0)
        return saved
    }

    /// Saves edited fields.
    func update(_ saved: SavedReceipt) throws {
        var updated = saved
        updated.updatedAt = Date()
        try write(updated)
        if let index = receipts.firstIndex(where: { candidate in candidate.id == saved.id }) {
            receipts[index] = updated
        }
    }

    /// Deletes the receipt and its photos.
    func delete(id: UUID) {
        _ = try? FileManager.default.removeItem(at: directoryURL(for: id))
        thumbnailCache.removeObject(forKey: id as NSUUID)
        receipts.removeAll { saved in saved.id == id }
    }

    // MARK: - Files

    func directoryURL(for id: UUID) -> URL {
        return folder.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// `page` is zero-based; files are named page-1.jpg, page-2.jpg, …
    func pageImageURL(for id: UUID, page: Int) -> URL {
        return directoryURL(for: id).appendingPathComponent("page-\(page + 1).jpg")
    }

    func thumbnailURL(for id: UUID) -> URL {
        return directoryURL(for: id).appendingPathComponent(ReceiptStore.thumbnailFileName)
    }

    func pageImage(for id: UUID, page: Int) -> UIImage? {
        return UIImage(contentsOfFile: pageImageURL(for: id, page: page).path)
    }

    func thumbnail(for id: UUID) -> UIImage? {
        let key = id as NSUUID
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        guard let image = UIImage(contentsOfFile: thumbnailURL(for: id).path) else {
            return nil
        }
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    private func write(_ saved: SavedReceipt) throws {
        let data = try JSONEncoder().encode(saved)
        let url = directoryURL(for: saved.id).appendingPathComponent(ReceiptStore.receiptFileName)
        try data.write(to: url, options: ReceiptStore.writeOptions)
    }

    private func prepareFolder() {
        let fileManager = FileManager.default
        _ = try? fileManager.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: ReceiptStore.protection)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = folder
        _ = try? url.setResourceValues(values)
    }
}
