import Foundation

/// Someone who shares costs. "Me" (the phone's owner) has a fixed ID and is
/// part of every group.
struct Person: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    /// Index into Theme.pastels for the avatar.
    var colorIndex: Int

    static let meID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var isMe: Bool {
        return id == Person.meID
    }

    /// Up to two initials ("Sam Lee" → "SL"), or "?" without a name.
    var initials: String {
        let words = name.split(whereSeparator: { character in character == " " || character == "-" })
        let letters = words.prefix(2).compactMap { word in word.first }
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
    }

    static func makeMe(name: String = "Me") -> Person {
        return Person(id: meID, name: name, colorIndex: 0)
    }
}

extension Array where Element == Person {
    func person(_ id: UUID) -> Person? {
        return first { person in person.id == id }
    }

    /// The display name for an ID: "You" for me, otherwise the person's name.
    func displayName(_ id: UUID) -> String {
        if id == Person.meID {
            return "You"
        }
        return person(id)?.name ?? "Someone"
    }
}
