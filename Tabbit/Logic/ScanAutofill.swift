import Foundation

/// Turns a scan into a receipt to review: the fields it could read are filled in
/// and marked as autofilled; the ones it looked for but couldn't read are marked too.
enum ScanAutofill {

    static func record(from processed: ProcessedScan, source: ReceiptSource, groupID: UUID?,
                       paidBy: UUID = Person.meID, now: Date = Date()) -> ReceiptRecord {
        let parsed = processed.receipt
        var autofilled: Set<ReceiptField> = []
        var unreadable: Set<ReceiptField> = []

        let merchant = parsed.merchant ?? ""
        if merchant.isEmpty {
            unreadable.insert(.merchant)
        } else {
            autofilled.insert(.merchant)
        }

        var date = Calendar.current.startOfDay(for: now)
        if let found = parsed.date?.dateValue {
            date = found
            autofilled.insert(.date)
        } else {
            unreadable.insert(.date)
        }

        // The address, time and payment method are on most receipts; say so when they weren't found.
        let location = parsed.location ?? ""
        if location.isEmpty {
            unreadable.insert(.location)
        } else {
            autofilled.insert(.location)
        }
        if parsed.time != nil {
            autofilled.insert(.time)
        } else {
            unreadable.insert(.time)
        }
        let paymentMethod = parsed.paymentMethod ?? ""
        if paymentMethod.isEmpty {
            unreadable.insert(.payment)
        } else {
            autofilled.insert(.payment)
        }

        let category = CategoryGuesser.guess(merchant: merchant, items: parsed.lineItems.map { item in item.name },
                                             suggestion: processed.suggestedCategory)
        if category != .other {
            autofilled.insert(.category)
        }

        if parsed.total != nil {
            autofilled.insert(.total)
        } else {
            unreadable.insert(.total)
        }
        if parsed.tax != nil {
            autofilled.insert(.tax)
        }
        if parsed.tip != nil {
            autofilled.insert(.tip)
        }
        if parsed.lineItems.isEmpty {
            unreadable.insert(.items)
        } else {
            autofilled.insert(.items)
        }

        let items = parsed.lineItems.map { line in
            SplitItem(name: line.name, price: line.amount, assignees: [], confidence: line.confidence)
        }
        return ReceiptRecord(
            groupID: groupID,
            createdAt: now,
            updatedAt: now,
            merchant: merchant,
            location: location,
            date: date,
            time: parsed.time,
            paymentMethod: paymentMethod,
            category: category,
            paidBy: paidBy,
            items: items,
            tax: parsed.tax,
            tip: parsed.tip.map { value in TipValue.amount(value) },
            total: parsed.total,
            includeFees: true,
            source: source,
            autofilled: autofilled,
            unreadable: unreadable,
            pageImageCount: processed.pageJPEGs.count,
            scan: processed.scan,
            parsed: parsed,
            languageCorrection: processed.languageCorrection
        )
    }
}

