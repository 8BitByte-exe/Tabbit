import XCTest
@testable import Tabbit

/// Search, sorting, CSV export, stats, category guessing and scan autofill.
final class LogicTests: XCTestCase {

    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        return utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Search

    private let latte = ReceiptRecord(merchant: "Daily Grind", category: .food,
                                      items: [SplitItem(name: "Oat Latte", price: Decimal(string: "5.25")!)],
                                      total: Decimal(string: "12.50")!)

    func testSearchMatchesMerchantCategoryItemsAndAmounts() {
        XCTAssertTrue(ReceiptSearch.matches(latte, query: "grind"))
        XCTAssertTrue(ReceiptSearch.matches(latte, query: "food"))
        XCTAssertTrue(ReceiptSearch.matches(latte, query: "latte"))
        XCTAssertTrue(ReceiptSearch.matches(latte, query: "12.50"))
        XCTAssertTrue(ReceiptSearch.matches(latte, query: "5.25"))
        XCTAssertTrue(ReceiptSearch.matches(latte, query: "daily latte"))
        XCTAssertFalse(ReceiptSearch.matches(latte, query: "pizza"))
        XCTAssertTrue(ReceiptSearch.matches(latte, query: "  "))
    }

    func testSearchMatchesDates() {
        var receipt = latte
        receipt.date = day(2026, 11, 3)
        let month = DateFormatter()
        month.dateFormat = "MMMM"
        XCTAssertTrue(ReceiptSearch.matches(receipt, query: month.string(from: receipt.date)))
        XCTAssertTrue(ReceiptSearch.matches(receipt, query: "2026"))
    }

    func testSortOrders() {
        let small = ReceiptRecord(merchant: "Bakery", date: day(2026, 1, 2), total: money("3.00"))
        let big = ReceiptRecord(merchant: "Airline", date: day(2026, 1, 1), total: money("300.00"))
        let mid = ReceiptRecord(merchant: "Cafe", date: day(2026, 1, 3), total: money("30.00"))
        let all = [small, big, mid]
        XCTAssertEqual(ReceiptSearch.sorted(all, by: .newest).map { r in r.merchant }, ["Cafe", "Bakery", "Airline"])
        XCTAssertEqual(ReceiptSearch.sorted(all, by: .oldest).map { r in r.merchant }, ["Airline", "Bakery", "Cafe"])
        XCTAssertEqual(ReceiptSearch.sorted(all, by: .highest).map { r in r.merchant }, ["Airline", "Cafe", "Bakery"])
        XCTAssertEqual(ReceiptSearch.sorted(all, by: .lowest).map { r in r.merchant }, ["Bakery", "Cafe", "Airline"])
        XCTAssertEqual(ReceiptSearch.sorted(all, by: .merchant).map { r in r.merchant }, ["Airline", "Bakery", "Cafe"])
    }

    // MARK: - CSV

    func testCSVEscaping() {
        XCTAssertEqual(CSVExporter.escape("plain"), "plain")
        XCTAssertEqual(CSVExporter.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVExporter.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSVExporter.escape("two\nlines"), "\"two\nlines\"")
    }

