import XCTest
@testable import Tabbit

/// Personal vs business receipts: storage, the editor's form, the My Receipts filter and the CSV.
final class ExpenseKindTests: XCTestCase {

    private func json(_ record: ReceiptRecord) throws -> [String: Any] {
        let data = try JSONEncoder().encode(record)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> ReceiptRecord {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(ReceiptRecord.self, from: data)
    }

    func testNewReceiptsArePersonal() {
        XCTAssertEqual(ReceiptRecord().expense, .personal)
    }

    func testBusinessSurvivesSaving() throws {
        let record = ReceiptRecord(merchant: "Shell", category: .fuel, expense: .business, total: money("50.00"))
        let object = try json(record)
        XCTAssertEqual(object["expense"] as? String, "business")
        XCTAssertEqual(try decode(object).expense, .business)
    }

    func testOlderFilesWithoutAnExpenseArePersonal() throws {
        var object = try json(ReceiptRecord(merchant: "Cafe", total: money("4.00")))
        object.removeValue(forKey: "expense")
        XCTAssertEqual(try decode(object).expense, .personal)
    }

    func testUnknownExpenseValueIsPersonal() throws {
        var object = try json(ReceiptRecord(merchant: "Cafe", total: money("4.00")))
        object["expense"] = "something-new"
        XCTAssertEqual(try decode(object).expense, .personal)
    }

    /// The unreleased 1.3 test build filed receipts under a business with `businessID`.
    func testReceiptFiledUnderABusinessBecomesBusiness() throws {
        var object = try json(ReceiptRecord(merchant: "Esso", total: money("60.00")))
        object.removeValue(forKey: "expense")
        object["businessID"] = UUID().uuidString
        object["jobID"] = UUID().uuidString
        let loaded = try decode(object)
        XCTAssertEqual(loaded.expense, .business)
        // Saved again, it keeps the label in the new field.
        XCTAssertEqual(try json(loaded)["expense"] as? String, "business")
    }

    func testFormKeepsTheChoice() {
        let base = ReceiptRecord(merchant: "Shell", total: money("50.00"))
        var form = ReceiptForm(base)
        XCTAssertEqual(form.expense, .personal)
        form.expense = .business
        XCTAssertEqual(form.record(updating: base).expense, .business)
    }

    func testFilterAndYearTotal() {
        let calendar = Calendar.current
        let thisYear = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let lastYear = calendar.date(from: DateComponents(year: 2025, month: 12, day: 30))!
        let fuel = ReceiptRecord(merchant: "Shell", date: thisYear, expense: .business, total: money("50.00"))
        let hotel = ReceiptRecord(merchant: "Inn", date: thisYear, expense: .business, total: money("120.00"))
        let old = ReceiptRecord(merchant: "Esso", date: lastYear, expense: .business, total: money("40.00"))
        let coffee = ReceiptRecord(merchant: "Cafe", date: thisYear, total: money("4.00"))
        let all = [fuel, hotel, old, coffee]

        XCTAssertEqual(all.filter { receipt in ReceiptSearch.ExpenseFilter.business.includes(receipt) }.count, 3)
        XCTAssertEqual(all.filter { receipt in ReceiptSearch.ExpenseFilter.personal.includes(receipt) }.map { receipt in receipt.merchant },
                       ["Cafe"])
        XCTAssertEqual(all.filter { receipt in ReceiptSearch.ExpenseFilter.all.includes(receipt) }.count, 4)

        let business = all.filter { receipt in receipt.expense == .business }
        let midYear = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        XCTAssertEqual(ReceiptSearch.total(of: business, inYearOf: midYear), money("170.00"))
    }

    func testSearchFindsBusiness() {
        let fuel = ReceiptRecord(merchant: "Shell", expense: .business, total: money("50.00"))
        let coffee = ReceiptRecord(merchant: "Cafe", total: money("4.00"))
        XCTAssertTrue(ReceiptSearch.matches(fuel, query: "business"))
        XCTAssertFalse(ReceiptSearch.matches(coffee, query: "business"))
    }

    func testCSVHasAType() {
        let me = Person.makeMe(name: "Sam")
        let fuel = ReceiptRecord(merchant: "Shell", category: .fuel, expense: .business, total: money("50.00"))
        let lines = CSVExporter.csv(receipts: [fuel], groups: [], me: me)
            .split(separator: "\r\n").map { line in String(line) }
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("Category,Type,Paid by"))
        XCTAssertTrue(lines[1].contains("Shell,Fuel,Business,Sam"))
    }
}
