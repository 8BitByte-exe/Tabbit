import Foundation

/// Exports receipts as CSV (one row per item; receipts without items get one row).
enum CSVExporter {

    static let header = ["Group", "Date", "Merchant", "Category", "Paid by", "Item", "Item price",
                         "Shared by", "Tax", "Tip", "Total"]

    static func csv(receipts: [ReceiptRecord], groups: [SplitGroup], me: Person, businesses: [Business] = []) -> String {
        let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { group in (group.id, group) })
        let businessesByID = Dictionary(uniqueKeysWithValues: businesses.map { business in (business.id, business) })
        var rows: [[String]] = [header]
        let sorted = receipts.sorted { first, second in first.date < second.date }

        for receipt in sorted {
            let group = receipt.groupID.flatMap { id in groupsByID[id] }
            let people = group?.members ?? [me]
            let business = receipt.businessID.flatMap { id in businessesByID[id] }
            let groupName = group?.displayName ?? business.map { business in "Work: \(business.displayName)" } ?? "My Receipts"
            let payer = name(receipt.paidBy, people: people, me: me)
            let base = [groupName, isoDate(receipt.date), receipt.displayTitle, receipt.category.title, payer]
            let fees = [plain(receipt.tax), plain(receipt.tip.map { tip in tip.amount(itemsSubtotal: receipt.itemsSubtotal) }),
                        plain(receipt.effectiveTotal)]
            if receipt.items.isEmpty {
                rows.append(base + ["", "", "Everyone"] + fees)
            } else {
                for item in receipt.items {
                    let shared = item.assignees.isEmpty
                        ? "Everyone"
                        : item.assignees.map { id in name(id, people: people, me: me) }.joined(separator: "; ")
                    rows.append(base + [item.name, plain(item.price), shared] + fees)
                }
            }
        }
        return rows.map { row in row.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// RFC 4180: quote fields containing commas, quotes or line breaks; double the quotes.
    static func escape(_ field: String) -> String {
        let needsQuotes = field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r")
        guard needsQuotes else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Writes the CSV to the temporary folder and returns its URL.
    static func write(receipts: [ReceiptRecord], groups: [SplitGroup], me: Person, businesses: [Business] = []) -> URL? {
        let text = csv(receipts: receipts, groups: groups, me: me, businesses: businesses)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tabbit-receipts.csv")
        do {
            try Data(text.utf8).write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    private static func name(_ id: UUID, people: [Person], me: Person) -> String {
        if id == me.id {
            return me.name
        }
        return people.person(id)?.name ?? "Someone"
    }

    private static func plain(_ value: Decimal?) -> String {
        guard let value = value else {
            return ""
        }
        return MoneyInput.editText(value)
    }

    private static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
