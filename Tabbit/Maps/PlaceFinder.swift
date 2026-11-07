import Foundation
import MapKit

/// Looks up a store. Apple Maps in the app; a stand-in in tests. Called from the main actor
/// (the search itself runs in MapKit while it waits).
@MainActor
protocol PlaceSearching {
    /// The place, or nil if there's nothing for the query. Throws `PlaceSearchError` when the
    /// search couldn't be done.
    func find(_ query: PlaceQuery) async throws -> FoundPlace?
}

enum PlaceSearchError: Error, Equatable {
    /// Apple Maps asks the app to slow down.
    case throttled
    /// No connection, or Apple Maps didn't answer.
    case unreachable
}

/// Finds stores with Apple Maps (MapKit's local search).
///
/// The only thing sent is the query's text: the store's name and the address printed on the
/// receipt. MapKit makes the request; Tabbit has no networking code of its own.
struct AppleMapsSearcher: PlaceSearching {

    func find(_ query: PlaceQuery) async throws -> FoundPlace? {
        // The store at that address is the best pin ("Sobeys, 100 Main St, Burlington");
        // if Apple Maps doesn't know the store, the address alone still places it.
        if !query.merchant.isEmpty, let place = try await search(query.text, types: [.pointOfInterest, .address]) {
            return place
        }
        return try await search(query.address, types: [.address, .pointOfInterest])
    }

    private func search(_ text: String, types: MKLocalSearch.ResultType) async throws -> FoundPlace? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = types
        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch let error as MKError {
            switch error.code {
            case .placemarkNotFound:
                return nil
            case .loadingThrottled:
                throw PlaceSearchError.throttled
            default:
                throw PlaceSearchError.unreachable
            }
        } catch {
            throw PlaceSearchError.unreachable
        }
        guard let item = response.mapItems.first else {
            return nil
        }
        let coordinate = item.placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }
        let address = item.placemark.title ?? item.name ?? ""
        return FoundPlace(latitude: coordinate.latitude, longitude: coordinate.longitude, address: address)
    }
}

/// Whether the person turned the map on. Off by default: turning it on is what lets store
/// names and addresses go to Apple Maps, and what draws the map at all.
enum MapSettings {
    static let enabledKey = "map.enabled"

    static var isEnabled: Bool {
        return UserDefaults.standard.bool(forKey: enabledKey)
    }
}

/// Finds receipts' stores on the map, one at a time, and keeps each place with its receipt.
///
/// Only runs while the map is turned on (Settings, or the Map tab's button). Each receipt is
/// looked up once; a place is looked up again only if the store's name or address changes.
@MainActor
final class PlaceFinder: ObservableObject {

    enum Phase: Equatable {
        case idle
        case finding(done: Int, total: Int)
        /// Apple Maps couldn't be reached; the rest wait for Try Again.
        case unreachable
    }

    @Published private(set) var phase: Phase = .idle

    private let searcher: PlaceSearching
    /// The pause between lookups, to stay well under Apple Maps' limit.
    private let pause: UInt64
    /// How long to wait when Apple Maps asks to slow down.
    private let throttleWait: UInt64
    private var task: Task<Void, Never>?
    private var runID = 0

    init(searcher: PlaceSearching = AppleMapsSearcher(), pauseNanoseconds: UInt64 = 400_000_000,
         throttleWaitNanoseconds: UInt64 = 60_000_000_000) {
        self.searcher = searcher
        self.pause = pauseNanoseconds
        self.throttleWait = throttleWaitNanoseconds
    }

    var isRunning: Bool {
        return task != nil
    }

    /// Starts looking up every receipt that's waiting for a place, if the map is on.
    /// Does nothing while a lookup is already running (it picks up new receipts itself).
    func start(in store: TabbitStore) {
        guard MapSettings.isEnabled, task == nil, !ReceiptMap.waiting(store.receipts).isEmpty else {
            return
        }
        runID += 1
        let current = runID
        task = Task { [weak self] in
            await self?.findWaiting(in: store)
            if self?.runID == current {
                self?.task = nil
            }
        }
    }

    /// Stops looking things up (the map was turned off).
    func stop() {
        task?.cancel()
        task = nil
        runID += 1
        phase = .idle
    }

    /// Looks up the receipts waiting for a place until none are left. Receipts that get an
    /// address while this runs are looked up too.
    func findWaiting(in store: TabbitStore) async {
        var tried: Set<String> = []
        var done = 0
        var total = 0
        while !Task.isCancelled {
            let batch = ReceiptMap.waiting(store.receipts).compactMap { receipt -> (UUID, PlaceQuery)? in
                guard let query = PlaceQuery.make(for: receipt) else {
                    return nil
                }
                let attempt = receipt.id.uuidString + "\n" + query.key
                return tried.contains(attempt) ? nil : (receipt.id, query)
            }
            guard !batch.isEmpty else {
                break
            }
            total += batch.count
            phase = .finding(done: done, total: total)
            for (id, query) in batch {
                tried.insert(id.uuidString + "\n" + query.key)
                let found: FoundPlace?
                do {
                    found = try await search(query)
                } catch {
                    if !Task.isCancelled {
                        phase = .unreachable
                    }
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                // The receipt may have changed or gone while Apple Maps answered.
                if let receipt = store.receipt(id), PlaceQuery.make(for: receipt)?.key == query.key {
                    store.setPlace(ReceiptPlace(query: query.key, found: found), for: id)
                }
                done += 1
                phase = .finding(done: done, total: total)
                if pause > 0 {
                    try? await Task.sleep(nanoseconds: pause)
                }
            }
        }
        if !Task.isCancelled {
            phase = .idle
        }
    }

    /// One lookup. If Apple Maps asks to slow down, waits and tries once more.
    private func search(_ query: PlaceQuery) async throws -> FoundPlace? {
        do {
            return try await searcher.find(query)
        } catch PlaceSearchError.throttled {
            try await Task.sleep(nanoseconds: throttleWait)
            return try await searcher.find(query)
        }
    }
}
