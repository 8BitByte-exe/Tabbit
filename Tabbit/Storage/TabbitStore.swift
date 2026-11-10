import Foundation
import SwiftUI
import UIKit

/// Everything Tabbit keeps, on this iPhone only.
///
/// Layout in `Application Support/Receipts/` (the same folder as v0.4):
/// - `profile.json`: me
/// - `groups.json`: groups, members and recorded payments
/// - `<receipt id>/receipt.json`, `page-1.jpg`, `page-2.jpg`, …, `thumbnail.jpg`
/// - `work.json`: businesses with their jobs and invoices (Work)
/// - `Work/<invoice id>.pdf`: invoices attached to them
///
/// The folder is excluded from iCloud Backup (the owner chose device-only) and
/// files use complete data protection (encrypted whenever the phone is locked).
/// v0.4 receipts are migrated to My Receipts the first time they're read.
@MainActor
final class TabbitStore: ObservableObject {

    @Published private(set) var me: Person = Person.makeMe()
    /// Newest first.
    @Published private(set) var groups: [SplitGroup] = []
    /// Work: oldest first, so the first business set up stays at the top.
    @Published var businesses: [Business] = []
    /// Newest first (by date, then when added).
    @Published private(set) var receipts: [ReceiptRecord] = []
    /// Receipt files that couldn't be read. They stay on disk, untouched.
    @Published private(set) var unreadableCount: Int = 0
    /// The last save error, for a gentle message in the UI.
    @Published var lastError: String?

    let folder: URL

    private let thumbnailCache = NSCache<NSUUID, UIImage>()

