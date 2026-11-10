import XCTest
@testable import Tabbit

final class TabbitStoreTests: XCTestCase {

    private func temporaryFolder() -> URL {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("TabbitStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    @MainActor
    func testGroupsReceiptsAndProfileSurviveARestart() throws {
        let folder = temporaryFolder()
        let store = TabbitStore(folder: folder)
        store.updateMe(name: "Sam", colorIndex: 3)
        let alex = Person(id: UUID(), name: "Alex", colorIndex: 1)
        let group = SplitGroup(name: "Lisbon", category: .trip, members: [store.me, alex])
        store.save(group)
        let receipt = ReceiptRecord(groupID: group.id, merchant: "Pastelaria", paidBy: alex.id,
                                    items: [SplitItem(name: "Pastel de nata", price: money("1.20"), assignees: [alex.id])],
                                    tip: .percent(money("10")), total: money("6.00"))
        try store.add(receipt, pageJPEGs: [Data([0xFF, 0xD8])], thumbnailJPEG: Data([0xFF]))

        let reopened = TabbitStore(folder: folder)
        XCTAssertEqual(reopened.me.name, "Sam")
        XCTAssertEqual(reopened.me.colorIndex, 3)
        XCTAssertEqual(reopened.groups.map { saved in saved.name }, ["Lisbon"])
        XCTAssertEqual(reopened.group(group.id)?.members.map { person in person.name }, ["Sam", "Alex"])
        let loaded = try XCTUnwrap(reopened.receipt(receipt.id))
        XCTAssertEqual(loaded.merchant, "Pastelaria")
        XCTAssertEqual(loaded.paidBy, alex.id)
        XCTAssertEqual(loaded.items.first?.price, money("1.20"))
        XCTAssertEqual(loaded.items.first?.assignees, [alex.id])
        XCTAssertEqual(loaded.tip, .percent(money("10")))
        XCTAssertEqual(loaded.total, money("6.00"))
        XCTAssertEqual(loaded.pageImageCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reopened.thumbnailURL(for: receipt.id).path))
    }

    @MainActor
    func testMeIsAlwaysAMember() {
        let store = TabbitStore(folder: temporaryFolder())
        store.save(SplitGroup(name: "Dinner", members: [Person(id: UUID(), name: "Alex", colorIndex: 1)]))
        XCTAssertEqual(store.groups.first?.members.first?.isMe, true)
    }

    @MainActor
    func testMovingAReceiptResetsPeopleWhoArentInTheNewGroup() throws {
        let store = TabbitStore(folder: temporaryFolder())
        let alex = Person(id: UUID(), name: "Alex", colorIndex: 1)
        let trip = SplitGroup(name: "Trip", members: [store.me, alex])
        let home = SplitGroup(name: "Home", members: [store.me])
        store.save(trip)
        store.save(home)
        let receipt = try store.add(ReceiptRecord(groupID: trip.id, paidBy: alex.id,
                                                  items: [SplitItem(name: "Fuel", price: money("40.00"),
                                                                    assignees: [alex.id])]))
        store.move(receipt.id, to: home.id)
        let moved = try XCTUnwrap(store.receipt(receipt.id))
        XCTAssertEqual(moved.groupID, home.id)
        XCTAssertEqual(moved.paidBy, Person.meID)
        XCTAssertEqual(moved.items.first?.assignees, [])
    }

    @MainActor
    func testDeletingAGroupCanKeepItsReceipts() throws {
        let store = TabbitStore(folder: temporaryFolder())
        let group = SplitGroup(name: "Party", members: [store.me])
        store.save(group)
        let receipt = try store.add(ReceiptRecord(groupID: group.id, total: money("20.00")))
        store.deleteGroup(group.id, keepReceipts: true)
        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertNil(store.receipt(receipt.id)?.groupID)
        XCTAssertEqual(store.receipts(in: nil).count, 1)
    }

    @MainActor
    func testMarkPaidPersistsAndSettles() throws {
        let folder = temporaryFolder()
        let store = TabbitStore(folder: folder)
        let alex = Person(id: UUID(), name: "Alex", colorIndex: 1)
        let group = SplitGroup(name: "Lunch", members: [store.me, alex])
        store.save(group)
        try store.add(ReceiptRecord(groupID: group.id, paidBy: alex.id, total: money("20.00")))
        let saved = try XCTUnwrap(store.group(group.id))
        let transfers = store.transfers(in: saved)
        XCTAssertEqual(transfers.map { transfer in transfer.cents }, [1000])
        store.markPaid(transfers[0], in: group.id)

        let reopened = TabbitStore(folder: folder)
        let reloaded = try XCTUnwrap(reopened.group(group.id))
        XCTAssertEqual(reloaded.settlements.count, 1)
        XCTAssertTrue(reopened.transfers(in: reloaded).isEmpty)
    }

    @MainActor
    func testRemovingAMemberClearsTheirAssignments() throws {
        let store = TabbitStore(folder: temporaryFolder())
        let alex = Person(id: UUID(), name: "Alex", colorIndex: 1)
        var group = SplitGroup(name: "Trip", members: [store.me, alex])
        store.save(group)
        let receipt = try store.add(ReceiptRecord(groupID: group.id,
                                                  items: [SplitItem(name: "Tour", price: money("10.00"),
                                                                    assignees: [alex.id])]))
        XCTAssertTrue(store.isReferenced(alex.id, in: group.id))
        group.members.removeAll { person in person.id == alex.id }
        store.save(group)
        XCTAssertEqual(store.receipt(receipt.id)?.items.first?.assignees, [])
    }

    @MainActor
    func testVersion04ReceiptsMoveToMyReceipts() throws {
        let folder = temporaryFolder()
        let id = UUID()
        let directory = folder.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = """
        {"id":"\(id.uuidString)","createdAt":800000000,"updatedAt":800000000,"pageImageCount":1,
         "receipt":{"merchant":"Corner Market","lineItems":[{"name":"Bread","amount":"3.49"}],"total":"3.49","parser":"rules","notes":[]},
         "parsed":{"merchant":"CORNER MARKET","lineItems":[],"parser":"rules","notes":[]},
         "scan":{"pageCount":1,"blocks":[]}}
        """
        try Data(legacy.utf8).write(to: directory.appendingPathComponent("receipt.json"))

        let store = TabbitStore(folder: folder)
        let migrated = try XCTUnwrap(store.receipt(id))
        XCTAssertNil(migrated.groupID)
        XCTAssertEqual(migrated.merchant, "Corner Market")
        XCTAssertEqual(migrated.items.map { item in item.name }, ["Bread"])
        XCTAssertEqual(migrated.total, money("3.49"))
        XCTAssertEqual(migrated.category, .groceries)
        XCTAssertEqual(migrated.pageImageCount, 1)

        // Rewritten in the new format, so it loads the same way next time.
        let data = try Data(contentsOf: directory.appendingPathComponent("receipt.json"))
        XCTAssertEqual(TabbitStore.decodeRecord(data)?.migrated, false)
    }

    @MainActor
    func testStorageIsExcludedFromICloudBackup() throws {
        let folder = temporaryFolder()
        _ = TabbitStore(folder: folder)
        let values = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    @MainActor
    func testDeleteRemovesPhotos() throws {
        let store = TabbitStore(folder: temporaryFolder())
        let receipt = try store.add(ReceiptRecord(total: money("1.00")), pageJPEGs: [Data([1])])
        store.delete(receipt.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directoryURL(for: receipt.id).path))
        XCTAssertTrue(store.receipts.isEmpty)
    }

    func testMoneyStaysExactInJSON() throws {
        let fixed = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let record = ReceiptRecord(createdAt: fixed, updatedAt: fixed, date: fixed,
                                   items: [SplitItem(name: "Thing", price: money("0.62"))],
                                   tax: money("0.05"), tip: .amount(money("0.10")), total: money("0.77"))
        let data = try JSONEncoder().encode(record)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"0.62\""), json)
        XCTAssertEqual(try JSONDecoder().decode(ReceiptRecord.self, from: data), record)
    }
}
