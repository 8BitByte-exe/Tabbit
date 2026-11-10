import CoreLocation
import Foundation

/// What Tabbit asks Apple Maps to find for a receipt: the store's name and the address
/// printed on the receipt. Nothing else about the receipt is ever sent.
struct PlaceQuery: Equatable {
    /// The store's name, or empty when the address already contains it.
    let merchant: String
    /// The printed address, on one line.
    let address: String

    /// Kept with the found place (`ReceiptPlace.query`), so a changed name or address is
    /// looked up again.
    var key: String {
        return merchant.isEmpty ? address : merchant + " | " + address
    }

    /// What's searched for: "Sobeys, 100 Main St, Burlington".
    var text: String {
        return merchant.isEmpty ? address : merchant + ", " + address
    }

    /// The query for a receipt, or nil if it has no address to look up.
    static func make(for receipt: ReceiptRecord) -> PlaceQuery? {
        let address = oneLine(receipt.location)
        guard address.count >= 3, address.rangeOfCharacter(from: .letters) != nil else {
            return nil
        }
        var merchant = oneLine(receipt.merchant)
        if !merchant.isEmpty && address.lowercased().range(of: merchant.lowercased()) != nil {
            merchant = ""
        }
        return PlaceQuery(merchant: merchant, address: address)
    }

    /// Single spaces, no line breaks.
    static func oneLine(_ text: String) -> String {
        return text.components(separatedBy: .whitespacesAndNewlines)
            .filter { word in !word.isEmpty }
            .joined(separator: " ")
    }
}

/// Receipts on the map: which have a place, which wait for one, and the pins to draw.
enum ReceiptMap {

    enum Status: Equatable {
        /// No address to look up.
        case noAddress
        /// It has an address that hasn't been looked up yet, or that changed since.
        case waiting
        /// Apple Maps found it.
        case found
        /// Apple Maps found nothing for its address.
        case notFound
    }

    static func status(of receipt: ReceiptRecord) -> Status {
        guard let query = PlaceQuery.make(for: receipt) else {
            return .noAddress
        }
        guard let place = receipt.place, place.query == query.key else {
            return .waiting
        }
        return place.isFound ? .found : .notFound
    }

    /// Receipts to look up, in the order given (newest first in the store).
    static func waiting(_ receipts: [ReceiptRecord]) -> [ReceiptRecord] {
        return receipts.filter { receipt in status(of: receipt) == .waiting }
    }

    /// Receipts that aren't on the map: addresses Apple Maps couldn't find first (those
    /// are worth fixing), then receipts with no address.
    static func unplaced(_ receipts: [ReceiptRecord]) -> [ReceiptRecord] {
        let notFound = receipts.filter { receipt in status(of: receipt) == .notFound }
        let noAddress = receipts.filter { receipt in status(of: receipt) == .noAddress }
        return notFound + noAddress
    }

    /// One pin on the map. Receipts from the same store share it.
    struct Pin: Identifiable, Equatable {
        let id: String
        let latitude: Double
        let longitude: Double
        /// The store's name, or "3 receipts" when different names share the spot.
        let title: String
        /// The address printed on the newest receipt.
        let address: String
        /// The newest receipt's category, for the pin's icon.
        let category: SpendCategory
        /// Newest first.
        let receiptIDs: [UUID]

        var coordinate: CLLocationCoordinate2D {
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    /// Places closer than this (in degrees, about 10 m) share a pin.
    static let sameSpot: Double = 0.0001

    /// The pins for receipts that have been found, one per spot, in the order of each spot's
    /// newest receipt.
    static func pins(for receipts: [ReceiptRecord]) -> [Pin] {
        var order: [String] = []
        var grouped: [String: [ReceiptRecord]] = [:]
        var coordinates: [String: (latitude: Double, longitude: Double)] = [:]
        for receipt in receipts where status(of: receipt) == .found {
            guard let place = receipt.place, let latitude = place.latitude, let longitude = place.longitude else {
                continue
            }
            let key = "\(Int((latitude / sameSpot).rounded())),\(Int((longitude / sameSpot).rounded()))"
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = []
                coordinates[key] = (latitude: latitude, longitude: longitude)
            }
            grouped[key]?.append(receipt)
        }
        return order.compactMap { key -> Pin? in
            guard let group = grouped[key], let newest = group.first, let coordinate = coordinates[key] else {
                return nil
            }
            let names = Set(group.map { receipt in receipt.displayTitle })
            let title = names.count == 1 ? newest.displayTitle : "\(group.count) receipts"
            return Pin(id: key, latitude: coordinate.latitude, longitude: coordinate.longitude, title: title,
                       address: PlaceQuery.oneLine(newest.location), category: newest.category,
                       receiptIDs: group.map { receipt in receipt.id })
        }
    }
}
