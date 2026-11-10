import Foundation

/// Turns a scan into a receipt to review: the fields it could read are filled in
/// and marked as autofilled; the ones it looked for but couldn't read are marked too.
enum ScanAutofill {

    static func record(from processed: ProcessedScan, source: ReceiptSource, groupID: UUID?,
                       paidBy: UUID = Person.meID, now: Date = Date()) -> ReceiptRecord {
        let parsed = processed.receipt
        var autofilled: Set<ReceiptField> = []
        var unreadable: Set<ReceiptField> = []

        var checks: [FieldCheck] = []
        // Misread letters in the store's name, fixed from the iPhone's dictionary.
        let printedMerchant = parsed.merchant ?? ""
        let merchant = OCRSpelling.repairedName(printedMerchant)
        if merchant != printedMerchant {
            checks.append(FieldCheck(field: .merchant, reason: "Corrected from “\(printedMerchant)”, which the scan seems to have misread."))
        }
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

        let receiptLines = LineGrouper.lines(from: processed.scan).map { line in line.text }
        if let parsedDate = parsed.date, let check = dateCheck(for: parsedDate, lines: receiptLines, now: now) {
            checks.append(check)
        }

        let guess = CategoryGuesser.guessWithSource(merchant: merchant, items: parsed.lineItems.map { item in item.name },
                                                    suggestion: processed.suggestedCategory, receiptLines: receiptLines)
        let category = guess.category
        if category != .other {
            autofilled.insert(.category)
        }
        switch guess.source {
        case .intelligence:
            checks.append(FieldCheck(field: .category, reason: "Apple Intelligence's guess: the store's name doesn't say what it is."))
        case .items:
            checks.append(FieldCheck(field: .category, reason: "Guessed from the items: the store's name doesn't say what it is."))
        case .merchant, .departments, .none:
            break
        }

        let isPaymentSlip = parsed.notes.contains(RulesReceiptParser.paymentSlipNote)
        if parsed.total != nil && !isPaymentSlip
            && ReceiptValidator.checks(for: parsed).contains(where: { check in !check.passed }) {
            checks.append(FieldCheck(field: .total, reason: "The items, tax and total don't add up. Compare them with the receipt."))
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
            // A card slip has no items to read.
            if !isPaymentSlip {
                unreadable.insert(.items)
            }
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
            checks: checks,
            pageImageCount: processed.pageJPEGs.count,
            scan: processed.scan,
            parsed: parsed,
            languageCorrection: processed.languageCorrection
        )
    }
}

extension ScanAutofill {

    /// Receipts are normally scanned within this many days; another reading of the date
    /// this recent is worth a look.
    static let freshDays = 60

    /// A "Check" mark for the date: when it's long ago or in the future, or when the printed
    /// digits could also mean another recent date ("03/04/26").
    static func dateCheck(for date: CalendarDate, lines: [String], now: Date) -> FieldCheck? {
        guard let reading = ReceiptDateParser.firstReading(in: lines, reference: now), reading.date == date else {
            return nil
        }
        if !ReceiptDateParser.isRecent(date, reference: now) {
            let when = (ReceiptDateParser.daysBefore(now, date) ?? 0) < 0 ? "in the future" : "more than a year ago"
            return FieldCheck(field: .date, reason: "Printed as “\(reading.printed)”, which is \(when).")
        }
        let otherRecent = reading.alternatives.first { other in
            guard let days = ReceiptDateParser.daysBefore(now, other) else {
                return false
            }
            return days >= -2 && days <= freshDays
        }
        if let other = otherRecent, let value = other.dateValue {
            return FieldCheck(field: .date,
                              reason: "Printed as “\(reading.printed)”, which could also mean \(DateText.long(value)).")
        }
        return nil
    }
}

/// Guesses a spending category from the merchant name, what the receipt itself shows
/// (department headings), Apple Intelligence's suggestion, then the items.
///
/// Keywords of 4 letters or fewer must be whole words ("inn" mustn't match "dinner",
/// "tea" mustn't match "steak"); longer ones may appear inside words ("bakery" in
/// "bakeryhouse"). Rules are checked in order, so specific ones come first.
enum CategoryGuesser {
    private static let rules: [(SpendCategory, [String])] = [
        (.health, ["drug mart", "pharmaprix", "rexall"]),
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
                      "rewe", "edeka", "mercado", "albert heijn", "spar", "coop", "publix", "wegmans", "mercadona",
                      "sobeys", "loblaws", "no frills", "nofrills", "food basics", "freshco", "zehrs", "fortinos",
                      "longo's", "longos", "farm boy", "superstore", "iga", "provigo", "maxi", "metro", "foodland",
                      "save-on", "t&t", "food lion", "giant eagle", "h-e-b", "meijer", "sprouts"]),
        (.fuel, ["fuel", "gas station", "petrol", "shell", "chevron", "exxon", "esso", "texaco", "arco", "valero",
                 "tankstelle", "diesel", "unleaded"]),
        (.transport, ["uber", "lyft", "taxi", "cab", "parking", "transit", "rail", "railway", "train", "bus",
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

    /// A store name that names its category ("Joe's Pizza") wins; then what the receipt shows
    /// about the store (department headings mean a supermarket); then Apple Intelligence's
    /// suggestion, which understands the whole receipt; then keywords in the items.
    static func guess(merchant: String, items: [String], suggestion: SpendCategory? = nil,
                      receiptLines: [String] = []) -> SpendCategory {
        return guessWithSource(merchant: merchant, items: items, suggestion: suggestion,
                               receiptLines: receiptLines).category
    }

    /// What the category was decided from, so a weak guess can be marked for checking.
    enum Source: Equatable {
        case merchant
        case departments
        case intelligence
        case items
        case none
    }

    static func guessWithSource(merchant: String, items: [String], suggestion: SpendCategory? = nil,
                                receiptLines: [String] = []) -> (category: SpendCategory, source: Source) {
        if let category = match(merchant) {
            return (category: category, source: .merchant)
        }
        if let category = departmentHint(in: receiptLines) {
            return (category: category, source: .departments)
        }
        if let suggestion = suggestion, suggestion != .other {
            return (category: suggestion, source: .intelligence)
        }
        if let category = match(items.joined(separator: " ")) {
            return (category: category, source: .items)
        }
        return (category: .other, source: .none)
    }

    /// Food departments a supermarket prints over its items. One of the clear ones, or two of any.
    private static let groceryDepartments: Set<String> = [
        "PRODUCE", "GROCERY", "GROCERIES", "DAIRY", "FROZEN", "MEAT", "MEATS", "SEAFOOD", "DELI", "BAKERY",
    ]
    private static let clearGroceryDepartments: Set<String> = ["PRODUCE", "GROCERY", "GROCERIES", "DAIRY", "FROZEN"]

    /// Groceries, if the receipt prints food department headings ("PRODUCE", "21-GROCERY").
    static func departmentHint(in lines: [String]) -> SpendCategory? {
        var found: Set<String> = []
        for line in lines where ReceiptKeywords.isHeading(line) {
            for word in ReceiptKeywords.words(in: line) where groceryDepartments.contains(word) {
                found.insert(word)
            }
        }
        if !found.isDisjoint(with: clearGroceryDepartments) || found.count >= 2 {
            return .groceries
        }
        return nil
    }

    private static func match(_ text: String) -> SpendCategory? {
        return exactMatch(text)
    }

    private static func exactMatch(_ text: String) -> SpendCategory? {
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
