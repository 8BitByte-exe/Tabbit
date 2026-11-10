import Foundation
import NaturalLanguage

/// The receipt's own writing: its main script and language, found on the device.
///
/// OCR sometimes fills a faint character in from the wrong alphabet ("13.00名", "$24.9îŚ",
/// "BUYă" on an English receipt). A receipt doesn't switch alphabets inside a word, so each
/// word is read in context:
/// - A word that is clearly another script (two or more of its letters) is kept: a Greek
///   name on an English receipt, or an English line on a Greek one.
/// - A stray character from another script inside a word becomes its look-alike in the
///   word's script (Greek "Α" in "ΒΑΝΑΝΑ" stays, Cyrillic "С" in "COFFEE" becomes "C"), or
///   is dropped when it has none ("名" in "13.00名").
/// - An accented letter the receipt's language doesn't write ("ă" in English) loses its
///   accent when the word around it looks garbled: next to digits, or a lowercase letter in
///   an all-caps word. Real words keep their accents ("Crème" on an English menu).
struct ReceiptAlphabet: Equatable {

    enum Script: String, Equatable {
        case latin, greek, cyrillic, cjk, arabic, hebrew, thai
    }

    /// The script most of the receipt's letters are in.
    let script: Script
    /// The receipt's main language ("en", "fr", "el"), or nil when it's unclear.
    let language: String?

    /// A language is taken when the recognizer gives it at least this probability.
    static let languageThreshold = 0.6

    init(script: Script, language: String?) {
        self.script = script
        self.language = language
    }

    /// The alphabet of these texts (a receipt's blocks or lines).
    init(texts: [String]) {
        var counts: [Script: Int] = [:]
        for text in texts {
            for scalar in text.unicodeScalars {
                if let script = ReceiptAlphabet.script(of: scalar) {
                    counts[script, default: 0] += 1
                }
            }
        }
        let main = counts.max { first, second in first.value < second.value }?.key ?? .latin
        self.script = main
        self.language = ReceiptAlphabet.mainLanguage(of: texts)
    }

