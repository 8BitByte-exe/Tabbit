import XCTest
@testable import Tabbit

/// The map: what's looked up for a receipt, when, and how receipts become pins.
/// Apple Maps can't be reached from CI, so lookups go to a stand-in.
final class ReceiptMapTests: XCTestCase {

    private func temporaryFolder() -> URL {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("ReceiptMapTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func found(_ receipt: ReceiptRecord, _ latitude: Double, _ longitude: Double) -> ReceiptRecord {
        var copy = receipt
        let query = PlaceQuery.make(for: copy)
        copy.place = ReceiptPlace(query: query?.key ?? "",
                                  found: FoundPlace(latitude: latitude, longitude: longitude, address: ""))
        return copy
    }

    // MARK: - Queries

    func testTheQueryIsTheStoreAndItsPrintedAddress() {
        let receipt = ReceiptRecord(merchant: "Sobeys", location: "100 Main St,\nBurlington, On  L7P 0A0")
        let query = PlaceQuery.make(for: receipt)
        XCTAssertEqual(query?.text, "Sobeys, 100 Main St, Burlington, On L7P 0A0")
        XCTAssertEqual(query?.address, "100 Main St, Burlington, On L7P 0A0")

        // A store name that's already in the address isn't repeated.
        let named = ReceiptRecord(merchant: "Sobeys", location: "Burlington Sobeys #742, 100 Main St")
        XCTAssertEqual(PlaceQuery.make(for: named)?.text, "Burlington Sobeys #742, 100 Main St")

        // Nothing to look up without an address.
        XCTAssertNil(PlaceQuery.make(for: ReceiptRecord(merchant: "Sobeys")))
        XCTAssertNil(PlaceQuery.make(for: ReceiptRecord(merchant: "Sobeys", location: "  ")))
        XCTAssertNil(PlaceQuery.make(for: ReceiptRecord(merchant: "Sobeys", location: "#742")))
    }

    func testAChangedAddressIsLookedUpAgain() {
        var receipt = ReceiptRecord(merchant: "Sobeys", location: "100 Main St, Burlington")
        XCTAssertEqual(ReceiptMap.status(of: receipt), .waiting)
        receipt = found(receipt, 43.33, -79.79)
        XCTAssertEqual(ReceiptMap.status(of: receipt), .found)

        receipt.location = "200 Main St, Burlington"
        XCTAssertEqual(ReceiptMap.status(of: receipt), .waiting)
        receipt.merchant = ""
        receipt.location = ""
        XCTAssertEqual(ReceiptMap.status(of: receipt), .noAddress)

        var missing = ReceiptRecord(merchant: "Kiosk", location: "Kiosk 3, Old Town")
        missing.place = ReceiptPlace(query: PlaceQuery.make(for: missing)?.key ?? "", found: nil)
        XCTAssertEqual(ReceiptMap.status(of: missing), .notFound)
    }

    // MARK: - Pins

    func testReceiptsFromTheSameStoreShareAPin() {
        let first = found(ReceiptRecord(merchant: "Time Out Market", location: "Av. 24 de Julho 49, Lisboa",
                                        category: .food), 38.70690, -9.14590)
        let second = found(ReceiptRecord(merchant: "Time Out Market", location: "Av. 24 de Julho 49, Lisboa",
                                         category: .drinks), 38.70691, -9.14589)
        let elsewhere = found(ReceiptRecord(merchant: "Pastelaria Belém", location: "Rua de Belém 84, Lisboa",
                                            category: .food), 38.6975, -9.2032)
        let noAddress = ReceiptRecord(merchant: "City Power")
        let pins = ReceiptMap.pins(for: [first, second, elsewhere, noAddress])

        XCTAssertEqual(pins.count, 2)
        XCTAssertEqual(pins.first?.title, "Time Out Market")
        XCTAssertEqual(pins.first?.receiptIDs, [first.id, second.id])
        XCTAssertEqual(pins.first?.category, .food)
        XCTAssertEqual(pins.first?.address, "Av. 24 de Julho 49, Lisboa")
        XCTAssertEqual(pins.last?.receiptIDs, [elsewhere.id])

        // Different names at one spot (a food court) show how many receipts are there.
        let stall = found(ReceiptRecord(merchant: "Croqueteria", location: "Av. 24 de Julho 49, Lisboa"),
                          38.70690, -9.14590)
        XCTAssertEqual(ReceiptMap.pins(for: [first, stall]).first?.title, "2 receipts")
    }

    func testReceiptsNotOnTheMapListTheOnesToFixFirst() {
        let noAddress = ReceiptRecord(merchant: "City Power")
        var notFound = ReceiptRecord(merchant: "Kiosk", location: "Kiosk 3, Old Town")
        notFound.place = ReceiptPlace(query: PlaceQuery.make(for: notFound)?.key ?? "", found: nil)
        let waiting = ReceiptRecord(merchant: "Sobeys", location: "100 Main St, Burlington")
        let placed = found(ReceiptRecord(merchant: "Shell", location: "1 King St, Toronto"), 43.6, -79.4)

        let unplaced = ReceiptMap.unplaced([noAddress, notFound, waiting, placed])
        XCTAssertEqual(unplaced.map { receipt in receipt.id }, [notFound.id, noAddress.id])
        XCTAssertEqual(ReceiptMap.waiting([noAddress, notFound, waiting, placed]).map { receipt in receipt.id },
                       [waiting.id])
    }

    // MARK: - Saving

    func testThePlaceIsSavedWithTheReceipt() throws {
        let receipt = found(ReceiptRecord(merchant: "Sobeys", location: "100 Main St, Burlington"), 43.33, -79.79)
        let data = try JSONEncoder().encode(receipt)
        let decoded = try JSONDecoder().decode(ReceiptRecord.self, from: data)
        XCTAssertEqual(decoded.place, receipt.place)
        XCTAssertEqual(ReceiptMap.status(of: decoded), .found)

        // Receipts saved before the map have no place, and are looked up when it's turned on.
        let older = try JSONEncoder().encode(ReceiptRecord(merchant: "Sobeys", location: "100 Main St, Burlington"))
        let decodedOlder = try JSONDecoder().decode(ReceiptRecord.self, from: older)
        XCTAssertNil(decodedOlder.place)
        XCTAssertEqual(ReceiptMap.status(of: decodedOlder), .waiting)
    }

    @MainActor
    func testEditingAReceiptKeepsAPlaceFoundMeanwhile() throws {
        let store = TabbitStore(folder: temporaryFolder())
        let receipt = try store.add(ReceiptRecord(merchant: "Sobeys", location: "100 Main St, Burlington"))
        let place = ReceiptPlace(query: PlaceQuery.make(for: receipt)?.key ?? "",
                                 found: FoundPlace(latitude: 43.33, longitude: -79.79, address: ""))
        store.setPlace(place, for: receipt.id)

        // The editor opened before the place was found, so its copy has none.
        var edited = receipt
        edited.paymentMethod = "Visa"
        try store.update(edited)
        XCTAssertEqual(store.receipt(receipt.id)?.place, place)
        XCTAssertEqual(TabbitStore(folder: store.folder).receipt(receipt.id)?.place, place)
    }

    @MainActor
    func testTypingAnAddressReplacesTheScannedOne() throws {
        let store = TabbitStore(folder: temporaryFolder())
        let receipt = try store.add(ReceiptRecord(merchant: "Kiosk", unreadable: [.location]))
        store.setLocation("  Rua Augusta 120, Lisboa ", for: receipt.id)
        let saved = try XCTUnwrap(store.receipt(receipt.id))
        XCTAssertEqual(saved.location, "Rua Augusta 120, Lisboa")
        XCTAssertFalse(saved.unreadable.contains(.location))
        XCTAssertEqual(ReceiptMap.status(of: saved), .waiting)
    }

    // MARK: - Looking up

    @MainActor
    private final class FakeSearcher: PlaceSearching {
        var places: [String: FoundPlace] = [:]
        var error: PlaceSearchError?
        var throttleOnce = false
        private(set) var queries: [String] = []

        func find(_ query: PlaceQuery) async throws -> FoundPlace? {
            queries.append(query.text)
            if throttleOnce {
                throttleOnce = false
                throw PlaceSearchError.throttled
            }
            if let error = error {
                throw error
            }
            return places[query.address]
        }
    }

    @MainActor
    func testEachReceiptIsLookedUpOnce() async throws {
        let store = TabbitStore(folder: temporaryFolder())
        let sobeys = try store.add(ReceiptRecord(merchant: "Sobeys", location: "100 Main St, Burlington"))
        let kiosk = try store.add(ReceiptRecord(merchant: "Kiosk", location: "Kiosk 3, Old Town"))
        let power = try store.add(ReceiptRecord(merchant: "City Power"))
        let searcher = FakeSearcher()
        searcher.places["100 Main St, Burlington"] = FoundPlace(latitude: 43.33, longitude: -79.79,
                                                                address: "100 Main St, Burlington ON")
        let finder = PlaceFinder(searcher: searcher, pauseNanoseconds: 0, throttleWaitNanoseconds: 0)

        await finder.findWaiting(in: store)
        XCTAssertEqual(searcher.queries.sorted(), ["Kiosk, Kiosk 3, Old Town", "Sobeys, 100 Main St, Burlington"])
        XCTAssertEqual(store.receipt(sobeys.id)?.place?.latitude, 43.33)
        XCTAssertEqual(ReceiptMap.status(of: try XCTUnwrap(store.receipt(kiosk.id))), .notFound)
        XCTAssertNil(store.receipt(power.id)?.place)
        XCTAssertEqual(finder.phase, .idle)

        // Nothing is looked up twice, even after a restart.
        let reopened = TabbitStore(folder: store.folder)
        await finder.findWaiting(in: reopened)
        XCTAssertEqual(searcher.queries.count, 2)

        // A typed address is looked up.
        reopened.setLocation("Rua Augusta 120, Lisboa", for: kiosk.id)
        searcher.places["Rua Augusta 120, Lisboa"] = FoundPlace(latitude: 38.71, longitude: -9.14, address: "")
        await finder.findWaiting(in: reopened)
        XCTAssertEqual(searcher.queries.last, "Kiosk, Rua Augusta 120, Lisboa")
        XCTAssertEqual(ReceiptMap.status(of: try XCTUnwrap(reopened.receipt(kiosk.id))), .found)
        XCTAssertEqual(ReceiptMap.pins(for: reopened.receipts).count, 2)
    }

    @MainActor
    func testNoConnectionLeavesReceiptsWaiting() async throws {
        let store = TabbitStore(folder: temporaryFolder())
        let receipt = try store.add(ReceiptRecord(merchant: "Sobeys", location: "100 Main St, Burlington"))
        let searcher = FakeSearcher()
        searcher.error = .unreachable
        let finder = PlaceFinder(searcher: searcher, pauseNanoseconds: 0, throttleWaitNanoseconds: 0)

        await finder.findWaiting(in: store)
        XCTAssertEqual(finder.phase, .unreachable)
        XCTAssertEqual(ReceiptMap.status(of: try XCTUnwrap(store.receipt(receipt.id))), .waiting)

        // Apple Maps asking to slow down is waited out, not a failure.
        searcher.error = nil
        searcher.throttleOnce = true
        searcher.places["100 Main St, Burlington"] = FoundPlace(latitude: 43.33, longitude: -79.79, address: "")
        await finder.findWaiting(in: store)
        XCTAssertEqual(finder.phase, .idle)
        XCTAssertEqual(ReceiptMap.status(of: try XCTUnwrap(store.receipt(receipt.id))), .found)
    }
}
