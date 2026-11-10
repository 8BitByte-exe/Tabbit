import Foundation

/// Finds the most likely set of purchases that adds up to the receipt's own numbers.
///
/// Every line that might be a purchase carries evidence: points for or against it from
/// the layout (price column, detail lines under an item), the keywords ("YOU SAVED",
/// "REG PRICE"), and Apple Intelligence's label when it has one. Lines with positive
/// evidence are counted. When the counted lines don't add up, the cheapest set of
/// changes that makes them add up is used, where changing a line costs as much as the
/// evidence against the change. Lines Tabbit is sure about never change, and when two
/// different changes are equally cheap nothing is guessed.
///
/// Both readers use this: the rules parser with layout and keyword evidence, and the
/// Apple Intelligence verifier with the model's labels added on top.
enum ItemReconciler {

    /// A line that may be a purchase.
    struct Choice {
        /// What it adds to the items when counted (negative for money off).
        let amount: Decimal
        /// Another reading of the amount ("2 BANANAS 1.99" as 3.98), or nil.
        let alternative: Decimal?
        /// Above 0 it's counted unless the numbers say otherwise.
        let evidence: Int
    }

    /// One change: count or leave out a line, or switch it to its other reading (`swap`).
    struct Move: Equatable {
        let index: Int
        let swap: Bool
        let cost: Int
    }

    /// The cheapest way to reach a sum: which moves (bits of `mask`) and what they cost.
    struct Fix: Equatable {
        let cost: Int
        let mask: Int
    }

    /// Lines with evidence this strong either way never change.
    static let maxMovableEvidence = 5
    /// At most this many moves are tried (2^12 combinations).
    static let maxMoves = 12
    /// Fixes that cost more than this are too far from what the receipt seems to say.
    static let maxFixCost = 12
    /// Switching a line to its other reading.
    static let swapCost = 2

    static func isCounted(_ choice: Choice) -> Bool {
        return choice.evidence > 0
    }

    /// The changes worth trying, cheapest first.
    static func moves(for choices: [Choice]) -> [Move] {
        var moves: [Move] = []
        for (index, choice) in choices.enumerated() where choice.amount != 0 {
            let magnitude = abs(choice.evidence)
            let movable = magnitude <= maxMovableEvidence
            if movable {
                moves.append(Move(index: index, swap: false, cost: max(magnitude, 1)))
            }
            if choice.alternative != nil && (isCounted(choice) || movable) {
                moves.append(Move(index: index, swap: true, cost: swapCost))
            }
        }
        let ordered = moves.enumerated().sorted { first, second in
            if first.element.cost != second.element.cost {
                return first.element.cost < second.element.cost
            }
            return first.offset < second.offset
        }
        return Array(ordered.map { entry in entry.element }.prefix(maxMoves))
    }

    /// Every sum (in cents) the items can reach, with the cheapest fix for each. A sum that two
    /// different fixes reach at the same lowest cost is left out: no guessing.
    static func reachableSums(_ choices: [Choice], moves: [Move]) -> [Int: Fix] {
        var best: [Int: Fix] = [:]
        var ambiguous: Set<Int> = []
        let baseCounted = choices.map { choice in isCounted(choice) }
        for mask in 0..<(1 << moves.count) {
            var counted = baseCounted
            var swapped: Set<Int> = []
            var cost = 0
            for (bit, move) in moves.enumerated() where mask & (1 << bit) != 0 {
                cost += move.cost
                if move.swap {
                    swapped.insert(move.index)
                } else {
                    counted[move.index].toggle()
                }
            }
            // Reading a line the other way only matters if it's counted.
            if cost > maxFixCost || swapped.contains(where: { index in !counted[index] }) {
                continue
            }
            var sum = 0
            for (index, choice) in choices.enumerated() where counted[index] {
                let amount = swapped.contains(index) ? (choice.alternative ?? choice.amount) : choice.amount
                sum += Money.cents(amount)
            }
            if let existing = best[sum] {
                if cost < existing.cost {
                    best[sum] = Fix(cost: cost, mask: mask)
                    ambiguous.remove(sum)
                } else if cost == existing.cost {
                    ambiguous.insert(sum)
                }
            } else {
                best[sum] = Fix(cost: cost, mask: mask)
            }
        }
        for sum in ambiguous {
            best[sum] = nil
        }
        return best
    }

    /// The fix that makes the items equal `target`, within a cent.
    static func lookup(_ target: Decimal, in fixes: [Int: Fix]) -> Fix? {
        let cents = Money.cents(target)
        var found: Fix?
        for candidate in [cents, cents - 1, cents + 1] {
            if let fix = fixes[candidate], found == nil || fix.cost < (found?.cost ?? Int.max) {
                found = fix
            }
        }
        return found
    }

    /// The moves a fix is made of, in the order of the lines.
    static func applied(_ fix: Fix, moves: [Move]) -> [Move] {
        var result: [Move] = []
        for (bit, move) in moves.enumerated() where fix.mask & (1 << bit) != 0 {
            result.append(move)
        }
        return result.sorted { first, second in
            if first.index != second.index {
                return first.index < second.index
            }
            return !first.swap && second.swap
        }
    }
}
