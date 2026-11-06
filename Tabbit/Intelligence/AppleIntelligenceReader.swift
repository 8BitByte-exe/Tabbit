#if canImport(FoundationModels)
import Foundation
import FoundationModels

// Apple Intelligence's on-device language model (iOS 26). Nothing here goes over
// the network: Foundation Models runs entirely on the iPhone.
//
// The model labels the receipt's numbered lines; it never writes an amount. Every
// field is required (no optionals): the model tends to leave optional fields out,
// which is what lost the total in 1.1's first build.

@available(iOS 26.0, *)
@Generable
enum GeneratedLineKind {
    case item
    case discount
    case subtotal
    case tax
    case taxTotal
    case tip
    case total
    case payment
    case savings
    case unitPrice
    case other
}

@available(iOS 26.0, *)
@Generable
struct GeneratedLineLabel {
    @Guide(description: "The number in brackets at the start of the line, like 4 for [4]")
    var line: Int

    @Guide(description: "What the line is")
    var kind: GeneratedLineKind

    @Guide(description: "For an item or discount, its name the way a person would say it. Empty for every other kind.")
    var name: String
}

@available(iOS 26.0, *)
@Generable
struct GeneratedReceiptReading {
    @Guide(description: "The business's brand name only, like Best Buy, Shell or Trader Joe's. Never the address, city, branch or store number.")
    var storeName: String

    @Guide(description: "One label for every numbered line, in order")
    var lines: [GeneratedLineLabel]

    @Guide(description: "True if the receipt says its prices already include the tax, like VAT included or HST included")
    var pricesIncludeTax: Bool

    @Guide(description: "What the purchase was for: one category from the list in the instructions")
    var category: String

    @Guide(description: "The purchase date as YYYY-MM-DD, or an empty string if no date is printed")
    var date: String
}

@available(iOS 26.0, *)
extension GeneratedLineKind {
    var plain: ModelLineKind {
        switch self {
        case .item: return .item
        case .discount: return .discount
        case .subtotal: return .subtotal
        case .tax: return .tax
        case .taxTotal: return .taxTotal
        case .tip: return .tip
        case .total: return .total
        case .payment: return .payment
        case .savings: return .savings
        case .unitPrice: return .unitPrice
        case .other: return .other
        }
    }
}

@available(iOS 26.0, *)
extension GeneratedReceiptReading {
    var plain: ModelReceiptReading {
        return ModelReceiptReading(
            storeName: storeName,
            labels: lines.map { label in
                ModelReceiptReading.Label(line: label.line, kind: label.kind.plain, name: label.name)
            },
            pricesIncludeTax: pricesIncludeTax,
            category: category,
            date: date
        )
    }
}

@available(iOS 26.0, *)
enum AppleIntelligenceReader {

    static var status: IntelligenceStatus {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .notSupported
            case .appleIntelligenceNotEnabled:
                return .turnedOff
            case .modelNotReady:
                return .downloading
            @unknown default:
                return .notSupported
            }
        @unknown default:
            return .notSupported
        }
    }

    /// Asks the on-device model to label the receipt's lines. Greedy sampling, so the
    /// same scan always gives the same answer.
    static func read(prompt: String) async throws -> ModelReceiptReading {
        let session = LanguageModelSession(instructions: ReceiptPrompt.instructions)
        let response = try await session.respond(to: prompt, generating: GeneratedReceiptReading.self,
                                                 options: GenerationOptions(sampling: .greedy))
        return response.content.plain
    }

    /// True if the prompt didn't fit the model's context window.
    static func isTooLong(_ error: Error) -> Bool {
        guard let generationError = error as? LanguageModelSession.GenerationError else {
            return false
        }
        if case .exceededContextWindowSize = generationError {
            return true
        }
        return false
    }

    /// True if Apple's safety filter stopped the model.
    static func isGuardrail(_ error: Error) -> Bool {
        guard let generationError = error as? LanguageModelSession.GenerationError else {
            return false
        }
        if case .guardrailViolation = generationError {
            return true
        }
        return false
    }
}
#endif
