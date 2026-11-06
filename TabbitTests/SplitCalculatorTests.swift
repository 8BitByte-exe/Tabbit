import XCTest
@testable import Tabbit

final class SplitCalculatorTests: XCTestCase {

    private let alex = UUID()
    private let blair = UUID()
    private let casey = UUID()

    private var members: [UUID] {
        return [alex, blair, casey]
    }

    private func cents(_ split: ReceiptSplit) -> [Int] {
        return members.map { id in split.share(for: id)?.totalCents ?? -1 }
    }

    // MARK: - Allocation

    func testAllocateHandsOutLeftoverCentsInOrder() {
        XCTAssertEqual(SplitCalculator.allocate(1000, weights: [1, 1, 1]), [334, 333, 333])
        XCTAssertEqual(SplitCalculator.allocate(-1000, weights: [1, 1, 1]), [-334, -333, -333])
        XCTAssertEqual(SplitCalculator.allocate(100, weights: [1, 3]), [25, 75])
        XCTAssertEqual(SplitCalculator.allocate(1, weights: [1, 1]), [1, 0])
        XCTAssertEqual(SplitCalculator.allocate(10, weights: [0, 0]), [0, 0])
        XCTAssertEqual(SplitCalculator.allocate(0, weights: [1, 2]), [0, 0])
    }

    func testAllocateFavorsLargestRemainders() {
        // 100 × (1/6, 2/6, 3/6) = 16.67, 33.33, 50 → the 0.67 remainder gets the extra cent.
        XCTAssertEqual(SplitCalculator.allocate(100, weights: [1, 2, 3]), [17, 33, 50])
    }

    // MARK: - Receipts

    private func dinner(includeFees: Bool = true, tip: TipValue? = .amount(money("6.00")),
                        total: Decimal? = nil) -> ReceiptRecord {
        return ReceiptRecord(
            merchant: "Trattoria",
            paidBy: alex,
            items: [
                SplitItem(name: "Pizza", price: money("30.00")),
                SplitItem(name: "Wine", price: money("20.00"), assignees: [alex, blair]),
            ],
            tax: money("4.00"),
            tip: tip,
            total: total,
            includeFees: includeFees
        )
    }

    func testItemsSplitEvenlyAndFeesFollowItems() {
        let split = SplitCalculator.split(dinner(), members: members)
        // Items: Alex 10 + 10, Blair 10 + 10, Casey 10. Fees 10.00 split 2:2:1.
        XCTAssertEqual(cents(split), [2400, 2400, 1200])
        XCTAssertEqual(split.totalCents, 6000)
        XCTAssertEqual(split.share(for: casey)?.items.map { item in item.name }, ["Pizza"])
        XCTAssertEqual(split.share(for: casey)?.feeCents, 200)
        XCTAssertEqual(split.share(for: alex)?.items.first?.splitWays, 3)
    }

    func testWithoutFeesThePayerCoversTaxAndTip() {
        let split = SplitCalculator.split(dinner(includeFees: false), members: members)
        XCTAssertEqual(cents(split), [3000, 2000, 1000])
    }

    func testTipAsPercentOfItems() {
        let receipt = dinner(tip: .percent(money("10")))
        XCTAssertEqual(receipt.tipAmount, money("5.00"))
        XCTAssertEqual(receipt.computedTotal, money("59.00"))
        XCTAssertEqual(SplitCalculator.split(receipt, members: members).totalCents, 5900)
    }

    func testPrintedTotalDifferenceIsSpreadLikeFees() {
        // A 5.00 service charge only shows in the printed total.
        let receipt = dinner(total: money("65.00"))
        XCTAssertEqual(receipt.totalMismatch, money("5.00"))
        let split = SplitCalculator.split(receipt, members: members)
        XCTAssertEqual(split.totalCents, 6500)
        XCTAssertEqual(cents(split), [2600, 2600, 1300])
    }

    func testReceiptWithoutItemsSplitsTheTotalEvenly() {
        let receipt = ReceiptRecord(merchant: "Taxi", paidBy: blair, total: money("10.00"))
        XCTAssertEqual(cents(SplitCalculator.split(receipt, members: members)), [334, 333, 333])
    }

    func testUnknownAssigneesFallBackToEveryone() {
        let receipt = ReceiptRecord(items: [SplitItem(name: "Snacks", price: money("9.00"), assignees: [UUID()])])
        XCTAssertEqual(cents(SplitCalculator.split(receipt, members: members)), [300, 300, 300])
    }

    func testDiscountItemsReduceShares() {
        let receipt = ReceiptRecord(items: [
            SplitItem(name: "Chips", price: money("6.00"), assignees: [alex, blair]),
            SplitItem(name: "Coupon", price: money("-2.00"), assignees: [alex, blair]),
        ])
        XCTAssertEqual(cents(SplitCalculator.split(receipt, members: members)), [200, 200, 0])
    }

    func testSharesAlwaysAddUpToTheTotal() {
        let prices = ["0.01", "0.07", "1.00", "3.33", "10.10", "99.99"]
        for (index, price) in prices.enumerated() {
            let receipt = ReceiptRecord(
                items: [
                    SplitItem(name: "A", price: money(price)),
                    SplitItem(name: "B", price: money(price), assignees: [blair, casey]),
                ],
                tax: money("0.\(index + 1)7"),
                tip: .percent(money("15"))
            )
            let split = SplitCalculator.split(receipt, members: members)
            XCTAssertEqual(split.totalCents, Money.cents(receipt.effectiveTotal), "price \(price)")
        }
    }

    func testPersonalReceiptBelongsToMe() {
        let receipt = ReceiptRecord(total: money("12.34"))
        let split = SplitCalculator.split(receipt, members: [Person.meID])
        XCTAssertEqual(split.share(for: Person.meID)?.totalCents, 1234)
    }
}
