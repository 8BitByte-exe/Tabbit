#if canImport(FoundationModels)
import Foundation
import FoundationModels

// Apple Intelligence's on-device language model (iOS 26). Nothing here goes over
// the network: Foundation Models runs entirely on the iPhone.

@available(iOS 26.0, *)
@Generable
struct GeneratedReceiptItem {
    @Guide(description: "The item's text exactly as printed on the receipt")
    var printedText: String

    @Guide(description: "A short, readable name for the item, with abbreviations expanded and normal capitalization")
    var name: String

    @Guide(description: "The line's price exactly as printed, like 4.99, or negative like -1.00 for a discount")
    var price: String
}

@available(iOS 26.0, *)
@Generable
struct GeneratedReceipt {
    @Guide(description: "The store or restaurant name as printed near the top, in normal capitalization")
    var merchant: String?

    @Guide(description: "The purchase date as YYYY-MM-DD, only if a date is printed")
    var date: String?

    @Guide(description: "Every item bought, in the order printed")
    var items: [GeneratedReceiptItem]

    @Guide(description: "The subtotal exactly as printed, if there is one")
    var subtotal: String?

    @Guide(description: "The tax exactly as printed, if there is one. Add several tax lines together.")
    var tax: String?

    @Guide(description: "A tip or gratuity that was charged, exactly as printed, if there is one")
    var tip: String?

    @Guide(description: "The total to pay exactly as printed")
    var total: String?

    @Guide(description: "True if the receipt says the prices already include tax, such as VAT, MwSt, IVA, TVA or BTW")
    var pricesIncludeTax: Bool

    @Guide(description: "What the purchase was for: one category from the list in the instructions")
    var category: String
}

@available(iOS 26.0, *)
extension GeneratedReceipt {
    var draft: ModelReceiptDraft {
        return ModelReceiptDraft(
            merchant: merchant,
            date: date,
            items: items.map { item in
                ModelReceiptDraft.Item(printedText: item.printedText, name: item.name, price: item.price)
            },
            subtotal: subtotal,
            tax: tax,
            tip: tip,
            total: total,
            pricesIncludeTax: pricesIncludeTax,
            category: category
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

    /// Asks the on-device model to read the receipt. Greedy sampling, so the same
    /// scan always gives the same answer.
    static func read(prompt: String) async throws -> ModelReceiptDraft {
        let session = LanguageModelSession(instructions: ReceiptPrompt.instructions)
        let response = try await session.respond(to: prompt, generating: GeneratedReceipt.self,
                                                 options: GenerationOptions(sampling: .greedy))
        return response.content.draft
    }
}
#endif