    private static let receiptFileName = "receipt.json"
    private static let thumbnailFileName = "thumbnail.jpg"
    private static let groupsFileName = "groups.json"
    private static let profileFileName = "profile.json"
    static let protection: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
    static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtection]

    init(folder: URL = TabbitStore.defaultFolder()) {
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

    // MARK: - Queries

    func group(_ id: UUID?) -> SplitGroup? {
        guard let id = id else {
            return nil
        }
        return groups.first { group in group.id == id }
    }

    func receipt(_ id: UUID) -> ReceiptRecord? {
        return receipts.first { receipt in receipt.id == id }
    }

    /// Receipts in a group, or My Receipts for nil (not in a group or a business). Newest first.
    func receipts(in groupID: UUID?) -> [ReceiptRecord] {
        return receipts.filter { receipt in receipt.groupID == groupID && receipt.businessID == nil }
    }

    /// Personal receipts: everything except a business's expenses (for the profile's spending).
    var personalReceipts: [ReceiptRecord] {
        return receipts.filter { receipt in receipt.businessID == nil }
    }

    /// The people a receipt can be split between.
    func people(for groupID: UUID?) -> [Person] {
        if let group = group(groupID) {
            return group.members
        }
        return [me]
    }

    func memberIDs(for groupID: UUID?) -> [UUID] {
        return people(for: groupID).map { person in person.id }
    }

    func split(_ receipt: ReceiptRecord) -> ReceiptSplit {
        return SplitCalculator.split(receipt, members: memberIDs(for: receipt.groupID))
    }

    func total(of group: SplitGroup) -> Decimal {
        return receipts(in: group.id).reduce(Decimal(0)) { sum, receipt in sum + receipt.effectiveTotal }
    }

    func balances(in group: SplitGroup) -> [UUID: Int] {
        return SettleUp.balances(receipts: receipts(in: group.id), members: group.memberIDs,
                                 settlements: group.settlements)
    }

    func transfers(in group: SplitGroup) -> [Transfer] {
        return SettleUp.transfers(for: group, receipts: receipts(in: group.id))
    }

    /// True if removing this person would change history (they paid or have items).
    func isReferenced(_ personID: UUID, in groupID: UUID) -> Bool {
        if let group = group(groupID),
           group.settlements.contains(where: { settlement in settlement.from == personID || settlement.to == personID }) {
            return true
        }
        return receipts(in: groupID).contains { receipt in
            receipt.paidBy == personID || receipt.items.contains { item in item.assignees.contains(personID) }
        }
    }

    // MARK: - Profile

    func updateMe(name: String, colorIndex: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        me.name = trimmed.isEmpty ? "Me" : trimmed
        me.colorIndex = colorIndex
        for index in groups.indices {
            if let memberIndex = groups[index].members.firstIndex(where: { person in person.isMe }) {
                groups[index].members[memberIndex] = me
            }
        }
        writeProfile()
        writeGroups()
    }

    // MARK: - Groups

    /// Adds a new group or saves changes to an existing one. Me is always a member.
    func save(_ group: SplitGroup) {
        var updated = group
        updated.updatedAt = Date()
        if !updated.members.contains(where: { person in person.isMe }) {
            updated.members.insert(me, at: 0)
        }
        if let index = groups.firstIndex(where: { candidate in candidate.id == group.id }) {
            groups[index] = updated
            // People who left the group can't be assigned or pay any more.
            for receipt in receipts(in: group.id) {
                var cleaned = receipt
                clean(&cleaned, members: updated.memberIDs)
                if cleaned != receipt {
                    _ = try? write(cleaned)
                    replaceInMemory(cleaned)
                }
            }
        } else {
            groups.insert(updated, at: 0)
        }
        writeGroups()
    }

    /// Deletes a group. Its receipts are deleted too, or moved to My Receipts.
    func deleteGroup(_ id: UUID, keepReceipts: Bool) {
        for receipt in receipts(in: id) {
            if keepReceipts {
                move(receipt.id, to: nil)
            } else {
                delete(receipt.id)
            }
        }
        groups.removeAll { group in group.id == id }
        writeGroups()
    }

    func markPaid(_ transfer: Transfer, in groupID: UUID) {
        guard let index = groups.firstIndex(where: { group in group.id == groupID }) else {
            return
        }
        groups[index].settlements.append(Settlement(from: transfer.from, to: transfer.to, amount: transfer.amount))
        groups[index].updatedAt = Date()
        writeGroups()
    }

    func removeSettlement(_ settlementID: UUID, in groupID: UUID) {
        guard let index = groups.firstIndex(where: { group in group.id == groupID }) else {
            return
        }
        groups[index].settlements.removeAll { settlement in settlement.id == settlementID }
        writeGroups()
    }

    // MARK: - Receipts

    /// Saves a new receipt with its photos.
    @discardableResult
    func add(_ record: ReceiptRecord, pageJPEGs: [Data] = [], thumbnailJPEG: Data? = nil) throws -> ReceiptRecord {
        var saved = record
        saved.pageImageCount = pageJPEGs.count
        clean(&saved, members: memberIDs(for: saved.groupID))
        let directory = directoryURL(for: saved.id)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: TabbitStore.protection)
            try writePhotos(pageJPEGs, thumbnail: thumbnailJPEG, for: saved.id)
            try write(saved)
        } catch {
            _ = try? FileManager.default.removeItem(at: directory)
            throw error
        }
        receipts.append(saved)
        sortReceipts()
        return saved
    }

    func update(_ record: ReceiptRecord) throws {
        var updated = record
        updated.updatedAt = Date()
        // A place found while the editor was open isn't lost when the edit is saved.
        if updated.place == nil, let stored = receipt(updated.id)?.place {
            updated.place = stored
        }
        clean(&updated, members: memberIDs(for: updated.groupID))
        try write(updated)
        replaceInMemory(updated)
    }

    /// Saves where a receipt's store is, as Apple Maps found it. Not an edit, so the
    /// receipt's "updated" time stays the same.
    func setPlace(_ place: ReceiptPlace?, for receiptID: UUID) {
        guard let index = receipts.firstIndex(where: { receipt in receipt.id == receiptID }) else {
            return
        }
        var record = receipts[index]
        record.place = place
        do {
            try write(record)
            receipts[index] = record
        } catch {
            lastError = "Couldn't save where the receipt is: \(error.localizedDescription)"
        }
    }

    /// The store's address, typed in by hand (the map's list of receipts without a place).
    func setLocation(_ location: String, for receiptID: UUID) {
        guard var record = receipt(receiptID) else {
            return
        }
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != record.location else {
            return
        }
        record.location = trimmed
        record.autofilled.remove(.location)
        record.unreadable.remove(.location)
        do {
            try update(record)
        } catch {
            lastError = "Couldn't save the address: \(error.localizedDescription)"
        }
    }

    func delete(_ receiptID: UUID) {
        _ = try? FileManager.default.removeItem(at: directoryURL(for: receiptID))
        thumbnailCache.removeObject(forKey: receiptID as NSUUID)
        receipts.removeAll { receipt in receipt.id == receiptID }
    }

    /// Moves a receipt to another group (or My Receipts). Payer and assignees that
    /// aren't in the new group are reset.
    func move(_ receiptID: UUID, to groupID: UUID?) {
        guard var record = receipt(receiptID) else {
            return
        }
        record.groupID = groupID
        record.businessID = nil
        record.jobID = nil
        do {
            try update(record)
        } catch {
            lastError = "Couldn't move the receipt: \(error.localizedDescription)"
        }
    }

    func replacePhotos(_ receiptID: UUID, pageJPEGs: [Data], thumbnailJPEG: Data?) throws {
        guard var record = receipt(receiptID) else {
            return
        }
        removePhotoFiles(receiptID)
        try writePhotos(pageJPEGs, thumbnail: thumbnailJPEG, for: receiptID)
        record.pageImageCount = pageJPEGs.count
        try update(record)
    }

    func removePhotos(_ receiptID: UUID) {
        guard var record = receipt(receiptID) else {
            return
        }
        removePhotoFiles(receiptID)
        record.pageImageCount = 0
        _ = try? update(record)
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
        return directoryURL(for: id).appendingPathComponent(TabbitStore.thumbnailFileName)
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

    func storageUsage() -> StorageUsage {
        return StorageUsage.measure(folder: folder)
    }

    // MARK: - Loading

    func reload() {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: folder.appendingPathComponent(TabbitStore.profileFileName)),
           let profile = try? decoder.decode(Person.self, from: data) {
            me = profile
        }
        if let data = try? Data(contentsOf: folder.appendingPathComponent(TabbitStore.groupsFileName)),
           let stored = try? decoder.decode([SplitGroup].self, from: data) {
            groups = stored.sorted { first, second in first.updatedAt > second.updatedAt }
        }
        loadWork()

        var loaded: [ReceiptRecord] = []
        var unreadable = 0
        let fileManager = FileManager.default
        let directories = (try? fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for directory in directories {
            let file = directory.appendingPathComponent(TabbitStore.receiptFileName)
            guard fileManager.fileExists(atPath: file.path), let data = try? Data(contentsOf: file) else {
                continue
            }
            if let record = TabbitStore.decodeRecord(data) {
                loaded.append(record.record)
                if record.migrated {
                    _ = try? write(record.record)
                }
            } else {
                unreadable += 1
            }
        }
        receipts = loaded
        sortReceipts()
        unreadableCount = unreadable
    }

    /// Reads a current receipt file, or migrates a v0.4 one (which had no `schema`).
    nonisolated static func decodeRecord(_ data: Data) -> (record: ReceiptRecord, migrated: Bool)? {
        let decoder = JSONDecoder()
        struct SchemaProbe: Decodable {
            let schema: Int?
        }
        let probe = try? decoder.decode(SchemaProbe.self, from: data)
        if probe?.schema != nil {
            guard let record = try? decoder.decode(ReceiptRecord.self, from: data) else {
                return nil
            }
            return (record: record, migrated: false)
        }
        guard let legacy = try? decoder.decode(LegacySavedReceipt.self, from: data) else {
            return nil
        }
        return (record: legacy.migrated(), migrated: true)
    }

    // MARK: - Private

    /// Keeps a receipt consistent with its group: payer and assignees must be members.
    private func clean(_ record: inout ReceiptRecord, members: [UUID]) {
        if !members.contains(record.paidBy) {
            record.paidBy = members.contains(Person.meID) ? Person.meID : (members.first ?? Person.meID)
        }
        for index in record.items.indices {
            record.items[index].assignees = record.items[index].assignees.filter { id in members.contains(id) }
        }
    }

    func replaceInMemory(_ record: ReceiptRecord) {
        if let index = receipts.firstIndex(where: { candidate in candidate.id == record.id }) {
            receipts[index] = record
        }
        sortReceipts()
    }

    private func sortReceipts() {
        receipts.sort { first, second in
            first.date != second.date ? first.date > second.date : first.createdAt > second.createdAt
        }
    }

    func write(_ record: ReceiptRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        let directory = directoryURL(for: record.id)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: TabbitStore.protection)
        }
        try data.write(to: directory.appendingPathComponent(TabbitStore.receiptFileName),
                       options: TabbitStore.writeOptions)
    }

    private func writePhotos(_ pages: [Data], thumbnail: Data?, for id: UUID) throws {
        for (index, data) in pages.enumerated() {
            try data.write(to: pageImageURL(for: id, page: index), options: TabbitStore.writeOptions)
        }
        if let thumbnail = thumbnail {
            try thumbnail.write(to: thumbnailURL(for: id), options: TabbitStore.writeOptions)
        }
        thumbnailCache.removeObject(forKey: id as NSUUID)
    }

    private func removePhotoFiles(_ id: UUID) {
        let directory = directoryURL(for: id)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(".jpg") {
            _ = try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        thumbnailCache.removeObject(forKey: id as NSUUID)
    }

    private func writeGroups() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(groups)
            try data.write(to: folder.appendingPathComponent(TabbitStore.groupsFileName),
                           options: TabbitStore.writeOptions)
        } catch {
            lastError = "Couldn't save groups: \(error.localizedDescription)"
        }
    }

    private func writeProfile() {
        do {
            let data = try JSONEncoder().encode(me)
            try data.write(to: folder.appendingPathComponent(TabbitStore.profileFileName),
                           options: TabbitStore.writeOptions)
        } catch {
            lastError = "Couldn't save your profile: \(error.localizedDescription)"
        }
    }

    private func prepareFolder() {
        let fileManager = FileManager.default
        _ = try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true,
                                             attributes: TabbitStore.protection)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = folder
        _ = try? url.setResourceValues(values)
    }
}

/// The v0.4 receipt file format, read once and migrated to ReceiptRecord.
struct LegacySavedReceipt: Decodable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let receipt: Receipt
    let parsed: Receipt
    let scan: ScanResult
    let pageImageCount: Int
    let languageCorrection: Bool?

    func migrated() -> ReceiptRecord {
        let date = receipt.date?.dateValue ?? Calendar.current.startOfDay(for: createdAt)
        let items = receipt.lineItems.map { line in
            SplitItem(name: line.name, price: line.amount, assignees: [], confidence: line.confidence)
        }
        let merchant = receipt.merchant ?? ""
        return ReceiptRecord(
            id: id,
            groupID: nil,
            createdAt: createdAt,
            updatedAt: updatedAt,
            merchant: merchant,
            date: date,
            category: CategoryGuesser.guess(merchant: merchant, items: items.map { item in item.name }),
            paidBy: Person.meID,
            items: items,
            tax: receipt.tax,
            tip: receipt.tip.map { value in TipValue.amount(value) },
            total: receipt.total,
            includeFees: true,
            source: .camera,
            autofilled: [],
            unreadable: [],
            pageImageCount: pageImageCount,
            scan: scan,
            parsed: parsed,
            languageCorrection: languageCorrection
        )
    }
}
