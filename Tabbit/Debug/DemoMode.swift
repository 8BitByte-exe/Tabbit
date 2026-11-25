#if DEBUG
import SwiftUI
import UIKit

/// Screenshot mode for CI (Debug builds only; the Release IPA doesn't contain it).
///
/// Launch arguments: `-TabbitDemo -TabbitScreen <screen>`, where screen is one of
/// groups, group, swipe, receipt, settle, edit, category, add, mine, sort, map, mappin, mapfix, mapoff,
/// groupmap, profile, profileedit, settings, whatsnew, processing, dialog or empty. Sample data goes into a throwaway folder, never the real store.
enum DemoMode {

    static var isEnabled: Bool {
        return ProcessInfo.processInfo.arguments.contains("-TabbitDemo")
    }

    static var screen: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard isEnabled, let index = arguments.firstIndex(of: "-TabbitScreen"), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    static func freshFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TabbitDemo", isDirectory: true)
        _ = try? FileManager.default.removeItem(at: folder)
        return folder
    }

    // MARK: - Sample people and groups

    private static func id(_ suffix: Int) -> UUID {
        let digits = String(suffix, radix: 16, uppercase: true)
        let hex = String(repeating: "0", count: max(0, 12 - digits.count)) + digits
        return UUID(uuidString: "D3E00000-0000-0000-0000-\(hex)")!
    }

    private static let alex = Person(id: id(1), name: "Alex", colorIndex: 1)
    private static let blair = Person(id: id(2), name: "Blair", colorIndex: 2)
    private static let casey = Person(id: id(3), name: "Casey", colorIndex: 3)
    private static let drew = Person(id: id(4), name: "Drew", colorIndex: 4)

    static let lisbonID = id(100)
    private static let flatID = id(101)
    private static let dinnerID = id(102)
    static let timeOutID = id(200)

    private static func daysAgo(_ days: Int) -> Date {
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: -days, to: today) ?? today
    }

    private static func amount(_ text: String) -> Decimal {
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    /// The receipt with its store already found on the map (so screenshots never look anything up).
    private static func placed(_ record: ReceiptRecord, _ latitude: Double, _ longitude: Double) -> ReceiptRecord {
        var copy = record
        if let query = PlaceQuery.make(for: copy) {
            copy.place = ReceiptPlace(query: query.key, found: FoundPlace(latitude: latitude, longitude: longitude,
                                                                          address: copy.location))
        }
        return copy
    }

    private static func item(_ name: String, _ price: String, _ people: [Person] = [],
                             confidence: Float? = nil) -> SplitItem {
        return SplitItem(name: name, price: amount(price), assignees: people.map { person in person.id },
                         confidence: confidence)
    }

    @MainActor
    static func populate(_ store: TabbitStore) {
        store.updateMe(name: "Sam", colorIndex: 0)
        guard screen != "empty" else {
            return
        }
        let me = store.me

        // Saved oldest first: the last one saved is at the top of the list.
        store.save(SplitGroup(id: dinnerID, name: "Friday Dinner", category: .event, members: [me, blair, drew]))
        store.save(SplitGroup(id: flatID, name: "Flat 4B", category: .home, members: [me, alex]))
        store.save(SplitGroup(id: lisbonID, name: "Lisbon Trip", category: .trip, members: [me, alex, blair, casey]))

        let pastelaria = receiptImage(lines: ["PASTELARIA BELEM", "Rua de Belem 84", "",
                                              "6 PASTEL DE NATA        7.20", "2 GALAO                 2.40",
                                              "1 ESPRESSO              1.80", "", "TOTAL                  11.40"])
        let records: [(ReceiptRecord, UIImage?)] = [
            (placed(ReceiptRecord(groupID: lisbonID, merchant: "Hotel Alfama", location: "Rua de São Miguel 12, Lisboa",
                                  date: daysAgo(3), category: .lodging, paidBy: me.id, total: amount("480.00")),
                    38.7114, -9.1296), nil),
            (placed(ReceiptRecord(groupID: lisbonID, merchant: "Tram 28", location: "Praça Martim Moniz, Lisboa",
                                  date: daysAgo(2), category: .transport, paidBy: blair.id, total: amount("25.60")),
                    38.7163, -9.1361), nil),
            (placed(ReceiptRecord(groupID: lisbonID, merchant: "Pastelaria Belém", location: "Rua de Belém 84, Lisboa",
                                  date: daysAgo(1), category: .food, paidBy: alex.id,
                                  items: [item("Pastel de nata ×6", "7.20"), item("Galão ×2", "2.40", [me, blair]),
                                          item("Espresso", "1.80", [alex])],
                                  total: amount("11.40"), source: .camera),
                    38.6975, -9.2032), pastelaria),
            (placed(ReceiptRecord(id: timeOutID, groupID: lisbonID, merchant: "Time Out Market",
                           location: "Av. 24 de Julho 49, Lisboa", date: daysAgo(0),
                           time: ClockTime(hour: 20, minute: 15), paymentMethod: "Mastercard",
                           category: .food, paidBy: casey.id,
                           items: [item("Bacalhau à Brás", "18.50", [casey, alex]),
                                   item("Grilled octopus", "22.00", [me, blair]),
                                   item("Vinho verde", "16.00"),
                                   item("Pastéis", "6.50", [me])],
                           tax: amount("3.78"), tip: .percent(amount("10")), source: .camera),
                    38.7069, -9.1459), nil),
            (ReceiptRecord(groupID: flatID, merchant: "Fresh Mart", date: daysAgo(2), category: .groceries,
                           paidBy: alex.id,
                           items: [item("Oat milk", "3.98"), item("Sourdough", "5.49"), item("Avocados", "4.50"),
                                   item("Coffee beans", "14.99", [me]), item("Dish soap", "3.29")],
                           tax: amount("1.12")), nil),
            (ReceiptRecord(groupID: flatID, merchant: "City Power", date: daysAgo(4), category: .utilities,
                           paidBy: me.id, total: amount("84.00")), nil),
            (ReceiptRecord(groupID: dinnerID, merchant: "Trattoria Roma", date: daysAgo(5), category: .food,
                           paidBy: drew.id,
                           items: [item("Margherita", "14.00", [blair]), item("Diavola", "16.00", [drew]),
                                   item("Carbonara", "17.50", [me]), item("Tiramisu", "9.00")],
                           tax: amount("4.20"), tip: .amount(amount("9.00"))), nil),
            // My Receipts, over a few months for the profile charts.
            (placed(ReceiptRecord(merchant: "The Daily Grind", location: "Rua Augusta 120, Lisboa",
                                  date: daysAgo(0), category: .coffee,
                                  items: [item("Oat latte", "5.25"), item("Almond croissant", "4.50")],
                                  tax: amount("0.87"), source: .camera),
                    38.7108, -9.1376), nil),
            // On a receipt, but Apple Maps found nothing for it: listed under "Not on the Map".
            (notFound(ReceiptRecord(merchant: "Corner Kiosk", location: "Kiosk 3, Old Town",
                                    date: daysAgo(2), category: .shopping, total: amount("6.50"))), nil),
            (ReceiptRecord(merchant: "Shell", location: "1200 Bay St, Toronto", date: daysAgo(1), category: .fuel,
                           expense: .business, items: [item("Fuel", "64.10")], tax: amount("8.33"),
                           source: .camera), nil),
            (ReceiptRecord(merchant: "Hardware Plus", date: daysAgo(1), category: .household,
                           items: [item("Extension cord", "12.99"), item("Wood screws", "6.49")],
                           tax: amount("1.56")), nil),
            (ReceiptRecord(merchant: "Corner Pharmacy", date: daysAgo(3), category: .health,
                           total: amount("14.20")), nil),
            (ReceiptRecord(merchant: "Cinema Lumière", date: daysAgo(34), category: .entertainment,
                           total: amount("24.00")), nil),
            (ReceiptRecord(merchant: "Green Grocer", date: daysAgo(40), category: .groceries,
                           total: amount("96.30")), nil),
            (ReceiptRecord(merchant: "Book Nook", date: daysAgo(70), category: .shopping,
                           total: amount("142.00")), nil),
            (ReceiptRecord(merchant: "Bike Shop", date: daysAgo(100), category: .transport,
                           total: amount("88.00")), nil),
            (ReceiptRecord(merchant: "Sushi Bar", date: daysAgo(130), category: .food,
                           total: amount("164.50")), nil),
            (ReceiptRecord(merchant: "Garden Centre", date: daysAgo(155), category: .household,
                           total: amount("118.00")), nil),
        ]
        for (record, image) in records {
            let pages = image.flatMap { picture in ScanProcessor.jpegData(for: picture, maxDimension: 2000, quality: 0.8) }
            let thumbnail = image.flatMap { picture in ScanProcessor.jpegData(for: picture, maxDimension: 320, quality: 0.8) }
            _ = try? store.add(record, pageJPEGs: pages.map { data in [data] } ?? [], thumbnailJPEG: thumbnail)
        }

        store.markPaid(Transfer(from: casey.id, to: me.id, cents: 4000), in: lisbonID)
    }

    private static func notFound(_ record: ReceiptRecord) -> ReceiptRecord {
        var copy = record
        if let query = PlaceQuery.make(for: copy) {
            copy.place = ReceiptPlace(query: query.key, found: nil)
        }
        return copy
    }

    // MARK: - Screens

    @MainActor
    static func prepare(router: AppRouter, flow: ReceiptFlow, store: TabbitStore) {
        // The map is on in every screenshot except the one that shows turning it on.
        UserDefaults.standard.set(screen != "mapoff", forKey: MapSettings.enabledKey)
        switch screen {
        case "group", "swipe":
            router.groupsPath = [.group(lisbonID)]
        case "receipt":
            router.groupsPath = [.group(lisbonID), .receipt(timeOutID, inGroup: lisbonID)]
        case "settle":
            router.groupsPath = [.group(lisbonID), .settleUp(lisbonID)]
        case "edit", "category":
            router.groupsPath = [.group(lisbonID)]
            flow.session = scannedSession()
        case "add":
            router.groupsPath = [.group(lisbonID)]
            flow.addReceipt(to: lisbonID)
        case "mine", "sort":
            router.tab = .receipts
        case "map", "mappin", "mapfix", "mapoff":
            router.tab = .map
        case "groupmap":
            router.groupsPath = [.group(lisbonID), .map(lisbonID)]
        case "profile", "profileedit":
            router.tab = .profile
        case "settings":
            router.tab = .profile
            router.profilePath = [.settings]
        case "processing":
            flow.showProcessingForScreenshots()
        default:
            break
        }
    }

    /// A freshly scanned receipt, as the editor sees it: filled-in fields are
    /// marked, the date couldn't be read, the category needs a check and one item name is uncertain.
    @MainActor
    private static func scannedSession() -> EditorSession {
        let image = receiptImage(lines: ["MERCADO DA RIBEIRA", "", "SARDINHAS             12.00",
                                         "QUEIJO SERRA           9.80", "PAO ALENTEJ            3.20",
                                         "", "IVA                    1.50", "TOTAL                 26.50"])
        let record = ReceiptRecord(
            groupID: lisbonID,
            merchant: "Mercado da Ribeira",
            location: "Av. 24 de Julho 49, Lisboa",
            date: Calendar.current.startOfDay(for: Date()),
            time: ClockTime(hour: 13, minute: 42),
            paymentMethod: "Visa",
            category: .groceries,
            paidBy: Person.meID,
            items: [item("Sardinhas", "12.00", confidence: 0.95), item("Queijo Serra", "9.80", confidence: 0.9),
                    item("PAO ALENTEJ", "3.20", confidence: 0.4)],
            tax: amount("1.50"),
            total: amount("26.50"),
            source: .camera,
            autofilled: [.merchant, .location, .time, .payment, .category, .total, .tax, .items],
            unreadable: [.date],
            checks: [FieldCheck(field: .category,
                                reason: "Apple Intelligence's guess: the store's name doesn't say what it is.")],
            pageImageCount: 1
        )
        return EditorSession(record: record, pageJPEGs: [],
                             thumbnailJPEG: ScanProcessor.jpegData(for: image, maxDimension: 320, quality: 0.8),
                             isNew: true)
    }

    /// A plain "paper receipt" picture for photos and thumbnails.
    private static func receiptImage(lines: [String]) -> UIImage {
        let lineHeight: CGFloat = 34
        let size = CGSize(width: 600, height: CGFloat(lines.count) * lineHeight + 140)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor(white: 0.98, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 22, weight: .regular),
                .foregroundColor: UIColor(white: 0.18, alpha: 1),
            ]
            for (index, line) in lines.enumerated() {
                let point = CGPoint(x: 44, y: 70 + CGFloat(index) * lineHeight)
                (line as NSString).draw(at: point, withAttributes: attributes)
            }
        }
    }
}
#endif
