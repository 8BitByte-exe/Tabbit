import Foundation
import UIKit

/// Fixing words OCR misread, without a rule per mistake.
///
/// OCR mistakes aren't random: it confuses letters that look alike ("rn" and "m",
/// "0" and "O", "1" and "l", "5" and "S"). `distance` is an edit distance where those
/// look-alike swaps are cheap and every other change costs 1. A word that isn't in the
/// iPhone's dictionary is replaced by one of the dictionary's suggestions only when the
/// difference is look-alike swaps alone: "Cinerna" becomes "Cinema" (rn → m), but a brand
/// name like "Sobeys" stays, because no dictionary word is a look-alike of it.
enum OCRSpelling {

    /// Cost of swapping one look-alike for another.
    static let lookAlikeCost = 0.3
    /// A suggestion is taken only up to this cost: one look-alike swap, never a real edit.
    static let maximumRepairCost = 0.35

    /// Shapes OCR mixes up, each written as the pair of spellings (lowercase).
    static let lookAlikes: [(String, String)] = [
        ("rn", "m"), ("m", "nn"), ("vv", "w"), ("cl", "d"), ("li", "h"), ("ri", "n"),
        ("0", "o"), ("1", "l"), ("1", "i"), ("l", "i"), ("5", "s"), ("8", "b"), ("6", "b"), ("2", "z"),
        ("e", "c"), ("c", "o"), ("u", "v"), ("n", "h"), ("f", "t"), ("i", "j"), ("a", "o"), ("q", "g"),
    ]

    /// Edit distance where look-alike swaps cost `lookAlikeCost` and other changes 1. Ignores case.
    static func distance(_ first: String, _ second: String) -> Double {
        let a = Array(first.lowercased())
        let b = Array(second.lowercased())
        if a.isEmpty || b.isEmpty {
            return Double(max(a.count, b.count))
        }
        var table = Array(repeating: Array(repeating: 0.0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count {
            table[i][0] = Double(i)
        }
        for j in 0...b.count {
            table[0][j] = Double(j)
        }
        for i in 1...a.count {
            for j in 1...b.count {
                var best = min(table[i - 1][j] + 1, table[i][j - 1] + 1)
                let substitution: Double = a[i - 1] == b[j - 1] ? 0 : (isLookAlike(String(a[i - 1]), String(b[j - 1])) ? lookAlikeCost : 1)
                best = min(best, table[i - 1][j - 1] + substitution)
                // Look-alikes of different lengths ("rn" for "m").
                for (one, other) in lookAlikes where one.count != other.count {
                    for (left, right) in [(one, other), (other, one)] {
                        let leftCount = left.count
                        let rightCount = right.count
                        guard i >= leftCount, j >= rightCount else {
                            continue
                        }
                        if String(a[(i - leftCount)..<i]) == left && String(b[(j - rightCount)..<j]) == right {
                            best = min(best, table[i - leftCount][j - rightCount] + lookAlikeCost)
                        }
                    }
                }
                table[i][j] = best
            }
        }
        return table[a.count][b.count]
    }

    private static func isLookAlike(_ one: String, _ other: String) -> Bool {
        return lookAlikes.contains { pair in
            (pair.0 == one && pair.1 == other) || (pair.0 == other && pair.1 == one)
        }
    }

    /// The suggestion that only differs from `word` by look-alikes (the cheapest one), or nil.
    static func bestRepair(of word: String, suggestions: [String]) -> String? {
        var best: (word: String, cost: Double)?
        for suggestion in suggestions where suggestion.lowercased() != word.lowercased() {
            let cost = distance(word, suggestion)
            if cost <= maximumRepairCost && cost < (best?.cost ?? Double.greatestFiniteMagnitude) {
                best = (word: suggestion, cost: cost)
            }
        }
        return best?.word
    }

    /// `repaired` in the capitalization of `original` (all caps, capitalized or lower case).
    static func matchingCase(_ repaired: String, like original: String) -> String {
        if original == original.uppercased() && original != original.lowercased() {
            return repaired.uppercased()
        }
        if let first = original.first, first.isUppercase {
            return repaired.prefix(1).uppercased() + repaired.dropFirst().lowercased()
        }
        return repaired.lowercased()
    }

    // MARK: - Dictionary

    /// A store name with misread words repaired from the iPhone's dictionary (on the device,
    /// no network). Words of 4+ letters that the dictionary doesn't know are candidates;
    /// numbers, short words and words it knows are left as printed. Uses UIKit's text
    /// checker, so call it on the main thread.
    static func repairedName(_ name: String) -> String {
        let checker = UITextChecker()
        let language = dictionaryLanguage
        let words = name.components(separatedBy: " ")
        let repaired = words.map { word -> String in
            guard word.count >= 4, word.allSatisfy({ character in character.isLetter }) else {
                return word
            }
            let text = word.lowercased() as NSString
            let range = NSRange(location: 0, length: text.length)
            let misspelled = checker.rangeOfMisspelledWord(in: text as String, range: range, startingAt: 0,
                                                           wrap: false, language: language)
            guard misspelled.location != NSNotFound else {
                return word
            }
            let suggestions = checker.guesses(forWordRange: range, in: text as String, language: language) ?? []
            guard let fix = bestRepair(of: word, suggestions: suggestions),
                  fix.allSatisfy({ character in character.isLetter }) else {
                return word
            }
            return matchingCase(fix, like: word)
        }
        return repaired.joined(separator: " ")
    }

    /// The dictionary for the iPhone's first language that has one, or US English.
    static var dictionaryLanguage: String {
        let available = UITextChecker.availableLanguages
        for preferred in Locale.preferredLanguages {
            let normalized = preferred.replacingOccurrences(of: "-", with: "_")
            if available.contains(normalized) {
                return normalized
            }
            let base = String(normalized.prefix(2))
            if let match = available.first(where: { language in language.hasPrefix(base) }) {
                return match
            }
        }
        return available.contains("en_US") ? "en_US" : (available.first ?? "en_US")
    }
}