/// Guesses a spending category from the merchant name, then from the items.
///
/// Keywords of 4 letters or fewer must be whole words ("inn" mustn't match "dinner",
/// "tea" mustn't match "steak"); longer ones may appear inside words ("bakery" in
/// "bakeryhouse"). Rules are checked in order, so specific ones come first.
enum CategoryGuesser {
    private static let rules: [(SpendCategory, [String])] = [
        (.coffee, ["coffee", "espresso", "starbucks", "cafe", "café", "latte", "roastery", "roasters", "teahouse",
                   "tea", "dunkin", "costa", "kaffee", "cafeteria"]),
        (.food, ["restaurant", "grill", "bistro", "pizza", "pizzeria", "burger", "sushi", "taco", "kitchen", "diner",
                 "noodle", "deli", "bakery", "bäckerei", "boulangerie", "pastelaria", "trattoria", "osteria", "ramen",
                 "thai", "curry", "bbq", "cantina", "eatery", "brasserie", "taverna", "mcdonald", "chipotle", "kfc",
                 "bagel", "donut", "doughnut", "kebab", "falafel", "steakhouse", "dumpling", "pho", "takeaway"]),
        (.drinks, ["bar", "pub", "brewery", "brewing", "tavern", "wine", "cocktail", "beer", "liquor", "spirits",
                   "taproom", "lounge", "biergarten"]),
        (.groceries, ["market", "grocery", "grocer", "supermarket", "foods", "mart", "trader joe", "whole foods",
                      "aldi", "lidl", "kroger", "safeway", "costco", "produce", "tesco", "sainsbury", "carrefour",
                      "rewe", "edeka", "mercado", "albert heijn", "spar", "coop", "publix", "wegmans", "mercadona"]),
        (.fuel, ["fuel", "gas station", "petrol", "shell", "chevron", "exxon", "esso", "texaco", "arco", "valero",
                 "tankstelle", "diesel", "unleaded"]),
        (.transport, ["uber", "lyft", "taxi", "cab", "parking", "transit", "metro", "rail", "railway", "train", "bus",
                      "toll", "tram", "ferry", "subway", "bahn", "scooter", "car rental", "rental car"]),
        (.travel, ["airline", "airlines", "airways", "airport", "flight", "expedia", "lufthansa", "ryanair",
                   "easyjet", "travel", "tours", "excursion"]),
        (.lodging, ["hotel", "inn", "motel", "hostel", "resort", "lodge", "airbnb", "suites", "guesthouse", "b&b"]),
        (.rent, ["rent", "landlord", "lease", "mortgage", "apartment", "housing", "property management"]),
        (.utilities, ["electric", "electricity", "water", "utility", "utilities", "internet", "broadband", "energy",
                      "power", "telecom", "verizon", "vodafone", "comcast", "phone bill", "mobile"]),
        (.subscriptions, ["netflix", "spotify", "icloud", "hulu", "disney", "youtube", "patreon", "adobe",
                          "subscription", "membership", "apple.com"]),
        (.entertainment, ["cinema", "theater", "theatre", "movie", "museum", "tickets", "ticket", "concert",
                          "bowling", "arcade", "gallery", "zoo", "park", "festival", "karaoke", "escape room"]),
        (.health, ["pharmacy", "drug", "drugstore", "clinic", "dental", "dentist", "health", "cvs", "walgreens",
                   "doctor", "hospital", "optician", "apotheke", "farmacia", "medical"]),
        (.personalCare, ["salon", "barber", "spa", "beauty", "cosmetic", "cosmetics", "nail", "nails", "sephora",
                         "hair", "massage"]),
        (.fitness, ["gym", "fitness", "yoga", "pilates", "climbing", "swim", "crossfit", "sports", "golf"]),
        (.education, ["school", "university", "college", "tuition", "course", "academy", "udemy", "coursera",
                      "textbook"]),
        (.pets, ["pet", "pets", "vet", "veterinary", "petco", "petsmart", "animal"]),
        (.kids, ["toy", "toys", "kids", "baby", "children", "daycare", "nursery"]),
        (.gifts, ["gift", "gifts", "florist", "flowers", "charity", "donation"]),
        (.clothing, ["clothing", "apparel", "fashion", "zara", "uniqlo", "shoes", "boutique", "outfitters", "nike",
                     "adidas", "gap", "h&m"]),
        (.electronics, ["electronics", "apple store", "best buy", "bestbuy", "computer", "mediamarkt", "currys",
                        "camera"]),
        (.household, ["hardware", "home depot", "ikea", "lowe's", "garden", "furniture", "homeware", "homewares",
                      "bed bath", "diy"]),
        (.shopping, ["store", "shop", "outlet", "mall", "target", "walmart", "amazon", "department", "books"]),
    ]

    /// A store name that names its category ("Joe's Pizza") wins; then Apple Intelligence's
    /// suggestion, which understands the whole receipt; then keywords in the items.
    static func guess(merchant: String, items: [String], suggestion: SpendCategory? = nil) -> SpendCategory {
        if let category = match(merchant) {
            return category
        }
        if let suggestion = suggestion, suggestion != .other {
            return suggestion
        }
        return match(items.joined(separator: " ")) ?? .other
    }

    private static func match(_ text: String) -> SpendCategory? {
        let lowered = text.lowercased()
        guard !lowered.isEmpty else {
            return nil
        }
        let words = Set(lowered.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { word in
            !word.isEmpty
        })
        for (category, keywords) in rules {
            for keyword in keywords where matches(keyword, lowered: lowered, words: words) {
                return category
            }
        }
        return nil
    }

    private static func matches(_ keyword: String, lowered: String, words: Set<String>) -> Bool {
        if keyword.count <= 4 && !keyword.contains(" ") && !keyword.contains("&") && !keyword.contains(".") {
            return words.contains(keyword) || words.contains(keyword + "s")
        }
        return lowered.contains(keyword)
    }
}
