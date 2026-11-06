import XCTest
@testable import Tabbit

final class SettleUpTests: XCTestCase {

    private let alex = UUID()
    private let blair = UUID()
    private let casey = UUID()
    private let drew = UUID()

    private func transfers(_ balances: [UUID: Int], order: [UUID]) -> [String] {
        let names = [alex: "A", blair: "B", casey: "C", drew: "D"]
        return SettleUp.transfers(balances: balances, order: order).map { transfer in
            "\(names[transfer.from] ?? "?")→\(names[transfer.to] ?? "?") \(transfer.cents)"
        }
    }

    func testBalancesArePaidMinusOwed() {
        let receipt = ReceiptRecord(
            paidBy: alex,
            items: [
                SplitItem(name: "Pizza", price: money("30.00")),
                SplitItem(name: "Wine", price: money("20.00"), assignees: [alex, blair]),
            ],
            tax: money("4.00"),
            tip: .amount(money("6.00"))
        )
        let balances = SettleUp.balances(receipts: [receipt], members: [alex, blair, casey], settlements: [])
        XCTAssertEqual(balances[alex], 3600)
        XCTAssertEqual(balances[blair], -2400)
        XCTAssertEqual(balances[casey], -1200)
        XCTAssertEqual(balances.values.reduce(0, +), 0)
        XCTAssertEqual(transfers(balances, order: [alex, blair, casey]), ["B→A 2400", "C→A 1200"])
    }

    func testChainsAreSimplified() {
        // A owes B 10 and B owes C 10: one payment, A → C.
        let balances = [alex: -1000, blair: 0, casey: 1000]
        XCTAssertEqual(transfers(balances, order: [alex, blair, casey]), ["A→C 1000"])
    }

    func testLargestDebtorPaysLargestCreditorFirst() {
        let balances = [alex: 3000, blair: 2000, casey: -2500, drew: -2500]
        XCTAssertEqual(transfers(balances, order: [alex, blair, casey, drew]),
                       ["C→A 2500", "D→B 2000", "D→A 500"])
    }

    func testEveryoneEvenMeansNoTransfers() {
        XCTAssertTrue(SettleUp.transfers(balances: [alex: 0, blair: 0], order: [alex, blair]).isEmpty)
    }

    func testMarkingPaidSettlesTheDebt() {
        let receipt = ReceiptRecord(paidBy: alex, total: money("30.00"))
        let paid = Settlement(from: blair, to: alex, amount: money("10.00"))
        let balances = SettleUp.balances(receipts: [receipt], members: [alex, blair, casey], settlements: [paid])
        XCTAssertEqual(transfers(balances, order: [alex, blair, casey]), ["C→A 1000"])
    }

    func testDetailsShowTheReceiptsBehindADebt() {
        let dinner = ReceiptRecord(merchant: "Trattoria", paidBy: alex,
                                   items: [SplitItem(name: "Pasta", price: money("12.00"), assignees: [blair])])
        let taxi = ReceiptRecord(merchant: "Taxi", paidBy: casey, total: money("9.00"))
        let details = SettleUp.details(debtor: blair, creditor: alex, receipts: [dinner, taxi],
                                       members: [alex, blair, casey])
        XCTAssertEqual(details.map { detail in detail.merchant }, ["Trattoria"])
        XCTAssertEqual(details.first?.totalCents, 1200)
        XCTAssertEqual(details.first?.items.map { item in item.name }, ["Pasta"])
    }

    func testSummaryText() {
        let people = [Person(id: alex, name: "Alex", colorIndex: 0), Person(id: blair, name: "Blair", colorIndex: 1)]
        let text = SettleUp.summary(groupName: "Lisbon", transfers: [Transfer(from: blair, to: alex, cents: 2400)],
                                    people: people)
        XCTAssertTrue(text.hasPrefix("Lisbon: settle up"))
        XCTAssertTrue(text.contains("Blair → Alex: \(Money.string(money("24.00")))"))
        XCTAssertTrue(SettleUp.summary(groupName: "Lisbon", transfers: [], people: people).contains("settled up"))
    }
}
