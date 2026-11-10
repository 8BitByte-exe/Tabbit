import CoreLocation
import Foundation

/// Where a receipt's store is on the map.
///
/// Found once with Apple Maps from the store's name and the address printed on the receipt
/// (`PlaceQuery`), then kept with the receipt on this iPhone, so it's never looked up again
/// unless the name or address changes.
struct ReceiptPlace: Equatable, Codable {
    /// What was looked up (`PlaceQuery.key`). If the receipt's store or address no longer
    /// gives the same query, the place is out of date and is looked up again.
    var query: String
    /// Nil when Apple Maps found nothing for the query.
    var latitude: Double?
    var longitude: Double?
    /// Apple Maps' address for the place.
    var address: String
    var lookedUpAt: Date

    var isFound: Bool {
        return latitude != nil && longitude != nil
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude = latitude, let longitude = longitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension ReceiptPlace {
    /// The result of one lookup: `found` is nil when Apple Maps had nothing.
    init(query: String, found: FoundPlace?, at date: Date = Date()) {
        self.init(query: query, latitude: found?.latitude, longitude: found?.longitude,
                  address: found?.address ?? "", lookedUpAt: date)
    }
}

/// A place Apple Maps found.
struct FoundPlace: Equatable {
    let latitude: Double
    let longitude: Double
    /// Apple Maps' address for it.
    let address: String
}
