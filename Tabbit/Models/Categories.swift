import Foundation

/// What a group is for.
enum GroupCategory: String, Codable, CaseIterable, Identifiable {
    case trip
    case home
    case dining
    case event
    case friends
    case family
    case couple
    case sports
    case business
    case project
    case personal
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trip: return "Trip"
        case .home: return "Home"
        case .dining: return "Meal Out"
        case .event: return "Event"
        case .friends: return "Friends"
        case .family: return "Family"
        case .couple: return "Couple"
        case .sports: return "Sports"
        case .business: return "Work"
        case .project: return "Project"
        case .personal: return "Personal"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .trip: return "airplane"
        case .home: return "house.fill"
        case .dining: return "fork.knife"
        case .event: return "party.popper.fill"
        case .friends: return "person.2.fill"
        case .family: return "figure.2.and.child.holdinghands"
        case .couple: return "heart.fill"
        case .sports: return "sportscourt.fill"
        case .business: return "briefcase.fill"
        case .project: return "hammer.fill"
        case .personal: return "person.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }

    var colorIndex: Int {
        switch self {
        case .trip: return 1
        case .home: return 2
        case .dining: return 7
        case .event: return 3
        case .friends: return 0
        case .family: return 10
        case .couple: return 4
        case .sports: return 5
        case .business: return 6
        case .project: return 9
        case .personal: return 11
        case .other: return 8
        }
    }
}

/// What a receipt was for (used for stats, search and the profile ring).
/// New cases can be added freely; stored receipts keep their raw values.
enum SpendCategory: String, Codable, CaseIterable, Identifiable {
    case food
    case coffee
    case drinks
    case groceries
    case shopping
    case clothing
    case electronics
    case household
    case transport
    case fuel
    case travel
    case lodging
    case rent
    case utilities
    case subscriptions
    case entertainment
    case health
    case personalCare
    case fitness
    case education
    case pets
    case kids
    case gifts
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: return "Dining"
        case .coffee: return "Coffee"
        case .drinks: return "Drinks"
        case .groceries: return "Groceries"
        case .shopping: return "Shopping"
        case .clothing: return "Clothing"
        case .electronics: return "Electronics"
        case .household: return "Home"
        case .transport: return "Transport"
        case .fuel: return "Fuel"
        case .travel: return "Travel"
        case .lodging: return "Lodging"
        case .rent: return "Rent"
        case .utilities: return "Bills"
        case .subscriptions: return "Subscriptions"
        case .entertainment: return "Entertainment"
        case .health: return "Health"
        case .personalCare: return "Personal Care"
        case .fitness: return "Fitness"
        case .education: return "Education"
        case .pets: return "Pets"
        case .kids: return "Kids"
        case .gifts: return "Gifts"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .food: return "fork.knife"
        case .coffee: return "cup.and.saucer.fill"
        case .drinks: return "wineglass.fill"
        case .groceries: return "cart.fill"
        case .shopping: return "bag.fill"
        case .clothing: return "tshirt.fill"
        case .electronics: return "desktopcomputer"
        case .household: return "sofa.fill"
        case .transport: return "car.fill"
        case .fuel: return "fuelpump.fill"
        case .travel: return "airplane"
        case .lodging: return "bed.double.fill"
        case .rent: return "house.fill"
        case .utilities: return "bolt.fill"
        case .subscriptions: return "repeat.circle.fill"
        case .entertainment: return "ticket.fill"
        case .health: return "cross.case.fill"
        case .personalCare: return "scissors"
        case .fitness: return "dumbbell.fill"
        case .education: return "graduationcap.fill"
        case .pets: return "pawprint.fill"
        case .kids: return "figure.and.child.holdinghands"
        case .gifts: return "gift.fill"
        case .other: return "tag.fill"
        }
    }

    var colorIndex: Int {
        switch self {
        case .food: return 2
        case .coffee: return 7
        case .drinks: return 3
        case .groceries: return 0
        case .shopping: return 4
        case .clothing: return 10
        case .electronics: return 9
        case .household: return 5
        case .transport: return 1
        case .fuel: return 7
        case .travel: return 11
        case .lodging: return 3
        case .rent: return 5
        case .utilities: return 7
        case .subscriptions: return 9
        case .entertainment: return 10
        case .health: return 6
        case .personalCare: return 4
        case .fitness: return 0
        case .education: return 1
        case .pets: return 2
        case .kids: return 11
        case .gifts: return 4
        case .other: return 8
        }
    }
}