    func testCSVRowsPerItem() {
        let me = Person.makeMe(name: "Sam")
        let friend = Person(id: UUID(), name: "Alex", colorIndex: 1)
        let group = SplitGroup(name: "Trip, 2026", members: [me, friend])
        // Receipt dates are local midnight, like in the app.
        let local = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 4))!
        let receipt = ReceiptRecord(groupID: group.id, merchant: "Market", date: local,
                                    items: [SplitItem(name: "Bread", price: money("3.00")),
                                            SplitItem(name: "Wine", price: money("12.00"), assignees: [friend.id])],
                                    tax: money("1.00"))
        let lines = CSVExporter.csv(receipts: [receipt], groups: [group], me: me)
            .split(separator: "\r\n").map { line in String(line) }
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], CSVExporter.header.joined(separator: ","))
        XCTAssertTrue(lines[1].hasPrefix("\"Trip, 2026\",2026-05-04,Market,Other,Sam,Bread,3.00,Everyone,1.00,,16.00"))
        XCTAssertTrue(lines[2].contains("Wine,12.00,Alex"))
    }

    // MARK: - Stats

    func testSpendingStatsUseMyShare() {
        let friend = Person(id: UUID(), name: "Alex", colorIndex: 1)
        let group = SplitGroup(name: "Home", members: [Person.makeMe(), friend])
        let groceries = ReceiptRecord(groupID: group.id, date: day(2026, 11, 2), category: .groceries,
                                      paidBy: friend.id, total: money("40.00"))
        let coffee = ReceiptRecord(date: day(2026, 11, 3), category: .food, total: money("5.00"))
        let october = ReceiptRecord(date: day(2026, 10, 10), category: .food, total: money("20.00"))
        let stats = SpendingStats.compute(receipts: [groceries, coffee, october], groups: [group],
                                          now: day(2026, 11, 15), calendar: utc)
        XCTAssertEqual(stats.thisMonthCents, 2500)
        XCTAssertEqual(stats.lastMonthCents, 2000)
        XCTAssertEqual(stats.categories.map { total in total.category }, [.groceries, .food])
        XCTAssertEqual(stats.months.count, 6)
        XCTAssertEqual(stats.months.last?.cents, 2500)
        XCTAssertEqual(stats.receiptCount, 3)
        XCTAssertEqual(stats.iOweCents, 2000)
        XCTAssertEqual(stats.owedToMeCents, 0)
        XCTAssertEqual(stats.monthChange ?? 0, 0.25, accuracy: 0.0001)
    }

    // MARK: - Category guessing and autofill

    func testCategoryGuesses() {
        XCTAssertEqual(CategoryGuesser.guess(merchant: "The Daily Grind Cafe", items: []), .coffee)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "FRESH MART", items: []), .groceries)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Hotel Lisboa", items: []), .lodging)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "", items: ["Unleaded fuel"]), .fuel)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Zqx Ltd", items: []), .other)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Sushi Bar", items: []), .food)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "The Corner Pub", items: []), .drinks)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Uber", items: []), .transport)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Ryanair", items: []), .travel)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Happy Paws Vet", items: []), .pets)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Uniqlo", items: []), .clothing)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Spotify", items: []), .subscriptions)
        // Short keywords must be whole words: "inn" isn't in "dinner", "tea" isn't in "steak".
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Sunday Dinner Club", items: []), .other)
        XCTAssertEqual(CategoryGuesser.guess(merchant: "Big Steak", items: []), .other)
    }

    func testAutofillMarksWhatWasReadAndWhatWasnt() {
        let scan = ReceiptLayoutBuilder().row("FRESH MART").row("BREAD", "3.49").row("TOTAL", "3.49").build()
        let parsed = RulesReceiptParser().parse(scan)
        let processed = ProcessedScan(scan: scan, receipt: parsed, pageJPEGs: [Data([1])], thumbnailJPEG: nil,
                                      languageCorrection: false)
        let record = ScanAutofill.record(from: processed, source: .camera, groupID: nil)
        XCTAssertEqual(record.merchant, "FRESH MART")
        XCTAssertEqual(record.category, .groceries)
        XCTAssertEqual(record.total, money("3.49"))
        XCTAssertEqual(record.items.map { item in item.name }, ["BREAD"])
        XCTAssertTrue(record.autofilled.isSuperset(of: [.merchant, .total, .items, .category]))
        XCTAssertTrue(record.unreadable.contains(.date))
        XCTAssertEqual(record.pageImageCount, 1)
    }

    func testParserReadsTips() {
        let scan = ReceiptLayoutBuilder()
            .row("The Daily Grind Cafe")
            .row("Latte 4.50")
            .row("Muffin 3.25")
            .row("Subtotal 7.75")
            .row("Tax 0.69")
            .row("Tip 1.50")
            .row("Total 9.94")
            .build()
        let receipt = RulesReceiptParser().parse(scan)
        XCTAssertEqual(receipt.tip, money("1.50"))
        XCTAssertEqual(receipt.total, money("9.94"))
        XCTAssertEqual(itemList(receipt), itemList([("Latte", "4.50"), ("Muffin", "3.25")]))
        XCTAssertTrue(ReceiptValidator.checks(for: receipt).allSatisfy { check in check.passed })
    }
}