    /// The receipt's language from its words (digits and prices left out), or nil.
    static func mainLanguage(of texts: [String]) -> String? {
        var words: [String] = []
        for text in texts {
            for word in text.components(separatedBy: .whitespaces) {
                let letters = word.unicodeScalars.filter { scalar in script(of: scalar) != nil }
                if letters.count >= 2 && letters.count * 2 >= word.unicodeScalars.count {
                    words.append(word)
                }
            }
        }
        guard words.count >= 3 else {
            return nil
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(words.joined(separator: " "))
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        guard let best = hypotheses.max(by: { first, second in first.value < second.value }),
              best.value >= languageThreshold else {
            return nil
        }
        return best.key.rawValue
    }

    /// The script of a letter, or nil for digits, punctuation and symbols.
    static func script(of scalar: Unicode.Scalar) -> Script? {
        guard scalar.properties.isAlphabetic else {
            return nil
        }
        let value = scalar.value
        switch value {
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF:
            return value == 0xD7 || value == 0xF7 ? nil : .latin
        case 0x370...0x3FF, 0x1F00...0x1FFF:
            return .greek
        case 0x400...0x52F:
            return .cyrillic
        case 0x590...0x5FF:
            return .hebrew
        case 0x600...0x6FF, 0x750...0x77F, 0xFB50...0xFDFF, 0xFE70...0xFEFF:
            return .arabic
        case 0xE00...0xE7F:
            return .thai
        case 0x1100...0x11FF, 0x3040...0x30FF, 0x3130...0x318F, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xAC00...0xD7AF, 0xF900...0xFAFF:
            return .cjk
        default:
            return nil
        }
    }

    // MARK: - Letters

    /// The accented letters each language writes (lowercase). A language not listed keeps
    /// every letter as read.
    static let accentedLetters: [String: String] = [
        "en": "",
        "fr": "àâæçéèêëîïôœùûüÿ",
        "de": "äöüß",
        "es": "áéíñóúü",
        "it": "àèéìíîòóùú",
        "pt": "áâãàçéêíóôõú",
        "nl": "áéíóúëïöü",
        "sv": "åäöé",
        "da": "æøåé",
        "nb": "æøåé",
        "fi": "äöå",
        "pl": "ąćęłńóśźż",
        "cs": "áčďéěíňóřšťúůýž",
        "sk": "áäčďéíĺľňóôŕšťúýž",
        "hu": "áéíóöőúüű",
        "ro": "ăâîșțşţ",
        "tr": "çğıöşü",
        "hr": "čćđšž",
        "ca": "àçéèíïòóúü",
    ]

    /// Letters that look the same in two scripts, Greek or Cyrillic first, Latin second.
    static let crossScriptLookAlikes: [(Character, Character)] = [
        ("Α", "A"), ("Β", "B"), ("Ε", "E"), ("Ζ", "Z"), ("Η", "H"), ("Ι", "I"), ("Κ", "K"), ("Μ", "M"),
        ("Ν", "N"), ("Ο", "O"), ("Ρ", "P"), ("Τ", "T"), ("Υ", "Y"), ("Χ", "X"), ("ο", "o"), ("ν", "v"),
        ("А", "A"), ("В", "B"), ("Е", "E"), ("К", "K"), ("М", "M"), ("Н", "H"), ("О", "O"), ("Р", "P"),
        ("С", "C"), ("Т", "T"), ("Х", "X"), ("а", "a"), ("е", "e"), ("о", "o"), ("р", "p"), ("с", "c"),
        ("у", "y"), ("х", "x"), ("і", "i"), ("ѕ", "s"),
    ]

    /// The look-alike of `character` in `target`, if it has one.
    static func lookAlike(of character: Character, in target: Script) -> Character? {
        for (other, latin) in crossScriptLookAlikes {
            if target == .latin && character == other {
                return latin
            }
            if character == latin, let script = other.unicodeScalars.first.flatMap({ scalar in self.script(of: scalar) }),
               script == target {
                return other
            }
        }
        return nil
    }

    // MARK: - Reading in context

    /// `text` with characters that don't fit the receipt read as ones that do.
    func normalized(_ text: String) -> String {
        var source = text
        if script != .cjk {
            source = ReceiptAlphabet.narrowed(source)
        }
        let words = source.components(separatedBy: " ")
        let fixed = words.map { word in normalizedWord(word) }
        let joined = fixed.joined(separator: " ")
        if joined == text {
            return text
        }
        return joined
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Full-width forms ("：", "Ａ") as plain ones, outside Chinese, Japanese and Korean receipts.
    static func narrowed(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.value >= 0xFF01 && scalar.value <= 0xFF5E,
               let narrow = Unicode.Scalar(scalar.value - 0xFEE0) {
                result.append(narrow)
            } else {
                result.append(scalar)
            }
        }
        return String(result)
    }

    private func normalizedWord(_ word: String) -> String {
        let characters = Array(word)
        guard !characters.isEmpty else {
            return word
        }
        var counts: [Script: Int] = [:]
        for character in characters {
            if let script = ReceiptAlphabet.script(of: character) {
                counts[script, default: 0] += 1
            }
        }
        guard !counts.isEmpty else {
            return word
        }
        // A word written in another script (two letters or more) is that script; a word with
        // only a stray letter or two is read in the receipt's script.
        var reference = script
        if let best = counts.max(by: { first, second in first.value < second.value }),
           best.value >= 2, counts[script, default: 0] < best.value {
            reference = best.key
        }
        let hasDigit = characters.contains { character in character.isNumber }
        let otherLetters = characters.filter { character in
            ReceiptAlphabet.script(of: character) == reference
        }

        var result = ""
        for character in characters {
            guard let letterScript = ReceiptAlphabet.script(of: character) else {
                result.append(character)
                continue
            }
            if letterScript != reference {
                // A stray letter from another alphabet: its look-alike, or nothing.
                if let lookAlike = ReceiptAlphabet.lookAlike(of: character, in: reference) {
                    result.append(lookAlike)
                }
                continue
            }
            if reference == .latin, isForeignAccent(character),
               hasDigit || breaksCase(character, among: otherLetters) || otherLetters.count == 1 {
                result.append(contentsOf: folded(character, among: otherLetters))
                continue
            }
            result.append(character)
        }
        return result
    }

    /// An accented Latin letter that the receipt's language doesn't write.
    private func isForeignAccent(_ character: Character) -> Bool {
        let lower = character.lowercased()
        guard let scalar = lower.unicodeScalars.first, scalar.value > 0x7F else {
            return false
        }
        guard let language = language, let letters = ReceiptAlphabet.accentedLetters[language] else {
            return false
        }
        return !letters.contains(lower)
    }

    /// A lowercase letter in an otherwise all-caps word ("BUYă"), or the other way round.
    private func breaksCase(_ character: Character, among letters: [Character]) -> Bool {
        let others = letters.filter { letter in letter != character }
        guard others.count >= 2 else {
            return false
        }
        if character.isLowercase {
            return others.allSatisfy { letter in letter.isUppercase }
        }
        return others.allSatisfy { letter in letter.isLowercase }
    }

    /// The letter without its accent, in the case of the word around it.
    private func folded(_ character: Character, among letters: [Character]) -> String {
        let plain = String(character).folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let others = letters.filter { letter in letter != character }
        if others.count >= 2 && others.allSatisfy({ letter in letter.isUppercase }) {
            return plain.uppercased()
        }
        return plain
    }

    private static func script(of character: Character) -> Script? {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            // A letter with a combining accent: judge it by its base letter.
            return character.unicodeScalars.first.flatMap { scalar in script(of: scalar) }
        }
        return script(of: scalar)
    }
}
