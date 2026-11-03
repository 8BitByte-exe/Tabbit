import Foundation

/// Small helpers around NSRegularExpression (works on iOS 16, unlike some newer Swift Regex features).
enum Patterns {
    /// Compiles a pattern that is a constant in this codebase.
    /// A bad pattern is a programming error; unit tests exercise every pattern.
    static func make(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        return try! NSRegularExpression(pattern: pattern, options: options)
    }
}

extension NSRegularExpression {
    /// True if the pattern matches anywhere in `text`.
    func hasMatch(in text: String) -> Bool {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return firstMatch(in: text, options: [], range: range) != nil
    }

    /// All matches in `text`, in order.
    func allMatches(in text: String) -> [NSTextCheckingResult] {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return matches(in: text, options: [], range: range)
    }
}

extension NSTextCheckingResult {
    /// The text of capture group `index`, or nil if that group didn't take part in the match.
    func group(_ index: Int, in text: String) -> String? {
        let range = self.range(at: index)
        if range.location == NSNotFound {
            return nil
        }
        return (text as NSString).substring(with: range)
    }
}
