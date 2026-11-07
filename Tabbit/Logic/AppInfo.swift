import Foundation

/// The in-app "What's New" changelog.
enum Changelog {
    struct Entry: Identifiable {
        let version: String
        let title: String
        let highlights: [(symbol: String, text: String)]

        var id: String { version }
    }

    static let entries: [Entry] = [
        Entry(version: "1.2", title: "Map", highlights: [
            (symbol: "map.fill", text: "The new Map tab pins every receipt's store, from the address printed on the receipt. Tap a pin to see what you bought there."),
            (symbol: "airplane", text: "Each group has its own map too, so a trip shows everywhere you went."),
            (symbol: "mappin.slash", text: "Receipts without an address, or with one Apple Maps couldn't find, are listed so you can type the address in."),
            (symbol: "lock.fill", text: "The map is off until you turn it on. Then Apple Maps gets each store's name and address once, and nothing else leaves your iPhone."),
        ]),
        Entry(version: "1.1", title: "Apple Intelligence", highlights: [
            (symbol: "sparkles", text: "On iOS 26, Apple Intelligence reads your receipts: which lines are items, tax and the total, readable names, the store and the category. It runs entirely on your iPhone."),
            (symbol: "checkmark.shield.fill", text: "Every amount comes straight from the scan, and Tabbit picks the items, subtotal, tax and total that add up."),
            (symbol: "text.alignright", text: "Tabbit reads a receipt's layout: prices in the right-hand column are items, while quantities, deals and \"you saved\" lines under them are details. Nothing below the total is ever an item."),
            (symbol: "cart.fill", text: "Supermarket receipts with departments like GROCERY or PRODUCE are filed under Groceries."),
            (symbol: "fuelpump.fill", text: "Better with gas receipts, HST and GST, \"SUB\" and \"FINAL\" totals, department headings and \"you saved\" lines."),
            (symbol: "mappin.and.ellipse", text: "Scans now fill in the store's address, the time and how you paid, and say when the receipt doesn't show them."),
            (symbol: "number", text: "Quantities and prices per item: \"2 @ 1.99\" and \"1.99/ea\" are worked out, and deals like \"2 for 1\" are never items."),
            (symbol: "hand.draw.fill", text: "Swipe a payment right to mark it paid, and swipe again to undo."),
            (symbol: "hand.tap.fill", text: "Buttons and cards press in on every tap, even quick ones, and swiped cards stay open."),
            (symbol: "circle.lefthalf.filled", text: "Smoother switching between light and dark, and a tidier profile editor."),
        ]),
        Entry(version: "1.0", title: "Split with friends", highlights: [
            (symbol: "person.3.fill", text: "Groups for trips, events and home, with everyone you share costs with."),
            (symbol: "checklist", text: "Assign each item to the people who had it. Tax and tip follow along."),
            (symbol: "arrow.left.arrow.right", text: "Settle Up shows the fewest payments to make everyone even."),
            (symbol: "chart.pie.fill", text: "See where your money goes on your profile, across 24 categories."),
            (symbol: "text.viewfinder", text: "Reads more receipts: weights, discounts, and tax already included in European prices."),
            (symbol: "sparkles", text: "A calmer, tactile look in clean white or charcoal."),
        ]),
        Entry(version: "0.4", title: "Saved receipts", highlights: [
            (symbol: "tray.full.fill", text: "Receipts and photos are saved on your iPhone."),
            (symbol: "pencil", text: "Edit anything the scan got wrong."),
        ]),
        Entry(version: "0.3", title: "Smarter scanning", highlights: [
            (symbol: "text.viewfinder", text: "Better at tilted receipts, sale prices and misread totals."),
        ]),
    ]

    static var currentVersion: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static let lastSeenKey = "whatsNew.lastSeenVersion"
}

/// How much space Tabbit uses, for the storage meter.
struct StorageUsage: Equatable {
    var photoBytes: Int64
    var dataBytes: Int64
    var deviceFreeBytes: Int64?
    var deviceTotalBytes: Int64?

    var appBytes: Int64 {
        return photoBytes + dataBytes
    }

    static func measure(folder: URL) -> StorageUsage {
        var photos: Int64 = 0
        var data: Int64 = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        if let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) {
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                    continue
                }
                let size = Int64(values.fileSize ?? 0)
                if url.pathExtension.lowercased() == "jpg" {
                    photos += size
                } else {
                    data += size
                }
            }
        }
        var usage = StorageUsage(photoBytes: photos, dataBytes: data, deviceFreeBytes: nil, deviceTotalBytes: nil)
        let volumeKeys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        if let values = try? folder.resourceValues(forKeys: volumeKeys) {
            usage.deviceFreeBytes = values.volumeAvailableCapacityForImportantUsage
            usage.deviceTotalBytes = values.volumeTotalCapacity.map { value in Int64(value) }
        }
        return usage
    }

    static func format(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
