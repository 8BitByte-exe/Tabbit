import Foundation

/// What a group is for.
enum GroupCategory: String, Codable, CaseIterable, Identifiable {
    case trip
    case event
    case home
    case business
    case personal
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trip: return "Trip"
        case .event: return "Event"
        case .home: return "Home"
        case .business: return "Business"
        case .personal: return "Personal"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .trip: return "airplane"
        case .event: return "party.popper.fill"
        case .home: return "house.fill"
        case .business: return "briefcase.fill"
        case .personal: return "person.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }

    var colorIndex: Int {
        switch self {
        case .trip: return 1
        case .event: return 3
        case .home: return 2
        case .business: return 6
        case .personal: return 0
        case .other: return 8
        }
    }
}

/// What a receipt was for (used for stats and search).
enum SpendCategory: String, Codable, CaseIterable, Identifiable {
    case food
    case groceries
    case transport
    case lodging
    case shopping
    case entertainment
    case utilities
    case health
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: return "Food & Drink"
        case .groceries: return "Groceries"
        case .transport: return "Transport"
        case .lodging: return "Lodging"
        case .shopping: return "Shopping"
        case .entertainment: return "Entertainment"
        case .utilities: return "Bills"
        case .health: return "Health"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .food: return "fork.knife"
        case .groceries: return "cart.fill"
        case .transport: return "car.fill"
        case .lodging: return "bed.double.fill"
        case .shopping: return "bag.fill"
        case .entertainment: return "ticket.fill"
        case .utilities: return "bolt.fill"
        case .health: return "cross.case.fill"
        case .other: return "tag.fill"
        }
    }

    var colorIndex: Int {
        switch self {
        case .food: return 2
        case .groceries: return 0
        case .transport: return 1
        case .lodging: return 3
        case .shopping: return 4
        case .entertainment: return 7
        case .utilities: return 5
        case .health: return 6
        case .other: return 8
        }
    }
}
