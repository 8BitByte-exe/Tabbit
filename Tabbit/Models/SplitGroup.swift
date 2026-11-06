import Foundation

/// A group of people sharing costs (a trip, a dinner, a household).
/// Named SplitGroup so it doesn't clash with SwiftUI's `Group`.
struct SplitGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var category: GroupCategory
    /// Everyone in the group, me first.
    var members: [Person]
    var createdAt: Date
    var updatedAt: Date
    /// Payments recorded with "Mark Paid".
    var settlements: [Settlement]

    init(id: UUID = UUID(), name: String, category: GroupCategory = .other, members: [Person],
         createdAt: Date = Date(), updatedAt: Date = Date(), settlements: [Settlement] = []) {
        self.id = id
        self.name = name
        self.category = category
        self.members = members
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.settlements = settlements
    }

    var memberIDs: [UUID] {
        return members.map { person in person.id }
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Group" : trimmed
    }
}
